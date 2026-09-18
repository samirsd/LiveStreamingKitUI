import Foundation
import Combine
import LiveStreamingKit

/// Owns one listener presentation and its playback. Replacing or dismissing
/// a presentation invalidates its work before waiting for network teardown.
@MainActor
public final class LiveListenerCoordinator: ObservableObject {
    @Published public private(set) var engagement: LiveStreamEngagementController?

    private let client: LiveStreamClient
    private let playback: any LiveListenerPlaybackBridge
    private var generation: UInt64 = 0
    private var statusSubscription: AnyCancellable?
    private var playbackStarted = false

    public init(client: LiveStreamClient, playback: any LiveListenerPlaybackBridge) {
        self.client = client
        self.playback = playback
    }

    public func present(sessionID: String, source: String?) async {
        if let current = engagement, current.sessionID == sessionID {
            if current.lastErrorMessage != nil {
                await retry(ifPresenting: current)
            }
            return
        }

        generation &+= 1
        let requestGeneration = generation
        let previous = detachCurrentEngagement()
        await previous?.stop()
        guard generation == requestGeneration, !Task.isCancelled else { return }

        let controller = LiveStreamEngagementController(
            sessionID: sessionID,
            client: client,
            source: source
        )
        engagement = controller
        statusSubscription = controller.$sessionStatus.sink { [weak self, weak controller] status in
            guard let self, let controller, self.engagement === controller else { return }
            self.updatePlayback(status: status, sessionID: controller.sessionID)
        }
        await controller.start()
    }

    public func dismiss() async {
        generation &+= 1
        let previous = detachCurrentEngagement()
        await previous?.stop()
    }

    /// Sheet callbacks carry their original controller so an old sheet's
    /// dismissal cannot close a newer presentation.
    public func dismiss(ifPresenting controller: LiveStreamEngagementController) async {
        guard engagement === controller else { return }
        await dismiss()
    }

    public func retry(ifPresenting controller: LiveStreamEngagementController) async {
        guard engagement === controller, !controller.isLoading else { return }
        let requestGeneration = generation
        playback.stopLiveStream()
        playbackStarted = false
        await controller.stop()
        guard generation == requestGeneration, engagement === controller else { return }
        await controller.start()
    }

    private func detachCurrentEngagement() -> LiveStreamEngagementController? {
        let previous = engagement
        statusSubscription = nil
        engagement = nil
        playbackStarted = false
        if previous != nil { playback.stopLiveStream() }
        return previous
    }

    private func updatePlayback(status: String, sessionID: String) {
        switch status {
        case "live", "ended":
            guard !playbackStarted else { return }
            let rootURL = URL(string: "/", relativeTo: client.baseURL)?.absoluteURL ?? client.baseURL
            let masterURL = rootURL
                .appendingPathComponent("live")
                .appendingPathComponent(sessionID)
                .appendingPathComponent("master.m3u8")
            playback.playLiveStream(url: masterURL, title: "live broadcast", sessionID: sessionID)
            playbackStarted = true
        case "failed":
            if playbackStarted { playback.stopLiveStream() }
            playbackStarted = false
        default:
            break
        }
    }
}
