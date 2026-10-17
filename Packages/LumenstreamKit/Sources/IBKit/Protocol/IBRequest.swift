import Foundation

/// A message the client can send. Each case knows how to encode itself for a
/// given negotiated ``IBServerVersion``.
///
/// Phase 1 covers the session bootstrap; market data, account and historical
/// requests are added in later phases (see Docs/IBIntegration.md).
public enum IBRequest: Sendable, Hashable {
    /// Sent once, right after the version handshake.
    case startAPI(clientID: Int, optionalCapabilities: String = "")
    case requestCurrentTime
    case requestManagedAccounts
    case requestIDs(count: Int = 1)
    case requestMarketDataType(IBMarketDataType)

    public func payload(for serverVersion: IBServerVersion) -> Data {
        var writer = IBFieldWriter()
        switch self {
        case let .startAPI(clientID, optionalCapabilities):
            writer.append(IBOutboundMessageID.startAPI)
            writer.append(2) // message version
            writer.append(clientID)
            writer.append(optionalCapabilities)
        case .requestCurrentTime:
            writer.append(IBOutboundMessageID.requestCurrentTime)
            writer.append(1)
        case .requestManagedAccounts:
            writer.append(IBOutboundMessageID.requestManagedAccounts)
            writer.append(1)
        case let .requestIDs(count):
            writer.append(IBOutboundMessageID.requestIDs)
            writer.append(1)
            writer.append(count)
        case let .requestMarketDataType(type):
            writer.append(IBOutboundMessageID.requestMarketDataType)
            writer.append(1)
            writer.append(type.rawValue)
        }
        return writer.payload
    }
}

/// Which market data feed TWS should serve.
public enum IBMarketDataType: Int, Sendable, Hashable, CaseIterable {
    case live = 1
    case frozen = 2
    /// Free, 15–20 minute delayed data. Works without market data subscriptions,
    /// which makes it the default for paper accounts.
    case delayed = 3
    case delayedFrozen = 4
}
