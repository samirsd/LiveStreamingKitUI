import SwiftUI
import LiveStreamingKit

public struct LiveStreamStatusBadge: View {
    public let state: LiveStreamState

    public init(state: LiveStreamState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .modifier(PulsingOpacity(active: isLive))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityLabel(Text(label))
    }

    private var label: String {
        switch state {
        case .idle, .stopped: return LiveStreamCopy.offline
        case .preparing: return LiveStreamCopy.starting
        case .live: return LiveStreamCopy.live
        case .stopping: return LiveStreamCopy.stopping
        case .failed: return LiveStreamCopy.failed
        }
    }

    private var tint: Color {
        switch state {
        case .live: return .red
        case .preparing, .stopping: return .yellow
        case .failed: return .orange
        case .idle, .stopped: return .gray
        }
    }

    private var isLive: Bool {
        if case .live = state { return true }
        return false
    }
}

private struct PulsingOpacity: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.35 : 1.0)
            .animation(active ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: dimmed)
            .onAppear { if active { dimmed = true } }
            .onChange(of: active) { _, newValue in
                dimmed = newValue
            }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        LiveStreamStatusBadge(state: .idle)
        LiveStreamStatusBadge(state: .preparing)
        LiveStreamStatusBadge(state: .live(
            session: LiveStreamSession(
                id: "abc",
                ingestToken: "tok",
                ingestURL: URL(string: "https://example.com/i")!,
                listenerURL: URL(string: "https://example.com/l")!,
                masterPlaylistURL: URL(string: "https://example.com/m")!
            ),
            since: Date()
        ))
        LiveStreamStatusBadge(state: .failed(.backendUnreachable(URL(string: "https://example.com")!)))
    }
    .padding()
}
