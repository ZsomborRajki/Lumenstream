import Synchronization

/// Correlates requests with their responses.
///
/// Hands out request IDs and keeps one stream continuation per in-flight request,
/// so the read loop can route a decoded event to the caller that asked for it.
/// Lock-protected rather than actor-isolated: routing happens on the read loop for
/// every message and must not hop executors.
///
/// Requests come in two kinds. **One-shot** requests (contract details) belong to the
/// socket they were sent on and fail when it drops. **Streaming** requests (market
/// data, from Phase 3) outlive sockets: they are replayed on the next session with
/// the same ID, so their consumers see one uninterrupted stream.
final class IBRequestRegistry: Sendable {
    typealias Continuation = AsyncThrowingStream<IBEvent, any Error>.Continuation

    struct Entry: Sendable {
        let request: IBRequest
        /// Sent when the consumer stops listening before TWS finished the response.
        let cancel: IBRequest?
        let isStreaming: Bool
        /// The session the request was last sent on.
        var session: Int
        let continuation: Continuation
    }

    private struct State {
        var nextID: Int
        var entries: [Int: Entry] = [:]
    }

    private let state: Mutex<State>

    init(firstID: Int = 1) {
        state = Mutex(State(nextID: firstID))
    }

    func makeID() -> Int {
        state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
    }

    func register(_ id: Int, _ entry: Entry) {
        state.withLock { $0.entries[id] = entry }
    }

    func remove(_ id: Int) -> Entry? {
        state.withLock { $0.entries.removeValue(forKey: id) }
    }

    var activeCount: Int {
        state.withLock { $0.entries.count }
    }

    /// Delivers `event` to the request it answers.
    ///
    /// Returns `true` when the event was consumed. Notices are never consumed: a
    /// failing request also shows up in the session's notice log. Events for unknown
    /// IDs fall through to the session stream too.
    ///
    /// Continuations are resumed outside the lock, because finishing one runs its
    /// `onTermination` handler, which calls back into ``remove(_:)``.
    func route(_ event: IBEvent) -> Bool {
        guard let id = event.requestID else { return false }

        if case let .notice(notice) = event {
            if notice.failsRequest {
                remove(id)?.continuation.finish(throwing: IBProtocolError.requestFailed(code: notice.code, message: notice.message))
            } else {
                state.withLock { $0.entries[id] }?.continuation.yield(event)
            }
            return false
        }

        let entry = state.withLock { state in
            event.endsResponse ? state.entries.removeValue(forKey: id) : state.entries[id]
        }
        guard let entry else { return false }
        entry.continuation.yield(event)
        if event.endsResponse { entry.continuation.finish() }
        return true
    }

    /// Fails the one-shot requests sent on `session`, whose socket is gone.
    /// Streaming requests stay registered for replay.
    func socketClosed(session: Int, error: any Error) {
        let failed = state.withLock { state in
            let ids = state.entries.filter { !$0.value.isStreaming && $0.value.session == session }.keys
            return ids.compactMap { state.entries.removeValue(forKey: $0) }
        }
        for entry in failed { entry.continuation.finish(throwing: error) }
    }

    /// Ends every request, streaming ones included.
    func finishAll(throwing error: any Error) {
        let all = state.withLock { state in
            defer { state.entries.removeAll() }
            return Array(state.entries.values)
        }
        for entry in all { entry.continuation.finish(throwing: error) }
    }

    /// The streaming requests to replay on `session`, marked as sent on it.
    func adoptStreamingRequests(session: Int) -> [IBRequest] {
        state.withLock { state in
            var requests: [IBRequest] = []
            for (id, entry) in state.entries where entry.isStreaming {
                state.entries[id]?.session = session
                requests.append(entry.request)
            }
            return requests
        }
    }
}
