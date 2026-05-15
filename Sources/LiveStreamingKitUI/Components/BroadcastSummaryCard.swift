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
    /// URL of the local AAC archive the engine wrote during the broadcast,
    /// or nil if archiving wasn't enabled / no segments were captured.
    /// Surfaces a "share broadcast" button when non-nil.
    public let archiveURL: URL?
    /// Size of the archive in bytes — drives a "(n MB)" hint next to the
    /// share button. Zero suppresses the hint.
    public let archiveBytes: Int
    /// Called when the broadcaster taps "share broadcast". The host is
    /// responsible for presenting the appropriate share UI (UIActivity
    /// view, custom in-app sheet, library import, etc).
    public let onShareArchive: ((URL) -> Void)?
    public let onDismiss: () -> Void

    public init(
        totalListeners: Int,
        peakListenerCount: Int,
        reactionTotals: [String: Int],
        archiveURL: URL? = nil,
        archiveBytes: Int = 0,
        onShareArchive: ((URL) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.totalListeners = totalListeners
        self.peakListenerCount = peakListenerCount
        self.reactionTotals = reactionTotals
        self.archiveURL = archiveURL
        self.archiveBytes = archiveBytes
        self.onShareArchive = onShareArchive
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

            shareBroadcastSection

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

    /// Renders the "share broadcast" button + size hint when the engine
    /// saved a local archive. Hidden entirely when archiving was off or
    /// the broadcast produced no audio (no segments captured).
    @ViewBuilder
    private var shareBroadcastSection: some View {
        if let url = archiveURL, let onShare = onShareArchive {
            Button {
                onShare(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("share broadcast")
                        .font(.caption.weight(.semibold))
                    if archiveBytes > 0 {
                        Text(humanReadableSize(archiveBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Compact size formatter for the "share broadcast (n MB)" hint.
    private func humanReadableSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
