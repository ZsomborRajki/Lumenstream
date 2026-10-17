import Foundation
import Observation

/// Live price state for one instrument.
///
/// Each quote is its own `@Observable` object so a tick for one symbol only
/// invalidates the views reading *that* symbol, never the whole list. This
/// per-row isolation is the basis of the app's rendering strategy.
@Observable
public final class Quote: Identifiable {
    public let id: String
    public var last: Double?
    public var bid: Double?
    public var ask: Double?
    public var previousClose: Double?
    public var updatedAt: Date?

    public init(symbol: String, last: Double? = nil, bid: Double? = nil, ask: Double? = nil, previousClose: Double? = nil) {
        id = symbol
        self.last = last
        self.bid = bid
        self.ask = ask
        self.previousClose = previousClose
    }

    public var symbol: String { id }

    public var change: Double? {
        guard let last, let previousClose else { return nil }
        return last - previousClose
    }

    public var changePercent: Double? {
        guard let change, let previousClose, previousClose != 0 else { return nil }
        return change / previousClose
    }
}
