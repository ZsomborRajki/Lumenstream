import Foundation
import Testing

@testable import IBKit

/// End-to-end tests of `IBConnection` against ``IBTestServer``: real sockets,
/// no TWS required.
@Suite("Loopback", .timeLimit(.minutes(1)))
struct LoopbackTests {
    private static let fast = IBReconnectPolicy(initialDelay: .milliseconds(50), maximumDelay: .milliseconds(200))

    private static let appleData = [
        "10", "", "AAPL", "STK", "", "0", "", "SMART", "USD", "AAPL", "NMS", "NMS", "265598", "0.01",
        "", "", "SMART,NASDAQ", "1", "0", "APPLE INC", "NASDAQ",
    ]

    /// Connects and keeps draining the session stream: dropping the stream would
    /// close the socket.
    private static func open(_ connection: IBConnection, to endpoint: IBEndpoint) async throws -> Task<Void, any Error> {
        let events = try await connection.connect(to: endpoint)
        return Task { for try await _ in events {} }
    }

    @Test func handshakeAndBootstrap() async throws {
        let startAPI = Locked<[String]>([])
        let server = try await IBTestServer { peer, _ in
            let fields = try await peer.acceptHandshake()
            startAPI.withLock { $0 = fields }
            try await peer.send("9", "1", "1001")
            try await peer.send("15", "1", "DU111,DU222")
            try await peer.send("4", "2", "-1", "2104", "Market data farm connection is OK:usfarm", "")
            await peer.hold()
        }
        let connection = IBConnection()
        let events = try await connection.connect(to: server.endpoint)

        var decoded: [IBEvent] = []
        for try await event in events {
            if case .transport = event { continue }
            decoded.append(event)
            if case .notice = event { break }
        }
        #expect(decoded == [
            .connected(serverVersion: IBServerVersion(176), connectionTime: "20261017 10:00:00 CET"),
            .nextValidOrderID(1001),
            .managedAccounts(["DU111", "DU222"]),
            .notice(IBNotice(requestID: -1, code: 2104, message: "Market data farm connection is OK:usfarm")),
        ])
        #expect(startAPI.value == ["71", "2", "7", ""])
        await connection.disconnect()
    }

    @Test func contractDetailsRoundTrip() async throws {
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            let request = try await peer.readFields()
            guard request.first == "9", request[4] == "AAPL" else { return }
            var data = Self.appleData
            data[1] = request[2] // echo the request ID
            try await peer.send(fields: data)
            try await peer.send("52", "1", request[2])
            await peer.hold()
        }
        let connection = IBConnection()
        let session = try await Self.open(connection, to: server.endpoint)
        defer { session.cancel() }

        let matches = try await connection.contractDetails(for: .stock("AAPL"))
        #expect(matches.map(\.contract.contractID) == [265_598])
        #expect(matches.first?.longName == "APPLE INC")
        #expect(await connection.activeRequestCount == 0)
        await connection.disconnect()
    }

    @Test func requestErrorFailsTheCall() async throws {
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            let request = try await peer.readFields()
            try await peer.send("4", "2", request[2], "200", "No security definition has been found for the request", "")
            await peer.hold()
        }
        let connection = IBConnection()
        let session = try await Self.open(connection, to: server.endpoint)
        defer { session.cancel() }

        await #expect(throws: IBProtocolError.requestFailed(code: 200, message: "No security definition has been found for the request")) {
            try await connection.contractDetails(for: .stock("NOPE"))
        }
        await connection.disconnect()
    }

    @Test func pendingRequestFailsWhenTheSocketDrops() async throws {
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            _ = try await peer.readFields()
            // Returning closes the socket without answering.
        }
        let connection = IBConnection()
        let events = try await connection.connect(to: server.endpoint)
        let drain = Task { for try await _ in events {} }

        await #expect(throws: IBProtocolError.connectionClosed) {
            try await connection.contractDetails(for: .stock("AAPL"))
        }
        await #expect(throws: IBProtocolError.connectionClosed) {
            try await drain.value
        }
    }

    @Test func refusedConnectionFailsFast() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let connection = IBConnection()
        // Nothing listens on port 1; Network framework reports `waiting(ECONNREFUSED)`.
        await #expect {
            _ = try await connection.connect(to: IBEndpoint(host: "127.0.0.1", port: 1, clientID: 1))
        } throws: { error in
            if case .connectionUnavailable = error as? IBProtocolError { true } else { false }
        }
        #expect(clock.now - started < .seconds(5))
    }

    @Test func silentServerTimesOut() async throws {
        let server = try await IBTestServer { peer, _ in await peer.hold() }
        let connection = IBConnection(handshakeTimeout: .milliseconds(300))
        await #expect(throws: IBProtocolError.handshakeTimedOut) {
            _ = try await connection.connect(to: server.endpoint)
        }
    }

    /// The M1 exit criterion in miniature: TWS goes away mid-session and comes
    /// back. The session stream reports the drop, reconnects, and replays the
    /// streaming request under its original ID.
    @Test func sessionsSurviveARestart() async throws {
        let (replays, replayed) = AsyncStream.makeStream(of: [String].self)
        let server = try await IBTestServer { peer, index in
            try await peer.acceptHandshake()
            try await peer.send("15", "1", "DU\(index)")
            let request = try await peer.readFields()
            if index == 0 { return } // "TWS restarts"
            replayed.yield(request)
            await peer.hold()
        }
        let connection = IBConnection()
        var subscription: AsyncThrowingStream<IBEvent, any Error>?
        var subscriptionID = ""
        var log: [String] = []

        for try await event in await connection.sessions(to: server.endpoint, policy: Self.fast) {
            switch event {
            case .connected:
                log.append("connected")
                if subscription == nil {
                    subscription = try await connection.responses(
                        to: { subscriptionID = "\($0)"; return .requestContractDetails(requestID: $0, contract: .stock("SPY")) },
                        isStreaming: true
                    )
                }
            case let .managedAccounts(accounts):
                log.append(accounts.joined())
            case let .reconnecting(attempt, _, _):
                log.append("reconnecting \(attempt)")
            default:
                continue
            }
            if log.count == 5 { break }
        }

        #expect(log == ["connected", "DU0", "reconnecting 1", "connected", "DU1"])
        var iterator = replays.makeAsyncIterator()
        let replay = await iterator.next()
        #expect(replay?[2] == subscriptionID)
        #expect(replay?[4] == "SPY")
        #expect(server.acceptedCount == 2)
        await connection.disconnect()
        _ = subscription
    }

    @Test func clientIDCollisionStopsRetrying() async throws {
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            try await peer.send("4", "2", "-1", "326", "Unable to connect as the client id is already in use. Retry with a unique client id.", "")
        }
        let connection = IBConnection()
        await #expect(throws: IBProtocolError.clientIDInUse(7)) {
            for try await _ in await connection.sessions(to: server.endpoint, policy: Self.fast) {}
        }
        #expect(server.acceptedCount == 1)
    }

    @Test func dataLostNoticeReplaysSubscriptions() async throws {
        let (requests, received) = AsyncStream.makeStream(of: [String].self)
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            received.yield(try await peer.readFields())
            try await peer.send("4", "2", "-1", "1101", "Connectivity between IB and TWS has been restored - data lost.", "")
            received.yield(try await peer.readFields())
            await peer.hold()
        }
        let connection = IBConnection()
        let events = try await connection.connect(to: server.endpoint)
        let drain = Task { for try await _ in events {} }
        let subscription = try await connection.responses(
            to: { .requestContractDetails(requestID: $0, contract: .stock("QQQ")) },
            isStreaming: true
        )

        var iterator = requests.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first != nil)
        #expect(first == second)
        await connection.disconnect()
        drain.cancel()
        _ = subscription
    }

    @Test func leavingEarlySendsTheCancelRequest() async throws {
        let (requests, received) = AsyncStream.makeStream(of: [String].self)
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            while true { received.yield(try await peer.readFields()) }
        }
        let connection = IBConnection()
        let session = try await Self.open(connection, to: server.endpoint)
        defer { session.cancel() }

        let responses = try await connection.responses(
            to: { .requestContractDetails(requestID: $0, contract: .stock("IWM")) },
            cancel: { _ in .requestIDs(count: 99) }, // stand-in until cancelMktData exists
            isStreaming: true
        )
        let listener = Task { for try await _ in responses {} }
        var iterator = requests.makeAsyncIterator()
        _ = await iterator.next()
        listener.cancel()

        #expect(await iterator.next() == ["8", "1", "99"])
        #expect(await connection.activeRequestCount == 0)
        await connection.disconnect()
    }

    @Test func disconnectEndsStreamingRequests() async throws {
        let server = try await IBTestServer { peer, _ in
            try await peer.acceptHandshake()
            await peer.hold()
        }
        let connection = IBConnection()
        let session = try await Self.open(connection, to: server.endpoint)
        defer { session.cancel() }
        let responses = try await connection.responses(
            to: { .requestContractDetails(requestID: $0, contract: .stock("DIA")) },
            isStreaming: true
        )
        await connection.disconnect()
        await #expect(throws: IBProtocolError.notConnected) {
            for try await _ in responses {}
        }
    }
}
