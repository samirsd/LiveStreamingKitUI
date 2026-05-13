import XCTest
@testable import LiveStreamingKitUI

final class LiveStreamCopyTests: XCTestCase {

    func testAllCopyIsLowercaseExceptIntentionalCases() {
        // Carnyx house style: lowercase everywhere. The only acceptable uppercase is
        // when a proper noun is unavoidable (e.g. "Apple Music"). All strings below
        // must be lowercase except for the explicit allow-list.
        let allowProperNouns: Set<String> = ["apple music"]
        let copy: [String] = [
            LiveStreamCopy.goLive,
            LiveStreamCopy.stopLive,
            LiveStreamCopy.starting,
            LiveStreamCopy.stopping,
            LiveStreamCopy.live,
            LiveStreamCopy.offline,
            LiveStreamCopy.failed,
            LiveStreamCopy.share,
            LiveStreamCopy.copy,
            LiveStreamCopy.copied,
            LiveStreamCopy.openInPlayer,
            LiveStreamCopy.listeners,
            LiveStreamCopy.latency,
            LiveStreamCopy.segmentsSent,
            LiveStreamCopy.kbps,
            LiveStreamCopy.recordingPreservedNote,
            LiveStreamCopy.listenerLabel,
            LiveStreamCopy.listenerHint,
            LiveStreamCopy.enableForNext,
            LiveStreamCopy.titleField,
            LiveStreamCopy.titlePlaceholder,
        ]
        for entry in copy {
            let normalized = entry.lowercased()
            XCTAssertEqual(entry, normalized, "'\(entry)' must be lowercase per Carnyx house style")
        }
    }

    func testNoCopyIsEmpty() {
        let copy = [
            LiveStreamCopy.goLive,
            LiveStreamCopy.stopLive,
            LiveStreamCopy.live,
            LiveStreamCopy.offline,
            LiveStreamCopy.failed,
        ]
        for entry in copy {
            XCTAssertFalse(entry.isEmpty)
        }
    }
}
