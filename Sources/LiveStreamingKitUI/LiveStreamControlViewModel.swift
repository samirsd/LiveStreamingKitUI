import Foundation
import Combine
import SwiftUI
import LiveStreamingKit

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
    @Published public private(set) var segmentsSent: Int = 0
    @Published public private(set) var latencyMilliseconds: Int = 0
    @Published public private(set) var activeSession: LiveStreamSession?
    @Published public private(set) var lastErrorMessage: String?

    /// How long each emitted reaction stays in `floatingReactions` before
    /// being auto-pruned. Matches the listener page's 1.8s float duration
    /// so a reaction appears in both viewers at roughly the same time.
    public static let reactionFloatDuration: TimeInterval = 1.8

    private let startHandler: StartHandler
    private let stopHandler: StopHandler
    private var liveStartedAt: Date?
    private var tickerTask: Task<Void, Never>?

    public init(startHandler: @escaping StartHandler, stopHandler: @escaping StopHandler) {
        self.startHandler = startHandler
        self.stopHandler = stopHandler
    }

    public func ingest(_ event: LiveStreamEvent) {
        switch event {
        case .stateChanged(let newState):
            state = newState
            switch newState {
            case .live(let session, let since):
                activeSession = session
                liveStartedAt = since
                startTicker()
            case .stopped, .idle, .failed:
                activeSession = nil
                liveStartedAt = nil
                stopTicker()
                // Drop any in-flight floating reactions so a stale emoji
                // doesn't outlive the broadcast. The aggregate counts
                // (`totalListeners`, `peakListenerCount`, `reactionTotals`)
                // stay so the post-session view can show them.
                floatingReactions.removeAll()
                if case .failed(let error) = newState {
                    lastErrorMessage = String(describing: error)
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
        default:
            break
        }
    }

    public func toggle() async {
        switch state {
        case .idle, .stopped, .failed:
            await start()
        case .live, .preparing:
            await stop()
        case .stopping:
            break
        }
    }

    public var isWorking: Bool {
        switch state {
        case .preparing, .stopping: return true
        default: return false
        }
    }

    public var isLive: Bool {
        if case .live = state { return true }
        return false
    }

    public var primaryButtonTitle: String {
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
        let elapsed = Int(Date().timeIntervalSince(liveStartedAt))
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
        do {
            _ = try await startHandler()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    private func stop() async {
        await stopHandler()
    }

    private func startTicker() {
        stopTicker()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self?.objectWillChange.send() }
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
