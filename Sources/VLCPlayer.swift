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
/// The delegate method signatures changed between VLCKit 3 and 4, and polling
/// four properties twice a second costs nothing while staying version-agnostic.
@MainActor
final class VLCPlayerController: ObservableObject {
    @Published var isPlaying = false
    @Published var position: Float = 0
    @Published var elapsedText = "--:--"
    @Published var remainingText = "--:--"
    @Published var isBuffering = true
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
    private var ticker: Timer?

    init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        #if os(iOS)
        // Without this, playback stops on silent-switch and can't continue in background.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func attach(to view: PlatformView) {
        player.drawable = view
    }

    // MARK: - Tracks

    /// Tracks only exist once VLC has parsed the container, so this is polled
    /// alongside playback state rather than read once at load.
    private func refreshTracks() {
        audioTracks = player.audioTracks.map {
            TrackInfo(id: $0.trackId, name: $0.trackName, isSelected: $0.isSelected)
        }
        subtitleTracks = player.textTracks.map {
            TrackInfo(id: $0.trackId, name: $0.trackName, isSelected: $0.isSelected)
        }
    }

    func selectAudioTrack(id: String) {
        guard let track = player.audioTracks.first(where: { $0.trackId == id }) else { return }
        player.deselectAllAudioTracks()
        track.isSelected = true
        refreshTracks()
    }

    /// Passing nil turns subtitles off.
    func selectSubtitleTrack(id: String?) {
        if let id, let track = player.textTracks.first(where: { $0.trackId == id }) {
            player.selectTextTracks([track])
        } else {
            player.deselectAllTextTracks()
        }
        refreshTracks()
    }

    func load(url: URL, username: String, password: String) {
        guard let media = VLCMedia(url: url) as VLCMedia? else { return }

        // Generous caching: Usenet files stream from a CDN and stutter on the
        // default 300ms buffer, especially over cellular.
        media.addOption(":network-caching=5000")
        media.addOption(":file-caching=5000")
        media.addOption(":http-reconnect")

        if !username.isEmpty {
            media.addOption(":http-user=\(username)")
            media.addOption(":http-pwd=\(password)")
        }

        player.media = media
        player.play()
        isBuffering = true
        startTicker()
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        refresh()
    }

    func seek(to newPosition: Float) {
        let clamped = max(0, min(1, newPosition))
        player.position = .init(clamped)
    }

    /// Jump forward or back. VLCKit's jump methods take seconds as Int32.
    func skip(seconds: Int32) {
        if seconds >= 0 {
            player.jumpForward(.init(seconds))
        } else {
            player.jumpBackward(.init(-seconds))
        }
        refresh()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        isPlaying = player.isPlaying

        if !isScrubbing {
            position = Float(player.position)
        }

        elapsedText = (player.time as VLCTime?)?.stringValue ?? "--:--"
        remainingText = (player.remainingTime as VLCTime?)?.stringValue ?? "--:--"

        // Once the clock moves off zero we have real frames.
        if isBuffering && Float(player.position) > 0 {
            isBuffering = false
        }

        refreshTracks()
    }
}

// MARK: - SwiftUI bridge

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

/// VLC only needs somewhere to draw; it should never consume touches.
/// Without this the video layer swallows every tap and the overlay controls
/// can't be summoned back once they auto-hide.
#if os(macOS)
final class PassthroughVideoView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#else
final class PassthroughVideoView: UIView {}
#endif

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
