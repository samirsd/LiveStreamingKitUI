import XCTest
import LiveStreamingKit
@testable import LiveStreamingKitUI

@MainActor
final class LiveStreamControlViewModelTests: XCTestCase {
    func testInitialStateIsOfflineCopy() {
        let viewModel = LiveStreamControlViewModel(
            startHandler: { LiveStreamSession(
                id: "x",
                ingestToken: "t",
                ingestURL: URL(string: "https://example.com")!,
                listenerURL: URL(string: "https://example.com")!,
                masterPlaylistURL: URL(string: "https://example.com")!
            )},
            stopHandler: {}
        )
        XCTAssertEqual(viewModel.primaryButtonTitle, LiveStreamCopy.goLive)
        XCTAssertFalse(viewModel.isLive)
    }

    func testLiveTransitionUpdatesActiveSession() {
        let viewModel = makeViewModel()
        let session = LiveStreamSession(
            id: "live",
            ingestToken: "tok",
            ingestURL: URL(string: "https://example.com/i")!,
            listenerURL: URL(string: "https://example.com/l")!,
            masterPlaylistURL: URL(string: "https://example.com/m")!
        )
        viewModel.ingest(.stateChanged(.live(session: session, since: Date())))
        XCTAssertTrue(viewModel.isLive)
        XCTAssertEqual(viewModel.activeSession?.id, "live")
        XCTAssertEqual(viewModel.primaryButtonTitle, LiveStreamCopy.stopLive)
    }

    func testSegmentUploadIncrementsCounter() {
        let viewModel = makeViewModel()
        viewModel.ingest(.segmentUploaded(sequence: 0, bytes: 1024, durationMs: 240))
        viewModel.ingest(.segmentUploaded(sequence: 1, bytes: 1024, durationMs: 180))
        XCTAssertEqual(viewModel.segmentsSent, 2)
        XCTAssertEqual(viewModel.latencyMilliseconds, 180)
    }

    func testListenerCountUpdates() {
        let viewModel = makeViewModel()
        viewModel.ingest(.listenerCountChanged(7))
        XCTAssertEqual(viewModel.listenerCount, 7)
    }

    func testFailedStateRecordsError() {
        let viewModel = makeViewModel()
        viewModel.ingest(.stateChanged(.failed(.backendUnreachable(URL(string: "https://example.com")!))))
        XCTAssertNotNil(viewModel.lastErrorMessage)
        XCTAssertEqual(viewModel.primaryButtonTitle, LiveStreamCopy.goLive)
    }

    func testUptimeFormatsBelowAndAboveOneHour() {
        let viewModel = makeViewModel()
        let session = LiveStreamSession(
            id: "x", ingestToken: "t",
            ingestURL: URL(string: "https://example.com")!,
            listenerURL: URL(string: "https://example.com")!,
            masterPlaylistURL: URL(string: "https://example.com")!
        )
        viewModel.ingest(.stateChanged(.live(session: session, since: Date().addingTimeInterval(-65))))
        XCTAssertEqual(viewModel.formattedUptime, "01:05")
        viewModel.ingest(.stateChanged(.live(session: session, since: Date().addingTimeInterval(-3725))))
        XCTAssertEqual(viewModel.formattedUptime, "1:02:05")
    }

    private func makeViewModel() -> LiveStreamControlViewModel {
        LiveStreamControlViewModel(
            startHandler: { LiveStreamSession(
                id: "x", ingestToken: "t",
                ingestURL: URL(string: "https://example.com")!,
                listenerURL: URL(string: "https://example.com")!,
                masterPlaylistURL: URL(string: "https://example.com")!
            )},
            stopHandler: {}
        )
    }
}
