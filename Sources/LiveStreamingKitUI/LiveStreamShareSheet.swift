import SwiftUI

#if canImport(UIKit)
import UIKit

public struct LiveStreamShareSheet: UIViewControllerRepresentable {
    public let url: URL
    public let title: String?

    public init(url: URL, title: String? = nil) {
        self.url = url
        self.title = title
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [url]
        if let title { items.insert(title + " — " + LiveStreamCopy.listenerLabel as Any, at: 0) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
