import SwiftUI
import AVKit
import FontKit

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
            item: Binding<LiveListenerPresentation?>(
                get: {
                    guard coordinator.shouldPresentListenerSheet else { return nil }
                    return coordinator.engagement.map { LiveListenerPresentation(controller: $0) }
                },
                set: { newValue in
                    guard newValue == nil, let presentedController,
                          coordinator.shouldPresentListenerSheet else { return }
                    Task { await coordinator.dismiss(ifPresenting: presentedController) }
                }
            )
        ) { presentation in
            LiveListenerContent(controller: presentation.controller, coordinator: coordinator)
        }
    }
}

@MainActor
public struct LiveListenerContent: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: LiveStreamEngagementController
    @ObservedObject var coordinator: LiveListenerCoordinator
    private let showsVideo: Bool
    private let showsHeader: Bool

    public init(controller: LiveStreamEngagementController, coordinator: LiveListenerCoordinator,
                showsVideo: Bool = true, showsHeader: Bool = true) {
        self.controller = controller
        self.coordinator = coordinator
        self.showsVideo = showsVideo
        self.showsHeader = showsHeader
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showsHeader { HStack {
                    Text(title)
                        .customFontStyle(.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        Task { await coordinator.dismiss(ifPresenting: controller) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(FontKit.colors.textSecondary)
                    }
                    .accessibilityLabel("close and stop listening")
                } }

                if coordinator.playbackState == .authorizing {
                    ProgressView("checking listening access…")
                } else if case .accessRequired(let requirement) = coordinator.playbackState {
                    Text(requirement == .authenticationRequired
                         ? "Sign in to check your Carnyx Pro access to this broadcast."
                         : "Listen to this broadcast with Carnyx Pro. See available subscription and trial options.")
                        .foregroundStyle(FontKit.colors.textSecondary)
                    if coordinator.canRequestAccess {
                        Button(requirement == .authenticationRequired ? "Sign in to listen" : "See listening options") {
                            coordinator.requestAccess(ifPresenting: controller)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("livestream.listener.access")
                    }
                    retryButton(title: "check access again")
                } else if case .failed(let message) = coordinator.playbackState {
                    Text(message).foregroundStyle(FontKit.colors.textSecondary)
                    retryButton(title: reconnectTitle)
                } else if coordinator.playbackState == .expired {
                    Text("Reconnect to renew your listening access and keep listening.")
                        .foregroundStyle(FontKit.colors.textSecondary)
                    retryButton(title: reconnectTitle)
                } else if controller.isLoading {
                    ProgressView("connecting to broadcast…")
                } else if let error = controller.lastErrorMessage {
                    Text(error)
                        .foregroundStyle(FontKit.colors.textSecondary)
                    retryButton(title: "try again")
                } else if controller.sessionStatus == "failed" {
                    Text("this broadcast is no longer available.")
                        .foregroundStyle(FontKit.colors.textSecondary)
                    retryButton(title: "try again")
                } else {
                    if !controller.isLive && !controller.isEnded {
                        Text(controller.isVideoBroadcast ? "video will be ready when the broadcaster goes live." : "audio will start when the broadcaster goes live.")
                            .foregroundStyle(FontKit.colors.textSecondary)
                    }
                    if showsVideo, let player = coordinator.videoPlayer {
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
            .customFontStyle(.body)
            .foregroundStyle(FontKit.colors.textPrimary)
            .tint(FontKit.colors.accent)
            .padding(20)
        }
        .background(FontKit.colors.backgroundPrimary)
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
