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
    public static let clientMinimum = Self(100)

    /// Highest version we advertise. Deliberately capped below the protobuf-era
    /// versions so the server stays on the classic text protocol until IBKit has
    /// decoders for the newer layouts. See Docs/IBIntegration.md, "Version strategy".
    public static let clientMaximum = Self(176)

    /// Text sent in the handshake, e.g. `v100..176`.
    public static var handshakeRange: String {
        "v\(clientMinimum.rawValue)..\(clientMaximum.rawValue)"
    }
}

/// Server versions that change message layouts IBKit cares about.
/// Values mirror the `MIN_SERVER_VER_*` constants in the reference client's
/// `server_versions.py` (anything below ``clientMinimum`` is always available and not listed).
extension IBServerVersion {
    /// Contract data gains an (unused) market-data size multiplier field.
    public static let mdSizeMultiplier = IBServerVersion(110)
    /// Error message text, contract long names and reject JSON escape non-ASCII
    /// characters as `\uXXXX`.
    public static let encodeMessageASCII7 = IBServerVersion(153)
    /// Contract data drops its message version field and the size multiplier.
    public static let sizeRules = IBServerVersion(164)
    /// Error messages carry an advanced-order-reject JSON field.
    public static let advancedOrderReject = IBServerVersion(166)
    /// Contract requests carry a bond issuer ID field.
    public static let bondIssuerID = IBServerVersion(176)
    /// Contract data carries a separate last trade date field.
    public static let lastTradeDate = IBServerVersion(182)
    /// Error messages drop their version field and gain an error timestamp.
    public static let errorTime = IBServerVersion(194)
    /// First version that switches messages to protobuf payloads.
    public static let protobuf = IBServerVersion(201)
}
