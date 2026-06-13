import SwiftUI

/// "N listening now" with two behaviors layered on the bare count:
///
/// 1. A short scale pulse whenever ``count`` increments. Reads from the
///    `accessibilityReduceMotion` environment so the pulse is skipped under
///    "Reduce Motion".
/// 2. A transient "+N listening" toast that appears for ``toastDuration``
///    each time the count goes up. Multiple back-to-back joins collapse into
///    the most recent delta rather than stacking.
///
/// First-observed value never animates — that's the existing audience as of
/// view appearance, not a fresh join.
public struct ListenerCountChip: View {
    public let count: Int
    /// When false, suppress the toast (used when status is pending — there's
    /// no audience yet so "+1 listening" is nonsense).
    public let toastEnabled: Bool
    public var toastDuration: TimeInterval = 2.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previousCount: Int?
    @State private var toastDelta: Int?
    @State private var toastTask: Task<Void, Never>?
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseTask: Task<Void, Never>?

    public init(count: Int, toastEnabled: Bool, toastDuration: TimeInterval = 2.2) {
        self.count = count
        self.toastEnabled = toastEnabled
        self.toastDuration = toastDuration
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .scaleEffect(pulseScale)
                Text(LiveStreamCopy.listeners)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let delta = toastDelta {
                Text(deltaCopy(delta))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
                    .foregroundStyle(Color.accentColor)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity
                        )
                    )
                    .accessibilityLabel(Text(deltaCopy(delta)))
            }
        }
        .onChange(of: count) { _, newValue in
            handleCountChange(newValue)
        }
        .onAppear {
            previousCount = count
        }
        .animation(.easeInOut(duration: 0.2), value: toastDelta != nil)
    }

    // MARK: -

    private func handleCountChange(_ newValue: Int) {
        defer { previousCount = newValue }
        guard let prev = previousCount else { return }
        let delta = newValue - prev
        guard delta > 0 else { return }

        // Bounce the count number once. Spring-back happens by running the
        // animation closure with the bumped scale, then a short Task that
        // settles back to 1.0.
        if !reduceMotion {
            pulseTask?.cancel()
            pulseTask = Task { @MainActor in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                    pulseScale = 1.35
                }
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    pulseScale = 1.0
                }
            }
        }
        guard toastEnabled else { return }

        toastDelta = delta
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toastDuration * 1_000_000_000))
            toastDelta = nil
        }
    }

    private func deltaCopy(_ delta: Int) -> String {
        "+\(delta) \(LiveStreamCopy.listenerJoinedSuffix)"
    }
}
