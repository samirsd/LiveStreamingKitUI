import SwiftUI

/// One-shot celebration card that surfaces after the broadcaster ends a set.
///
/// Designed to be rendered as a sheet or overlay above `LiveStreamControlView`
/// when ``isPresented`` flips true. Shows the same totals the listener page
/// shows post-stream — totals, peak concurrent, top reactions — so the
/// broadcaster gets the social-proof payoff.
///
/// The card doesn't fetch anything; it reads the values its caller has
/// already collected via `LiveStreamControlViewModel`. Caller is responsible
/// for flipping ``isPresented`` based on whatever lifecycle they want
/// (typically: observe state going from `.live` to `.stopped`).
public struct BroadcastSummaryCard: View {
    public let totalListeners: Int
    public let peakListenerCount: Int
    public let reactionTotals: [String: Int]
    public let onDismiss: () -> Void

    public init(
        totalListeners: Int,
        peakListenerCount: Int,
        reactionTotals: [String: Int],
        onDismiss: @escaping () -> Void
    ) {
        self.totalListeners = totalListeners
        self.peakListenerCount = peakListenerCount
        self.reactionTotals = reactionTotals
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(LiveStreamCopy.broadcastEndedTitle)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(2)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("\(totalListeners)")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text(totalListeners == 1 ? LiveStreamCopy.listeners.dropLast() + " " : LiveStreamCopy.listeners)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if peakListenerCount > 0 {
                Text("\(LiveStreamCopy.peakListenersLabel) \(peakListenerCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
            }

            reactionRow

            Button(action: onDismiss) {
                Text(LiveStreamCopy.broadcastSummaryDismiss)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(1.5)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: Color.black.opacity(0.08), radius: 22, y: 8)
        )
    }

    @ViewBuilder
    private var reactionRow: some View {
        let entries = LiveStreamReactionDisplay.orderedTypes.compactMap { type -> (String, Int)? in
            guard let n = reactionTotals[type], n > 0 else { return nil }
            return (type, n)
        }
        if !entries.isEmpty {
            HStack(spacing: 16) {
                ForEach(entries, id: \.0) { type, count in
                    HStack(spacing: 4) {
                        Text(LiveStreamReactionDisplay.emoji[type] ?? "·")
                        Text("\(count)")
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
    }
}
