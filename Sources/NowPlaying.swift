import Foundation
import MediaPlayer

/// Publishes playback state to the lock screen and Control Center, and routes
/// their commands back to the player.
///
/// The app already declares the `audio` background mode, so sound continues
/// when the screen locks. Without this class the system has no idea what is
/// playing and the lock-screen controls do nothing, which feels broken.
@MainActor
final class NowPlayingController {
    private var isWired = false
    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onSkip: ((Double) -> Void)?
    private var onSeek: ((Double) -> Void)?

    func wire(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        skip: @escaping (Double) -> Void,
        seek: @escaping (Double) -> Void
    ) {
        onPlay = play
        onPause = pause
        onSkip = skip
        onSeek = seek

        // Targets are added once; the closures above are swapped freely.
        guard !isWired else { return }
        isWired = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.onSkip?(-10)
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.onSkip?(30)
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onSeek?(event.positionTime)
            return .success
        }
    }

    func update(title: String, elapsed: Double, duration: Double, isPlaying: Bool, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Easynews",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
