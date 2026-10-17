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
/// The actor owns the socket, the outbound rate limit and the request registry;
/// inbound frames are read and decoded on a `@concurrent` loop and delivered as an
/// `AsyncThrowingStream`.
///
/// Use ``sessions(to:policy:)`` for a connection that survives TWS restarts, or
/// ``connect(to:)`` for a single socket.
public actor IBConnection {
    private var connection: NetworkConnection<TCP>?
    private var readTask: Task<Void, Never>?
    private var supervisor: Task<Void, Never>?
    private var rateLimiter = IBRateLimiter(messagesPerSecond: 50)
    private let registry = IBRequestRegistry()
    /// Bumped by every `connect`, so teardown and handshake steps belonging to an
    /// older socket can tell they have been superseded and leave the new one alone.
    private var session = 0
    /// Bumped by every `sessions(to:policy:)` and `disconnect()`, for the same reason.
    private var supervision = 0
    private let handshakeTimeout: Duration

    public private(set) var serverVersion: IBServerVersion?

    public init(handshakeTimeout: Duration = .seconds(10)) {
        self.handshakeTimeout = handshakeTimeout
    }

    // MARK: - Sessions

    /// Opens the socket, performs the version handshake and `startApi`, and
    /// returns the stream of everything TWS sends from then on.
    ///
    /// Fails fast with ``IBProtocolError/connectionUnavailable(_:)`` when nothing is
    /// listening, instead of waiting for the network to change. Ending iteration of
    /// the stream closes the socket. Streaming requests survive and are replayed on
    /// the next `connect`; ``disconnect()`` ends them.
    public func connect(to endpoint: IBEndpoint) async throws -> AsyncThrowingStream<IBEvent, any Error> {
        try Task.checkCancellation()
        closeSocket()
        session += 1
        let session = self.session

        let connection = try Self.makeSocket(to: endpoint)
        let (events, continuation) = AsyncThrowingStream.makeStream(of: IBEvent.self)
        let (states, stateContinuation) = AsyncStream.makeStream(of: NetworkChannel<TCP>.State.self)
        connection.onStateUpdate { _, state in
            continuation.yield(.transport(IBTransportState(state)))
            stateContinuation.yield(state)
        }
        self.connection = connection
        // Installed before anything can finish the stream, and scoped to this
        // session: a late teardown from an older stream must not kill a newer one.
        continuation.onTermination = { _ in
            Task { await self.closeSocket(session: session) }
        }

        do {
            defer { stateContinuation.finish() }
            let (version, connectionTime) = try await Self.handshake(on: connection, states: states, timeout: handshakeTimeout)
            guard version >= .clientMinimum else {
                throw IBProtocolError.unsupportedServerVersion(version.rawValue)
            }
            // The actor is reentrant across the awaits above; if another `connect`
            // took over meanwhile, `self.connection` is no longer this socket.
            guard session == self.session else { throw CancellationError() }
            serverVersion = version

            // Claim the client ID. TWS then pushes nextValidId, managedAccounts
            // and farm-status notices without being asked.
            try await send(.startAPI(clientID: endpoint.clientID))
            guard session == self.session else { throw CancellationError() }
            continuation.yield(.connected(serverVersion: version, connectionTime: connectionTime))

            let onSubscriptionsLost: @Sendable () async -> Void = { [weak self] in
                await self?.replayStreamingRequests(session: session)
            }
            let reader = SessionReader(
                connection: connection,
                decoder: IBMessageDecoder(serverVersion: version),
                registry: registry,
                session: session,
                clientID: endpoint.clientID,
                continuation: continuation,
                onSubscriptionsLost: onSubscriptionsLost
            )
            readTask = Task { await reader.run() }
            for request in registry.adoptStreamingRequests(session: session) {
                try await send(request)
            }
        } catch {
            closeSocket(session: session)
            continuation.finish(throwing: error)
            throw error
        }

        return events
    }

    /// A connection that keeps itself alive: connects, and whenever the socket
    /// drops (TWS restarted, Mac asleep, network change) waits according to
    /// `policy` and connects again, emitting ``IBEvent/reconnecting(attempt:delay:reason:)``
    /// in between and ``IBEvent/connected(serverVersion:connectionTime:)`` for every new socket.
    ///
    /// The first connection is not retried, so a wrong host or port fails right away,
    /// unless `policy` sets ``IBReconnectPolicy/retriesFirstConnection`` (for resuming
    /// a session that was already reconnecting).
    /// The stream throws once retrying stops, either because the policy gave up or
    /// because retrying cannot help (client ID in use). Ending iteration disconnects.
    /// A newer call to `sessions` or ``disconnect()`` supersedes this one.
    public func sessions(to endpoint: IBEndpoint, policy: IBReconnectPolicy = .standard) -> AsyncThrowingStream<IBEvent, any Error> {
        supervisor?.cancel()
        supervision += 1
        let supervision = self.supervision
        let (events, continuation) = AsyncThrowingStream.makeStream(of: IBEvent.self)
        continuation.onTermination = { _ in
            Task { await self.endSupervision(supervision) }
        }
        supervisor = Task {
            await self.supervise(endpoint: endpoint, policy: policy, into: continuation)
        }
        return events
    }

    /// Closes the socket, stops reconnecting and ends every outstanding request.
    public func disconnect() {
        supervisor?.cancel()
        supervisor = nil
        supervision += 1
        closeSocket()
        registry.finishAll(throwing: IBProtocolError.notConnected)
    }

    @concurrent
    nonisolated private func supervise(
        endpoint: IBEndpoint,
        policy: IBReconnectPolicy,
        into continuation: AsyncThrowingStream<IBEvent, any Error>.Continuation
    ) async {
        var attempt = 0
        var hasConnected = policy.retriesFirstConnection
        while !Task.isCancelled {
            let failure: any Error
            do {
                let events = try await connect(to: endpoint)
                let connectedAt = ContinuousClock.now
                hasConnected = true
                do {
                    for try await event in events {
                        continuation.yield(event)
                    }
                    failure = IBProtocolError.connectionClosed
                } catch {
                    failure = error
                }
                if ContinuousClock.now - connectedAt >= policy.stableSessionDuration {
                    attempt = 0
                }
            } catch {
                failure = error
            }
            if Task.isCancelled { break }

            attempt += 1
            guard hasConnected, Self.isRetryable(failure), let delay = policy.delay(forAttempt: attempt) else {
                continuation.finish(throwing: failure)
                return
            }
            continuation.yield(.reconnecting(attempt: attempt, delay: delay, reason: String(describing: failure)))
            do {
                try await Task.sleep(for: delay)
            } catch {
                break
            }
        }
        continuation.finish()
    }

    nonisolated private static func isRetryable(_ error: any Error) -> Bool {
        switch error as? IBProtocolError {
        case .clientIDInUse, .invalidEndpoint, .unsupportedServerVersion: false
        default: true
        }
    }

    private func endSupervision(_ supervision: Int) {
        guard supervision == self.supervision else { return }
        disconnect()
    }

    // MARK: - Requests

    /// Sends a request, pacing all outbound traffic to TWS's 50 messages/second limit.
    public func send(_ request: IBRequest) async throws {
        guard let connection, let serverVersion else { throw IBProtocolError.notConnected }
        let slot = rateLimiter.reserve()
        if slot > .now {
            try await Task.sleep(until: slot, clock: .continuous)
        }
        try await connection.send(IBFrame.encode(request.payload(for: serverVersion)))
    }

    /// Looks up every contract matching `contract`. Ambiguous queries return several
    /// matches. TWS answers an unknown instrument with error 200, which throws
    /// ``IBProtocolError/requestFailed(code:message:)``. Throws `CancellationError`
    /// when the calling task is cancelled, rather than returning a partial list.
    public func contractDetails(for contract: IBContract) async throws -> [IBContractDetails] {
        let responses = try await responses { .requestContractDetails(requestID: $0, contract: contract) }
        var matches: [IBContractDetails] = []
        for try await event in responses {
            if case let .contractDetails(_, details) = event {
                matches.append(details)
            }
        }
        // A cancelled consumer ends iteration early without an error; don't pass
        // off the matches received so far as the complete answer.
        try Task.checkCancellation()
        return matches
    }

    /// Sends a request under a fresh request ID and returns the events that answer it.
    ///
    /// The stream finishes after the response's end marker, throws
    /// ``IBProtocolError/requestFailed(code:message:)`` when TWS rejects the request,
    /// and throws ``IBProtocolError/connectionClosed`` if a one-shot request's socket
    /// drops. Streaming requests are replayed on reconnect instead. Ending iteration
    /// early sends `cancel`, if given.
    func responses(
        to makeRequest: (Int) -> IBRequest,
        cancel makeCancel: ((Int) -> IBRequest)? = nil,
        isStreaming: Bool = false
    ) async throws -> AsyncThrowingStream<IBEvent, any Error> {
        guard connection != nil else { throw IBProtocolError.notConnected }
        let id = registry.makeID()
        let request = makeRequest(id)
        let (responses, continuation) = AsyncThrowingStream.makeStream(of: IBEvent.self)
        continuation.onTermination = { [registry] _ in
            // Still registered means TWS hasn't finished the response: the consumer left early.
            guard let cancel = registry.remove(id)?.cancel else { return }
            Task { try? await self.send(cancel) }
        }
        registry.register(id, .init(request: request, cancel: makeCancel?(id), isStreaming: isStreaming, session: session, continuation: continuation))
        do {
            try await send(request)
        } catch {
            registry.remove(id)?.continuation.finish(throwing: error)
            throw error
        }
        return responses
    }

    /// Number of requests awaiting a response or holding a subscription.
    var activeRequestCount: Int { registry.activeCount }

    // MARK: - Teardown

    /// Drops the socket. `NetworkConnection` closes once its last reference goes
    /// away. One-shot requests sent on it fail; streaming ones wait for replay.
    private func closeSocket() {
        readTask?.cancel()
        readTask = nil
        connection = nil
        serverVersion = nil
        registry.socketClosed(session: session, error: IBProtocolError.connectionClosed)
    }

    /// Closes only if `session` is still the current one.
    private func closeSocket(session: Int) {
        guard session == self.session else { return }
        closeSocket()
    }

    /// Re-sends streaming requests after TWS reports 1101 ("connectivity restored,
    /// data lost"): the socket survived, but TWS dropped every subscription.
    private func replayStreamingRequests(session: Int) async {
        guard session == self.session else { return }
        for request in registry.adoptStreamingRequests(session: session) {
            try? await send(request)
        }
    }

    // MARK: - Reading

    private static func makeSocket(to endpoint: IBEndpoint) throws -> NetworkConnection<TCP> {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw IBProtocolError.invalidEndpoint(host: endpoint.host, port: endpoint.port)
        }
        return NetworkConnection(to: .hostPort(host: NWEndpoint.Host(endpoint.host), port: port)) {
            // Keepalive notices a peer that vanished without closing (Mac asleep,
            // Wi-Fi gone) within about 35 s; TWS itself sends nothing while idle.
            TCP().noDelay(true).keepalive(idleTimeInSeconds: 20, count: 3, intervalInSeconds: 5)
        }
    }

    /// Sends the client hello and reads the server's version and clock.
    ///
    /// Races the exchange against socket trouble and a timeout: when nothing is
    /// listening, `NetworkConnection` parks in `waiting(ECONNREFUSED)` and `send`
    /// suspends until the task is cancelled, so neither would ever fail by itself.
    @concurrent
    private static func handshake(
        on connection: NetworkConnection<TCP>,
        states: AsyncStream<NetworkChannel<TCP>.State>,
        timeout: Duration
    ) async throws -> (IBServerVersion, String) {
        try await withThrowingTaskGroup(of: (IBServerVersion, String)?.self) { group in
            group.addTask {
                // "API\0" followed by our supported version range as the first frame.
                var hello = IBFrame.apiPrefix
                hello.append(IBFrame.encode(Data(IBServerVersion.handshakeRange.utf8)))
                try await connection.send(hello)

                var reader = IBFieldReader(payload: try await readFrame(from: connection))
                return (IBServerVersion(try reader.int()), try reader.string())
            }
            group.addTask {
                for await state in states {
                    switch state {
                    case let .waiting(error), let .failed(error):
                        throw IBProtocolError.connectionUnavailable(describe(error))
                    default:
                        continue
                    }
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw IBProtocolError.handshakeTimedOut
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let result { return result }
            }
            throw CancellationError()
        }
    }

    fileprivate static func readFrame(from connection: NetworkConnection<TCP>) async throws -> Data {
        // Read the header as bytes: `receive(as: UInt32.self)` traps when the peer
        // closes the socket, because it loads from the empty end-of-stream buffer.
        let length = IBFrame.payloadLength(header: try await receive(exactly: IBFrame.headerLength, from: connection))
        guard length <= IBFrame.maximumLength else { throw IBProtocolError.frameTooLarge(length) }
        guard length > 0 else { return Data() }
        return try await receive(exactly: length, from: connection)
    }

    /// `receive(exactly:)` returns short (usually empty) content instead of throwing
    /// when the peer closes the socket or the receiving task is cancelled.
    private static func receive(exactly count: Int, from connection: NetworkConnection<TCP>) async throws -> Data {
        let content = try await connection.receive(exactly: count).content
        guard content.count == count else {
            try Task.checkCancellation()
            throw IBProtocolError.connectionClosed
        }
        return content
    }

    nonisolated private static func describe(_ error: NWError) -> String {
        if case let .posix(code) = error {
            return String(cString: strerror(code.rawValue))
        }
        return String(describing: error)
    }
}

/// The inbound half of one socket: reads frames, decodes them off the actor,
/// routes request responses through the registry and forwards the rest.
private struct SessionReader: Sendable {
    let connection: NetworkConnection<TCP>
    let decoder: IBMessageDecoder
    let registry: IBRequestRegistry
    let session: Int
    let clientID: Int
    let continuation: AsyncThrowingStream<IBEvent, any Error>.Continuation
    let onSubscriptionsLost: @Sendable () async -> Void

    @concurrent
    func run() async {
        do {
            while true {
                try Task.checkCancellation()
                let payload = try await IBConnection.readFrame(from: connection)
                let event: IBEvent
                do {
                    event = try decoder.decode(payload)
                } catch {
                    // Frames are length-prefixed, so one message IBKit can't decode doesn't
                    // desync the stream: pass it on raw instead of dropping the socket.
                    // It may have answered a pending one-shot request, which would then
                    // never complete, so fail those (there are no request timeouts).
                    registry.socketClosed(session: session, error: error)
                    continuation.yield(Self.undecodable(payload))
                    continue
                }
                if registry.route(event) { continue }
                continuation.yield(event)

                guard case let .notice(notice) = event else { continue }
                if notice.code == 326 {
                    // TWS closes the socket right after; reconnecting would collide again.
                    throw IBProtocolError.clientIDInUse(clientID)
                }
                if notice.connectivity == .restored(dataLost: true) {
                    // Off the read loop: replaying waits on the outbound rate limit.
                    Task { await onSubscriptionsLost() }
                }
            }
        } catch is CancellationError {
            registry.socketClosed(session: session, error: IBProtocolError.connectionClosed)
            continuation.finish()
        } catch {
            registry.socketClosed(session: session, error: error)
            continuation.finish(throwing: error)
        }
    }

    private static func undecodable(_ payload: Data) -> IBEvent {
        let fields = IBFieldReader(payload: payload).fields
        return .unhandled(messageID: fields.first.flatMap { Int($0) } ?? -1, fields: Array(fields.dropFirst()))
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
