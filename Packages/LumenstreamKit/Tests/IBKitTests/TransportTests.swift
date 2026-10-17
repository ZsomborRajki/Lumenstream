import Foundation
import Testing

@testable import IBKit

@Suite("Reconnect policy")
struct ReconnectPolicyTests {
    @Test func backoffDoublesUpToTheCap() {
        let policy = IBReconnectPolicy.standard
        let delays = (1...7).map { policy.delay(forAttempt: $0) }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)])
    }

    @Test func hugeAttemptCountsStayAtTheCap() {
        #expect(IBReconnectPolicy.standard.delay(forAttempt: 10000) == .seconds(30))
    }

    @Test func attemptsRunOut() {
        let policy = IBReconnectPolicy(maximumAttempts: 2)
        #expect(policy.delay(forAttempt: 2) != nil)
        #expect(policy.delay(forAttempt: 3) == nil)
        #expect(IBReconnectPolicy.never.delay(forAttempt: 1) == nil)
    }
}

@Suite("Framing")
struct FramingTests {
    @Test func payloadLengthReadsSlices() {
        let bytes = Data([0xFF, 0x00, 0x00, 0x01, 0x02])
        #expect(IBFrame.payloadLength(header: bytes.dropFirst()) == 258)
    }
}

@Suite("Request registry")
struct RequestRegistryTests {
    private func entry(_ request: IBRequest = .requestCurrentTime, streaming: Bool = false, session: Int = 1)
        -> (IBRequestRegistry.Entry, AsyncThrowingStream<IBEvent, any Error>) {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: IBEvent.self)
        return (.init(request: request, cancel: nil, isStreaming: streaming, session: session, continuation: continuation), stream)
    }

    private func details(_ symbol: String) -> IBContractDetails {
        IBContractDetails(contract: .stock(symbol), marketName: "", longName: "", minimumTick: 0.01, priceMagnifier: 1, validExchanges: [])
    }

    @Test func idsIncrease() {
        let registry = IBRequestRegistry(firstID: 100)
        #expect(registry.makeID() == 100)
        #expect(registry.makeID() == 101)
    }

    @Test func routesResponsesUntilTheEndMarker() async throws {
        let registry = IBRequestRegistry()
        let (entry, stream) = entry()
        registry.register(5, entry)

        #expect(registry.route(.contractDetails(requestID: 5, details("AAPL"))))
        #expect(registry.route(.contractDetailsEnd(requestID: 5)))
        #expect(!registry.route(.contractDetails(requestID: 6, details("MSFT"))), "unknown IDs fall through")
        #expect(!registry.route(.managedAccounts(["DU1"])))

        var received: [IBEvent] = []
        for try await event in stream { received.append(event) }
        #expect(received == [.contractDetails(requestID: 5, details("AAPL")), .contractDetailsEnd(requestID: 5)])
        #expect(registry.activeCount == 0)
    }

    @Test func errorNoticeFailsTheRequestAndStillReachesTheSession() async {
        let registry = IBRequestRegistry()
        let (entry, stream) = entry()
        registry.register(5, entry)

        #expect(!registry.route(.notice(IBNotice(requestID: 5, code: 200, message: "No security definition"))))
        await #expect(throws: IBProtocolError.requestFailed(code: 200, message: "No security definition")) {
            for try await _ in stream {}
        }
        #expect(registry.activeCount == 0)
    }

    @Test func socketLossFailsOneShotsAndKeepsStreams() async {
        let registry = IBRequestRegistry()
        let (oneShot, oneShotStream) = entry(session: 1)
        let (streaming, _) = entry(.requestIDs(count: 3), streaming: true, session: 1)
        let (newer, _) = entry(session: 2)
        registry.register(1, oneShot)
        registry.register(2, streaming)
        registry.register(3, newer)

        registry.socketClosed(session: 1, error: IBProtocolError.connectionClosed)
        await #expect(throws: IBProtocolError.connectionClosed) {
            for try await _ in oneShotStream {}
        }
        #expect(registry.activeCount == 2)
        #expect(registry.adoptStreamingRequests(session: 2) == [.requestIDs(count: 3)])
    }

    @Test func finishAllEndsStreams() async {
        let registry = IBRequestRegistry()
        let (streaming, stream) = entry(streaming: true)
        registry.register(1, streaming)
        registry.finishAll(throwing: IBProtocolError.notConnected)
        await #expect(throws: IBProtocolError.notConnected) {
            for try await _ in stream {}
        }
    }
}
