# LiveStreamingKitUI

SwiftUI views for [LiveStreamingKit](https://github.com/samirsd/LiveStreamingKit). Lowercase copy throughout, matching Carnyx's house style.

## Views

- `LiveStreamControlView` — full-bleed start/stop control with state, listener count, share affordance, floating reactions overlay, and an end-of-stream summary card.
- `LiveStreamStatusBadge` — small inline badge for surfacing "live" status in a list row.
- `LiveStreamShareSheet` — system share sheet preconfigured with the listener URL + tape title.
- `LiveStreamCopyURLButton` — one-tap copy of the listener URL.
- `LiveStreamSettingsToggle` — toggle to enable live streaming for the next recording.
- `LiveStreamLatencyMeter` — small ms-latency readout, mainly for diagnostic use.

### Engagement components

The control view embeds these by default. Exposed publicly so consumers can compose them into other surfaces (a band-room remote, a watch glance, etc.).

- `ListenerCountChip(count:toastEnabled:)` — "N listeners" with a spring pulse on increment and a transient "+N joined" toast.
- `VibeMeter(reactions:windowSeconds:saturationCount:)` — capsule bar driven by recent reaction velocity (rolling 6s window by default).
- `BroadcastSummaryCard(totalListeners:peakListenerCount:reactionTotals:onDismiss:)` — overlay rendered after a `.live → .stopped/.failed` transition.
- `FloatingReactionsOverlay` — small ZStack that animates each reaction upward + fading. Re-renders driven by `LiveStreamControlViewModel.floatingReactions`.
- `LiveStreamReactionDisplay` — public emoji map + canonical type ordering so consumers stay visually consistent.

All animations honor `accessibilityReduceMotion` — the pulse, vibe glow, and reaction y-rise drop to opacity-only fades when "Reduce Motion" is on.

### View-model state

`LiveStreamControlViewModel` adds, beyond the original metrics:

- `totalListeners: Int`, `peakListenerCount: Int`
- `reactionTotals: [String: Int]`
- `floatingReactions: [LiveReactionEvent]` (auto-pruned after `reactionFloatDuration`, default 1.8s)
- `justEndedBroadcast: Bool` — flips true on `.live → .stopped/.failed`, reset via `acknowledgeBroadcastEnd()`

### Pro listener integration

`LiveListenerCoordinator` obtains an authenticated playback grant before starting
audio. Its `playbackState` distinguishes access checks, sign-in/Pro requirements,
connection failures, and grant expiry. `liveListenerSheet` renders those states.
Provide `onAccessRequired` to open account sign-in or the broadcast's web listening
options. Trial eligibility remains a checkout decision.

Forward account identity changes to `authenticationDidChange()` and player errors
to `playbackDidFail()`. Both stop owned audio and require explicit retry; retry
always requests a fresh grant. On grant expiry, audio stops and the sheet offers
reconnection rather than failing silently. Closing/replacing the presentation
invalidates outstanding grant requests.

### Video listeners

Session metadata with `media_type: "video"` selects a single native `AVPlayer`
inside the listener sheet. Its HLS rendition owns both picture and sound; the
host's audio-only playback bridge is not started. Missing media metadata keeps
the existing audio behavior. Video dimensions determine aspect-fit framing,
including 9:16 portrait broadcasts, and native controls provide play, seek and
fullscreen playback.

Initial video presentation prepares the player and requires a play gesture.
Backgrounding pauses video and does not automatically resume it. Dismissal,
account replacement, grant expiry and failures remove the current player item.
Failures expose fixed recovery copy rather than raw errors containing signed
media URLs.

Video grants may include `media_url_refresh_after_seconds`. The coordinator
reauthorizes and reloads the rendition before private object links expire,
preserving current position and paused/playing intent. A renewal rejection
stops playback and shows the existing access/retry state. This also supports
ended replays whose HLS playlist otherwise would not refresh automatically.

`LiveListenerVideoPlayback` can be injected for lifecycle tests or a host video
player. The default `AVPlayerLiveListenerVideoPlayback` retains one player and
replaces its item after authorization. Physical device capture and long-running
venue/network tests remain part of application release validation.

### Host popup presentation

The default listener still uses `liveListenerSheet`. A host with an existing
video popup can opt into `LiveListenerCoordinator(videoPresentationMode:
.hostPopup)`. Observe `usesHostVideoPresentation` and borrow `videoPlayer`;
the coordinator remains the sole owner of playback authorization, renewal,
position restoration and player-item replacement. Do not construct another
player or request a second grant. Metadata resolves before video suppresses
the normal sheet; audio and initial metadata failures retain that sheet.

Embed `LiveListenerContent(controller:coordinator:showsVideo:false,
showsHeader:false)` below the borrowed player to retain reactions, listening
options and reconnect controls. The content uses FontKit typography and
semantic colors. Forward account changes and background pauses as usual.
When switching to other media, call `beginDismiss(ifPresenting:)` to detach
authorized playback synchronously before awaiting social-poller shutdown.
Fence popup updates by the exact controller/request identity so late renewals
cannot dismiss a newer selection. Live status changes should update existing
chrome without expanding a docked player, and live HLS has no finite progress.

This presentation API accepts an already known session ID. It does not add
recording-to-video discovery: a cloud-only recording on another device still
needs authorized server metadata linking the recording to its video session.
The local archive catalog is not a substitute for that server contract.

## Installation

```swift
.package(path: "../LiveStreamingKitUI")
```
