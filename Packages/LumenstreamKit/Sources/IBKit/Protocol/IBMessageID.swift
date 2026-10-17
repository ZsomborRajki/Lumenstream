/// Message identifiers sent by TWS / IB Gateway (first field of every inbound payload).
///
/// Only the messages Lumenstream plans to consume are listed; anything else is
/// surfaced as ``IBEvent/unhandled(messageID:fields:)``.
public enum IBInboundMessageID: Int, Sendable {
    case tickPrice = 1
    case tickSize = 2
    case orderStatus = 3
    case errorMessage = 4
    case openOrder = 5
    case accountValue = 6
    case portfolioValue = 7
    case accountUpdateTime = 8
    case nextValidID = 9
    case contractData = 10
    case executionData = 11
    case managedAccounts = 15
    case historicalData = 17
    case tickGeneric = 45
    case tickString = 46
    case currentTime = 49
    case contractDataEnd = 52
    case accountDownloadEnd = 54
    case tickSnapshotEnd = 57
    case marketDataType = 58
    case position = 61
    case positionEnd = 62
    case accountSummary = 63
    case accountSummaryEnd = 64
    case tickRequestParameters = 81
    case historicalDataUpdate = 90
    case pnl = 94
    case pnlSingle = 95
}

/// Message identifiers the client sends to TWS / IB Gateway.
public enum IBOutboundMessageID: Int, Sendable {
    case requestMarketData = 1
    case cancelMarketData = 2
    case requestAccountUpdates = 6
    case requestIDs = 8
    case requestContractData = 9
    case requestManagedAccounts = 17
    case requestHistoricalData = 20
    case cancelHistoricalData = 25
    case requestCurrentTime = 49
    case requestMarketDataType = 59
    case requestPositions = 61
    case requestAccountSummary = 62
    case cancelAccountSummary = 63
    case cancelPositions = 64
    case startAPI = 71
    case requestMatchingSymbols = 81
    case requestPnL = 92
    case cancelPnL = 93
}
