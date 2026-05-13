import SwiftUI
import LiveStreamingKit

@MainActor
public struct LiveStreamControlView: View {
    @ObservedObject public var viewModel: LiveStreamControlViewModel

    public init(viewModel: LiveStreamControlViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            primaryButton
            metricsRow
            listenerLinkSection
            footnote
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var header: some View {
        HStack {
            LiveStreamStatusBadge(state: viewModel.state)
            Spacer()
            if viewModel.isLive {
                Text(viewModel.formattedUptime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await viewModel.toggle() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isWorking {
                    ProgressView().controlSize(.small)
                }
                Text(viewModel.primaryButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.primaryButtonTint)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        .accessibilityIdentifier("livestream.toggle")
    }

    private var metricsRow: some View {
        HStack(spacing: 16) {
            metric(value: "\(viewModel.listenerCount)", label: LiveStreamCopy.listeners)
            metric(value: viewModel.latencyText, label: LiveStreamCopy.latency)
            metric(value: "\(viewModel.segmentsSent)", label: LiveStreamCopy.segmentsSent)
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var listenerLinkSection: some View {
        if let session = viewModel.activeSession {
            VStack(alignment: .leading, spacing: 6) {
                Text(LiveStreamCopy.listenerLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(session.listenerURL.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    LiveStreamCopyURLButton(url: session.listenerURL)
                }
                Text(LiveStreamCopy.listenerHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footnote: some View {
        Text(LiveStreamCopy.recordingPreservedNote)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    let viewModel = LiveStreamControlViewModel.preview()
    return LiveStreamControlView(viewModel: viewModel)
        .padding()
}
