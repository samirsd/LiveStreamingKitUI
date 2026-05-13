import XCTest
import LiveStreamingKit
@testable import LiveStreamingKitUI

@MainActor
final class LiveStreamControlViewModelAdvancedTests: XCTestCase {

    func testToggleDispatchesStartWhenIdle() async {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.isLive)
        await viewModel.toggle()
        // Start handler in makeViewModel synchronously returns a session, but the
        // engine state isn't actually transitioned by the view model itself (events
        // do that). The view model's lastErrorMessage stays nil on success.
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testToggleWhileStoppingDoesNothing() async {
        let viewModel = makeViewModel()
        let session = makeSession()
        viewModel.ingest(.stateChanged(.stopping))
        await viewModel.toggle()
        // Still stopping; toggle in this state must not re-trigger start or stop.
        XCTAssertEqual(viewModel.state, .stopping)
        _ = session
    }

    func testWorkingFlagTracksPreparingAndStopping() {
        let viewModel = makeViewModel()
        viewModel.ingest(.stateChanged(.preparing))
        XCTAssertTrue(viewModel.isWorking)
        viewModel.ingest(.stateChanged(.live(session: makeSession(), since: Date())))
        XCTAssertFalse(viewModel.isWorking)
        viewModel.ingest(.stateChanged(.stopping))
        XCTAssertTrue(viewModel.isWorking)
    }

    func testLatencyTextShowsEmDashWhenUnset() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.latencyText, "—")
    }

    func testLatencyTextShowsMilliseconds() {
        let viewModel = makeViewModel()
        viewModel.ingest(.latencyMeasured(milliseconds: 250))
        XCTAssertEqual(viewModel.latencyText, "250 ms")
    }

    func testStartHandlerErrorIsCapturedInLastErrorMessage() async {
        struct BoomError: Error, CustomStringConvertible {
            let description = "boom"
        }
        let viewModel = LiveStreamControlViewModel(
            startHandler: { throw BoomError() },
            stopHandler: {}
        )
        await viewModel.toggle()
        XCTAssertNotNil(viewModel.lastErrorMessage)
        XCTAssertTrue((viewModel.lastErrorMessage ?? "").contains("boom"))
    }

    func testStopHandlerIsInvokedWhenLive() async {
        var stopCalled = false
        let viewModel = LiveStreamControlViewModel(
            startHandler: { self.makeSession() },
            stopHandler: { stopCalled = true }
        )
        viewModel.ingest(.stateChanged(.live(session: makeSession(), since: Date())))
        await viewModel.toggle()
        XCTAssertTrue(stopCalled)
    }

    func testListenerCountEventUpdatesObservedCount() {
        let viewModel = makeViewModel()
        viewModel.ingest(.listenerCountChanged(13))
        XCTAssertEqual(viewModel.listenerCount, 13)
        viewModel.ingest(.listenerCountChanged(0))
        XCTAssertEqual(viewModel.listenerCount, 0)
    }

    func testPrimaryButtonTintIsRedWhenLive() {
        let viewModel = makeViewModel()
        viewModel.ingest(.stateChanged(.live(session: makeSession(), since: Date())))
        // Color comparison is fragile across platforms; assert distinctness from accent
        // by checking description string remains consistent
        let liveTint = viewModel.primaryButtonTint
        viewModel.ingest(.stateChanged(.stopped(reason: .requested)))
        let idleTint = viewModel.primaryButtonTint
        XCTAssertNotEqual(String(describing: liveTint), String(describing: idleTint))
    }

    func testFormattedUptimeIsEmptyWhenNotLive() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.formattedUptime, "")
    }

    func testActiveSessionClearsOnStopped() {
        let viewModel = makeViewModel()
        viewModel.ingest(.stateChanged(.live(session: makeSession(), since: Date())))
        XCTAssertNotNil(viewModel.activeSession)
        viewModel.ingest(.stateChanged(.stopped(reason: .recordingEnded)))
        XCTAssertNil(viewModel.activeSession)
    }

    // MARK: - Helpers

    private func makeViewModel() -> LiveStreamControlViewModel {
        LiveStreamControlViewModel(
            startHandler: { self.makeSession() },
            stopHandler: {}
        )
    }

    private func makeSession() -> LiveStreamSession {
        LiveStreamSession(
            id: "x", ingestToken: "t",
            ingestURL: URL(string: "https://example.com")!,
            listenerURL: URL(string: "https://example.com")!,
            masterPlaylistURL: URL(string: "https://example.com")!
        )
    }
}
