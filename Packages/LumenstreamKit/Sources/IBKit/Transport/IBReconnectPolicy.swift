import Foundation

/// Exponential backoff between reconnection attempts.
///
/// TWS takes 30–60 seconds to come back after a restart (and IB Gateway restarts
/// itself daily), so the default policy retries indefinitely, capping the wait at 30 s.
public struct IBReconnectPolicy: Sendable, Hashable {
    public var initialDelay: Duration
    public var maximumDelay: Duration
    public var multiplier: Double
    /// `nil` retries forever.
    public var maximumAttempts: Int?
    /// A session that stayed up this long counts as healthy, and resets the backoff.
    public var stableSessionDuration: Duration

    public init(
        initialDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(30),
        multiplier: Double = 2,
        maximumAttempts: Int? = nil,
        stableSessionDuration: Duration = .seconds(30)
    ) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
        self.multiplier = multiplier
        self.maximumAttempts = maximumAttempts
        self.stableSessionDuration = stableSessionDuration
    }

    public static let standard = Self()
    public static let never = Self(maximumAttempts: 0)

    /// How long to wait before attempt number `attempt` (starting at 1),
    /// or `nil` once the attempts are used up.
    public func delay(forAttempt attempt: Int) -> Duration? {
        guard attempt >= 1 else { return .zero }
        if let maximumAttempts, attempt > maximumAttempts { return nil }
        // Computed in seconds so large attempt counts can't overflow `Duration`.
        let seconds = initialDelay.seconds * pow(multiplier, Double(attempt - 1))
        return seconds < maximumDelay.seconds ? .seconds(seconds) : maximumDelay
    }
}

extension Duration {
    /// The duration as fractional seconds.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
