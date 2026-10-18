import Foundation
import Combine
import LiveStreamingKit
@preconcurrency import AVFoundation

public enum LiveListenerPlaybackState: Equatable, Sendable {
    case idle
    case authorizing
    case playing
    case accessRequired(LiveListenerAccessError)
    case failed(String)
    case expired
}

/// Owns one listener presentation, its Pro authorization, and playback.
@MainActor
public final class LiveListenerCoordinator: ObservableObject {
    @Published public private(set) var engagement: LiveStreamEngagementController?
    @Published public private(set) var playbackState: LiveListenerPlaybackState = .idle
    @Published public private(set) var videoPlayer: AVPlayer?

    private let client: LiveStreamClient
    private let playback: any LiveListenerPlaybackBridge
    private let videoPlayback: any LiveListenerVideoPlayback
    private let grantProvider: @MainActor (String) async throws -> LiveListenerPlaybackGrant
    private let accessAction: (@MainActor (String, LiveListenerAccessError) -> Void)?
    private var generation: UInt64 = 0
    private var statusSubscription: AnyCancellable?
    private var authorizationTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var mediaRefreshTask: Task<Void, Never>?
    private var pendingVideoContinuation: LiveListenerVideoSnapshot?
    private var playbackStarted = false

    public init(
        client: LiveStreamClient,
        playback: any LiveListenerPlaybackBridge,
        videoPlayback: (any LiveListenerVideoPlayback)? = nil,
        grantProvider: (@MainActor (String) async throws -> LiveListenerPlaybackGrant)? = nil,
        onAccessRequired: (@MainActor (String, LiveListenerAccessError) -> Void)? = nil
    ) {
        self.client = client
        self.playback = playback
        self.videoPlayback = videoPlayback ?? AVPlayerLiveListenerVideoPlayback()
        self.grantProvider = grantProvider ?? { try await client.fetchPlaybackGrant(sessionID: $0) }
        accessAction = onAccessRequired
        self.videoPlayback.onFailure = { [weak self] in self?.playbackDidFail() }
    }

    public func present(sessionID: String, source: String?) async {
        if let current = engagement, current.sessionID == sessionID {
            if current.lastErrorMessage != nil || canRetryPlayback {
                await retry(ifPresenting: current)
            }
            return
        }
        generation &+= 1
        let requestGeneration = generation
        let previous = detachCurrentEngagement()
        await previous?.stop()
        guard generation == requestGeneration, !Task.isCancelled else { return }

        let controller = LiveStreamEngagementController(sessionID: sessionID, client: client, source: source)
        engagement = controller
        statusSubscription = controller.$sessionStatus.sink { [weak self, weak controller] status in
            guard let self, let controller, self.engagement === controller else { return }
            self.updatePlayback(status: status, controller: controller)
        }
        await controller.start()
        await authorizationTask?.value
    }

    public func dismiss() async {
        generation &+= 1
        let previous = detachCurrentEngagement()
        await previous?.stop()
    }

    public func dismiss(ifPresenting controller: LiveStreamEngagementController) async {
        guard engagement === controller else { return }
        await dismiss()
    }

    public func retry(ifPresenting controller: LiveStreamEngagementController) async {
        guard engagement === controller, !controller.isLoading, playbackState != .authorizing else { return }
        generation &+= 1
        let requestGeneration = generation
        if videoPlayer != nil { pendingVideoContinuation = videoPlayback.snapshot }
        stopPlayback()
        playbackState = .idle
        await controller.stop()
        guard generation == requestGeneration, engagement === controller else { return }
        await controller.start()
        await authorizationTask?.value
    }

    public var canRequestAccess: Bool { accessAction != nil }

    public func requestAccess(ifPresenting controller: LiveStreamEngagementController) {
        guard engagement === controller, case .accessRequired(let error) = playbackState else { return }
        accessAction?(controller.sessionID, error)
    }

    /// Invalidates grants on sign-out or account replacement before any awaited
    /// response can start audio under an earlier account's permission.
    public func authenticationDidChange() {
        guard engagement != nil else { return }
        generation &+= 1
        pendingVideoContinuation = nil
        stopPlayback()
        playbackState = .failed("Your account changed. Reconnect to check access for this account.")
    }

    /// Hosts forward player failures; a rejected/expired HLS request must not
    /// leave the listener sheet claiming that audio is playing.
    public func playbackDidFail() {
        guard engagement != nil, playbackStarted else { return }
        generation &+= 1
        if videoPlayer != nil {
            pendingVideoContinuation = LiveListenerVideoSnapshot(position: videoPlayback.snapshot.position, playing: false)
        }
        stopPlayback()
        playbackState = .failed("Playback interrupted. Reconnect to check your access.")
    }

    private var canRetryPlayback: Bool {
        switch playbackState {
        case .accessRequired, .failed, .expired: true
        case .idle, .authorizing, .playing: false
        }
    }

    private func detachCurrentEngagement() -> LiveStreamEngagementController? {
        let previous = engagement
        statusSubscription = nil
        engagement = nil
        pendingVideoContinuation = nil
        stopPlayback()
        playbackState = .idle
        return previous
    }

    private func stopPlayback() {
        authorizationTask?.cancel()
        authorizationTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        mediaRefreshTask?.cancel()
        mediaRefreshTask = nil
        if videoPlayer != nil {
            videoPlayback.stop()
            videoPlayer = nil
        } else if playbackStarted { playback.stopLiveStream() }
        playbackStarted = false
    }

    /// Match the web listener: backgrounding pauses video without silently
    /// resuming audible playback when the scene becomes active again.
    public func pauseVideoForBackground() {
        videoPlayback.pause()
        if var pendingVideoContinuation {
            pendingVideoContinuation.playing = false
            self.pendingVideoContinuation = pendingVideoContinuation
        }
    }

    private func updatePlayback(status: String, controller: LiveStreamEngagementController) {
        switch status {
        case "live", "ended":
            guard !playbackStarted, playbackState == .idle else { return }
            beginPlaybackAuthorization(controller: controller)
        case "failed":
            stopPlayback()
            playbackState = .failed("This broadcast is no longer available.")
        default:
            break
        }
    }

    private func beginPlaybackAuthorization(controller: LiveStreamEngagementController, refreshingVideo: Bool = false) {
        let requestGeneration = generation
        if !refreshingVideo { playbackState = .authorizing }
        authorizationTask = Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else { return }
            do {
                let grant = try await self.grantProvider(controller.sessionID)
                guard self.generation == requestGeneration, self.engagement === controller,
                      !Task.isCancelled else { return }
                guard grant.expiresAt > Date() else { throw LiveListenerAccessError.invalidResponse }
                if controller.isVideoBroadcast {
                    let continuation = refreshingVideo ? self.videoPlayback.snapshot : self.pendingVideoContinuation
                    self.pendingVideoContinuation = nil
                    self.videoPlayback.prepare(url: grant.masterPlaylistURL, restoring: continuation)
                    self.videoPlayer = self.videoPlayback.player
                } else {
                    self.playback.playLiveStream(
                        url: grant.masterPlaylistURL, title: "live broadcast", sessionID: controller.sessionID
                    )
                }
                self.playbackStarted = true
                self.playbackState = .playing
                self.scheduleExpiry(grant.expiresAt, generation: requestGeneration, controller: controller)
                if controller.isVideoBroadcast, let refreshAfter = grant.mediaURLRefreshAfterSeconds {
                    self.scheduleMediaRefresh(after: refreshAfter, generation: requestGeneration, controller: controller)
                }
            } catch {
                guard self.generation == requestGeneration, self.engagement === controller,
                      !Task.isCancelled else { return }
                self.stopPlayback()
                if let accessError = error as? LiveListenerAccessError,
                   accessError == .authenticationRequired || accessError == .subscriptionRequired {
                    self.playbackState = .accessRequired(accessError)
                } else {
                    self.playbackState = .failed("Couldn’t connect to this broadcast. Try again to listen.")
                }
            }
            if self.generation == requestGeneration { self.authorizationTask = nil }
        }
    }

    private func scheduleExpiry(_ date: Date, generation: UInt64, controller: LiveStreamEngagementController) {
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self, weak controller] in
            do { try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow))) } catch { return }
            guard let self, let controller, self.generation == generation,
                  self.engagement === controller else { return }
            if self.videoPlayer != nil {
                self.pendingVideoContinuation = LiveListenerVideoSnapshot(position: self.videoPlayback.snapshot.position, playing: false)
            }
            self.stopPlayback()
            self.playbackState = .expired
        }
    }

    private func scheduleMediaRefresh(after seconds: TimeInterval, generation: UInt64, controller: LiveStreamEngagementController) {
        guard seconds.isFinite, seconds > 0 else { return }
        mediaRefreshTask?.cancel()
        mediaRefreshTask = Task { @MainActor [weak self, weak controller] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, let controller, self.generation == generation,
                  self.engagement === controller, self.videoPlayer != nil else { return }
            self.beginPlaybackAuthorization(controller: controller, refreshingVideo: true)
        }
    }
}
