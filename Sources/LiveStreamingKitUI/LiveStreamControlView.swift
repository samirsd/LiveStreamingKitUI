import SwiftUI
import LiveStreamingKit

@MainActor
public struct LiveStreamControlView: View {
    @ObservedObject public var viewModel: LiveStreamControlViewModel

    public init(viewModel: LiveStreamControlViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                header
                primaryButton
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
    }

    private var header: some View {
        HStack {
            LiveStreamStatusBadge(state: viewModel.state)
            Spacer()
            if viewModel.isLive {
                Text(viewModel.formattedUptime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.listenerCount)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(LiveStreamCopy.listeners)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if viewModel.totalListeners > 0 || viewModel.peakListenerCount > 0 {
                    // Compact lifetime stats sit under "listening now" so a
                    // glance still answers "how big is this set right now?"
                    // without the broadcaster losing the trend numbers.
                    Text(lifetimeStatsCopy)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            metric(value: viewModel.latencyText, label: LiveStreamCopy.latency)
            metric(value: "\(viewModel.segmentsSent)", label: LiveStreamCopy.segmentsSent)
        }
    }

    private var lifetimeStatsCopy: String {
        var parts: [String] = []
        if viewModel.totalListeners > 0 {
            parts.append("\(viewModel.totalListeners) total")
        }
        if viewModel.peakListenerCount > 0 {
            parts.append("peak \(viewModel.peakListenerCount)")
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
            .opacity(hasAppeared ? 0.2 : 1)
            .offset(x: offsetX, y: hasAppeared ? -110 : -10)
            .animation(.easeOut(duration: LiveStreamControlViewModel.reactionFloatDuration), value: hasAppeared)
            .onAppear { hasAppeared = true }
    }
}
