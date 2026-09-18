import SwiftUI

public extension View {
    /// Present the listener at the scene root. Closing the sheet also stops
    /// the stream owned by that presentation.
    func liveListenerSheet(coordinator: LiveListenerCoordinator) -> some View {
        modifier(LiveListenerSheetModifier(coordinator: coordinator))
    }
}

private struct LiveListenerPresentation: Identifiable {
    let controller: LiveStreamEngagementController
    var id: ObjectIdentifier { ObjectIdentifier(controller) }
}

@MainActor
private struct LiveListenerSheetModifier: ViewModifier {
    @ObservedObject var coordinator: LiveListenerCoordinator

    func body(content: Content) -> some View {
        let presentedController = coordinator.engagement
        content.sheet(
            item: Binding(
                get: { coordinator.engagement.map { LiveListenerPresentation(controller: $0) } },
                set: { newValue in
                    guard newValue == nil, let presentedController else { return }
                    Task { await coordinator.dismiss(ifPresenting: presentedController) }
                }
            )
        ) { presentation in
            LiveListenerSheetContent(controller: presentation.controller, coordinator: coordinator)
        }
    }
}

@MainActor
private struct LiveListenerSheetContent: View {
    @ObservedObject var controller: LiveStreamEngagementController
    let coordinator: LiveListenerCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        Task { await coordinator.dismiss(ifPresenting: controller) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("close and stop listening")
                }

                if controller.isLoading {
                    ProgressView("connecting to broadcast…")
                } else if let error = controller.lastErrorMessage {
                    Text(error)
                        .foregroundStyle(.secondary)
                    retryButton(title: "try again")
                } else if controller.sessionStatus == "failed" {
                    Text("this broadcast is no longer available.")
                        .foregroundStyle(.secondary)
                    retryButton(title: "try again")
                } else {
                    if !controller.isLive && !controller.isEnded {
                        Text("audio will start when the broadcaster goes live.")
                            .foregroundStyle(.secondary)
                    }
                    LiveEngagementOverlay(controller: controller, layout: .expanded)
                    if controller.isLive || controller.isEnded {
                        retryButton(title: "reconnect audio")
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        if controller.isLoading { return "connecting" }
        if controller.lastErrorMessage != nil { return "broadcast unavailable" }
        switch controller.sessionStatus {
        case "live": return LiveStreamCopy.live
        case "ended": return "broadcast ended"
        case "failed": return "broadcast unavailable"
        default: return "waiting for broadcast"
        }
    }

    private func retryButton(title: String) -> some View {
        Button(title) {
            Task { await coordinator.retry(ifPresenting: controller) }
        }
        .buttonStyle(.bordered)
        .disabled(controller.isLoading)
    }
}
