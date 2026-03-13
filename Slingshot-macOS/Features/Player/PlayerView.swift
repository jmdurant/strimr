import AVFoundation
import AVKit
import os
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: PlayerViewModel
    @State private var player = AVPlayer()
    @State private var didInjectSettings = false
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var timelinePosition = 0.0
    @State private var timeObserver: Any?
    @State private var showingTerminationAlert = false
    @State private var terminationAlertMessage = ""
    @State private var activePlaybackURL: URL?
    @State private var appliedResumeOffset = false

    private let controlsHideDelay: TimeInterval = 3.0

    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MacAVPlayerView(player: player)
                .ignoresSafeArea()
                .onAppear {
                    setupTimeObserver()
                    startPlaybackIfNeeded(url: viewModel.playbackURL)
                }
                .onDisappear {
                    removeTimeObserver()
                    player.pause()
                    viewModel.handleStop()
                }

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    controlsVisible ? hideControls() : showControls(temporarily: true)
                }
                .onHover { isHovering in
                    if isHovering {
                        showControls(temporarily: true)
                    }
                }

            if viewModel.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if controlsVisible {
                PlayerControlsView(
                    title: viewModel.media?.primaryLabel,
                    subtitle: viewModel.media?.tertiaryLabel,
                    isPaused: viewModel.isPaused,
                    position: timelineBinding,
                    duration: viewModel.duration,
                    seekBackwardSeconds: settingsManager.playback.seekBackwardSeconds,
                    seekForwardSeconds: settingsManager.playback.seekForwardSeconds,
                    onDismiss: { dismissPlayer() },
                    onSeekBackward: { jump(by: -seekBackwardInterval) },
                    onPlayPause: togglePlayPause,
                    onSeekForward: { jump(by: seekForwardInterval) },
                    onScrubbingChanged: handleScrubbing(editing:),
                    onToggleFullscreen: toggleFullscreen
                )
                .transition(.opacity)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .task {
            if !didInjectSettings {
                viewModel.settingsManager = settingsManager
                didInjectSettings = true
            }
            guard activePlaybackURL == nil || viewModel.media == nil else { return }
            NSLog("[Slingshot] Player loading — ratingKey: %@", viewModel.playQueue.selectedRatingKey ?? "nil")
            await viewModel.load()
            NSLog("[Slingshot] Player loaded — url: %@, error: %@", viewModel.playbackURL?.absoluteString ?? "nil", viewModel.errorMessage ?? "none")
        }
        .onChange(of: viewModel.playbackURL) { _, newURL in
            startPlaybackIfNeeded(url: newURL)
        }
        .onChange(of: viewModel.position) { _, newValue in
            guard !isScrubbing else { return }
            timelinePosition = newValue
        }
        .onChange(of: viewModel.terminationMessage) { _, newValue in
            guard let newValue else { return }
            terminationAlertMessage = newValue
            showingTerminationAlert = true
            player.pause()
        }
        .alert("Playback Terminated", isPresented: $showingTerminationAlert) {
            Button("Dismiss") {
                dismissPlayer()
            }
        } message: {
            Text(terminationAlertMessage)
        }
        .onKeyPress(.space) {
            togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            jump(by: -seekBackwardInterval)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            jump(by: seekForwardInterval)
            return .handled
        }
        .onKeyPress(.escape) {
            dismissPlayer()
            return .handled
        }
    }

    private var timelineBinding: Binding<Double> {
        Binding(
            get: { timelinePosition },
            set: { timelinePosition = $0 }
        )
    }

    private func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            viewModel.isPaused = true
        } else {
            player.play()
            viewModel.isPaused = false
        }
        showControls(temporarily: true)
    }

    private func jump(by seconds: Double) {
        let currentTime = player.currentTime().seconds
        let newTime = max(0, currentTime + seconds)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
        viewModel.position = newTime
        showControls(temporarily: true)
    }

    private func startPlaybackIfNeeded(url: URL?) {
        guard let url else { return }
        guard activePlaybackURL != url else { return }

        activePlaybackURL = url
        appliedResumeOffset = false

        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        player.play()
        viewModel.isPaused = false

        applyResumeOffsetIfNeeded()
        showControls(temporarily: true)
    }

    private func applyResumeOffsetIfNeeded() {
        guard viewModel.shouldResumeFromOffset else { return }
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
    }

    private func dismissPlayer() {
        hideControlsTask?.cancel()
        player.pause()
        viewModel.handleStop()
        dismiss()
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            timelinePosition = viewModel.position
            hideControlsTask?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            let seekTime = CMTime(seconds: timelinePosition, preferredTimescale: 600)
            player.seek(to: seekTime)
            viewModel.position = timelinePosition
            scheduleControlsHide()
        }
    }

    private func showControls(temporarily: Bool) {
        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily, !isScrubbing {
            scheduleControlsHide()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeInOut) {
            controlsVisible = false
        }
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()

        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(controlsHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut) {
                controlsVisible = false
            }
        }
    }

    private func toggleFullscreen() {
        if let window = NSApplication.shared.keyWindow {
            window.toggleFullScreen(nil)
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            if !isScrubbing {
                viewModel.handlePropertyChange(
                    property: .timePos,
                    data: seconds,
                    isScrubbing: false
                )
            }

            if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                viewModel.handlePropertyChange(
                    property: .duration,
                    data: duration,
                    isScrubbing: false
                )
            }

            let isPaused = player.timeControlStatus == .paused
            viewModel.handlePropertyChange(
                property: .pause,
                data: isPaused,
                isScrubbing: isScrubbing
            )

            let isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            viewModel.handlePropertyChange(
                property: .pausedForCache,
                data: isBuffering,
                isScrubbing: isScrubbing
            )
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}

private struct MacAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
