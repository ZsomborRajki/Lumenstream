import Foundation

/// A decoded inbound message, or a transport-level change.
public enum IBEvent: Sendable, Equatable {
    case connected(serverVersion: IBServerVersion, connectionTime: String)
    case transport(IBTransportState)
    case nextValidOrderID(Int)
    case managedAccounts([String])
    case currentTime(Date)
    case notice(IBNotice)
    /// A message IBKit does not decode yet. Kept so the app can log it.
    case unhandled(messageID: Int, fields: [String])
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
}
