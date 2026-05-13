# LiveStreamingKitUI

SwiftUI views for [LiveStreamingKit](https://github.com/samirsd/LiveStreamingKit). Lowercase copy throughout, matching Carnyx's house style.

## Views

- `LiveStreamControlView` — full-bleed start/stop control with state, listener count, share affordance.
- `LiveStreamStatusBadge` — small inline badge for surfacing "live" status in a list row.
- `LiveStreamShareSheet` — system share sheet preconfigured with the listener URL + tape title.
- `LiveStreamCopyURLButton` — one-tap copy of the listener URL.
- `LiveStreamSettingsToggle` — toggle to enable live streaming for the next recording.
- `LiveStreamLatencyMeter` — small ms-latency readout, mainly for diagnostic use.

## Installation

```swift
.package(path: "../LiveStreamingKitUI")
```
