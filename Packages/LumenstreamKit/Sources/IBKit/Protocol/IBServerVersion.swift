/// The protocol version negotiated during the handshake.
///
/// The server picks the highest version both sides support, and that number gates
/// the field layout of nearly every message, so encoders and decoders take it as input.
public struct IBServerVersion: Sendable, Hashable, Comparable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Lowest version we accept: the first one using length-prefixed framing.
    public static let clientMinimum = IBServerVersion(100)

    /// Highest version we advertise. Deliberately capped below the protobuf-era
    /// versions so the server stays on the classic text protocol until IBKit has
    /// decoders for the newer layouts. See Docs/IBIntegration.md, "Version strategy".
    public static let clientMaximum = IBServerVersion(176)

    /// Text sent in the handshake, e.g. `v100..176`.
    public static var handshakeRange: String {
        "v\(clientMinimum.rawValue)..\(clientMaximum.rawValue)"
    }
}

/// Server versions that change message layouts IBKit cares about.
/// Values mirror the `MIN_SERVER_VER_*` constants in the reference client
/// (anything below ``clientMinimum`` is always available and not listed).
extension IBServerVersion {
    /// Error message text (and reject JSON) escape non-ASCII characters as `\uXXXX`.
    public static let encodeMessageASCII7 = IBServerVersion(161)
    /// Error messages carry an advanced-order-reject JSON field.
    public static let advancedOrderReject = IBServerVersion(166)
    /// Error messages drop their version field and gain an error timestamp.
    public static let errorTime = IBServerVersion(194)
}
