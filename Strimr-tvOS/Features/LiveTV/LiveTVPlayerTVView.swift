import AVFoundation
import AVKit
import SwiftUI

struct LiveTVPlayerTVView: View {
    let streamURL: URL
    let channelName: String

    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player, isReady {
                AVPlayerView(player: player, channelName: channelName)
                    .ignoresSafeArea()
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

        statusObservation = item.observe(\.status) { [channelName] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    let titleItem = AVMetadataItem.makeTitle(channelName)
                    item.externalMetadata = [titleItem]
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
}
