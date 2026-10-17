import Foundation

/// Identifies an instrument for TWS. Either a resolved ``contractID`` or a
/// symbol/security type/exchange/currency combination is enough for most requests.
public struct IBContract: Sendable, Hashable {
    /// IB's unique contract identifier (`conId`). `nil` until resolved.
    public var contractID: Int?
    public var symbol: String
    /// `STK`, `ETF` is still `STK`, `OPT`, `FUT`, `CASH`, `IND`, …
    public var securityType: String
    /// Routing exchange, usually `SMART`.
    public var exchange: String
    /// Listing exchange, used to disambiguate `SMART`-routed symbols (e.g. `NASDAQ`).
    public var primaryExchange: String
    public var currency: String
    public var localSymbol: String
    public var tradingClass: String
    public var multiplier: String

    public init(
        contractID: Int? = nil,
        symbol: String,
        securityType: String,
        exchange: String,
        primaryExchange: String = "",
        currency: String,
        localSymbol: String = "",
        tradingClass: String = "",
        multiplier: String = ""
    ) {
        self.contractID = contractID
        self.symbol = symbol
        self.securityType = securityType
        self.exchange = exchange
        self.primaryExchange = primaryExchange
        self.currency = currency
        self.localSymbol = localSymbol
        self.tradingClass = tradingClass
        self.multiplier = multiplier
    }

    /// A SMART-routed stock or ETF.
    public static func stock(_ symbol: String, exchange: String = "SMART", primaryExchange: String = "", currency: String = "USD") -> Self {
        Self(symbol: symbol, securityType: "STK", exchange: exchange, primaryExchange: primaryExchange, currency: currency)
    }
}

extension IBContract {
    /// Contract fields in the layout `reqContractDetails` uses.
    ///
    /// Options and futures fields (expiry, strike, right) are sent empty; Lumenstream
    /// only resolves stocks for now. Strike goes out as `0.0`, which TWS treats as unset.
    func encodeForContractDetails(into writer: inout IBFieldWriter, serverVersion: IBServerVersion) {
        writer.append(contractID ?? 0)
        writer.append(symbol)
        writer.append(securityType)
        writer.append("") // lastTradeDateOrContractMonth
        writer.append(0.0) // strike
        writer.append("") // right
        writer.append(multiplier)
        writer.append(exchange)
        writer.append(primaryExchange)
        writer.append(currency)
        writer.append(localSymbol)
        writer.append(tradingClass)
        writer.append(false) // includeExpired
        writer.append("") // secIdType
        writer.append("") // secId
        if serverVersion >= .bondIssuerID {
            writer.append("") // issuerId
        }
    }
}

/// The subset of a `contractData` message Lumenstream uses.
public struct IBContractDetails: Sendable, Hashable {
    public var contract: IBContract
    public var marketName: String
    public var longName: String
    public var minimumTick: Double
    public var priceMagnifier: Int
    /// Exchanges the contract can be routed to.
    public var validExchanges: [String]

    public init(contract: IBContract, marketName: String, longName: String, minimumTick: Double, priceMagnifier: Int, validExchanges: [String]) {
        self.contract = contract
        self.marketName = marketName
        self.longName = longName
        self.minimumTick = minimumTick
        self.priceMagnifier = priceMagnifier
        self.validExchanges = validExchanges
    }
}
