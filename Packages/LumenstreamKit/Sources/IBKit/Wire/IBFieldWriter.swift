import Foundation

/// Builds the payload of one TWS API message: a run of NUL-terminated ASCII fields.
///
/// The length prefix is added separately by ``IBFrame``.
public struct IBFieldWriter: Sendable {
    public private(set) var payload = Data()

    public init() {}

    public mutating func append(_ value: String) {
        payload.append(contentsOf: value.utf8)
        payload.append(0)
    }

    public mutating func append(_ value: Int) {
        append(String(value))
    }

    /// Unset optional numbers are sent as empty fields.
    public mutating func append(_ value: Int?) {
        append(value.map(String.init) ?? "")
    }

    public mutating func append(_ value: Double) {
        append(String(value))
    }

    public mutating func append(_ value: Double?) {
        append(value.map { String($0) } ?? "")
    }

    /// Booleans travel as `0` / `1`.
    public mutating func append(_ value: Bool) {
        append(value ? 1 : 0)
    }

    public mutating func append(_ id: IBOutboundMessageID) {
        append(id.rawValue)
    }
}
