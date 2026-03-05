import SwiftUI

struct LiveTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let streamURL: URL
    let channelName: String

    @State private var playerCoordinator: any PlayerCoordinating = PlayerFactory.makeCoordinator(
        for: .mpv,
        options: PlayerOptions()
    )
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var isBuffering = false
    @State private var mediaLoaded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerFactory.makeView(
                selection: .mpv,
                coordinator: playerCoordinator,
                onPropertyChange: { property, data in
                    if property == .pausedForCache {
                        isBuffering = (data as? Bool) ?? false
                    }
                },
                onPlaybackEnded: {
                    dismiss()
                },
                onMediaLoaded: {
                    mediaLoaded = true
                }
            )
            .ignoresSafeArea()
            .onTapGesture { toggleControls() }
            .overlay { controlsOverlay }

            if !mediaLoaded {
                ProgressView("Tuning...")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if mediaLoaded, isBuffering {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Buffering...")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            playerCoordinator.play(streamURL)
            scheduleControlsHide()
        }
        .onDisappear {
            controlsTask?.cancel()
            playerCoordinator.destruct()
        }
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5), in: Circle())
                }
                Spacer()
            }

            Spacer()

            HStack {
                Text(channelName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                Spacer()
            }
        }
        .padding()
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .allowsHitTesting(showControls)
    }

    private func toggleControls() {
        if showControls {
            withAnimation { showControls = false }
            controlsTask?.cancel()
        } else {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        showControls = true
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
}
