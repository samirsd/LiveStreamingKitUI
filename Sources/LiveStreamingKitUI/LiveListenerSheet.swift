import SwiftUI

public extension View {
    /// Mounts the in-app listener overlay sheet driven by a
    /// `LiveListenerCoordinator`.
    ///
    /// One call site at the app/scene root is enough — the modifier
    /// observes the coordinator's `engagement` and presents a sheet over
    /// the current view whenever a listener session is active. Swiping
    /// the sheet down calls `coordinator.dismiss()` so the host's
    /// playback bridge also stops the stream.
    ///
    /// ```swift
    /// // At the SwiftUI scene root, in the composition root:
    /// RootView()
    ///     .liveListenerSheet(coordinator: CarnyxLiveListenerComposition.shared)
    /// ```
    func liveListenerSheet(coordinator: LiveListenerCoordinator) -> some View {
        modifier(LiveListenerSheetModifier(coordinator: coordinator))
    }
}

@MainActor
private struct LiveListenerSheetModifier: ViewModifier {
    @ObservedObject var coordinator: LiveListenerCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { coordinator.engagement != nil },
                    set: { newValue in
                        if !newValue {
                            // Swipe-down dismissal. Async so the sheet's
                            // animation gets to complete before we tear
                            // playback down — feels less abrupt.
                            Task { await coordinator.dismiss() }
                        }
                    }
                )
            ) {
                if let controller = coordinator.engagement {
                    LiveListenerSheetContent(controller: controller)
                }
            }
    }
}

@MainActor
private struct LiveListenerSheetContent: View {
    @ObservedObject var controller: LiveStreamEngagementController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Drag handle hint — sheets get one by default, the spacer
            // here is just visual breathing room above the title.
            Spacer().frame(height: 6)

            Text(LiveStreamCopy.live)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .kerning(2)
                .foregroundStyle(.secondary)

            LiveEngagementOverlay(controller: controller, layout: .expanded)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
