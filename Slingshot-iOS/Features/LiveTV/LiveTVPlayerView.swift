import Combine
import SwiftUI

struct LiveTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let streamURL: URL
    let channelName: String
    let programTitle: String?
    let programEndsAt: Date?

    @State private var playerCoordinator: any PlayerCoordinating
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var isPaused = false
    @State private var isBuffering = false
    @State private var mediaLoaded = false
    @State private var isForceClosing = false
    @State private var isResumingFromBackground: Bool

    init(streamURL: URL, channelName: String, programTitle: String? = nil, programEndsAt: Date? = nil) {
        self.streamURL = streamURL
        self.channelName = channelName
        self.programTitle = programTitle
        self.programEndsAt = programEndsAt
        if let existing = LiveActivityManager.shared.liveTVCoordinator,
           LiveActivityManager.shared.liveTVStreamURL == streamURL
        {
            _playerCoordinator = State(initialValue: existing)
            _isResumingFromBackground = State(initialValue: true)
            _isPaused = State(initialValue: existing.isPaused)
        } else {
            _playerCoordinator = State(initialValue: PlayerFactory.makeCoordinator(for: .mpv, options: PlayerOptions()))
            _isResumingFromBackground = State(initialValue: false)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerFactory.makeView(
                selection: .mpv,
                coordinator: playerCoordinator,
                onPropertyChange: { property, data in
                    if property == .pause {
                        isPaused = (data as? Bool) ?? false
                    } else if property == .pausedForCache {
                        isBuffering = (data as? Bool) ?? false
                    }
                },
                onPlaybackEnded: {
                    dismissPlayer(force: true)
                },
                onMediaLoaded: {
                    mediaLoaded = true
                }
            )
            .ignoresSafeArea()
            .onTapGesture { toggleControls() }

            if showControls {
                controlsOverlay
            }

            if !mediaLoaded {
                ProgressView("Tuning...")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if mediaLoaded, isBuffering, !showControls {
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
            if isResumingFromBackground {
                isResumingFromBackground = false
                mediaLoaded = true
            } else {
                playerCoordinator.play(streamURL)
            }
            scheduleControlsHide()
            LiveActivityManager.shared.startLiveTV(channelName: channelName, coordinator: playerCoordinator, streamURL: streamURL)
        }
        .onDisappear {
            controlsTask?.cancel()
            if isForceClosing {
                LiveActivityManager.shared.stopLiveTV()
            } else {
                playerCoordinator.retainForBackground()
            }
        }
    }

    private func dismissPlayer(force: Bool = false) {
        if force {
            isForceClosing = true
            NotificationCenter.default.post(name: Notification.Name("slingshot.livetv.finished"), object: nil)
        }
        dismiss()
    }

    // MARK: - Controls Overlay

    @ViewBuilder
    private var controlsOverlay: some View {
        ZStack {
            // Gradient background matching VOD player
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    // Back button (dismiss, keep playing)
                    Button { dismissPlayer() } label: {
                        Image(systemName: "chevron.backward")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(channelName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let programTitle {
                            Text(programTitle)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                Spacer(minLength: 0)

                // Bottom area: auxiliary row + timeline
                VStack(spacing: 18) {
                    // Auxiliary controls row
                    HStack(alignment: .bottom, spacing: 16) {
                        // Stop button (force close)
                        Button { dismissPlayer(force: true) } label: {
                            Image(systemName: "stop.fill")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }

                        AudioRoutePickerButton()
                            .frame(width: 42, height: 42)
                            .background(
                                .white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )

                        Spacer(minLength: 12)

                        if isBuffering {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .controlSize(.small)
                                Text("Buffering")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        PlayerBadge("LIVE")
                    }
                    .padding(.horizontal, 24)

                    // Program timeline
                    LiveTVTimelineView(programEndsAt: programEndsAt)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Center play/pause
            PlayPauseButton(isPaused: isPaused) {
                playerCoordinator.togglePlayback()
                scheduleControlsHide()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Controls Logic

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

// MARK: - Live TV Timeline

private struct LiveTVTimelineView: View {
    let programEndsAt: Date?

    @State private var progress: Double = 0
    @State private var remainingText: String = ""

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                    if programEndsAt != nil {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: 28)

            HStack {
                Text(remainingText)
                Spacer()
                if let programEndsAt {
                    Text(programEndsAt, style: .time)
                }
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .onAppear { updateProgress() }
        .onReceive(timer) { _ in updateProgress() }
    }

    private func updateProgress() {
        guard let programEndsAt else {
            remainingText = "LIVE"
            return
        }

        let remaining = programEndsAt.timeIntervalSinceNow
        guard remaining > 0 else {
            progress = 1.0
            remainingText = "Ended"
            return
        }

        let minutes = Int(remaining / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            remainingText = "\(hours)h \(mins)m remaining"
        } else {
            remainingText = "\(minutes)m remaining"
        }

        let totalEstimate = estimatedDuration(remaining: remaining)
        let elapsed = totalEstimate - remaining
        progress = min(max(elapsed / totalEstimate, 0), 1)
    }

    private func estimatedDuration(remaining: TimeInterval) -> TimeInterval {
        let totalMinutes = Int(ceil(remaining / 60))
        if totalMinutes <= 30 {
            return 30 * 60
        } else if totalMinutes <= 60 {
            return 60 * 60
        } else if totalMinutes <= 90 {
            return 90 * 60
        } else if totalMinutes <= 120 {
            return 120 * 60
        } else {
            return remaining
        }
    }
}
