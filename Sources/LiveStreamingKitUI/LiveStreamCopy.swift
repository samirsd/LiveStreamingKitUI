import Foundation

/// Centralized lowercase copy for live-streaming UI surfaces.
/// All Carnyx-facing strings live in lowercase per the house style.
public enum LiveStreamCopy {
    public static let goLive = "go live"
    public static let stopLive = "stop live"
    public static let starting = "preparing stream…"
    public static let stopping = "ending stream…"
    public static let live = "live"
    public static let offline = "offline"
    public static let failed = "stream failed"
    public static let share = "share listener link"
    public static let copy = "copy listener link"
    public static let copied = "copied"
    public static let openInPlayer = "open in apple music"
    public static let listeners = "listeners"
    public static let latency = "latency"
    public static let segmentsSent = "segments sent"
    public static let kbps = "kbps"
    public static let recordingPreservedNote = "stems keep recording locally regardless of stream state."
    public static let listenerLabel = "live link"
    public static let listenerHint = "anyone with this link can listen to this set live."
    public static let enableForNext = "stream the next recording"
    public static let titleField = "set name"
    public static let titlePlaceholder = "untitled set"

    // MARK: - Engagement

    public static let listenerJoinedSuffix = "joined"
    public static let listenerJoinedSingularPrefix = "+1"
    public static let totalListenersLabel = "total"
    public static let peakListenersLabel = "peak"
    public static let reactionsLabel = "reactions"
    public static let vibeLabel = "vibe"
    public static let broadcastEndedTitle = "set complete"
    public static let broadcastSummaryDismiss = "done"
    public static let waitingForListeners = "waiting for first listener"
    public static let firstReactionHint = "your listeners can react in real time"
}
