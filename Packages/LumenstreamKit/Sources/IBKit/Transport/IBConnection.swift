import Foundation
import Network

/// Where to find TWS or IB Gateway, and which API client slot to claim.
public struct IBEndpoint: Sendable, Hashable {
    public var host: String
    public var port: UInt16
    /// TWS allows up to 32 concurrent API clients, each with a unique ID.
    public var clientID: Int

    public init(host: String, port: UInt16, clientID: Int) {
        self.host = host
        self.port = port
        self.clientID = clientID
    }
}

/// One API session with TWS / IB Gateway over a raw TCP socket.
///
/// Built on Network framework's structured-concurrency `NetworkConnection`.
/// The actor owns the socket and the outbound rate limit; inbound frames are
/// read and decoded on a `@concurrent` loop and delivered as an `AsyncThrowingStream`.
public actor IBConnection {
    private var connection: NetworkConnection<TCP>?
    private var readTask: Task<Void, Never>?
    private var rateLimiter = IBRateLimiter(messagesPerSecond: 50)
    /// Bumped by every `connect`, so teardown and handshake steps belonging to an
    /// older session can tell they have been superseded and leave the new one alone.
    private var session = 0

    public private(set) var serverVersion: IBServerVersion?

    public init() {}

    /// Opens the socket, performs the version handshake and `startApi`, and
    /// returns the stream of everything TWS sends from then on.
    ///
    /// Ending iteration of the stream tears the session down.
    public func connect(to endpoint: IBEndpoint) async throws -> AsyncThrowingStream<IBEvent, any Error> {
        disconnect()
        session += 1
        let session = self.session

        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw IBProtocolError.invalidEndpoint(host: endpoint.host, port: endpoint.port)
        }

        let (events, continuation) = AsyncThrowingStream.makeStream(of: IBEvent.self)
        let connection = NetworkConnection(to: .hostPort(host: NWEndpoint.Host(endpoint.host), port: port)) {
            TCP().noDelay(true)
        }
        connection.onStateUpdate { _, state in
            continuation.yield(.transport(IBTransportState(state)))
        }
        self.connection = connection
        // Installed before anything can finish the stream, and scoped to this
        // session: a late teardown from an older stream must not kill a newer one.
        continuation.onTermination = { _ in
            Task { await self.disconnect(session: session) }
        }

        do {
            // 1. "API\0" followed by our supported version range as the first frame.
            var hello = IBFrame.apiPrefix
            hello.append(IBFrame.encode(Data(IBServerVersion.handshakeRange.utf8)))
            try await connection.send(hello)

            // 2. The server answers with the negotiated version and its clock.
            var reader = IBFieldReader(payload: try await Self.readFrame(from: connection))
            let version = IBServerVersion(try reader.int())
            let connectionTime = try reader.string()
            guard version >= .clientMinimum else {
                throw IBProtocolError.unsupportedServerVersion(version.rawValue)
            }
            // The actor is reentrant across the awaits above; if another `connect`
            // took over meanwhile, `self.connection` is no longer this socket.
            guard session == self.session else { throw CancellationError() }
            serverVersion = version

            // 3. Claim the client ID. TWS then pushes nextValidId, managedAccounts
            //    and farm-status notices without being asked.
            try await send(.startAPI(clientID: endpoint.clientID))
            guard session == self.session else { throw CancellationError() }
            continuation.yield(.connected(serverVersion: version, connectionTime: connectionTime))

            let decoder = IBMessageDecoder(serverVersion: version)
            readTask = Task {
                await Self.readLoop(connection, decoder: decoder, into: continuation)
            }
        } catch {
            disconnect(session: session)
            continuation.finish(throwing: error)
            throw error
        }

        return events
    }

    /// Sends a request, pacing all outbound traffic to TWS's 50 messages/second limit.
    public func send(_ request: IBRequest) async throws {
        guard let connection, let serverVersion else { throw IBProtocolError.notConnected }
        let slot = rateLimiter.reserve()
        if slot > .now {
            try await Task.sleep(until: slot, clock: .continuous)
        }
        try await connection.send(IBFrame.encode(request.payload(for: serverVersion)))
    }

    /// Drops the socket. `NetworkConnection` closes once its last reference goes away.
    public func disconnect() {
        readTask?.cancel()
        readTask = nil
        connection = nil
        serverVersion = nil
    }

    /// Tears down only if `session` is still the current one.
    private func disconnect(session: Int) {
        guard session == self.session else { return }
        disconnect()
    }

    // MARK: - Reading

    @concurrent
    private static func readLoop(
        _ connection: NetworkConnection<TCP>,
        decoder: IBMessageDecoder,
        into continuation: AsyncThrowingStream<IBEvent, any Error>.Continuation
    ) async {
        do {
            while !Task.isCancelled {
                let payload = try await readFrame(from: connection)
                continuation.yield(try decoder.decode(payload))
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func readFrame(from connection: NetworkConnection<TCP>) async throws -> Data {
        let length = Int(try await connection.receive(as: UInt32.self).content)
        guard length <= IBFrame.maximumLength else { throw IBProtocolError.frameTooLarge(length) }
        guard length > 0 else { return Data() }
        return try await connection.receive(exactly: length).content
    }
}

extension IBTransportState {
    init(_ state: NetworkChannel<TCP>.State) {
        switch state {
        case .setup, .preparing: self = .preparing
        case .ready: self = .ready
        case let .waiting(error): self = .waiting(String(describing: error))
        case let .failed(error): self = .failed(String(describing: error))
        case .cancelled: self = .cancelled
        @unknown default: self = .preparing
        }
    }
}
