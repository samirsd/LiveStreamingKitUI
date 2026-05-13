import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public struct LiveStreamCopyURLButton: View {
    public let url: URL
    @State private var copied = false

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        Button {
            copy()
        } label: {
            Label(copied ? LiveStreamCopy.copied : LiveStreamCopy.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("livestream.copyURL")
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif
