import AVFoundation
import AVKit
import SwiftUI

struct WatchLivePlayerView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss

    let streamURL: URL
    let channelName: String

    @State private var coordinator: WatchAVPlayerController?
    @State private var avPlayer: AVPlayer?
    @State private var isLandscape = false
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                }
                .padding()
            } else if let avPlayer {
                GeometryReader { geo in
                    let w = isLandscape ? geo.size.height : geo.size.width
                    let h = isLandscape ? geo.size.width : geo.size.height
                    let screenRatio = w / h
                    let videoRatio: CGFloat = 16.0 / 9.0
                    let scale = videoRatio / screenRatio
                    VideoPlayer(player: avPlayer)
                        .scaleEffect(y: scale)
                        .frame(width: w, height: h)
                        .rotationEffect(isLandscape ? .degrees(90) : .zero)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay {
                            let buttonOpacity: Double = showControls ? 0.7 : 0
                            VStack {
                                HStack {
                                    Button { dismiss() } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(.black.opacity(0.4), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }
                                Spacer()
                                HStack {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            isLandscape.toggle()
                                        }
                                        scheduleControlsHide()
                                    } label: {
                                        Image(systemName: "crop.rotate")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(.black.opacity(0.4), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                    Text(channelName)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.4), in: Capsule())
                                }
                            }
                            .padding(8)
                            .opacity(buttonOpacity)
                            .animation(.easeInOut(duration: 0.3), value: showControls)
                            .allowsHitTesting(showControls)
                        }
                }
                .clipped()
                .ignoresSafeArea()
                .toolbar(.hidden)
                .persistentSystemOverlays(.hidden)
                .onAppear { scheduleControlsHide() }
                .simultaneousGesture(
                    TapGesture().onEnded { scheduleControlsHide() }
                )
            } else {
                ProgressView("Tuning...")
            }
        }
        .task {
            await setupPlayer()
        }
        .onDisappear {
            teardown()
        }
    }

    private func setupPlayer() async {
        let proxy = HLSProxyServer.shared
        if let serverBase = plexApiContext.baseURLServer {
            do {
                try await proxy.start(baseURL: serverBase)
            } catch {
                errorMessage = "Failed to start proxy: \(error.localizedDescription)"
                return
            }
        }

        let playURL = proxy.proxyURL(for: streamURL) ?? streamURL

        let playerCoordinator = WatchAVPlayerController(options: PlayerOptions())
        coordinator = playerCoordinator

        // Wait for readyToPlay before attaching to VideoPlayer
        playerCoordinator.onMediaLoaded = { [playerCoordinator] in
            avPlayer = playerCoordinator.player
        }

        playerCoordinator.play(playURL)
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
        coordinator?.destruct()
        coordinator = nil
        avPlayer = nil
        HLSProxyServer.shared.stop()
    }
}
