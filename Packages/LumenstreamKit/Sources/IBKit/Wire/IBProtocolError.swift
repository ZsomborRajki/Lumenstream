/// Failures raised while talking the TWS API protocol.
public enum IBProtocolError: Error, Sendable, Equatable {
    case unexpectedEndOfMessage(field: Int)
    case malformedField(String, expected: String)
    case frameTooLarge(Int)
    case unsupportedServerVersion(Int)
    case invalidEndpoint(host: String, port: UInt16)
    case notConnected
    /// The socket could not reach TWS (refused, unreachable, no network).
    /// Network framework reports these as a `waiting` state rather than failing.
    case connectionUnavailable(String)
    /// TWS accepted the socket but did not finish the handshake in time.
    case handshakeTimedOut
    /// The peer closed the socket (TWS quit, restarted, or logged out).
    case connectionClosed
    /// Another API client already holds this client ID (TWS error 326).
    case clientIDInUse(Int)
    /// TWS answered a request with an error notice.
    case requestFailed(code: Int, message: String)
}

extension IBProtocolError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unexpectedEndOfMessage(field): "Message ended early at field \(field)"
        case let .malformedField(raw, expected): "Expected \(expected), got “\(raw)”"
        case let .frameTooLarge(length): "Frame of \(length) bytes exceeds the limit"
        case let .unsupportedServerVersion(version): "Server version \(version) is too old"
        case let .invalidEndpoint(host, port): "Invalid address \(host):\(port)"
        case .notConnected: "Not connected"
        case let .connectionUnavailable(reason): "Can't reach TWS: \(reason)"
        case .handshakeTimedOut: "TWS accepted the connection but didn't respond"
        case .connectionClosed: "TWS closed the connection"
        case let .clientIDInUse(clientID): "Client ID \(clientID) is already in use"
        case let .requestFailed(code, message): "Error \(code): \(message)"
        }
    }
}
