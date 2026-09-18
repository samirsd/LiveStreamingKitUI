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

    func testProRejectionShowsListeningActionWithoutStartingAudioAndRetryGetsNewGrant() async {
        let transport = ListenerTransport(grantCodes: [403, 200])
        let playback = ListenerPlaybackSpy()
        var requestedSession: String?
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback,
            onAccessRequired: { sessionID, error in
                XCTAssertEqual(error, .subscriptionRequired)
                requestedSession = sessionID
            })
        await coordinator.present(sessionID: "paid", source: "link")
        let controller = coordinator.engagement!
        XCTAssertEqual(coordinator.playbackState, .accessRequired(.subscriptionRequired))
        XCTAssertTrue(playback.playedSessions.isEmpty)
        coordinator.requestAccess(ifPresenting: controller)
        XCTAssertEqual(requestedSession, "paid")
        XCTAssertTrue(playback.playedSessions.isEmpty)

        await coordinator.retry(ifPresenting: controller)
        XCTAssertEqual(coordinator.playbackState, .playing)
        XCTAssertEqual(playback.playedURLs.first?.query, "playback_token=grant-2")
        let requests = await transport.grantRequestCount
        XCTAssertEqual(requests, 2)
        await coordinator.dismiss()
    }

    func testSignedOutServerResponseOffersSignInInsteadOfLiveAudio() async {
        let transport = ListenerTransport(grantCodes: [401])
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "sign-in", source: nil)
        XCTAssertEqual(coordinator.playbackState, .accessRequired(.authenticationRequired))
        XCTAssertTrue(playback.playedSessions.isEmpty)
        await coordinator.dismiss()
    }

    func testDismissDuringGrantRequestDiscardsLateAuthorization() async {
        let transport = ListenerTransport(holdFirstGrant: true)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        let present = Task { await coordinator.present(sessionID: "closing", source: nil) }
        await transport.waitForFirstGrant()
        XCTAssertEqual(coordinator.playbackState, .authorizing)
        await coordinator.dismiss()
        await transport.releaseFirstGrant()
        await present.value
        XCTAssertNil(coordinator.engagement)
        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertTrue(playback.playedSessions.isEmpty)
    }

    func testAccountChangeInvalidatesInFlightGrantAndStopsExistingPlayback() async {
        let transport = ListenerTransport(holdFirstGrant: true)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        let present = Task { await coordinator.present(sessionID: "account", source: nil) }
        await transport.waitForFirstGrant()
        coordinator.authenticationDidChange()
        await transport.releaseFirstGrant()
        await present.value
        XCTAssertTrue(playback.playedSessions.isEmpty)
        if case .failed = coordinator.playbackState {} else { XCTFail("Must request explicit reconnection") }
        await coordinator.retry(ifPresenting: coordinator.engagement!)
        XCTAssertTrue(playback.isPlayingLiveStream)
        coordinator.authenticationDidChange()
        XCTAssertFalse(playback.isPlayingLiveStream)
        await coordinator.dismiss()
    }

    func testGrantExpiryStopsAudioAndOffersExplicitRenewal() async {
        let transport = ListenerTransport(grantLifetime: 0.2)
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "expires", source: nil)
        XCTAssertEqual(coordinator.playbackState, .playing)
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(coordinator.playbackState, .expired)
        XCTAssertFalse(playback.isPlayingLiveStream)
        await coordinator.retry(ifPresenting: coordinator.engagement!)
        XCTAssertEqual(coordinator.playbackState, .playing)
        XCTAssertEqual(playback.playedURLs.last?.query, "playback_token=grant-2")
        await coordinator.dismiss()
    }

    func testPlayerFailureDoesNotLeaveListenerClaimingPlaybackIsActive() async {
        let transport = ListenerTransport()
        let playback = ListenerPlaybackSpy()
        let coordinator = LiveListenerCoordinator(client: makeClient(transport), playback: playback)
        await coordinator.present(sessionID: "error", source: nil)
        coordinator.playbackDidFail()
        XCTAssertFalse(playback.isPlayingLiveStream)
        if case .failed = coordinator.playbackState {} else { XCTFail("Should offer reconnect") }
        await coordinator.dismiss()
    }

    private func makeClient(_ transport: ListenerTransport) -> LiveStreamClient {
        LiveStreamClient(
            config: LiveStreamConfig(
                ingestBaseURL: URL(string: "https://example.test/")!,
                authTokenProvider: { "account-token" }
            ),
            transport: transport
        )
    }
}

@MainActor
private final class ListenerPlaybackSpy: LiveListenerPlaybackBridge {
    var playedSessions: [String] = []
    var playedURLs: [URL] = []
    var isPlayingLiveStream = false
    var onPlay: (() -> Void)?

    func playLiveStream(url: URL, title: String, sessionID: String) {
        playedSessions.append(sessionID)
        playedURLs.append(url)
        isPlayingLiveStream = true
        onPlay?()
    }

    func stopLiveStream() { isPlayingLiveStream = false }
}

private actor ListenerTransport: HTTPTransport {
    private let holdFirstStatus: Bool
    private let holdFirstGrant: Bool
    private var grantCodes: [Int]
    private let grantLifetime: TimeInterval
    private var grantWaiters: [CheckedContinuation<Void, Never>] = []
    private var grantResponse: CheckedContinuation<Void, Never>?
    private(set) var grantRequestCount = 0
    private var statuses: [String]
    private var statusCodes: [Int]
    private var firstStatusWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstStatusResponse: CheckedContinuation<Void, Never>?
    private(set) var statusRequestCount = 0
    private(set) var reactionRequestCount = 0

    init(holdFirstStatus: Bool = false, statuses: [String] = ["live"], statusCodes: [Int] = [200], holdFirstGrant: Bool = false, grantCodes: [Int] = [200], grantLifetime: TimeInterval = 43200) {
        self.holdFirstGrant = holdFirstGrant
        self.grantCodes = grantCodes
        self.grantLifetime = grantLifetime
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

    func waitForFirstGrant() async {
        if grantRequestCount > 0 { return }
        await withCheckedContinuation { grantWaiters.append($0) }
    }

    func releaseFirstGrant() { grantResponse?.resume(); grantResponse = nil }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isReaction = request.url!.path.contains("reactions")
        let body: Data
        let code: Int
        if request.url!.lastPathComponent == "playback" {
            grantRequestCount += 1
            code = grantCodes.count > 1 ? grantCodes.removeFirst() : grantCodes[0]
            let session = request.url!.pathComponents.dropLast().last!
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expires = formatter.string(from: Date().addingTimeInterval(grantLifetime))
            body = code == 200 ? Data("{\"master_playlist_url\":\"https://example.test/live/\(session)/master.m3u8?playback_token=grant-\(grantRequestCount)\",\"expires_at\":\"\(expires)\",\"expires_in\":43200}".utf8) : Data(#"{"code":"subscription_required"}"#.utf8)
            if holdFirstGrant && grantRequestCount == 1 {
                await withCheckedContinuation { continuation in
                    grantResponse = continuation
                    grantWaiters.forEach { $0.resume() }; grantWaiters.removeAll()
                }
            } else {
                grantWaiters.forEach { $0.resume() }; grantWaiters.removeAll()
            }
        } else if isReaction {
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
