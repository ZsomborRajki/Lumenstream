import Foundation
import SwiftData

/// An instrument pinned to the watchlist. Live prices are not persisted;
/// they live in ``Quote`` objects on ``LumenstreamModel``.
@Model
public final class WatchlistSymbol {
    #Unique<WatchlistSymbol>([\.symbol, \.exchange])
    #Index<WatchlistSymbol>([\.sortIndex])

    public var symbol: String
    public var securityType: String
    public var exchange: String
    public var currency: String
    public var sortIndex: Int
    /// IB's contract ID, filled in once the contract has been resolved.
    public var contractID: Int?

    public init(symbol: String, securityType: String = "STK", exchange: String = "SMART", currency: String = "USD", sortIndex: Int, contractID: Int? = nil) {
        self.symbol = symbol
        self.securityType = securityType
        self.exchange = exchange
        self.currency = currency
        self.sortIndex = sortIndex
        self.contractID = contractID
    }
}

extension WatchlistSymbol {
    static func defaults() -> [WatchlistSymbol] {
        ["AAPL", "NVDA", "MSFT", "SPY"].enumerated().map { index, symbol in
            WatchlistSymbol(symbol: symbol, sortIndex: index)
        }
    }
}
