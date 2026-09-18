import Foundation
import SwiftUI
import LiveStreamingKit

/// Drives the listener-side engagement state for a live session — listener
/// count, reaction totals, the floating-emoji feed, lifetime stats.
///
/// Deliberately **does not** know about playback. The host app composes this
/// with whatever player it already uses (in Carnyx that's the popup
/// `PlayerViewController` from PlaybackKitUI). The engagement overlay
/// sits on top of the player view and observes this controller.
///
/// Architecturally it's a **Facade** over `LiveStreamClient` +
/// `LiveStreamSocialPoller`, projecting the kit's event stream into
/// `@Published` SwiftUI state. Same shape as the broadcaster-side
/// `LiveStreamControlViewModel`, minus the broadcast lifecycle bits.
@MainActor
public final class LiveStreamEngagementController: ObservableObject {
    @Published public private(set) var listenerCount: Int = 0
    @Published public private(set) var totalListeners: Int = 0
    @Published public private(set) var peakListenerCount: Int = 0
    @Published public private(set) var reactionTotals: [String: Int] = [:]
    @Published public private(set) var floatingReactions: [LiveReactionEvent] = []
    @Published public private(set) var sessionStatus: String = "pending"
    @Published public private(set) var hasLoadedInitialState: Bool = false
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    /// Float duration matches the broadcaster's `LiveStreamControlViewModel`
    /// and the web listener page — same reaction surfaces for the same
    /// amount of time across every device that sees it.
    public static let reactionFloatDuration: TimeInterval = 1.8

    public let sessionID: String
    public let source: String?

    private let client: LiveStreamClient
    private var poller: LiveStreamSocialPoller?
    private var session: LiveStreamSession?
    private var lifecycleID: UUID?

    public init(
        sessionID: String,
        client: LiveStreamClient,
        source: String? = nil
    ) {
        self.sessionID = sessionID
        self.client = client
        self.source = source
    }

    deinit {
        if let poller { Task { await poller.stop() } }
    }

    // MARK: - Lifecycle

    /// Failed initial loads can be retried. Every asynchronous continuation
    /// checks ownership so stopping during a request cannot restart polling.
    public func start() async {
        guard !isLoading, poller == nil else { return }
        let lifecycleID = UUID()
        self.lifecycleID = lifecycleID
        isLoading = true
        lastErrorMessage = nil
        hasLoadedInitialState = false
        sessionStatus = "pending"

        let placeholder = LiveStreamSession(
            id: sessionID,
            ingestToken: "",
            ingestURL: relativeURL("/api/v1/livestream/sessions/\(sessionID)/"),
            listenerURL: relativeURL("/live/\(sessionID)"),
            masterPlaylistURL: relativeURL("/live/\(sessionID)/master.m3u8")
        )
        session = placeholder

        let status = await client.fetchSessionStatus(placeholder)
        guard self.lifecycleID == lifecycleID else { return }
        isLoading = false
        guard !Task.isCancelled else {
            lastErrorMessage = "connection cancelled. try again to listen."
            return
        }
        guard let status else {
            lastErrorMessage = "couldn’t load this broadcast. check your connection and try again."
            return
        }
        listenerCount = status.listener_count ?? 0
        totalListeners = status.total_listeners ?? 0
        peakListenerCount = status.peak_listener_count ?? 0
        reactionTotals = status.reaction_totals ?? [:]
        hasLoadedInitialState = true
        sessionStatus = status.status

        let onEvent: @Sendable (LiveStreamEvent) -> Void = { [weak self] event in
            Task { @MainActor in
                guard let self, self.lifecycleID == lifecycleID else { return }
                self.ingest(event)
            }
        }
        let poller = LiveStreamSocialPoller(client: client, onEvent: onEvent)
        self.poller = poller
        await poller.start(placeholder)
        if self.lifecycleID != lifecycleID { await poller.stop() }
    }

    public func stop() async {
        lifecycleID = nil
        isLoading = false
        let previous = poller
        poller = nil
        session = nil
        await previous?.stop()
    }

    /// Fire a reaction. Surfaces a local optimistic float immediately and
    /// POSTs in the background. POST failure is silent — the user already
    /// saw the float, and the poll loop will dedupe the server-side echo.
    public func sendReaction(type: String) {
        guard canReact, let session else { return }
        let local = LiveReactionEvent(
            id: "local-\(UUID().uuidString)",
            type: type,
            ts: Date().timeIntervalSince1970
        )
        appendFloatingReaction(local)
        Task { [client] in
            _ = await client.postReaction(session, type: type)
        }
    }

    // MARK: - Convenience for the chrome overlay

    public var canReact: Bool {
        lifecycleID != nil && hasLoadedInitialState && (sessionStatus == "live" || sessionStatus == "ended")
    }

    public var isLive: Bool { sessionStatus == "live" }
    public var isEnded: Bool { sessionStatus == "ended" || sessionStatus == "failed" }

    // MARK: - Internals

    private func relativeURL(_ path: String) -> URL {
        URL(string: path, relativeTo: client.baseURL)?.absoluteURL ?? client.baseURL
    }

    private func ingest(_ event: LiveStreamEvent) {
        switch event {
        case .sessionStatusChanged(let status):
            sessionStatus = status
        case .listenerCountChanged(let n):
            listenerCount = n
        case .lifetimeListenerStatsChanged(let total, let peak):
            totalListeners = total
            peakListenerCount = peak
        case .reactionTotalsChanged(let totals):
            reactionTotals = totals
        case .reactionReceived(let reaction):
            appendFloatingReaction(reaction)
        case .stateChanged(let state):
            if case .stopped = state { sessionStatus = "ended" }
            if case .failed = state { sessionStatus = "failed" }
        default:
            break
        }
    }

    private func appendFloatingReaction(_ reaction: LiveReactionEvent) {
        floatingReactions.append(reaction)
        Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.reactionFloatDuration * 1_000_000_000)
            )
            self?.floatingReactions.removeAll { $0.id == reaction.id }
        }
    }
}
