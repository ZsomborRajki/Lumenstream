import Foundation
import Observation
import SwiftData

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

    /// The profile the current (or last attempted) session uses.
    public private(set) var activeProfileID: PersistentIdentifier?
    public private(set) var activeProfileName: String?
    /// TWS's clock string from the handshake, e.g. `20261017 10:00:00 CET`.
    public private(set) var serverTime: String?
    public private(set) var connectedSince: Date?
    /// Sockets opened by automatic reconnection during this session.
    public private(set) var reconnectCount = 0

    @ObservationIgnored private let connection = IBConnection()
    @ObservationIgnored private var eventPump: Task<Void, Never>?
    @ObservationIgnored private var activeEndpoint: IBEndpoint?
    /// Whether the current profile's session has been up before, so the next
    /// `.connected` counts as a reconnect.
    @ObservationIgnored private var hasConnectedBefore = false

    /// Keeps the in-memory notice log bounded.
    private static let noticeLimit = 200

    public init() {}

    // MARK: - Session

    public func connect(to profile: ConnectionProfile) {
        guard let port = UInt16(exactly: profile.port), port > 0 else {
            disconnect()
            // Nothing to retry: clear the previous profile so the status view
            // doesn't offer a "Try Again" for it.
            activeProfileID = nil
            activeProfileName = nil
            connectionState = .failed("Invalid port \(profile.port)")
            return
        }
        activeProfileID = profile.persistentModelID
        activeProfileName = profile.name
        reconnectCount = 0
        hasConnectedBefore = false
        start(IBEndpoint(host: profile.host, port: port, clientID: profile.clientID))
    }

    public func disconnect() {
        eventPump?.cancel()
        eventPump = nil
        activeEndpoint = nil
        Task { await connection.disconnect() }
        connectionState = .disconnected
        connectedSince = nil
    }

    /// Skips the remaining backoff and reconnects now.
    public func retryNow() {
        guard let activeEndpoint, connectionState != .disconnected else { return }
        // A session that was already reconnecting keeps doing so if this attempt
        // fails too (TWS still restarting); only a fresh start fails fast.
        var policy = IBReconnectPolicy.standard
        if case .reconnecting = connectionState { policy.retriesFirstConnection = true }
        start(activeEndpoint, policy: policy)
    }

    /// Called when the app returns to the foreground. iOS suspends sockets in the
    /// background, so a pending reconnect should not wait out its backoff.
    public func sceneDidBecomeActive() {
        if case .reconnecting = connectionState { retryNow() }
    }

    private func start(_ endpoint: IBEndpoint, policy: IBReconnectPolicy = .standard) {
        eventPump?.cancel()
        activeEndpoint = endpoint
        connectionState = .connecting

        eventPump = Task {
            do {
                for try await event in await connection.sessions(to: endpoint, policy: policy) {
                    apply(event)
                }
                // A cancelled pump has been superseded by connect()/disconnect(),
                // which already set the state; don't overwrite it.
                if !Task.isCancelled { connectionState = .disconnected }
            } catch {
                guard !Task.isCancelled else { return }
                connectionState = .failed(Self.explain(error, endpoint: endpoint))
                connectedSince = nil
            }
        }
    }

    // MARK: - Contracts

    /// Fills in IB contract IDs for watchlist symbols that don't have one yet.
    /// Symbols TWS can't resolve, or resolves ambiguously, are left alone.
    public func resolveContractIDs(for symbols: [WatchlistSymbol]) async {
        for symbol in symbols where symbol.contractID == nil {
            guard connectionState.isConnected, !Task.isCancelled else { return }
            let query = IBContract(symbol: symbol.symbol, securityType: symbol.securityType, exchange: symbol.exchange, currency: symbol.currency)
            guard let matches = try? await connection.contractDetails(for: query), matches.count == 1 else { continue }
            symbol.contractID = matches[0].contract.contractID
        }
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
        case let .connected(serverVersion, connectionTime):
            if hasConnectedBefore { reconnectCount += 1 }
            hasConnectedBefore = true
            connectionState = .connected(serverVersion: serverVersion.rawValue)
            serverTime = connectionTime
            connectedSince = .now
            Task { try? await connection.send(.requestMarketDataType(.delayed)) }

        case let .reconnecting(attempt, delay, reason):
            connectionState = .reconnecting(attempt: attempt, retryAt: .now + delay.seconds, reason: reason)

        case let .managedAccounts(list):
            accounts = list
            if selectedAccount.map(list.contains) != true { selectedAccount = list.first }

        case let .notice(notice):
            log(notice)
            applyConnectivity(of: notice)

        case .transport, .nextValidOrderID, .currentTime, .contractDetails, .contractDetailsEnd, .unhandled:
            break
        }
    }

    private func log(_ notice: IBNotice) {
        notices.insert(
            ServerNotice(requestID: notice.requestID, code: notice.code, message: notice.message, isInformational: notice.isInformational),
            at: 0
        )
        if notices.count > Self.noticeLimit { notices.removeLast(notices.count - Self.noticeLimit) }
    }

    private func applyConnectivity(of notice: IBNotice) {
        switch (notice.connectivity, connectionState) {
        case let (.lost, .connected(version)):
            connectionState = .brokerUnreachable(serverVersion: version)
        case let (.restored, .brokerUnreachable(version)):
            connectionState = .connected(serverVersion: version)
        default:
            break
        }
    }

    /// Turns transport errors into advice for the connection screen.
    private static func explain(_ error: any Error, endpoint: IBEndpoint) -> String {
        let address = "\(endpoint.host):\(endpoint.port)"
        switch error as? IBProtocolError {
        case let .connectionUnavailable(reason):
            return "Couldn't reach \(address) (\(reason)). Check that TWS or IB Gateway is running with socket clients enabled."
        case .handshakeTimedOut:
            return "\(address) accepted the connection but never answered. Look for an “Accept incoming connection” prompt in TWS."
        case .connectionClosed:
            return "TWS closed the connection. Make sure this device's IP address is in TWS's Trusted IPs."
        case let .clientIDInUse(clientID):
            return "Client ID \(clientID) is already in use by another API client. Choose a different one in the profile."
        default:
            return String(describing: error)
        }
    }
}

extension LumenstreamModel {
    /// A model pre-filled with sample state for previews.
    public static func preview() -> LumenstreamModel {
        let model = LumenstreamModel()
        model.connectionState = .connected(serverVersion: IBServerVersion.clientMaximum.rawValue)
        model.accounts = ["DU1234567", "DU7654321"]
        model.selectedAccount = "DU1234567"
        model.activeProfileName = "TWS Paper"
        model.serverTime = "20261017 10:00:00 CET"
        model.connectedSince = .now - 42 * 60
        for (symbol, last, close) in [("AAPL", 231.4, 229.1), ("NVDA", 142.8, 145.0), ("MSFT", 438.2, 436.9), ("SPY", 581.3, 579.6)] {
            model.quotes[symbol] = Quote(symbol: symbol, last: last, previousClose: close)
        }
        model.notices = [
            ServerNotice(requestID: -1, code: 2104, message: "Market data farm connection is OK:usfarm", isInformational: true),
            ServerNotice(requestID: -1, code: 2106, message: "HMDS data farm connection is OK:ushmds", isInformational: true),
            ServerNotice(requestID: 3, code: 200, message: "No security definition has been found for the request", isInformational: false),
        ]
        return model
    }
}
