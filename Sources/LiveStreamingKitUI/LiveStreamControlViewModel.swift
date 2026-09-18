import Foundation
import Combine
import SwiftUI
import LiveStreamingKit
import LoggingKit

@MainActor
public final class LiveStreamControlViewModel: ObservableObject {
    public typealias StartHandler = @MainActor () async throws -> LiveStreamSession
    public typealias StopHandler = @MainActor () async -> Void

    @Published public private(set) var state: LiveStreamState = .idle
    @Published public private(set) var listenerCount: Int = 0
    @Published public private(set) var totalListeners: Int = 0
    @Published public private(set) var peakListenerCount: Int = 0
    @Published public private(set) var reactionTotals: [String: Int] = [:]
    @Published public private(set) var floatingReactions: [LiveReactionEvent] = []
    /// Becomes true when a broadcast that went live reaches a terminal
    /// state, including after the intermediate stopping state. Consumers observe this to
    /// surface the post-broadcast summary card. Reset to false by calling
    /// ``acknowledgeBroadcastEnd()``.
    @Published public private(set) var justEndedBroadcast: Bool = false
    @Published public private(set) var segmentsSent: Int = 0
    @Published public private(set) var latencyMilliseconds: Int = 0
    @Published public private(set) var activeSession: LiveStreamSession?
    @Published public private(set) var lastErrorMessage: String?
    /// Short label identifying the streaming backend host (e.g. "dev.carnyx.app").
    /// When non-nil the broadcaster sheet renders a small chip near the
    /// status badge so it's obvious at a glance which environment you'll be
    /// streaming to. Host apps populate this from their `APIEnvironment` —
    /// production should pass `nil` so the chip stays hidden in shipping
    /// builds.
    @Published public var streamingHostLabel: String?
    /// Latest health classification reported by the engine's monitor task.
    /// Stays `.healthy` outside of `.live` states.
    @Published public private(set) var streamHealth: LiveStreamHealth = .healthy
    /// Short reason string accompanying the most recent non-healthy report
    /// (e.g. "uploads stalled 11s"). Empty when healthy.
    @Published public private(set) var streamHealthReason: String = ""
    /// File URL of the most recently finalized broadcast archive. Set when
    /// the engine emits `archiveSaved` after `stop()`. Nil between
    /// broadcasts. The post-broadcast summary card surfaces a "share
    /// broadcast" action when this is non-nil.
    @Published public private(set) var lastArchiveURL: URL?
    /// Size of the saved archive in bytes — used by the summary card to
    /// render a short "n MB" hint next to the share button.
    @Published public private(set) var lastArchiveBytes: Int = 0

    /// How long each emitted reaction stays in `floatingReactions` before
    /// being auto-pruned. Matches the listener page's 1.8s float duration
    /// so a reaction appears in both viewers at roughly the same time.
    public static let reactionFloatDuration: TimeInterval = 1.8

    private let startHandler: StartHandler
    private let stopHandler: StopHandler
    private var liveStartedAt: Date?
    private var tickerTask: Task<Void, Never>?
    private var startupTask: Task<LiveStreamSession, Error>?
    @Published private var isStartingCommand = false
    @Published private var isStoppingCommand = false
    private var startWasCancelled = false
    private var broadcastReachedLive = false

    public init(startHandler: @escaping StartHandler, stopHandler: @escaping StopHandler) {
        self.startHandler = startHandler
        self.stopHandler = stopHandler
    }

    public func ingest(_ event: LiveStreamEvent) {
        switch event {
        case .stateChanged(let newState):
            let previousState = state
            state = newState
            switch newState {
            case .preparing:
                if previousState != .preparing {
                    resetBroadcastMetrics()
                }
            case .live(let session, let since):
                if !broadcastReachedLive, previousState != .preparing {
                    resetBroadcastMetrics()
                }
                broadcastReachedLive = true
                activeSession = session
                liveStartedAt = since
                lastErrorMessage = nil
                startTicker()
            case .stopped, .idle, .failed:
                if broadcastReachedLive {
                    justEndedBroadcast = true
                    broadcastReachedLive = false
                }
                listenerCount = 0
                activeSession = nil
                liveStartedAt = nil
                stopTicker()
                // Drop any in-flight floating reactions so a stale emoji
                // doesn't outlive the broadcast. The aggregate counts
                // (`totalListeners`, `peakListenerCount`, `reactionTotals`)
                // stay so the post-session view can show them.
                floatingReactions.removeAll()
                // Health classification is a live-session concept — reset
                // so the next broadcast starts neutral.
                streamHealth = .healthy
                streamHealthReason = ""
                if case .failed(let error) = newState {
                    // Prefer the user-facing description so the broadcaster
                    // sheet shows "can't reach the streaming server (api.carnyx.app)"
                    // instead of "backendUnreachable(...)". The raw enum still
                    // ends up in os.Logger for engineers.
                    lastErrorMessage = error.userFacingDescription
                } else if case .stopped(let reason) = newState {
                    lastErrorMessage = recoveryMessage(for: reason)
                }
            default:
                break
            }
        case .segmentUploaded(_, _, let durationMs):
            segmentsSent += 1
            latencyMilliseconds = durationMs
        case .listenerCountChanged(let count):
            listenerCount = count
        case .lifetimeListenerStatsChanged(let total, let peak):
            totalListeners = total
            peakListenerCount = peak
        case .reactionTotalsChanged(let totals):
            reactionTotals = totals
        case .reactionReceived(let reaction):
            guard isLive else { return }
            // Append + auto-prune after `reactionFloatDuration`. We schedule
            // the prune off the same MainActor we're running on so the
            // @Published mutation is safe.
            floatingReactions.append(reaction)
            Task { @MainActor [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.reactionFloatDuration * 1_000_000_000)
                )
                self?.floatingReactions.removeAll { $0.id == reaction.id }
            }
        case .latencyMeasured(let ms):
            latencyMilliseconds = ms
        case .streamHealthChanged(let health, let reason):
            guard isLive else { return }
            streamHealth = health
            streamHealthReason = reason
        case .archiveSaved(let url, let byteCount):
            lastArchiveURL = url
            lastArchiveBytes = byteCount
        default:
            break
        }
    }

    /// Clear the ``justEndedBroadcast`` flag. Call from the
    /// `BroadcastSummaryCard`'s onDismiss callback (or any other consumer of
    /// the transition signal) once the celebration moment has been shown.
    public func acknowledgeBroadcastEnd() {
        justEndedBroadcast = false
    }

    /// Compatibility action for a single start/stop control. Intent-specific
    /// callers should use startBroadcast or stopBroadcast so a repeated start
    /// request can never accidentally stop a broadcast that just became live.
    public func toggle() async {
        switch state {
        case .idle, .stopped, .failed:
            await startBroadcast()
        case .live, .preparing:
            await stopBroadcast()
        case .stopping:
            break
        }
    }

    public func startBroadcast() async {
        guard !isStartingCommand, !isStoppingCommand else { return }
        switch state {
        case .idle, .stopped, .failed: break
        case .preparing, .live, .stopping: return
        }
        // Reserve the action before suspending; engine events arrive through
        // an asynchronous bridge and may not yet reflect this request.
        isStartingCommand = true
        startWasCancelled = false
        resetBroadcastMetrics()
        defer { isStartingCommand = false }
        VisibilityDiagnostics.trackFeatureAction(
            surface: .liveStreaming,
            feature: "broadcast_control",
            action: "go_live",
            phase: .started
        )
        await start()
    }

    public func stopBroadcast() async {
        guard !isStoppingCommand else { return }
        let canStop: Bool
        switch state {
        case .live, .preparing: canStop = true
        case .idle, .stopped, .failed: canStop = isStartingCommand
        case .stopping: canStop = false
        }
        guard canStop else { return }
        isStoppingCommand = true
        startWasCancelled = isStartingCommand || state == .preparing
        startupTask?.cancel()
        defer { isStoppingCommand = false }
        VisibilityDiagnostics.trackFeatureAction(
            surface: .liveStreaming,
            feature: "broadcast_control",
            action: "stop_live",
            phase: .started
        )
        await stopHandler()
    }

    public var isWorking: Bool {
        if isStartingCommand || isStoppingCommand { return true }
        switch state {
        case .preparing, .stopping: return true
        default: return false
        }
    }

    public var canCancelStart: Bool {
        !startWasCancelled && !isStoppingCommand && state != .stopping
            && (isStartingCommand || state == .preparing)
    }

    public var isLive: Bool {
        if case .live = state { return true }
        return false
    }

    public var primaryButtonTitle: String {
        if isStoppingCommand || (isStartingCommand && startWasCancelled) { return LiveStreamCopy.stopping }
        if isStartingCommand { return LiveStreamCopy.starting }
        switch state {
        case .preparing: return LiveStreamCopy.starting
        case .stopping: return LiveStreamCopy.stopping
        case .live: return LiveStreamCopy.stopLive
        default: return LiveStreamCopy.goLive
        }
    }

    public var primaryButtonTint: Color {
        switch state {
        case .live: return .red
        case .failed: return .orange
        default: return .accentColor
        }
    }

    public var latencyText: String {
        guard latencyMilliseconds > 0 else { return "—" }
        return "\(latencyMilliseconds) ms"
    }

    public var formattedUptime: String {
        guard let liveStartedAt else { return "" }
        let elapsed = max(0, Int(Date().timeIntervalSince(liveStartedAt)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Private

    private func start() async {
        lastErrorMessage = nil
        let task = Task { @MainActor [startHandler] in
            try Task.checkCancellation()
            return try await startHandler()
        }
        startupTask = task
        defer { startupTask = nil }
        do {
            _ = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            // Cancelling startup is a user action, not a broadcast failure.
        } catch let liveError as LiveStreamError {
            guard !startWasCancelled else { return }
            lastErrorMessage = liveError.userFacingDescription
            VisibilityDiagnostics.trackFeatureAction(
                surface: .liveStreaming,
                feature: "broadcast_control",
                action: "go_live",
                phase: .failed,
                properties: ["error_message": liveError.telemetryCategory]
            )
        } catch {
            guard !startWasCancelled else { return }
            lastErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "couldn't start the broadcast — please try again"
            VisibilityDiagnostics.trackFeatureAction(
                surface: .liveStreaming,
                feature: "broadcast_control",
                action: "go_live",
                phase: .failed,
                properties: ["error_message": String(describing: error)]
            )
        }
    }

    private func resetBroadcastMetrics() {
        listenerCount = 0
        totalListeners = 0
        peakListenerCount = 0
        reactionTotals = [:]
        floatingReactions = []
        segmentsSent = 0
        latencyMilliseconds = 0
        justEndedBroadcast = false
        lastArchiveURL = nil
        lastArchiveBytes = 0
        lastErrorMessage = nil
        streamHealth = .healthy
        streamHealthReason = ""
        broadcastReachedLive = false
    }

    private func recoveryMessage(for reason: LiveStreamState.StopReason) -> String? {
        switch reason {
        case .requested, .recordingEnded:
            return nil
        case .networkLost:
            return "the broadcast ended because the connection was lost. check your network, then go live again."
        case .backendClosed:
            return "the streaming server ended this broadcast. try going live again."
        case .appBackgrounded:
            return "the broadcast ended when the app closed. go live again when you're ready."
        case .interruptionTimedOut:
            return "the broadcast ended after an audio interruption. check your audio source, then go live again."
        }
    }

    private func startTicker() {
        stopTicker()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard let self else { return }
                self.objectWillChange.send()
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }
}

extension LiveStreamControlViewModel {
    public static func preview() -> LiveStreamControlViewModel {
        let viewModel = LiveStreamControlViewModel(
            startHandler: {
                LiveStreamSession(
                    id: "preview",
                    ingestToken: "tok",
                    ingestURL: URL(string: "https://example.com/i")!,
                    listenerURL: URL(string: "https://carnyx.live/preview")!,
                    masterPlaylistURL: URL(string: "https://example.com/m")!
                )
            },
            stopHandler: {}
        )
        viewModel.ingest(.stateChanged(.live(
            session: LiveStreamSession(
                id: "preview",
                ingestToken: "tok",
                ingestURL: URL(string: "https://example.com/i")!,
                listenerURL: URL(string: "https://carnyx.live/preview")!,
                masterPlaylistURL: URL(string: "https://example.com/m")!
            ),
            since: Date().addingTimeInterval(-187)
        )))
        viewModel.ingest(.listenerCountChanged(42))
        viewModel.ingest(.lifetimeListenerStatsChanged(total: 64, peak: 47))
        viewModel.ingest(.reactionTotalsChanged([
            "heart": 24, "fire": 12, "party": 4, "clap": 2, "rock": 9,
        ]))
        viewModel.ingest(.segmentUploaded(sequence: 12, bytes: 64_000, durationMs: 320))
        return viewModel
    }
}
