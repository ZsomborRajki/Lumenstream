import Foundation

/// Sequentially decodes the NUL-terminated fields of one TWS API message payload.
public struct IBFieldReader: Sendable {
    public let fields: [String]
    public private(set) var position = 0

    public init(payload: Data) {
        var fields = payload
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        // Every field is NUL-terminated, so splitting leaves one empty tail element.
        if fields.last == "" { fields.removeLast() }
        self.fields = fields
    }

    public var isAtEnd: Bool { position >= fields.count }

    /// The fields that have not been consumed yet.
    public var remaining: ArraySlice<String> { fields[min(position, fields.count)...] }

    public mutating func string() throws(IBProtocolError) -> String {
        guard position < fields.count else {
            throw .unexpectedEndOfMessage(field: position)
        }
        defer { position += 1 }
        return fields[position]
    }

    /// Empty fields decode as `0`, matching the reference client.
    public mutating func int() throws(IBProtocolError) -> Int {
        let raw = try string()
        if raw.isEmpty { return 0 }
        guard let value = Int(raw) else { throw .malformedField(raw, expected: "Int") }
        return value
    }

    /// Empty fields decode as `nil` ("unset" in IB terms).
    public mutating func optionalInt() throws(IBProtocolError) -> Int? {
        let raw = try string()
        if raw.isEmpty { return nil }
        guard let value = Int(raw) else { throw .malformedField(raw, expected: "Int") }
        return value
    }

    public mutating func double() throws(IBProtocolError) -> Double {
        try optionalDouble() ?? 0
    }

    public mutating func optionalDouble() throws(IBProtocolError) -> Double? {
        let raw = try string()
        if raw.isEmpty { return nil }
        guard let value = Double(raw) else { throw .malformedField(raw, expected: "Double") }
        return value
    }

    public mutating func bool() throws(IBProtocolError) -> Bool {
        try int() != 0
    }

    public mutating func skip(_ count: Int = 1) throws(IBProtocolError) {
        guard position + count <= fields.count else {
            throw .unexpectedEndOfMessage(field: fields.count)
        }
        position += count
    }
}
