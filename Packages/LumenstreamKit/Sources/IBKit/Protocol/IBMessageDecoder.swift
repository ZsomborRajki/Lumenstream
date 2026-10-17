import Foundation

/// Turns inbound payloads into ``IBEvent`` values for one negotiated server version.
///
/// Pure and `Sendable`: it runs on the connection's read loop, off the main actor.
public struct IBMessageDecoder: Sendable {
    public let serverVersion: IBServerVersion

    public init(serverVersion: IBServerVersion) {
        self.serverVersion = serverVersion
    }

    public func decode(_ payload: Data) throws(IBProtocolError) -> IBEvent {
        var reader = IBFieldReader(payload: payload)
        let rawID = try reader.int()
        guard let id = IBInboundMessageID(rawValue: rawID) else {
            return .unhandled(messageID: rawID, fields: Array(reader.remaining))
        }

        switch id {
        case .nextValidID:
            try reader.skip() // message version
            return .nextValidOrderID(try reader.int())

        case .managedAccounts:
            try reader.skip()
            let accounts = try reader.string()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .managedAccounts(accounts)

        case .currentTime:
            try reader.skip()
            return .currentTime(Date(timeIntervalSince1970: TimeInterval(try reader.int())))

        case .errorMessage:
            return .notice(try decodeNotice(&reader))

        default:
            return .unhandled(messageID: rawID, fields: Array(reader.remaining))
        }
    }

    private func decodeNotice(_ reader: inout IBFieldReader) throws(IBProtocolError) -> IBNotice {
        if serverVersion < .errorTime {
            try reader.skip() // message version
        }
        let requestID = try reader.int()
        let code = try reader.int()
        let isEscaped = serverVersion >= .encodeMessageASCII7
        let rawMessage = try reader.string()
        let message = isEscaped ? Self.unescapingUnicode(rawMessage) : rawMessage
        let rawRejectJSON = serverVersion >= .advancedOrderReject ? try reader.string() : ""
        let rejectJSON = isEscaped ? Self.unescapingUnicode(rawRejectJSON) : rawRejectJSON
        let timeMillis = serverVersion >= .errorTime ? try reader.optionalInt() : nil
        return IBNotice(
            requestID: requestID,
            code: code,
            message: message,
            advancedOrderRejectJSON: rejectJSON.isEmpty ? nil : rejectJSON,
            time: timeMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        )
    }

    /// Reverses TWS's ASCII-7 encoding: every `\uXXXX` becomes that UTF-16 code unit
    /// (surrogate pairs recombine), anything else passes through untouched.
    static func unescapingUnicode(_ text: String) -> String {
        guard text.contains("\\u") else { return text }
        let source = Array(text.utf16)
        var units: [UInt16] = []
        units.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 6 <= source.count, source[index + 1] == 0x75 {
                let hex = String(decoding: source[(index + 2)..<(index + 6)], as: UTF16.self)
                if hex.allSatisfy(\.isHexDigit), let unit = UInt16(hex, radix: 16) {
                    units.append(unit)
                    index += 6
                    continue
                }
            }
            units.append(source[index])
            index += 1
        }
        return String(decoding: units, as: UTF16.self)
    }
}
