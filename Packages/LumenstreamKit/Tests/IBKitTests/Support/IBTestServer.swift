import Foundation
import Network
import Synchronization

@testable import IBKit

/// A scripted stand-in for TWS on 127.0.0.1, built on `NetworkListener`.
///
/// Every accepted socket runs `script` with its zero-based index, so a test can
/// play a different part per connection (e.g. drop the first one to simulate a
/// TWS restart). Returning from the script closes that socket.
final class IBTestServer: Sendable {
    typealias Script = @Sendable (_ peer: IBTestPeer, _ index: Int) async throws -> Void

    let endpoint: IBEndpoint
    private let task: Task<Void, any Error>
    private let counter = Locked(0)

    var acceptedCount: Int { counter.value }

    init(clientID: Int = 7, script: @escaping Script) async throws {
        let listener = try NetworkListener(using: .parameters { TCP() }.localEndpoint(.hostPort(host: "127.0.0.1", port: 0)))
        let counter = counter
        task = Task {
            try await listener.run { connection in
                let index = counter.withLock { count in
                    defer { count += 1 }
                    return count
                }
                try await script(IBTestPeer(connection: connection), index)
            }
        }
        var port: UInt16 = 0
        for _ in 0..<200 where port == 0 {
            port = listener.port?.rawValue ?? 0
            if port == 0 { try await Task.sleep(for: .milliseconds(10)) }
        }
        guard port != 0 else { throw IBProtocolError.notConnected }
        endpoint = IBEndpoint(host: "127.0.0.1", port: port, clientID: clientID)
    }

    deinit { task.cancel() }
}

/// The server side of one socket, speaking the TWS framing.
struct IBTestPeer: Sendable {
    let connection: NetworkConnection<TCP>

    /// Plays the server half of the handshake and returns the `startApi` fields.
    @discardableResult
    func acceptHandshake(serverVersion: Int = 176) async throws -> [String] {
        let prefix = try await connection.receive(exactly: 4).content
        guard prefix == IBFrame.apiPrefix else {
            throw IBProtocolError.malformedField(String(bytes: prefix, encoding: .utf8) ?? "", expected: "API\\0")
        }
        _ = try await readFields() // "v100..176"
        try await send("\(serverVersion)", "20261017 10:00:00 CET")
        return try await readFields()
    }

    func readFields() async throws -> [String] {
        let header = try await connection.receive(exactly: IBFrame.headerLength).content
        guard header.count == IBFrame.headerLength else { throw IBProtocolError.connectionClosed }
        let length = IBFrame.payloadLength(header: header)
        let payload = length > 0 ? try await connection.receive(exactly: length).content : Data()
        return IBFieldReader(payload: payload).fields
    }

    func send(_ fields: String...) async throws {
        try await send(fields: fields)
    }

    func send(fields: [String]) async throws {
        try await connection.send(IBFrame.encode(Data(fields.map { $0 + "\0" }.joined().utf8)))
    }

    /// Keeps the socket open until the test tears the server down.
    func hold() async {
        try? await Task.sleep(for: .seconds(60))
    }
}

/// A `Mutex` that closures can capture: the box is shared, the lock isn't copied.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value { mutex.withLock { $0 } }

    func withLock<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        mutex.withLock { body(&$0) }
    }
}
