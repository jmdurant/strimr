import AVKit
import SwiftUI

struct LiveTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let streamURL: URL
    let channelName: String
    let programTitle: String?
    let programEndsAt: Date?

    @State private var player = AVPlayer()
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var isPaused = false
    @State private var isBuffering = false
    @State private var mediaLoaded = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
                .onHover { isHovering in
                    if isHovering { scheduleControlsHide() }
                }

            if showControls {
                controlsOverlay
            }

            if !mediaLoaded {
                ProgressView("Tuning...")
                    .foregroundStyle(.white)
            }

            if mediaLoaded, isBuffering, !showControls {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Buffering...")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            let playerItem = AVPlayerItem(url: streamURL)
            player.replaceCurrentItem(with: playerItem)
            player.play()

            let interval = CMTime(seconds: 1, preferredTimescale: 600)
            player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
                isPaused = player.timeControlStatus == .paused
                isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate

                if !mediaLoaded, player.currentItem?.status == .readyToPlay {
                    mediaLoaded = true
                }
            }

            scheduleControlsHide()
        }
        .onDisappear {
            controlsTask?.cancel()
            player.pause()
        }
        .onKeyPress(.space) {
            togglePlayPause()
            return .handled
        }
        .onKeyPress(.escape) {
            dismissPlayer()
            return .handled
        }
    }

    private func dismissPlayer() {
        player.pause()
        dismiss()
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button { dismissPlayer() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(channelName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let programTitle {
                            Text(programTitle)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    liveBadge
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer(minLength: 0)

                HStack(spacing: 16) {
                    if isBuffering {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Buffering")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    if let programEndsAt {
                        Text("Ends at \(programEndsAt, style: .time)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Button(action: togglePlayPause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showControls)
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red, in: Capsule())
    }

    private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
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
}
