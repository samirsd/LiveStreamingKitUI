import SwiftUI
import LiveStreamingKit

/// Composite engagement chrome the host app overlays on top of its existing
/// player surface for live HLS items. Pure presentation — observes a
/// `LiveStreamEngagementController` and renders the same five engagement
/// primitives the broadcaster and the web listener see:
///
/// 1. `ListenerCountChip` — "N listening" with the joined-toast + pulse.
/// 2. Lifetime stats line (post-stream only) — "N total · peak N".
/// 3. `ReactionTotalsRow` — per-type tallies.
/// 4. `ReactionBar` — five emoji buttons that fire reactions.
/// 5. `VibeMeter` — animated intensity bar.
/// 6. `FloatingReactionsOverlay` — emoji that rise + fade as listeners
///    react.
///
/// Caller picks the placement on the player view; nothing here positions
/// itself absolutely.
public struct LiveEngagementOverlay: View {
    @ObservedObject public var controller: LiveStreamEngagementController
    /// Optional layout — when `compact`, the reactions row sits inline with
    /// the listener chip (good for the popup bar). When `expanded`, fields
    /// stack vertically (good for the full-screen player).
    public var layout: Layout = .expanded

    public init(controller: LiveStreamEngagementController, layout: Layout = .expanded) {
        self.controller = controller
        self.layout = layout
    }

    public enum Layout: Sendable {
        case compact
        case expanded
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            switch layout {
            case .compact:
                compactBody
            case .expanded:
                expandedBody
            }
            FloatingReactionsOverlay(reactions: controller.floatingReactions)
                .allowsHitTesting(false)
                .padding(.top, 4)
                .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListenerCountChip(
                count: controller.listenerCount,
                toastEnabled: controller.isLive
            )
            if controller.isEnded {
                lifetimeStatsRow
            }
            reactionTotalsRow
            VibeMeter(reactions: controller.floatingReactions)
            ReactionBar(disabled: !canReact) { type in
                controller.sendReaction(type: type)
            }
        }
    }

    @ViewBuilder
    private var compactBody: some View {
        HStack(spacing: 12) {
            ListenerCountChip(
                count: controller.listenerCount,
                toastEnabled: controller.isLive
            )
            Spacer(minLength: 8)
            VibeMeter(reactions: controller.floatingReactions)
            ReactionBar(disabled: !canReact) { type in
                controller.sendReaction(type: type)
            }
        }
    }

    @ViewBuilder
    private var lifetimeStatsRow: some View {
        let total = controller.totalListeners
        let peak = controller.peakListenerCount
        if total > 0 || peak > 0 {
            HStack(spacing: 12) {
                if total > 0 {
                    Text("\(total) \(LiveStreamCopy.totalListenersLabel)")
                }
                if peak > 0 {
                    Text("\(LiveStreamCopy.peakListenersLabel) \(peak)")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reactionTotalsRow: some View {
        let entries = LiveStreamReactionDisplay.orderedTypes.compactMap { type -> (String, Int)? in
            guard let n = controller.reactionTotals[type], n > 0 else { return nil }
            return (type, n)
        }
        if !entries.isEmpty {
            HStack(spacing: 14) {
                ForEach(entries, id: \.0) { type, count in
                    HStack(spacing: 4) {
                        Text(LiveStreamReactionDisplay.emoji[type] ?? "·")
                        Text("\(count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        } else if controller.isLive {
            Text(LiveStreamCopy.firstReactionHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Reactions are accepted while live or replaying an ended session;
    /// pending broadcasts (status hasn't moved off "pending") reject 409
    /// from the backend so we disable the buttons proactively.
    private var canReact: Bool {
        controller.sessionStatus != "pending"
    }
}
