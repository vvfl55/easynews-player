import SwiftUI
import VLCKit

#if os(iOS)
import AVFoundation
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif

/// Owns the VLCMediaPlayer and publishes playback state to SwiftUI.
///
/// State is polled on a timer rather than read from VLCMediaPlayerDelegate.
/// The delegate signatures changed between VLCKit 3 and 4, and polling a
/// handful of properties twice a second costs nothing while staying
/// version-agnostic. Every published property is written only when it
/// actually changes, so SwiftUI is not re-rendered on every tick.
@MainActor
final class VLCPlayerController: ObservableObject {
    @Published var isPlaying = false
    @Published var position: Float = 0
    @Published var elapsedText = "--:--"
    @Published var remainingText = "--:--"
    @Published var isBuffering = true
    @Published var playbackError: String?
    @Published var durationSeconds: Double = 0
    @Published var rate: Float = 1.0
    @Published var audioTracks: [TrackInfo] = []
    @Published var subtitleTracks: [TrackInfo] = []

    struct TrackInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let isSelected: Bool
    }

    /// Set while the user drags the scrubber so polling doesn't fight the gesture.
    var isScrubbing = false

    let player = VLCMediaPlayer()
    let nowPlaying = NowPlayingController()

    private var ticker: Timer?
    private var pendingResume: Float?
    private var trackSignature = ""
    private var mediaTitle = ""
    private var lastNowPlayingPush = Date.distantPast
    private var lastNowPlayingState = false

    init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        #if os(iOS)
        // Without this, playback stops on the silent switch and cannot
        // continue while the screen is locked.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func attach(to view: PlatformView) {
        player.drawable = view
    }

    // MARK: - Loading

    func load(url: URL, username: String, password: String, title: String, resumeAt: Float?) {
        guard let media = VLCMedia(url: url) as VLCMedia? else {
            playbackError = "Couldn't open that URL."
            return
        }

        // Usenet files stream from a CDN and stutter badly on VLC's default
        // 300ms buffer, especially over cellular.
        media.addOption(":network-caching=5000")
        media.addOption(":file-caching=5000")
        media.addOption(":http-reconnect")

        if !username.isEmpty {
            media.addOption(":http-user=\(username)")
            media.addOption(":http-pwd=\(password)")
        }

        mediaTitle = title
        pendingResume = resumeAt
        playbackError = nil
        isBuffering = true

        player.media = media
        player.play()

        setScreenAwake(true)
        wireRemoteCommands()
        startTicker()
    }

    // MARK: - Transport

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
        refresh()
    }

    func play() {
        if !player.isPlaying { player.play() }
        refresh()
    }

    func pause() {
        if player.isPlaying { player.pause() }
        refresh()
    }

    func seek(to newPosition: Float) {
        let clamped = max(0, min(1, newPosition))
        player.position = .init(clamped)
    }

    func seek(toSeconds seconds: Double) {
        guard durationSeconds > 0 else { return }
        seek(to: Float(seconds / durationSeconds))
    }

    /// Jump forward or back. VLCKit 4 takes the interval as a double.
    func skip(seconds: Int32) {
        if seconds >= 0 {
            player.jumpForward(.init(seconds))
        } else {
            player.jumpBackward(.init(-seconds))
        }
        refresh()
    }

    func setRate(_ newRate: Float) {
        player.rate = newRate
        rate = newRate
    }

    func retry() {
        guard let media = player.media else { return }
        playbackError = nil
        isBuffering = true
        player.media = media
        player.play()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player.stop()
        setScreenAwake(false)
        nowPlaying.clear()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    // MARK: - Tracks

    func selectAudioTrack(id: String) {
        guard let track = player.audioTracks.first(where: { $0.trackId == id }) else { return }
        player.deselectAllAudioTracks()
        track.isSelected = true
        refreshTracks(force: true)
    }

    /// Passing nil turns subtitles off.
    func selectSubtitleTrack(id: String?) {
        if let id, let track = player.textTracks.first(where: { $0.trackId == id }) {
            player.selectTextTracks([track])
        } else {
            player.deselectAllTextTracks()
        }
        refreshTracks(force: true)
    }

    /// Tracks only exist once VLC has parsed the container, so they are polled.
    /// A signature check keeps this from republishing identical arrays twice a
    /// second, which would rebuild the track menus continuously.
    private func refreshTracks(force: Bool = false) {
        let audio = player.audioTracks
        let text = player.textTracks
        let signature = (audio + text)
            .map { "\($0.trackId):\($0.isSelected)" }
            .joined(separator: "|")

        guard force || signature != trackSignature else { return }
        trackSignature = signature

        audioTracks = audio.map {
            TrackInfo(id: $0.trackId, name: $0.trackName, isSelected: $0.isSelected)
        }
        subtitleTracks = text.map {
            TrackInfo(id: $0.trackId, name: $0.trackName, isSelected: $0.isSelected)
        }
    }

    // MARK: - Polling

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        let playing = player.isPlaying
        if isPlaying != playing { isPlaying = playing }

        let currentPosition = Float(player.position)
        if !isScrubbing, abs(position - currentPosition) > 0.0001 {
            position = currentPosition
        }

        let elapsed = (player.time as VLCTime?)?.stringValue ?? "--:--"
        if elapsedText != elapsed { elapsedText = elapsed }

        let remaining = (player.remainingTime as VLCTime?)?.stringValue ?? "--:--"
        if remainingText != remaining { remainingText = remaining }

        let lengthMs = player.media?.length.value?.doubleValue ?? 0
        let seconds = lengthMs / 1000
        if seconds > 0, abs(durationSeconds - seconds) > 0.5 { durationSeconds = seconds }

        // Once the clock moves off zero there are real frames on screen.
        if isBuffering && currentPosition > 0 { isBuffering = false }

        // Seek to the saved position only after playback has genuinely begun;
        // seeking during opening is ignored by VLC.
        if let resume = pendingResume, currentPosition > 0 {
            pendingResume = nil
            seek(to: resume)
        }

        if player.state == .error, playbackError == nil {
            playbackError = "Playback failed. The file may be incomplete, or your Easynews session may have expired."
            isBuffering = false
        }

        refreshTracks()
        updateNowPlaying()
    }

    // MARK: - System integration

    private func wireRemoteCommands() {
        nowPlaying.wire(
            play: { [weak self] in self?.togglePlayPause() },
            pause: { [weak self] in self?.pause() },
            skip: { [weak self] delta in self?.skip(seconds: Int32(delta)) },
            seek: { [weak self] seconds in self?.seek(toSeconds: seconds) }
        )
    }

    private func updateNowPlaying() {
        // Writing nowPlayingInfo crosses a process boundary, so push on state
        // changes and otherwise at most every two seconds rather than on
        // every 0.5s tick.
        let now = Date()
        let stateChanged = lastNowPlayingState != isPlaying
        guard stateChanged || now.timeIntervalSince(lastNowPlayingPush) >= 2 else { return }
        lastNowPlayingPush = now
        lastNowPlayingState = isPlaying

        nowPlaying.update(
            title: mediaTitle,
            elapsed: durationSeconds * Double(position),
            duration: durationSeconds,
            isPlaying: isPlaying,
            rate: rate
        )
    }

    /// A two-hour film should not be interrupted by the screen locking.
    private func setScreenAwake(_ awake: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }
}

// MARK: - SwiftUI bridge

/// VLC only needs somewhere to draw; it should never consume touches.
/// Without this the video layer swallows every tap and the overlay controls
/// cannot be summoned back once they auto-hide.
#if os(macOS)
final class PassthroughVideoView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#else
final class PassthroughVideoView: UIView {}
#endif

/// Hosts the VLC drawable surface. UIView on iOS, NSView on macOS.
///
/// @MainActor because it touches VLCPlayerController, which is main-actor
/// isolated. UIViewRepresentable/NSViewRepresentable are themselves
/// @MainActor, so the conformance in the extensions below still matches.
@MainActor
struct VLCVideoSurface {
    let controller: VLCPlayerController

    private func makeSurface() -> PlatformView {
        let view = PassthroughVideoView()
        #if os(macOS)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        #else
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        #endif
        controller.attach(to: view)
        return view
    }
}

#if os(iOS)
extension VLCVideoSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> PlatformView { makeSurface() }
    func updateUIView(_ uiView: PlatformView, context: Context) {}
}
#else
extension VLCVideoSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> PlatformView { makeSurface() }
    func updateNSView(_ nsView: PlatformView, context: Context) {}
}
#endif
