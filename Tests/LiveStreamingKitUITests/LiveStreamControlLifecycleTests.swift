import XCTest
import LiveStreamingKit
@testable import LiveStreamingKitUI

@MainActor
final class LiveStreamControlLifecycleTests: XCTestCase {
    func testNormalStopShowsSummaryAndRetainsArchiveAndTotals() {
        let model = makeModel()
        model.ingest(.stateChanged(.live(session: session(), since: Date())))
        model.ingest(.listenerCountChanged(3))
        model.ingest(.lifetimeListenerStatsChanged(total: 9, peak: 5))
        model.ingest(.reactionTotalsChanged(["heart": 7]))
        model.ingest(.stateChanged(.stopping))
        XCTAssertFalse(model.justEndedBroadcast)
        let url = URL(fileURLWithPath: "/tmp/broadcast.aac")
        model.ingest(.archiveSaved(url: url, byteCount: 100))
        model.ingest(.stateChanged(.stopped(reason: .requested)))

        XCTAssertTrue(model.justEndedBroadcast)
        XCTAssertNil(model.activeSession)
        XCTAssertEqual(model.listenerCount, 0)
        XCTAssertEqual(model.totalListeners, 9)
        XCTAssertEqual(model.peakListenerCount, 5)
        XCTAssertEqual(model.reactionTotals, ["heart": 7])
        XCTAssertEqual(model.lastArchiveURL, url)
        model.acknowledgeBroadcastEnd()
        model.ingest(.stateChanged(.stopped(reason: .requested)))
        XCTAssertFalse(model.justEndedBroadcast, "duplicate terminal events must not redisplay a dismissed summary")
    }

    func testPreparingCancellationDoesNotShowBroadcastSummary() {
        let model = makeModel()
        model.ingest(.stateChanged(.preparing))
        XCTAssertTrue(model.canCancelStart)
        model.ingest(.stateChanged(.stopping))
        XCTAssertFalse(model.canCancelStart)
        model.ingest(.stateChanged(.stopped(reason: .requested)))
        XCTAssertFalse(model.justEndedBroadcast)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testNewBroadcastClearsAllPriorSessionMetricsAndSummary() {
        let model = makeModel()
        model.ingest(.stateChanged(.live(session: session(), since: Date())))
        model.ingest(.listenerCountChanged(3))
        model.ingest(.lifetimeListenerStatsChanged(total: 9, peak: 5))
        model.ingest(.reactionTotalsChanged(["heart": 7]))
        model.ingest(.segmentUploaded(sequence: 0, bytes: 10, durationMs: 30))
        model.ingest(.archiveSaved(url: URL(fileURLWithPath: "/tmp/old.aac"), byteCount: 100))
        model.ingest(.stateChanged(.stopped(reason: .networkLost)))
        XCTAssertNotNil(model.lastErrorMessage)

        model.ingest(.stateChanged(.preparing))
        XCTAssertEqual(model.listenerCount, 0)
        XCTAssertEqual(model.totalListeners, 0)
        XCTAssertEqual(model.peakListenerCount, 0)
        XCTAssertEqual(model.reactionTotals, [:])
        XCTAssertEqual(model.segmentsSent, 0)
        XCTAssertEqual(model.latencyMilliseconds, 0)
        XCTAssertFalse(model.justEndedBroadcast)
        XCTAssertNil(model.lastArchiveURL)
        XCTAssertEqual(model.lastArchiveBytes, 0)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testRepeatedLiveEventDoesNotDiscardCurrentBroadcastMetrics() {
        let model = makeModel()
        let live = LiveStreamState.live(session: session(), since: Date())
        model.ingest(.stateChanged(live))
        model.ingest(.segmentUploaded(sequence: 0, bytes: 10, durationMs: 30))
        model.ingest(.reactionTotalsChanged(["heart": 3]))
        model.ingest(.stateChanged(live))
        XCTAssertEqual(model.segmentsSent, 1)
        XCTAssertEqual(model.reactionTotals, ["heart": 3])
    }

    func testStartReservationPreventsDuplicateCommandsBeforeEngineEventArrives() async {
        let deferred = DeferredStart()
        var startCount = 0
        let model = LiveStreamControlViewModel(startHandler: {
            startCount += 1
            return try await deferred.run()
        }, stopHandler: {})
        let first = Task { await model.startBroadcast() }
        await waitUntil { deferred.continuation != nil }
        XCTAssertTrue(model.isWorking)
        XCTAssertTrue(model.canCancelStart)
        XCTAssertEqual(model.primaryButtonTitle, LiveStreamCopy.starting)
        await model.startBroadcast()
        XCTAssertEqual(startCount, 1)
        deferred.continuation?.resume(returning: session())
        await first.value
        XCTAssertFalse(model.isWorking)
    }

    func testStopReservationPreventsDuplicateCommandsBeforeEngineEventArrives() async {
        var continuation: CheckedContinuation<Void, Never>?
        var stopCount = 0
        let model = LiveStreamControlViewModel(startHandler: { self.session() }, stopHandler: {
            stopCount += 1
            await withCheckedContinuation { continuation = $0 }
        })
        model.ingest(.stateChanged(.live(session: session(), since: Date())))
        let first = Task { await model.stopBroadcast() }
        await waitUntil { continuation != nil }
        XCTAssertTrue(model.isWorking)
        XCTAssertEqual(model.primaryButtonTitle, LiveStreamCopy.stopping)
        await model.stopBroadcast()
        XCTAssertEqual(stopCount, 1)
        continuation?.resume()
        await first.value
    }

    func testCancellationIsAvailableDuringStartAndDoesNotShowAnError() async {
        let deferred = DeferredStart()
        var stopped = false
        let model = LiveStreamControlViewModel(startHandler: {
            try await deferred.run()
        }, stopHandler: { stopped = true })
        let first = Task { await model.startBroadcast() }
        await waitUntil { deferred.continuation != nil }
        await model.stopBroadcast()
        XCTAssertTrue(stopped)
        deferred.continuation?.resume(throwing: CancellationError())
        await first.value
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.lastErrorMessage)
        XCTAssertFalse(model.justEndedBroadcast)
    }

    func testExplicitStartWhileLiveNeverStopsBroadcast() async {
        var starts = 0
        var stops = 0
        let model = LiveStreamControlViewModel(startHandler: {
            starts += 1
            return self.session()
        }, stopHandler: { stops += 1 })
        model.ingest(.stateChanged(.live(session: session(), since: Date())))
        await model.startBroadcast()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(model.isLive)
    }

    func testStopCancelsPendingNetworkWorkWithoutWaitingForTimeout() async {
        var started = false
        var cancelled = false
        let model = LiveStreamControlViewModel(startHandler: {
            started = true
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                cancelled = true
                throw error
            }
            return self.session()
        }, stopHandler: {})
        let first = Task { await model.startBroadcast() }
        await waitUntil { started }
        await model.stopBroadcast()
        await first.value
        XCTAssertTrue(cancelled, "cancelling startup must cancel the actual suspended network operation")
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testCallerCancellationReachesStartupHandler() async {
        var started = false
        var cancelled = false
        let model = LiveStreamControlViewModel(startHandler: {
            started = true
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                cancelled = true
                throw error
            }
            return self.session()
        }, stopHandler: {})
        let first = Task { await model.startBroadcast() }
        await waitUntil { started }
        first.cancel()
        await first.value
        XCTAssertTrue(cancelled)
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testUnexpectedEndExplainsHowToRecoverAndLateHealthCannotReviveWarning() {
        let model = makeModel()
        model.ingest(.stateChanged(.live(session: session(), since: Date())))
        model.ingest(.streamHealthChanged(.failing, reason: "uploads stalled"))
        model.ingest(.stateChanged(.stopping))
        model.ingest(.stateChanged(.stopped(reason: .interruptionTimedOut)))
        XCTAssertTrue(model.justEndedBroadcast)
        XCTAssertTrue(model.lastErrorMessage?.contains("audio interruption") == true)
        model.ingest(.streamHealthChanged(.failing, reason: "late event"))
        XCTAssertEqual(model.streamHealth, .healthy)
        XCTAssertEqual(model.streamHealthReason, "")
    }

    func testFutureStartTimestampNeverShowsNegativeUptime() {
        let model = makeModel()
        model.ingest(.stateChanged(.live(session: session(), since: Date().addingTimeInterval(60))))
        XCTAssertEqual(model.formattedUptime, "00:00")
    }

    private func makeModel() -> LiveStreamControlViewModel {
        LiveStreamControlViewModel(startHandler: { self.session() }, stopHandler: {})
    }

    private func session() -> LiveStreamSession {
        let url = URL(string: "https://example.com/live")!
        return LiveStreamSession(id: "session", ingestToken: "token", ingestURL: url, listenerURL: url, masterPlaylistURL: url)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("expected the suspended command to start")
    }

    @MainActor
    private final class DeferredStart {
        var continuation: CheckedContinuation<LiveStreamSession, Error>?

        func run() async throws -> LiveStreamSession {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
}
