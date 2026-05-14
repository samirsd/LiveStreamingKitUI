import SwiftUI
import LiveStreamingKit

/// Five-emoji reaction row used in the in-app listener view. Each tap fires
/// a single reaction via the injected handler; the caller is responsible for
/// network round-trip and optimistic feedback (typically: push to the
/// floating-reactions layer locally, then post the reaction to the backend).
///
/// Per-button throttle of 200ms so a thumb spam doesn't flood the backend
/// with identical events — matches the web client's behavior so both
/// sides feel the same to a listener jumping between devices.
public struct ReactionBar: View {
    /// Called when a reaction button is tapped. The bar handles its own
    /// throttle; the handler is invoked once per non-rate-limited tap.
    public let onReaction: (String) -> Void
    public var disabled: Bool = false

    @State private var lastSentAt: [String: Date] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(disabled: Bool = false, onReaction: @escaping (String) -> Void) {
        self.disabled = disabled
        self.onReaction = onReaction
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(LiveStreamReactionDisplay.orderedTypes, id: \.self) { type in
                Button {
                    fire(type: type)
                } label: {
                    Text(LiveStreamReactionDisplay.emoji[type] ?? "·")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReactionButtonStyle(reduceMotion: reduceMotion))
                .disabled(disabled)
                .accessibilityLabel(Text(accessibilityLabel(for: type)))
            }
        }
    }

    private func fire(type: String) {
        let now = Date()
        if let last = lastSentAt[type], now.timeIntervalSince(last) < 0.2 {
            return
        }
        lastSentAt[type] = now
        onReaction(type)
    }

    private func accessibilityLabel(for type: String) -> String {
        switch type {
        case "heart": return "send love"
        case "fire": return "fire"
        case "party": return "celebrate"
        case "clap": return "applaud"
        case "rock": return "rock on"
        default: return type
        }
    }
}

private struct ReactionButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.85 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
