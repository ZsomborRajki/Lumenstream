import Foundation

/// The app-facing lifecycle of the TWS session.
///
/// Value types in this main-actor-by-default module are marked `nonisolated`
/// so their conformances can be used from any isolation domain.
nonisolated public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(serverVersion: Int)
    /// The API socket is up, but TWS lost its own link to IB's servers
    /// (notice 1100). Data resumes by itself once TWS reconnects.
    case brokerUnreachable(serverVersion: Int)
    /// The socket dropped (TWS restarted, Mac asleep, network change). The next
    /// attempt starts at `retryAt`.
    case reconnecting(attempt: Int, retryAt: Date, reason: String)
    case failed(String)

    /// Whether requests can be sent right now.
    public var isConnected: Bool {
        switch self {
        case .connected, .brokerUnreachable: true
        default: false
        }
    }

    /// Whether a session is open or being worked on, i.e. there is something to disconnect.
    public var isActive: Bool {
        switch self {
        case .disconnected, .failed: false
        default: true
        }
    }
}

/// An error or status message reported by TWS, mapped out of IBKit so the UI
/// layer never depends on wire types.
nonisolated public struct ServerNotice: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let requestID: Int
    public let code: Int
    public let message: String
    public let receivedAt: Date
    public let isInformational: Bool

    public init(requestID: Int, code: Int, message: String, receivedAt: Date = .now, isInformational: Bool) {
        id = UUID()
        self.requestID = requestID
        self.code = code
        self.message = message
        self.receivedAt = receivedAt
        self.isInformational = isInformational
    }
}
