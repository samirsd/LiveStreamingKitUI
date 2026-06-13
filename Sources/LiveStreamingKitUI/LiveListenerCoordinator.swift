import Foundation
import LiveStreamingKit

/// Facade that wires a `liveListener` deep link into the host app's
/// playback stack and surfaces the engagement chrome.
///
/// The coordinator owns three concerns:
/// 1. Driving playback through an injected `LiveListenerPlaybackBridge`
///    (the app implements this, typically wrapping its existing audio
///    playback manager).
/// 2. Building + lifecycle-ing a `LiveStreamEngagementController` per
///    session, exposed via `@Published var engagement` for SwiftUI hosts
///    to bind to.
/// 3. Deduping re-presentations of the same session id so rapid taps
///    don't restart playback or double-mount the overlay.
///
/// Designed to be created once at the composition root and reused for the
/// lifetime of the app. Host views observe `engagement` going non-nil and
/// present `LiveEngagementOverlay`; the bundled `liveListenerSheet`
/// modifier does this with one line of glue.
@MainActor
public final class LiveListenerCoordinator: ObservableObject {

    /// Currently-active engagement controller, or nil when no listener
    /// session is presenting. Drives sheet/overlay visibility on hosts.
    @Published public private(set) var engagement: LiveStreamEngagementController?

    /// Last session id we tried to play. Internal dedupe key.
    private var presentedSessionID: String?

    private let client: LiveStreamClient
    private let playback: any LiveListenerPlaybackBridge

    public init(client: LiveStreamClient, playback: any LiveListenerPlaybackBridge) {
        self.client = client
        self.playback = playback
    }

    /// Push a live session into the host's player and start the engagement
    /// stream. Idempotent for the same `sessionID` while it's presenting.
    public func present(sessionID: String, source: String?) async {
        if presentedSessionID == sessionID, engagement != nil {
            return
        }
        await teardownCurrentEngagement()

        // Resolve the master playlist against the same base URL the
        // client targets, then hand off to the bridge. The bridge owns
        // the popup-bar / now-playing / audio-session details — this
        // coordinator never touches them.
        let masterURL = URL(
            string: "/live/\(sessionID)/master.m3u8",
            relativeTo: client.baseURL
        )?.absoluteURL ?? client.baseURL
        playback.playLiveStream(url: masterURL, title: "live broadcast", sessionID: sessionID)

        let controller = LiveStreamEngagementController(
            sessionID: sessionID,
            client: client,
            source: source
        )
        engagement = controller
        presentedSessionID = sessionID
        await controller.start()
    }

    /// Tear down the listener presentation. Safe to call when nothing is
    /// presenting. Stops both engagement polling and the underlying
    /// stream playback.
    public func dismiss() async {
        await teardownCurrentEngagement()
        playback.stopLiveStream()
    }

    // MARK: - Internals

    private func teardownCurrentEngagement() async {
        if let current = engagement {
            await current.stop()
        }
        engagement = nil
        presentedSessionID = nil
    }
}
