import AVKit
import SwiftUI

struct LiveTVPlayerTVView: UIViewControllerRepresentable {
    let streamURL: URL
    let channelName: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: streamURL)
        let controller = AVPlayerViewController()
        controller.player = player

        let titleItem = AVMetadataItem.makeTitle(channelName)
        player.currentItem?.externalMetadata = [titleItem]

        player.play()
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
