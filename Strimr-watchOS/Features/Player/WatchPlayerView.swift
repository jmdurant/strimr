import AVFoundation
import AVKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.strimr.app.watchos", category: "Player")

func writeDebug(_ msg: String) {
    let path = NSHomeDirectory() + "/tmp/strimr-debug.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

private protocol PlayerCallbackProviding: PlayerCoordinating {
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onMediaLoaded: (() -> Void)? { get set }
}

extension WatchAVPlayerController: PlayerCallbackProviding {}
extension WatchVLCPlayerController: PlayerCallbackProviding {}

struct WatchPlayerView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss

    let playQueue: PlayQueueState
    let shouldResumeFromOffset: Bool

    @State private var viewModel: PlayerViewModel?
    @State private var coordinator: (any PlayerCoordinating)?
    @State private var avPlayer: AVPlayer?
    @State private var nowPlayingManager: WatchNowPlayingManager?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView("Loading...")
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
                } else if let avPlayer {
                    VideoPlayer(player: avPlayer)
                        .ignoresSafeArea()
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
        VStack(spacing: 12) {
            Text(viewModel.media?.title ?? "")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let grandparentTitle = viewModel.media?.grandparentTitle {
                Text(grandparentTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let duration = viewModel.duration, duration > 0 {
                ProgressView(value: viewModel.position, total: duration)
                    .tint(.accentColor)

                HStack {
                    Text(viewModel.position.mediaDurationText())
                    Spacer()
                    Text(duration.mediaDurationText())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Button {
                    coordinator?.seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button {
                    coordinator?.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button {
                    coordinator?.seek(by: 30)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Button("Close") { dismiss() }
                .font(.caption)
        }
        .padding()
    }

    private func setupPlayer() async {
        writeDebug("[WatchPlayer] setupPlayer called, queue.selectedRatingKey=\(playQueue.selectedRatingKey ?? "nil")")
        let vm = PlayerViewModel(
            playQueue: playQueue,
            context: plexApiContext,
            shouldResumeFromOffset: shouldResumeFromOffset
        )
        viewModel = vm
        writeDebug("[WatchPlayer] calling vm.load()")
        await vm.load()
        writeDebug("[WatchPlayer] vm.load() returned")

        writeDebug("[WatchPlayer] load done, url=\(vm.playbackURL?.absoluteString ?? "nil"), error=\(vm.errorMessage ?? "none")")
        guard let url = vm.playbackURL else { return }

        let isVideo = vm.media?.type == .movie || vm.media?.type == .episode
        writeDebug("[WatchPlayer] mediaType=\(vm.media?.type.rawValue ?? "nil"), isVideo=\(isVideo), url=\(url.absoluteString)")

        if isVideo {
            writeDebug("[WatchPlayer] creating AVPlayer for video")

            // Start local proxy to handle .plex.direct TLS certs
            let proxy = HLSProxyServer.shared
            if let serverBase = plexApiContext.baseURLServer {
                do {
                    try await proxy.start(baseURL: serverBase)
                    writeDebug("[HLSProxy] started on port \(proxy.port)")
                } catch {
                    writeDebug("[HLSProxy] failed to start: \(error)")
                }
            }

            let playURL = proxy.proxyURL(for: url) ?? url
            writeDebug("[WatchPlayer] playURL=\(playURL.absoluteString)")

            let playerCoordinator = WatchAVPlayerController(options: PlayerOptions())
            coordinator = playerCoordinator
            setupPropertyCallbacks(viewModel: vm, coordinator: playerCoordinator)
            playerCoordinator.play(playURL)
            avPlayer = playerCoordinator.player

            if vm.shouldResumeFromOffset, let offset = vm.resumePosition, offset > 0 {
                playerCoordinator.seek(to: offset)
            }
        } else {
            writeDebug("[WatchPlayer] creating VLC for audio")
            let playerCoordinator = WatchVLCPlayerController(options: PlayerOptions())
            coordinator = playerCoordinator
            setupPropertyCallbacks(viewModel: vm, coordinator: playerCoordinator)
            playerCoordinator.play(url)

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

    private func teardown() {
        nowPlayingManager?.invalidate()
        nowPlayingManager = nil
        viewModel?.handleStop()
        coordinator?.destruct()
        coordinator = nil
        avPlayer = nil
        HLSProxyServer.shared.stop()
    }
}
