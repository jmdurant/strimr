import AVFoundation
import AVKit
import Combine
import SwiftUI

struct LiveTVPlayerTVView: View {
    let streamURL: URL
    let channelName: String
    let programTitle: String?
    let programEndsAt: Date?

    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?

    init(streamURL: URL, channelName: String, programTitle: String? = nil, programEndsAt: Date? = nil) {
        self.streamURL = streamURL
        self.channelName = channelName
        self.programTitle = programTitle
        self.programEndsAt = programEndsAt
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player, isReady {
                AVPlayerView(player: player, channelName: channelName)
                    .ignoresSafeArea()

                // Program info overlay at the bottom
                LiveTVInfoOverlay(channelName: channelName, programTitle: programTitle, programEndsAt: programEndsAt)
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(errorMessage)
                        .font(.title3)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView("Tuning \(channelName)...")
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardown() }
    }

    private func setupPlayer() {
        let asset = AVURLAsset(url: streamURL)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.play()

        statusObservation = item.observe(\.status) { [channelName, programTitle] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    var metadata: [AVMetadataItem] = [AVMetadataItem.makeTitle(channelName)]
                    if let programTitle {
                        metadata.append(AVMetadataItem.makeSubtitle(programTitle))
                    }
                    item.externalMetadata = metadata
                    player = avPlayer
                    isReady = true
                    statusObservation?.invalidate()
                    statusObservation = nil
                case .failed:
                    errorMessage = item.error?.localizedDescription ?? "Failed to load stream"
                    statusObservation?.invalidate()
                    statusObservation = nil
                default:
                    break
                }
            }
        }
    }

    private func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
    }
}

// MARK: - Program Info Overlay

private struct LiveTVInfoOverlay: View {
    let channelName: String
    let programTitle: String?
    let programEndsAt: Date?

    @State private var remainingText: String = ""
    @State private var progress: Double = 0
    @State private var isVisible = true

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()

            if isVisible, programTitle != nil || programEndsAt != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let programTitle {
                            Text(programTitle)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("LIVE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.red, in: Capsule())
                    }

                    if programEndsAt != nil {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.35))
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: proxy.size.width * progress)
                            }
                            .frame(height: 4)
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 20)
                    }

                    HStack {
                        Text(remainingText)
                        Spacer()
                        if let programEndsAt {
                            Text(programEndsAt, style: .time)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                }
                .padding(32)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            updateProgress()
            scheduleHide()
        }
        .onReceive(timer) { _ in updateProgress() }
    }

    private func scheduleHide() {
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.easeInOut(duration: 0.5)) {
                isVisible = false
            }
        }
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
        if totalMinutes <= 30 { return 30 * 60 }
        else if totalMinutes <= 60 { return 60 * 60 }
        else if totalMinutes <= 90 { return 90 * 60 }
        else if totalMinutes <= 120 { return 120 * 60 }
        else { return remaining }
    }
}

// MARK: - AVPlayerViewController wrapper

private struct AVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let channelName: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}

// MARK: - AVMetadataItem helper

private extension AVMetadataItem {
    static func makeTitle(_ title: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    static func makeSubtitle(_ subtitle: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierDescription
        item.value = subtitle as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
