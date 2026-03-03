import AVKit
import SwiftUI

struct LiveTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let streamURL: URL
    let channelName: String

    @State private var player: AVPlayer?
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
                    .overlay { controlsOverlay }
            } else {
                ProgressView("Tuning...")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { setupPlayer() }
        .onDisappear { teardown() }
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

    private func setupPlayer() {
        let avPlayer = AVPlayer(url: streamURL)
        avPlayer.play()
        player = avPlayer
        scheduleControlsHide()
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

    private func teardown() {
        controlsTask?.cancel()
        player?.pause()
        player = nil
    }
}
