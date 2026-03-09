import AVFoundation
import AVKit
import os
import SwiftUI

private protocol PlayerCallbackProviding: PlayerCoordinating {
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onMediaLoaded: (() -> Void)? { get set }
}

extension WatchAVPlayerController: PlayerCallbackProviding {}
extension WatchVLCPlayerController: PlayerCallbackProviding {}

struct WatchPlayerView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    let playQueue: PlayQueueState
    let shouldResumeFromOffset: Bool
    var localMedia: MediaItem? = nil
    var localPlaybackURL: URL? = nil

    @State private var viewModel: PlayerViewModel?
    @State private var coordinator: (any PlayerCoordinating)?
    @State private var avPlayer: AVPlayer?
    @State private var nowPlayingManager: WatchNowPlayingManager?
    @State private var isLandscape = false
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var playbackSpeed: Float = 1.0
    @State private var showVisualization = false

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { dismiss() } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(.black.opacity(0.4), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text(errorMessage)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Button("Close") { dismiss() }
                    }
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.4), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let avPlayer {
                    GeometryReader { geo in
                        let w = isLandscape ? geo.size.height : geo.size.width
                        let h = isLandscape ? geo.size.width : geo.size.height
                        let zoomEnabled = settingsManager.playback.zoomVideo
                        let screenRatio = w / h
                        let videoRatio: CGFloat = 16.0 / 9.0
                        let scale = zoomEnabled ? videoRatio / screenRatio : 1.0
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
                                        Button {
                                            cyclePlaybackSpeed()
                                            scheduleControlsHide()
                                        } label: {
                                            Text(speedLabel)
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(.black.opacity(0.4), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
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
                } else if viewModel.media?.type == .movie || viewModel.media?.type == .episode {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(viewModel.media?.title ?? "Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.4), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    audioPlayerView(viewModel: viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await setupPlayer()
        }
        .onDisappear {
            teardown()
        }
    }

    @ViewBuilder
    private func audioPlayerView(viewModel: PlayerViewModel) -> some View {
        VStack(spacing: 8) {
            audioAlbumArt
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            Text(viewModel.media?.title ?? "")
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if let grandparentTitle = viewModel.media?.grandparentTitle {
                Text(grandparentTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let duration = viewModel.duration, duration > 0 {
                WatchTimelineView(
                    position: viewModel.position,
                    duration: duration,
                    onSeek: { newPosition in
                        coordinator?.seek(to: newPosition)
                        viewModel.position = newPosition
                    }
                )
            }

            HStack(spacing: 20) {
                Button {
                    Task { await skipToPreviousTrack() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(!hasPreviousTrack)

                Button {
                    coordinator?.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await skipToNextTrack() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(!hasNextTrack)

                if let vlcCoordinator = coordinator as? WatchVLCPlayerController {
                    Button {
                        showVisualization = true
                    } label: {
                        Image(systemName: "waveform")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .fullScreenCover(isPresented: $showVisualization) {
                        WatchVisualizationView(spectrumData: vlcCoordinator.spectrumData)
                    }
                }
            }
        }
        .padding(.horizontal)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var audioAlbumArt: some View {
        if let ratingKey = localMedia?.id,
           let item = downloadManager.downloadStatus(for: ratingKey),
           let posterURL = downloadManager.localPosterURL(for: item) {
            PlexAsyncImage(url: posterURL) {
                audioArtPlaceholder
            }
            .aspectRatio(contentMode: .fill)
        } else if let thumbPath = viewModel?.media?.preferredThumbPath,
                  let imageRepo = try? ImageRepository(context: plexApiContext),
                  let url = imageRepo.transcodeImageURL(path: thumbPath, width: 160, height: 160) {
            PlexAsyncImage(url: url) {
                audioArtPlaceholder
            }
            .aspectRatio(contentMode: .fill)
        } else {
            audioArtPlaceholder
        }
    }

    private var audioArtPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private func setupPlayer() async {
        guard viewModel == nil else { return }

        let vm: PlayerViewModel
        if let localMedia, let localPlaybackURL {
            // Offline playback — local file, no server interaction
            vm = PlayerViewModel(
                localMedia: localMedia,
                localPlaybackURL: localPlaybackURL,
                context: plexApiContext,
                shouldResumeFromOffset: shouldResumeFromOffset
            )
            vm.settingsManager = settingsManager
            viewModel = vm
        } else {
            // Streaming playback
            AppLogger.fileLog("setupPlayer called, queue.selectedRatingKey=\(playQueue.selectedRatingKey ?? "nil")", logger: AppLogger.player)
            vm = PlayerViewModel(
                playQueue: playQueue,
                context: plexApiContext,
                shouldResumeFromOffset: shouldResumeFromOffset
            )
            vm.settingsManager = settingsManager
            viewModel = vm
            AppLogger.fileLog("calling vm.load()", logger: AppLogger.player)
            await vm.load()
            AppLogger.fileLog("vm.load() returned", logger: AppLogger.player)
            AppLogger.fileLog("load done, url=\(vm.playbackURL?.absoluteString ?? "nil"), error=\(vm.errorMessage ?? "none")", logger: AppLogger.player)
        }

        guard let url = vm.playbackURL else { return }

        let isLocal = localPlaybackURL != nil
        let isVideo = vm.media?.type == .movie || vm.media?.type == .episode
        let useVLC = isLocal && !isVideo  // VLC only for offline audio (has no HTTP access module)

        if useVLC {
            // Offline audio — use VLC for local file playback + visualization bridge
            AppLogger.fileLog("creating VLC for offline audio", logger: AppLogger.player)
            await WatchVLCPlayerController.activateAudioSession()

            let playerCoordinator = WatchVLCPlayerController(options: PlayerOptions())
            coordinator = playerCoordinator
            setupPropertyCallbacks(viewModel: vm, coordinator: playerCoordinator)
            playerCoordinator.play(url)

            if vm.shouldResumeFromOffset, let offset = vm.resumePosition, offset > 0 {
                playerCoordinator.seek(to: offset)
            }
        } else {
            // AVPlayer for all streaming (video + audio) and local video
            var playURL = url

            if !isLocal {
                let isHLS = url.pathExtension == "m3u8" || url.absoluteString.contains("/transcode/")
                if isHLS {
                    // HLS streams need proxy for TLS termination and URL rewriting
                    AppLogger.fileLog("creating AVPlayer for HLS streaming", logger: AppLogger.player)
                    let proxy = HLSProxyServer.shared
                    if let serverBase = plexApiContext.baseURLServer {
                        do {
                            try await proxy.start(baseURL: serverBase)
                            AppLogger.fileLog("started on port \(proxy.port)", logger: AppLogger.player)
                        } catch {
                            AppLogger.fileLog("HLSProxy failed to start: \(error)", logger: AppLogger.player)
                        }
                    }
                    playURL = proxy.proxyURL(for: url) ?? url
                } else {
                    // Direct media files (MP3, etc.) — AVPlayer handles HTTPS natively
                    AppLogger.fileLog("creating AVPlayer for direct streaming (no proxy)", logger: AppLogger.player)
                }
                AppLogger.fileLog("playURL=\(playURL.absoluteString)", logger: AppLogger.player)
            } else {
                AppLogger.fileLog("creating AVPlayer for local \(isVideo ? "video" : "audio")", logger: AppLogger.player)
            }

            let playerCoordinator = WatchAVPlayerController(options: PlayerOptions())
            coordinator = playerCoordinator
            setupPropertyCallbacks(viewModel: vm, coordinator: playerCoordinator)
            playerCoordinator.play(playURL)

            // Only set avPlayer for video — audio uses the audio player UI.
            // Wait for readyToPlay before attaching to VideoPlayer to avoid black screen.
            if isVideo {
                playerCoordinator.onMediaLoaded = { [playerCoordinator] in
                    avPlayer = playerCoordinator.player
                }
            }

            if vm.shouldResumeFromOffset, let offset = vm.resumePosition, offset > 0 {
                playerCoordinator.seek(to: offset)
            }
        }
    }

    private func setupPropertyCallbacks(viewModel: PlayerViewModel, coordinator: any PlayerCallbackProviding) {
        let manager = WatchNowPlayingManager(coordinator: coordinator)
        nowPlayingManager = manager

        if let media = viewModel.media {
            manager.updateMetadata(from: media, context: plexApiContext)
        }

        manager.onNextTrack = { [weak coordinator] in
            coordinator?.seek(by: 30)
        }
        manager.onPreviousTrack = { [weak coordinator] in
            coordinator?.seek(by: -15)
        }

        coordinator.onPropertyChange = { property, value in
            viewModel.handlePropertyChange(property: property, data: value, isScrubbing: false)

            switch property {
            case .timePos:
                if let position = value as? Double {
                    manager.updatePlaybackState(
                        position: position,
                        duration: viewModel.duration ?? 0,
                        rate: viewModel.isPaused ? 0.0 : 1.0
                    )
                }
            case .duration:
                if let duration = value as? Double {
                    manager.updatePlaybackState(
                        position: viewModel.position,
                        duration: duration,
                        rate: viewModel.isPaused ? 0.0 : 1.0
                    )
                }
            case .pause:
                if let isPaused = value as? Bool {
                    manager.updatePlaybackState(
                        position: viewModel.position,
                        duration: viewModel.duration ?? 0,
                        rate: isPaused ? 0.0 : 1.0
                    )
                }
            default:
                break
            }
        }

        coordinator.onPlaybackEnded = {
            Task { await viewModel.markPlaybackFinished() }
        }
    }

    private static let speedSteps: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]

    private var speedLabel: String {
        if playbackSpeed == 1.0 { return "1x" }
        let text = playbackSpeed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", playbackSpeed)
            : String(format: "%.2g", playbackSpeed)
        return "\(text)x"
    }

    private func cyclePlaybackSpeed() {
        let steps = Self.speedSteps
        if let idx = steps.firstIndex(of: playbackSpeed), idx + 1 < steps.count {
            playbackSpeed = steps[idx + 1]
        } else {
            playbackSpeed = steps[0]
        }
        coordinator?.setPlaybackRate(playbackSpeed)
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

    @Environment(WatchDownloadManager.self) private var downloadManager

    private var hasNextTrack: Bool {
        guard let currentId = viewModel?.media?.id else { return false }
        return playQueue.item(after: currentId) != nil
    }

    private var hasPreviousTrack: Bool {
        guard let currentId = viewModel?.media?.id else { return false }
        return playQueue.item(before: currentId) != nil
    }

    private func skipToNextTrack() async {
        guard let currentId = viewModel?.media?.id,
              let nextItem = playQueue.item(after: currentId) else { return }
        await switchToTrack(ratingKey: nextItem.ratingKey)
    }

    private func skipToPreviousTrack() async {
        guard let currentId = viewModel?.media?.id,
              let prevItem = playQueue.item(before: currentId) else { return }
        await switchToTrack(ratingKey: prevItem.ratingKey)
    }

    private func switchToTrack(ratingKey: String) async {
        // Tear down current player
        nowPlayingManager?.invalidate()
        nowPlayingManager = nil
        coordinator?.destruct()
        coordinator = nil
        avPlayer = nil
        viewModel?.handleStop()

        // Create new view model for the target track
        let vm = PlayerViewModel(
            playQueue: playQueue,
            ratingKey: ratingKey,
            context: plexApiContext,
            shouldResumeFromOffset: false
        )
        vm.settingsManager = settingsManager
        viewModel = vm
        await vm.load()

        guard let url = vm.playbackURL else { return }

        let isVideo = vm.media?.type == .movie || vm.media?.type == .episode

        var playURL = url
        let isHLS = url.pathExtension == "m3u8" || url.absoluteString.contains("/transcode/")
        if isHLS {
            let proxy = HLSProxyServer.shared
            if let serverBase = plexApiContext.baseURLServer {
                try? await proxy.start(baseURL: serverBase)
            }
            playURL = proxy.proxyURL(for: url) ?? url
        }

        let playerCoordinator = WatchAVPlayerController(options: PlayerOptions())
        coordinator = playerCoordinator
        setupPropertyCallbacks(viewModel: vm, coordinator: playerCoordinator)
        playerCoordinator.play(playURL)

        if isVideo {
            playerCoordinator.onMediaLoaded = { [playerCoordinator] in
                avPlayer = playerCoordinator.player
            }
        }
    }

    private func teardown() {
        nowPlayingManager?.invalidate()
        nowPlayingManager = nil
        coordinator?.destruct()
        coordinator = nil
        avPlayer = nil

        if localPlaybackURL != nil {
            // Save playback position for local resume
            if let vm = viewModel, let mediaId = localMedia?.id, vm.position > 0 {
                downloadManager.savePlaybackPosition(vm.position, forRatingKey: mediaId)
            }
            viewModel = nil
        } else {
            // Streaming — stop transcode session and HLS proxy
            viewModel?.handleStop()
            viewModel = nil
            HLSProxyServer.shared.stop()
        }
    }
}
