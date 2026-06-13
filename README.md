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

## Installation

```swift
.package(path: "../LiveStreamingKitUI")
```
