import Foundation
import Combine
@preconcurrency import AVFoundation

public struct LiveListenerVideoSnapshot: Equatable, Sendable {
    public var position: TimeInterval
    public var playing: Bool

    public init(position: TimeInterval, playing: Bool) {
        self.position = position
        self.playing = playing
    }
}

/// A single video player owns the HLS rendition's audio as well as its image.
/// The existing audio-only bridge must not be started for the same broadcast.
@MainActor
public protocol LiveListenerVideoPlayback: AnyObject {
    var player: AVPlayer { get }
    var snapshot: LiveListenerVideoSnapshot { get }
    var onFailure: (@MainActor () -> Void)? { get set }
    func prepare(url: URL, restoring: LiveListenerVideoSnapshot?)
    func pause()
    func stop()
}

@MainActor
public final class AVPlayerLiveListenerVideoPlayback: LiveListenerVideoPlayback {
    public let player = AVPlayer()
    public var onFailure: (@MainActor () -> Void)?
    private var observation: NSKeyValueObservation?
    private var endFailure: AnyCancellable?
    private var generation: UInt64 = 0

    public init() {
        player.automaticallyWaitsToMinimizeStalling = true
    }

    public var snapshot: LiveListenerVideoSnapshot {
        let position = player.currentTime().seconds
        return LiveListenerVideoSnapshot(
            position: position.isFinite ? max(0, position) : 0,
            playing: player.rate != 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        )
    }

    public func prepare(url: URL, restoring: LiveListenerVideoSnapshot?) {
        stop()
        let requestGeneration = generation
        let item = AVPlayerItem(url: url)
        endFailure = NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == requestGeneration else { return }
                    self.pause()
                    self.onFailure?()
                }
            }
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestGeneration,
                      self.player.currentItem === item else { return }
                if status == .failed {
                    self.pause()
                    // AVPlayer errors may contain media capabilities. The host
                    // receives only a fixed failure signal, never the raw error.
                    self.onFailure?()
                } else if status == .readyToPlay, let restoring {
                    let position = restoring.position.isFinite ? max(0, restoring.position) : 0
                    self.player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == requestGeneration else { return }
                            if restoring.playing { self.player.play() }
                        }
                    }
                }
            }
        }
        // Initial presentation prepares a frame; the native controls require a
        // play gesture. Only an already-playing authorized renewal resumes.
        player.replaceCurrentItem(with: item)
    }

    public func pause() { player.pause() }

    public func stop() {
        generation &+= 1
        observation?.invalidate()
        observation = nil
        endFailure?.cancel()
        endFailure = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
