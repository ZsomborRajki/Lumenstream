import Foundation
import Testing
@testable import IBKit

@Suite("Wire format")
struct WireTests {
    @Test func frameHasBigEndianLengthPrefix() {
        let frame = IBFrame.encode(Data("abc".utf8))
        #expect(Array(frame) == [0, 0, 0, 3, 0x61, 0x62, 0x63])
    }

    @Test func writerAndReaderRoundTrip() throws {
        var writer = IBFieldWriter()
        writer.append("AAPL")
        writer.append(42)
        writer.append(Int?.none)
        writer.append(1.5)
        writer.append(true)

        var reader = IBFieldReader(payload: writer.payload)
        #expect(try reader.string() == "AAPL")
        #expect(try reader.int() == 42)
        #expect(try reader.optionalInt() == nil)
        #expect(try reader.double() == 1.5)
        #expect(try reader.bool())
        #expect(reader.isAtEnd)
    }

    @Test func readerPreservesTrailingEmptyField() {
        let reader = IBFieldReader(payload: Data("x\0\0".utf8))
        #expect(reader.fields == ["x", ""])
    }

    @Test func readerThrowsPastEnd() {
        var reader = IBFieldReader(payload: Data("1\0".utf8))
        _ = try? reader.int()
        #expect(throws: IBProtocolError.unexpectedEndOfMessage(field: 1)) {
            try reader.string()
        }
    }

    @Test func startAPIEncoding() {
        let payload = IBRequest.startAPI(clientID: 7).payload(for: .clientMaximum)
        #expect(payload == Data("71\u{0}2\u{0}7\u{0}\u{0}".utf8))
    }

    @Test func rateLimiterSpacesSlots() {
        var limiter = IBRateLimiter(messagesPerSecond: 50)
        let now = ContinuousClock.now
        let first = limiter.reserve(now: now)
        let second = limiter.reserve(now: now)
        #expect(first == now)
        #expect(second == now + .milliseconds(20))
    }
}

@Suite("Decoding")
struct DecoderTests {
    private func payload(_ fields: String...) -> Data {
        Data(fields.map { $0 + "\0" }.joined().utf8)
    }

    @Test func nextValidID() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        #expect(try decoder.decode(payload("9", "1", "1001")) == .nextValidOrderID(1001))
    }

    @Test func managedAccounts() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        #expect(try decoder.decode(payload("15", "1", "DU111,DU222,")) == .managedAccounts(["DU111", "DU222"]))
    }

    @Test func noticeBeforeErrorTime() throws {
        let decoder = IBMessageDecoder(serverVersion: IBServerVersion(176))
        let event = try decoder.decode(payload("4", "2", "-1", "2104", "Market data farm connection is OK:usfarm", ""))
        guard case let .notice(notice) = event else {
            Issue.record("Expected a notice, got \(event)")
            return
        }
        #expect(notice.code == 2104)
        #expect(notice.requestID == -1)
        #expect(notice.isInformational)
        #expect(notice.advancedOrderRejectJSON == nil)
    }

    @Test func noticeWithErrorTime() throws {
        let decoder = IBMessageDecoder(serverVersion: .errorTime)
        let event = try decoder.decode(payload("4", "12", "200", "No security definition", "", "1700000000000"))
        guard case let .notice(notice) = event else {
            Issue.record("Expected a notice, got \(event)")
            return
        }
        #expect(notice.code == 200)
        #expect(notice.time == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func noticeTextIsUnicodeUnescaped() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        let event = try decoder.decode(payload("4", "2", "-1", "2104", "Piaci adatfarm kapcsolat rendben: \\u00e1\\ud83d\\ude00", ""))
        guard case let .notice(notice) = event else {
            Issue.record("Expected a notice, got \(event)")
            return
        }
        #expect(notice.message == "Piaci adatfarm kapcsolat rendben: \u{e1}\u{1F600}")
    }

    @Test func unescapeLeavesMalformedSequences() {
        #expect(IBMessageDecoder.unescapingUnicode("C:\\users \\u12") == "C:\\users \\u12")
    }

    @Test func unknownMessageIsPreserved() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        #expect(try decoder.decode(payload("999", "a", "b")) == .unhandled(messageID: 999, fields: ["a", "b"]))
    }
}
