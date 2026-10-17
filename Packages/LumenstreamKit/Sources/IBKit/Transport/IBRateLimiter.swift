/// Evenly spaces outbound messages. TWS disconnects clients that exceed
/// 50 messages per second, so every send reserves the next free slot.
struct IBRateLimiter: Sendable {
    let interval: Duration
    private var nextSlot = ContinuousClock.now

    init(messagesPerSecond: Int) {
        interval = .seconds(1) / messagesPerSecond
    }

    /// Reserves a slot synchronously (before any suspension), so concurrent
    /// senders on the owning actor can't claim the same one.
    mutating func reserve(now: ContinuousClock.Instant = .now) -> ContinuousClock.Instant {
        let slot = max(now, nextSlot)
        nextSlot = slot + interval
        return slot
    }
}
