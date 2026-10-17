import Foundation
import SwiftData

/// A saved TWS / IB Gateway endpoint.
@Model
public final class ConnectionProfile {
    #Unique<ConnectionProfile>([\.name])

    public var name: String
    public var host: String
    public var port: Int
    public var clientID: Int
    public var isPaperTrading: Bool
    public var createdAt: Date

    public init(name: String, host: String, port: Int, clientID: Int = 1, isPaperTrading: Bool, createdAt: Date = .now) {
        self.name = name
        self.host = host
        self.port = port
        self.clientID = clientID
        self.isPaperTrading = isPaperTrading
        self.createdAt = createdAt
    }
}

extension ConnectionProfile {
    /// IB's default socket ports for each product and account type.
    static func defaults() -> [ConnectionProfile] {
        let now = Date.now
        return [
            ConnectionProfile(name: "TWS Paper", host: "127.0.0.1", port: 7497, isPaperTrading: true, createdAt: now),
            ConnectionProfile(name: "Gateway Paper", host: "127.0.0.1", port: 4002, isPaperTrading: true, createdAt: now + 1),
            ConnectionProfile(name: "TWS Live", host: "127.0.0.1", port: 7496, isPaperTrading: false, createdAt: now + 2),
            ConnectionProfile(name: "Gateway Live", host: "127.0.0.1", port: 4001, isPaperTrading: false, createdAt: now + 3),
        ]
    }
}
