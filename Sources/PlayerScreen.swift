import SwiftUI

struct PlayerScreen: View {
    let request: PlaybackRequest

    @EnvironmentObject var state: AppState
    @StateObject private var player = VLCPlayerController()
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0
    @State private var seekFlash: String?

    private static let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCVideoSurface(controller: player)
                .ignoresSafeArea()

            tapLayer

            if let error = player.playbackError {
                errorOverlay(error)
            } else if player.isBuffering {
                bufferingOverlay
            }

            if let flash = seekFlash {
                Text(flash)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.55), in: Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if controlsVisible && player.playbackError == nil {
                controls.transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 420)
        #endif
    }

    // MARK: - Gestures

    /// Two halves so a double tap can seek in a direction. Single tap still
    /// toggles the overlay; attaching count: 2 first lets SwiftUI disambiguate.
    private var tapLayer: some View {
        HStack(spacing: 0) {
            seekZone(seconds: -10, label: "− 10s")
            seekZone(seconds: 30, label: "+ 30s")
        }
        .ignoresSafeArea()
    }

    private func seekZone(seconds: Int32, label: String) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                player.skip(seconds: seconds)
                flash(label)
            }
            .onTapGesture(count: 1) { toggleControls() }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if value.translation.height > 0 { dragOffset = value.translation.height }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Overlays

    private var bufferingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Buffering…")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .allowsHitTesting(false)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Retry") { player.retry() }
                    .buttonStyle(.borderedProminent)

                Button("Open in VLC") {
                    Task {
                        if let url = await state.externalPlayerURL(for: request.file, scheme: .vlc) {
                            openExternal(url)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .tint(.white)
        }
        .padding(24)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .padding(24)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            transportRow
            Spacer()
            scrubberRow
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.15), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")

            Text(request.file.baseName)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            trackMenus
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var trackMenus: some View {
        HStack(spacing: 8) {
            if player.audioTracks.count > 1 {
                Menu {
                    ForEach(player.audioTracks) { track in
                        Button {
                            player.selectAudioTrack(id: track.id)
                            scheduleHide()
                        } label: {
                            Text(track.isSelected ? "\(track.name)  ✓" : track.name)
                        }
                    }
                } label: {
                    circleIcon("waveform")
                }
                .accessibilityLabel("Audio track")
            }

            if !player.subtitleTracks.isEmpty {
                Menu {
                    Button("Off") {
                        player.selectSubtitleTrack(id: nil)
                        scheduleHide()
                    }
                    ForEach(player.subtitleTracks) { track in
                        Button {
                            player.selectSubtitleTrack(id: track.id)
                            scheduleHide()
                        } label: {
                            Text(track.isSelected ? "\(track.name)  ✓" : track.name)
                        }
                    }
                } label: {
                    circleIcon("captions.bubble")
                }
                .accessibilityLabel("Subtitles")
            }

            Menu {
                ForEach(Self.speeds, id: \.self) { speed in
                    Button {
                        player.setRate(speed)
                        scheduleHide()
                    } label: {
                        Text(player.rate == speed ? "\(speedLabel(speed))  ✓" : speedLabel(speed))
                    }
                }
            } label: {
                circleIcon("speedometer")
            }
            .accessibilityLabel("Playback speed")
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1.0 ? "Normal" : String(format: "%.2gx", speed)
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.35), in: Circle())
    }

    private var transportRow: some View {
        HStack(spacing: 40) {
            transportButton("gobackward.10", size: 30, label: "Back 10 seconds") {
                player.skip(seconds: -10)
            }
            transportButton(
                player.isPlaying ? "pause.fill" : "play.fill",
                size: 46,
                label: player.isPlaying ? "Pause" : "Play"
            ) {
                player.togglePlayPause()
                scheduleHide()
            }
            transportButton("goforward.30", size: 30, label: "Forward 30 seconds") {
                player.skip(seconds: 30)
            }
        }
    }

    private var scrubberRow: some View {
        HStack(spacing: 10) {
            Text(player.elapsedText)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 52, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(player.position) },
                    set: { player.seek(to: Float($0)) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    player.isScrubbing = editing
                    if editing { hideTask?.cancel() } else { scheduleHide() }
                }
            )
            .tint(.white)
            .accessibilityLabel("Playback position")

            Text(player.remainingText)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 26, height: size + 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Lifecycle

    private func start() {
        player.load(
            url: request.url,
            username: state.credentials.username,
            password: state.credentials.password,
            title: request.file.baseName,
            resumeAt: request.resumeAt
        )
        scheduleHide()
    }

    private func finish() {
        hideTask?.cancel()
        // Save before stopping; stop() tears the player down.
        PlaybackStore.saveResumePosition(player.position, for: request.file.id)
        player.stop()
    }

    // MARK: - Visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { seekFlash = text }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.2)) { seekFlash = nil }
        }
    }

    /// Auto-hide after a few idle seconds, but never while paused or scrubbing.
    /// A paused screen with no controls is a dead end.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, !player.isScrubbing, player.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private func openExternal(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}
