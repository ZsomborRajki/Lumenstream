import Foundation
import Observation
internal import IBKit

/// The app's single source of truth, in the spirit of Food Truck's `FoodTruckModel`.
///
/// Owned by the `App` and injected with `.environment(_:)`. Views read state
/// from here; the model owns the `IBConnection` and pumps its event stream
/// into observable state on the main actor.
@Observable
public final class LumenstreamModel {
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var accounts: [String] = []
    public private(set) var notices: [ServerNotice] = []
    public private(set) var quotes: [Quote.ID: Quote] = [:]
    public var selectedAccount: String?

    @ObservationIgnored private let connection = IBConnection()
    @ObservationIgnored private var eventPump: Task<Void, Never>?

    /// Keeps the in-memory notice log bounded.
    private static let noticeLimit = 200

    public init() {}

    // MARK: - Session

    public func connect(to profile: ConnectionProfile) {
        eventPump?.cancel()
        eventPump = nil
        guard let port = UInt16(exactly: profile.port), port > 0 else {
            connectionState = .failed("Invalid port \(profile.port)")
            return
        }
        let endpoint = IBEndpoint(host: profile.host, port: port, clientID: profile.clientID)
        connectionState = .connecting

        eventPump = Task {
            do {
                let events = try await connection.connect(to: endpoint)
                try await connection.send(.requestMarketDataType(.delayed))
                for try await event in events {
                    apply(event)
                }
                // A cancelled pump has been superseded by connect()/disconnect(),
                // which already set the state; don't overwrite it.
                if !Task.isCancelled { connectionState = .disconnected }
            } catch {
                guard !Task.isCancelled else { return }
                connectionState = error is CancellationError ? .disconnected : .failed(String(describing: error))
            }
        }
    }

    public func disconnect() {
        eventPump?.cancel()
        eventPump = nil
        Task { await connection.disconnect() }
        connectionState = .disconnected
    }

    // MARK: - Quotes

    /// Returns the shared quote object for a symbol, creating it on first use.
    public func quote(for symbol: String) -> Quote {
        if let quote = quotes[symbol] { return quote }
        let quote = Quote(symbol: symbol)
        quotes[symbol] = quote
        return quote
    }

    // MARK: - Event handling

    private func apply(_ event: IBEvent) {
        switch event {
        case let .connected(serverVersion, _):
            connectionState = .connected(serverVersion: serverVersion.rawValue)
        case let .managedAccounts(list):
            accounts = list
            if selectedAccount == nil { selectedAccount = list.first }
        case let .notice(notice):
            notices.insert(
                ServerNotice(requestID: notice.requestID, code: notice.code, message: notice.message, isInformational: notice.isInformational),
                at: 0
            )
            if notices.count > Self.noticeLimit { notices.removeLast(notices.count - Self.noticeLimit) }
        case let .transport(.failed(reason)):
            connectionState = .failed(reason)
        case .transport, .nextValidOrderID, .currentTime, .unhandled:
            break
        }
    }
}

extension LumenstreamModel {
    /// A model pre-filled with sample state for previews.
    public static func preview() -> LumenstreamModel {
        let model = LumenstreamModel()
        model.connectionState = .connected(serverVersion: IBServerVersion.clientMaximum.rawValue)
        model.accounts = ["DU1234567"]
        model.selectedAccount = "DU1234567"
        for (symbol, last, close) in [("AAPL", 231.4, 229.1), ("NVDA", 142.8, 145.0), ("MSFT", 438.2, 436.9), ("SPY", 581.3, 579.6)] {
            model.quotes[symbol] = Quote(symbol: symbol, last: last, previousClose: close)
        }
        model.notices = [
            ServerNotice(requestID: -1, code: 2104, message: "Market data farm connection is OK:usfarm", isInformational: true),
        ]
        return model
    }
}
