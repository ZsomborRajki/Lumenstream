/// Failures raised while talking the TWS API protocol.
public enum IBProtocolError: Error, Sendable, Equatable {
    case unexpectedEndOfMessage(field: Int)
    case malformedField(String, expected: String)
    case frameTooLarge(Int)
    case unsupportedServerVersion(Int)
    case invalidEndpoint(host: String, port: UInt16)
    case notConnected
}
