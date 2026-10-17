import Foundation

/// A decoded inbound message, or a transport-level change.
public enum IBEvent: Sendable, Equatable {
    case connected(serverVersion: IBServerVersion, connectionTime: String)
    case transport(IBTransportState)
    /// The socket dropped and ``IBConnection/sessions(to:policy:)`` will try
    /// again after `delay`. Followed by `.connected` once a new session is up.
    case reconnecting(attempt: Int, delay: Duration, reason: String)
    case nextValidOrderID(Int)
    case managedAccounts([String])
    case currentTime(Date)
    case notice(IBNotice)
    case contractDetails(requestID: Int, IBContractDetails)
    case contractDetailsEnd(requestID: Int)
    /// A message IBKit does not decode yet. Kept so the app can log it.
    case unhandled(messageID: Int, fields: [String])

    /// The request this event answers, for routing to the caller that sent it.
    /// Notices count only when they name a request (connection-wide ones use `-1`).
    var requestID: Int? {
        switch self {
        case let .contractDetails(requestID, _), let .contractDetailsEnd(requestID):
            requestID
        case let .notice(notice) where notice.requestID >= 0:
            notice.requestID
        default:
            nil
        }
    }

    /// Whether this is the last message of a finite response.
    var endsResponse: Bool {
        if case .contractDetailsEnd = self { true } else { false }
    }
}

/// Socket state, mirrored from Network framework without leaking its types.
public enum IBTransportState: Sendable, Equatable {
    case preparing
    case ready
    case waiting(String)
    case failed(String)
    case cancelled
}

/// TWS reports both errors and informational status (e.g. "market data farm
/// connection is OK") through the same error message.
public struct IBNotice: Sendable, Hashable {
    /// The request the notice refers to, or `-1` for connection-wide notices.
    public let requestID: Int
    public let code: Int
    public let message: String
    public let advancedOrderRejectJSON: String?
    public let time: Date?

    public init(requestID: Int, code: Int, message: String, advancedOrderRejectJSON: String? = nil, time: Date? = nil) {
        self.requestID = requestID
        self.code = code
        self.message = message
        self.advancedOrderRejectJSON = advancedOrderRejectJSON
        self.time = time
    }

    /// Codes 2100–2199 are status notices rather than failures.
    public var isInformational: Bool { (2100..<2200).contains(code) }

    /// Request-scoped codes that warn but leave the request running, such as
    /// 10167 "Displaying delayed market data".
    static let requestWarningCodes: Set<Int> = [10167]

    /// Whether this notice ends the request it names.
    var failsRequest: Bool {
        !isInformational && !Self.requestWarningCodes.contains(code)
    }

    /// The state of TWS's own link to IB's servers, for codes 1100–1102.
    /// The API socket stays up throughout; only data flow is affected.
    public var connectivity: IBConnectivity? {
        switch code {
        case 1100: .lost
        case 1101: .restored(dataLost: true)
        case 1102: .restored(dataLost: false)
        default: nil
        }
    }
}

/// Connectivity between TWS and IB's servers, as reported by notices 1100–1102.
public enum IBConnectivity: Sendable, Hashable {
    /// 1100: TWS lost its connection to IB.
    case lost
    /// 1101 (`dataLost`): restored, but market data subscriptions were dropped
    /// and must be re-requested. 1102: restored with subscriptions intact.
    case restored(dataLost: Bool)
}
