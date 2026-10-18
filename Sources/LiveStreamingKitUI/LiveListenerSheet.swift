import SwiftUI
import AVKit

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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: LiveStreamEngagementController
    @ObservedObject var coordinator: LiveListenerCoordinator

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

                if coordinator.playbackState == .authorizing {
                    ProgressView("checking listening access…")
                } else if case .accessRequired(let requirement) = coordinator.playbackState {
                    Text(requirement == .authenticationRequired
                         ? "Sign in to check your Carnyx Pro access to this broadcast."
                         : "Listen to this broadcast with Carnyx Pro. See available subscription and trial options.")
                        .foregroundStyle(.secondary)
                    if coordinator.canRequestAccess {
                        Button(requirement == .authenticationRequired ? "Sign in to listen" : "See listening options") {
                            coordinator.requestAccess(ifPresenting: controller)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("livestream.listener.access")
                    }
                    retryButton(title: "check access again")
                } else if case .failed(let message) = coordinator.playbackState {
                    Text(message).foregroundStyle(.secondary)
                    retryButton(title: reconnectTitle)
                } else if coordinator.playbackState == .expired {
                    Text("Reconnect to renew your listening access and keep listening.")
                        .foregroundStyle(.secondary)
                    retryButton(title: reconnectTitle)
                } else if controller.isLoading {
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
                        Text(controller.isVideoBroadcast ? "video will be ready when the broadcaster goes live." : "audio will start when the broadcaster goes live.")
                            .foregroundStyle(.secondary)
                    }
                    if let player = coordinator.videoPlayer {
                        VideoPlayer(player: player)
                            .aspectRatio(controller.videoAspectRatio, contentMode: .fit)
                            .frame(maxHeight: 540)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(controller.isLive ? "live video broadcast" : "video broadcast replay")
                            .accessibilityIdentifier("livestream.listener.video")
                    }
                    LiveEngagementOverlay(controller: controller, layout: .expanded)
                    if controller.isLive || controller.isEnded {
                        retryButton(title: reconnectTitle)
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents(controller.isVideoBroadcast ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { coordinator.pauseVideoForBackground() }
        }
    }

    private var title: String {
        switch coordinator.playbackState {
        case .authorizing: return "checking access"
        case .accessRequired(.authenticationRequired): return "sign in to listen"
        case .accessRequired: return "listen with Carnyx Pro"
        case .failed: return "playback interrupted"
        case .expired: return "reconnect to listen"
        case .idle, .playing: break
        }
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
        .disabled(controller.isLoading || coordinator.playbackState == .authorizing)
    }

    private var reconnectTitle: String { controller.isVideoBroadcast ? "reconnect video" : "reconnect audio" }
}
