import SwiftUI
import LiveStreamingKit

@MainActor
public struct LiveStreamControlView: View {
    @ObservedObject public var viewModel: LiveStreamControlViewModel
    /// Optional handler for the "share broadcast" button in the
    /// post-broadcast summary card. Hosts wire this to a UIActivity sheet
    /// or in-app share flow; nil hides the share affordance entirely.
    public var onShareArchive: ((URL) -> Void)?

    public init(
        viewModel: LiveStreamControlViewModel,
        onShareArchive: ((URL) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onShareArchive = onShareArchive
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                header
                primaryButton
                errorBanner
                metricsRow
                reactionTotalsRow
                listenerLinkSection
                footnote
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )

            // Floating reactions overlay. Anchored top-right so the emoji
            // float up alongside the listener-count metric. The view is
            // pointer-event-transparent so the underlying controls still
            // work.
            FloatingReactionsOverlay(reactions: viewModel.floatingReactions)
                .allowsHitTesting(false)
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .overlay {
            // The celebration card surfaces the moment a live broadcast
            // ends with the broadcaster still on this view. Tapping
            // "done" dismisses it (via acknowledgeBroadcastEnd) and the
            // post-stream stats remain visible in the underlying surface.
            if viewModel.justEndedBroadcast {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                BroadcastSummaryCard(
                    totalListeners: viewModel.totalListeners,
                    peakListenerCount: viewModel.peakListenerCount,
                    reactionTotals: viewModel.reactionTotals,
                    archiveURL: viewModel.lastArchiveURL,
                    archiveBytes: viewModel.lastArchiveBytes,
                    onShareArchive: onShareArchive,
                    onDismiss: { viewModel.acknowledgeBroadcastEnd() }
                )
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: viewModel.justEndedBroadcast)
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveStreamStatusBadge(state: viewModel.state)
            if let host = viewModel.streamingHostLabel {
                Text(host)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .accessibilityLabel("streaming to \(host)")
            }
            if viewModel.isLive {
                healthChip
            }
            Spacer()
            if viewModel.isLive {
                Text(viewModel.formattedUptime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Compact health indicator shown next to the live badge while the
    /// broadcast is active. Visible only when the engine reports a non-
    /// healthy state — healthy is the default-quiet design, so the chip
    /// appears precisely when the broadcaster needs to look.
    @ViewBuilder
    private var healthChip: some View {
        switch viewModel.streamHealth {
        case .healthy:
            EmptyView()
        case .degraded:
            healthBadge(
                tint: .yellow,
                label: "degraded",
                detail: viewModel.streamHealthReason
            )
        case .failing:
            healthBadge(
                tint: .red,
                label: "stream failing",
                detail: viewModel.streamHealthReason
            )
        }
    }

    private func healthBadge(tint: Color, label: String, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .accessibilityLabel(detail.isEmpty ? label : "\(label): \(detail)")
        .help(detail)
    }

    private var primaryButton: some View {
        Button {
            Task { await viewModel.toggle() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isWorking {
                    ProgressView().controlSize(.small)
                }
                Text(viewModel.primaryButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.primaryButtonTint)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityIdentifier("livestream.toggle")
    }

    private var metricsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    ListenerCountChip(
                        count: viewModel.listenerCount,
                        toastEnabled: viewModel.isLive
                    )
                    if viewModel.totalListeners > 0 || viewModel.peakListenerCount > 0 {
                        Text(lifetimeStatsCopy)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                metric(value: viewModel.latencyText, label: LiveStreamCopy.latency)
                metric(value: "\(viewModel.segmentsSent)", label: LiveStreamCopy.segmentsSent)
            }
            // VibeMeter sits below the metrics row because reactions arrive
            // fast and a wide bar reads better than a narrow column.
            // Only render while live (and during the brief post-stream tail)
            // — pending sessions have no reactions to meter.
            if viewModel.isLive || viewModel.justEndedBroadcast {
                VibeMeter(reactions: viewModel.floatingReactions)
            }
        }
    }

    private var lifetimeStatsCopy: String {
        var parts: [String] = []
        if viewModel.totalListeners > 0 {
            parts.append("\(viewModel.totalListeners) \(LiveStreamCopy.totalListenersLabel)")
        }
        if viewModel.peakListenerCount > 0 {
            parts.append("\(LiveStreamCopy.peakListenersLabel) \(viewModel.peakListenerCount)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var reactionTotalsRow: some View {
        let totals = viewModel.reactionTotals
        let nonZero = LiveStreamReactionDisplay.orderedTypes.compactMap { type -> (String, Int)? in
            guard let n = totals[type], n > 0 else { return nil }
            return (type, n)
        }
        if !nonZero.isEmpty {
            HStack(spacing: 14) {
                ForEach(nonZero, id: \.0) { type, count in
                    HStack(spacing: 4) {
                        Text(LiveStreamReactionDisplay.emoji[type] ?? "·")
                        Text("\(count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var listenerLinkSection: some View {
        if let session = viewModel.activeSession {
            VStack(alignment: .leading, spacing: 6) {
                Text(LiveStreamCopy.listenerLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(session.listenerURL.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    LiveStreamCopyURLButton(url: session.listenerURL)
                }
                Text(LiveStreamCopy.listenerHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footnote: some View {
        Text(LiveStreamCopy.recordingPreservedNote)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    /// Inline error surface for the last broadcast attempt. Sits directly
    /// under the primary button so the cause of a failed-to-go-live tap is
    /// always visible — previously the view model set `lastErrorMessage`
    /// but no view rendered it, so failures looked exactly like silence to
    /// the user.
    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.lastErrorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.top, 2)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.32), lineWidth: 0.5)
            )
            .accessibilityIdentifier("livestream.errorBanner")
        }
    }
}

#Preview {
    let viewModel = LiveStreamControlViewModel.preview()
    return LiveStreamControlView(viewModel: viewModel)
        .padding()
}

/// Visual mapping for the five reaction types served by the backend.
/// Exposed at module scope so both the totals row and the floating overlay
/// share a single source of truth for the emoji glyph + canonical ordering.
public enum LiveStreamReactionDisplay {
    public static let orderedTypes: [String] = ["heart", "fire", "party", "clap", "rock"]
    public static let emoji: [String: String] = [
        "heart": "♥",
        "fire": "🔥",
        "party": "🎉",
        "clap": "👏",
        "rock": "🤘",
    ]
}

/// SwiftUI overlay that renders each reaction in
/// `LiveStreamControlViewModel.floatingReactions` as a rising-and-fading
/// emoji. The view model is responsible for adding and removing entries on
/// its own schedule (default 1.8s float duration); this view only animates.
///
/// Each reaction is keyed by its id so SwiftUI's identity tracking handles
/// the animation lifecycle automatically — `.transition(.move + .opacity)`
/// fires on insertion / removal, with a small random horizontal offset so
/// bursts spread out instead of stacking.
struct FloatingReactionsOverlay: View {
    let reactions: [LiveReactionEvent]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(reactions) { reaction in
                FloatingReactionView(reaction: reaction)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.6)),
                            removal: .opacity.combined(with: .offset(y: -80))
                        )
                    )
            }
        }
        .animation(.easeOut(duration: 0.5), value: reactions.map(\.id))
        .frame(width: 80, height: 120, alignment: .topTrailing)
    }
}

private struct FloatingReactionView: View {
    let reaction: LiveReactionEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    // Stable random horizontal offset derived from the reaction id. Two
    // listeners' simultaneous reactions land at different x's, but the same
    // reaction's offset stays constant across re-renders.
    private var offsetX: CGFloat {
        let seed = reaction.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return CGFloat((seed % 40) - 20)
    }

    var body: some View {
        Text(LiveStreamReactionDisplay.emoji[reaction.type] ?? "·")
            .font(.title2)
            .opacity(hasAppeared ? (reduceMotion ? 0 : 0.2) : 1)
            .offset(
                x: offsetX,
                // Under reduce-motion, drop the y-rise — the reaction
                // still surfaces (fade in/out) but doesn't travel.
                y: reduceMotion ? 0 : (hasAppeared ? -110 : -10)
            )
            .animation(
                .easeOut(duration: LiveStreamControlViewModel.reactionFloatDuration),
                value: hasAppeared
            )
            .onAppear { hasAppeared = true }
    }
}
