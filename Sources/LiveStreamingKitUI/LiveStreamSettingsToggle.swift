import SwiftUI

public struct LiveStreamSettingsToggle: View {
    @Binding public var isEnabled: Bool
    @Binding public var title: String

    public init(isEnabled: Binding<Bool>, title: Binding<String>) {
        self._isEnabled = isEnabled
        self._title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LiveStreamCopy.enableForNext)
                        .font(.body)
                    Text(LiveStreamCopy.recordingPreservedNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LiveStreamCopy.titleField)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(LiveStreamCopy.titlePlaceholder, text: $title)
                        .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var enabled = true
    @Previewable @State var title = ""
    return LiveStreamSettingsToggle(isEnabled: $enabled, title: $title)
        .padding()
}
