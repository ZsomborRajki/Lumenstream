import Foundation

/// The app-facing lifecycle of the TWS session.
///
/// Value types in this main-actor-by-default module are marked `nonisolated`
/// so their conformances can be used from any isolation domain.
nonisolated public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(serverVersion: Int)
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
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
