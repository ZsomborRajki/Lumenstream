import Foundation
import Testing

@testable import IBKit

private func payload(_ fields: String...) -> Data {
    payload(fields)
}

private func payload(_ fields: [String]) -> Data {
    Data(fields.map { $0 + "\0" }.joined().utf8)
}

@Suite("Contracts")
struct ContractTests {
    @Test func contractDetailsRequestAtV176() {
        let request = IBRequest.requestContractDetails(requestID: 42, contract: .stock("AAPL", primaryExchange: "NASDAQ"))
        let fields = IBFieldReader(payload: request.payload(for: .clientMaximum)).fields
        #expect(fields == [
            "9", "8", "42",
            "0", "AAPL", "STK", "", "0.0", "", "",
            "SMART", "NASDAQ", "USD", "", "",
            "0", "", "",
            "", // issuerId, from v176
        ])
    }

    @Test func contractDetailsRequestOmitsIssuerIDBeforeV176() {
        let request = IBRequest.requestContractDetails(requestID: 1, contract: .stock("SPY"))
        let fields = IBFieldReader(payload: request.payload(for: IBServerVersion(175))).fields
        #expect(fields.count == 18)
    }

    @Test func resolvedContractSendsItsID() {
        let contract = IBContract(contractID: 265_598, symbol: "AAPL", securityType: "STK", exchange: "SMART", currency: "USD")
        let fields = IBFieldReader(payload: IBRequest.requestContractDetails(requestID: 1, contract: contract).payload(for: .clientMaximum)).fields
        #expect(fields[3] == "265598")
    }

    @Test func contractDataAtV176() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        let event = try decoder.decode(payload([
            "10", "42", "AAPL", "STK", "", "0", "", "SMART", "USD", "AAPL", "NMS", "NMS", "265598", "0.01",
            "", "ACTIVETIM,AD,ALERT", "SMART,AMEX,NASDAQ", "1", "0", "APPLE INC", "NASDAQ",
            "", "Technology", "Computers", "Computers", "US/Eastern", "20261017:0400-20261017:2000", "…",
        ]))
        guard case let .contractDetails(requestID, details) = event else {
            Issue.record("Expected contract details, got \(event)")
            return
        }
        #expect(requestID == 42)
        #expect(details.contract == IBContract(
            contractID: 265_598,
            symbol: "AAPL",
            securityType: "STK",
            exchange: "SMART",
            primaryExchange: "NASDAQ",
            currency: "USD",
            localSymbol: "AAPL",
            tradingClass: "NMS"
        ))
        #expect(details.marketName == "NMS")
        #expect(details.longName == "APPLE INC")
        #expect(details.minimumTick == 0.01)
        #expect(details.validExchanges == ["SMART", "AMEX", "NASDAQ"])
        #expect(details.priceMagnifier == 1)
    }

    /// Before `sizeRules` the message carries a version field and, from v110,
    /// an unused size multiplier after the minimum tick.
    @Test func contractDataBeforeSizeRules() throws {
        let decoder = IBMessageDecoder(serverVersion: IBServerVersion(150))
        let event = try decoder.decode(payload([
            "10", "8", "3", "MSFT", "STK", "", "0", "", "SMART", "USD", "MSFT", "NMS", "NMS", "272093", "0.01",
            "100", "", "LMT,MKT", "SMART,NASDAQ", "1", "0", "MICROSOFT CORP", "NASDAQ",
        ]))
        guard case let .contractDetails(requestID, details) = event else {
            Issue.record("Expected contract details, got \(event)")
            return
        }
        #expect(requestID == 3)
        #expect(details.contract.contractID == 272_093)
        #expect(details.contract.primaryExchange == "NASDAQ")
        #expect(details.longName == "MICROSOFT CORP")
    }

    @Test func contractLongNameIsUnescaped() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        let event = try decoder.decode(payload([
            "10", "1", "NESN", "STK", "", "0", "", "EBS", "CHF", "NESN", "NESN", "NESN", "38709539", "0.02",
            "", "", "EBS", "1", "0", "NESTL\\u00c9 SA-REG", "EBS",
        ]))
        guard case let .contractDetails(_, details) = event else {
            Issue.record("Expected contract details, got \(event)")
            return
        }
        #expect(details.longName == "NESTLÉ SA-REG")
    }

    @Test func contractDataEnd() throws {
        let decoder = IBMessageDecoder(serverVersion: .clientMaximum)
        #expect(try decoder.decode(payload("52", "1", "42")) == .contractDetailsEnd(requestID: 42))
    }
}

@Suite("Notices")
struct NoticeTests {
    @Test func ascii7EscapingStartsAtV153() throws {
        let escaped = payload("4", "2", "-1", "2104", "\\u00e1")
        let event = try IBMessageDecoder(serverVersion: IBServerVersion(153)).decode(escaped)
        #expect(event == .notice(IBNotice(requestID: -1, code: 2104, message: "\u{e1}")))

        let raw = payload("4", "2", "-1", "2104", "\\u00e1")
        let olderEvent = try IBMessageDecoder(serverVersion: IBServerVersion(152)).decode(raw)
        #expect(olderEvent == .notice(IBNotice(requestID: -1, code: 2104, message: "\\u00e1")))
    }

    @Test(arguments: [
        (1100, IBConnectivity.lost),
        (1101, .restored(dataLost: true)),
        (1102, .restored(dataLost: false)),
    ])
    func connectivityCodes(code: Int, expected: IBConnectivity) {
        #expect(IBNotice(requestID: -1, code: code, message: "").connectivity == expected)
    }

    @Test func requestFailurePolicy() {
        #expect(IBNotice(requestID: 1, code: 200, message: "No security definition").failsRequest)
        #expect(!IBNotice(requestID: 1, code: 10167, message: "Displaying delayed market data").failsRequest)
        #expect(!IBNotice(requestID: 1, code: 2104, message: "Farm OK").failsRequest)
    }

    @Test func routingUsesRequestScopedNoticesOnly() {
        #expect(IBEvent.notice(IBNotice(requestID: -1, code: 2104, message: "")).requestID == nil)
        #expect(IBEvent.notice(IBNotice(requestID: 9, code: 200, message: "")).requestID == 9)
    }
}
