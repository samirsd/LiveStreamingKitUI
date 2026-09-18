import XCTest
import LiveStreamingKit
@testable import LiveStreamingKitUI

@MainActor
final class LiveListenerLifecycleTests: XCTestCase {
    func testDismissDuringInitialRequestDoesNotStartPlaybackOrPolling() async {
        let transport = ListenerTransport(holdFirstStatus: true)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        let present = Task { await coordinator.present(sessionID: "first", source: nil) }
        await transport.waitForFirstStatus()
        let controller = coordinator.engagement

        await coordinator.dismiss()
        await transport.releaseFirstStatus()
        await present.value

        XCTAssertNil(coordinator.engagement)
        XCTAssertFalse(controller?.hasLoadedInitialState ?? true)
        XCTAssertTrue(playback.playedSessions.isEmpty)
        let reactionRequests = await transport.reactionRequestCount
        XCTAssertEqual(reactionRequests, 0)
    }

    func testReplacingSessionIgnoresOldResponseAndOldSheetDismissal() async {
        let transport = ListenerTransport(holdFirstStatus: true)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        let first = Task { await coordinator.present(sessionID: "first", source: nil) }
        await transport.waitForFirstStatus()
        let oldController = coordinator.engagement!

        await coordinator.present(sessionID: "second", source: "web")
        await transport.releaseFirstStatus()
        await first.value
        await coordinator.dismiss(ifPresenting: oldController)

        XCTAssertEqual(coordinator.engagement?.sessionID, "second")
        XCTAssertEqual(playback.playedSessions, ["second"])
        XCTAssertTrue(playback.isPlayingLiveStream)
        await coordinator.dismiss()
    }

    func testDuplicatePresentationWhileLoadingMakesOneRequest() async {
        let transport = ListenerTransport(holdFirstStatus: true)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        let first = Task { await coordinator.present(sessionID: "same", source: nil) }
        await transport.waitForFirstStatus()
        await coordinator.present(sessionID: "same", source: "web")
        let count = await transport.statusRequestCount
        XCTAssertEqual(count, 1)
        await transport.releaseFirstStatus()
        await first.value
        XCTAssertEqual(playback.playedSessions, ["same"])
        await coordinator.dismiss()
    }

    func testFailedLoadOffersRetryWithoutStartingAudio() async {
        let transport = ListenerTransport(statusCodes: [503, 200])
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "retry", source: nil)
        let controller = coordinator.engagement!
        XCTAssertNotNil(controller.lastErrorMessage)
        XCTAssertFalse(controller.isLoading)
        XCTAssertFalse(controller.canReact)
        XCTAssertTrue(playback.playedSessions.isEmpty)

        await coordinator.retry(ifPresenting: controller)
        XCTAssertNil(controller.lastErrorMessage)
        XCTAssertTrue(controller.hasLoadedInitialState)
        XCTAssertTrue(controller.canReact)
        XCTAssertEqual(playback.playedSessions, ["retry"])
        await coordinator.dismiss()
    }

    func testPendingBroadcastWaitsForLiveStatusBeforeStartingPlayback() async {
        let transport = ListenerTransport(statuses: ["pending", "live"])
        let playback = ListenerPlaybackSpy()
        let started = expectation(description: "broadcast becomes live")
        playback.onPlay = { started.fulfill() }
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "pending", source: nil)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(coordinator.engagement?.sessionStatus, "live")
        XCTAssertEqual(playback.playedSessions, ["pending"])
        await coordinator.dismiss()
    }

    func testFailedBroadcastDoesNotStartPlaybackOrAcceptReactions() async {
        let transport = ListenerTransport(statuses: ["failed"])
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "failed", source: nil)
        let controller = coordinator.engagement!
        controller.sendReaction(type: "heart")
        XCTAssertTrue(playback.playedSessions.isEmpty)
        XCTAssertFalse(controller.canReact)
        XCTAssertTrue(controller.floatingReactions.isEmpty)
        await coordinator.dismiss()
    }

    private func makeClient(_ transport: ListenerTransport) -> LiveStreamClient {
        LiveStreamClient(
            config: LiveStreamConfig(
                ingestBaseURL: URL(string: "https://example.test/")!,
                authTokenProvider: { nil }
            ),
            transport: transport
        )
    }
}

@MainActor
private final class ListenerPlaybackSpy: LiveListenerPlaybackBridge {
    var playedSessions: [String] = []
    var isPlayingLiveStream = false
    var onPlay: (() -> Void)?

    func playLiveStream(url: URL, title: String, sessionID: String) {
        playedSessions.append(sessionID)
        isPlayingLiveStream = true
        onPlay?()
    }

    func stopLiveStream() { isPlayingLiveStream = false }
}

private actor ListenerTransport: HTTPTransport {
    private let holdFirstStatus: Bool
    private var statuses: [String]
    private var statusCodes: [Int]
    private var firstStatusWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstStatusResponse: CheckedContinuation<Void, Never>?
    private(set) var statusRequestCount = 0
    private(set) var reactionRequestCount = 0

    init(holdFirstStatus: Bool = false, statuses: [String] = ["live"], statusCodes: [Int] = [200]) {
        self.holdFirstStatus = holdFirstStatus
        self.statuses = statuses
        self.statusCodes = statusCodes
    }

    func waitForFirstStatus() async {
        if statusRequestCount > 0 { return }
        await withCheckedContinuation { firstStatusWaiters.append($0) }
    }

    func releaseFirstStatus() {
        firstStatusResponse?.resume()
        firstStatusResponse = nil
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isReaction = request.url!.path.contains("reactions")
        let body: Data
        let code: Int
        if isReaction {
            reactionRequestCount += 1
            body = Data(#"{"reactions":[],"totals":{}}"#.utf8)
            code = 200
        } else {
            statusRequestCount += 1
            let status = statuses.count > 1 ? statuses.removeFirst() : statuses[0]
            code = statusCodes.count > 1 ? statusCodes.removeFirst() : statusCodes[0]
            body = Data("{\"status\":\"\(status)\",\"listener_count\":2}".utf8)
            if holdFirstStatus && statusRequestCount == 1 {
                await withCheckedContinuation { continuation in
                    firstStatusResponse = continuation
                    firstStatusWaiters.forEach { $0.resume() }
                    firstStatusWaiters.removeAll()
                }
            } else {
                firstStatusWaiters.forEach { $0.resume() }
                firstStatusWaiters.removeAll()
            }
        }
        return (body, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
