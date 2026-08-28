import SwiftUI

struct PlayerScreen: View {
    let request: PlaybackRequest

    @EnvironmentObject var state: AppState
    @StateObject private var player = VLCPlayerController()
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

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
                controls
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
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

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .padding(10)
                }
                .buttonStyle(.plain)

                Text(request.file.baseName)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 36) {
                transportButton("gobackward.10") { player.skip(seconds: -10) }
                transportButton(player.isPlaying ? "pause.fill" : "play.fill", size: 44) {
                    player.togglePlayPause()
                    scheduleHide()
                }
                transportButton("goforward.30") { player.skip(seconds: 30) }
            }

            Spacer()

            HStack(spacing: 10) {
                Text(player.elapsedText)
                    .font(.caption.monospacedDigit())

                Slider(
                    value: Binding(
                        get: { Double(player.position) },
                        set: { player.seek(to: Float($0)) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        player.isScrubbing = editing
                        if !editing { scheduleHide() }
                    }
                )

                Text(player.remainingText)
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat = 28,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size + 20, height: size + 20)
        }
        .buttonStyle(.plain)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible { scheduleHide() }
    }

    /// Auto-hide the overlay after a few idle seconds, but never mid-scrub.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !player.isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }
}
