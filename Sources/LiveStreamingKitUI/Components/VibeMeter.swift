import SwiftUI
import LiveStreamingKit

/// Aggregate "energy" indicator for the broadcaster's view. Renders as a
/// horizontal capsule whose fill + glow track the velocity of incoming
/// reactions over a rolling window.
///
/// Decoupled from individual reactions: each ``reactions`` change observed
/// pushes a timestamp into a fixed-window ring; the intensity is the count
/// in the window normalized to a saturating denominator. The bar fades
/// continuously between observations so a quiet moment visibly relaxes the
/// vibe without the broadcaster needing to look closely.
public struct VibeMeter: View {
    public let reactions: [LiveReactionEvent]
    public var windowSeconds: TimeInterval = 6
    public var saturationCount: Int = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stamps: [Date] = []
    @State private var seenIDs: Set<String> = []
    @State private var intensity: Double = 0
    @State private var tickTask: Task<Void, Never>?

    public init(
        reactions: [LiveReactionEvent],
        windowSeconds: TimeInterval = 6,
        saturationCount: Int = 12
    ) {
        self.reactions = reactions
        self.windowSeconds = windowSeconds
        self.saturationCount = saturationCount
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(LiveStreamCopy.vibeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Capsule(style: .continuous)
                .fill(.quaternary)
                .frame(width: 80, height: 4)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: max(0, intensity * 80), height: 4)
                        .shadow(
                            color: reduceMotion
                                ? .clear
                                : Color.accentColor.opacity(intensity * 0.55),
                            radius: reduceMotion ? 0 : max(0, intensity * 6),
                            x: 0,
                            y: 0
                        )
                        .animation(.easeOut(duration: 0.18), value: intensity)
                }
        }
        .onChange(of: reactions) { _, newValue in
            // Capture only ids we haven't already counted so re-renders that
            // pass the same array don't double-bump intensity.
            let now = Date()
            for reaction in newValue where !seenIDs.contains(reaction.id) {
                seenIDs.insert(reaction.id)
                stamps.append(now)
            }
            trimAndRecompute()
        }
        .onAppear { startTicker() }
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
        }
        .accessibilityElement()
        .accessibilityLabel(Text(LiveStreamCopy.vibeLabel))
        .accessibilityValue(Text("\(Int(intensity * 100)) percent"))
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                trimAndRecompute()
            }
        }
    }

    private func trimAndRecompute() {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        stamps = stamps.filter { $0 >= cutoff }
        let target = min(1.0, Double(stamps.count) / Double(max(1, saturationCount)))
        // Exponential smoothing so the bar never jumps abruptly.
        intensity = intensity + (target - intensity) * 0.35
    }
}
