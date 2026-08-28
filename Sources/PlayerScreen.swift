import SwiftUI

struct PlayerScreen: View {
    let request: PlaybackRequest

    @EnvironmentObject var state: AppState
    @StateObject private var player = VLCPlayerController()
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCVideoSurface(controller: player)
                .ignoresSafeArea()

            if player.isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Buffering…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if controlsVisible {
                controls.transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .gesture(
            // Swipe down to leave, so there is always a way out even if the
            // overlay happens to be hidden.
            DragGesture()
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
        )
        .onAppear {
            player.load(
                url: request.url,
                username: state.credentials.username,
                password: state.credentials.password
            )
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            player.stop()
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 420)
        #endif
    }

    // MARK: - Overlay

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
            }
        }
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.35), in: Circle())
    }

    private var transportRow: some View {
        HStack(spacing: 40) {
            transportButton("gobackward.10", size: 30) { player.skip(seconds: -10) }
            transportButton(player.isPlaying ? "pause.fill" : "play.fill", size: 46) {
                player.togglePlayPause()
                scheduleHide()
            }
            transportButton("goforward.30", size: 30) { player.skip(seconds: 30) }
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 26, height: size + 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
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
}
