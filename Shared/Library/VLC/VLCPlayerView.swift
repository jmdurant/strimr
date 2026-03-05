import AVKit
import Foundation
import SwiftUI

struct VLCPlayerView: UIViewControllerRepresentable {
    var coordinator: Coordinator

    func makeUIViewController(context: Context) -> some UIViewController {
        // Reuse the retained player when resuming from background playback
        if let existing = coordinator.reuseRetainedPlayer() {
            existing.playDelegate = coordinator
            return existing
        }
        let vlc = VLCPlayerViewController(options: coordinator.options)
        vlc.playDelegate = coordinator
        vlc.playUrl = coordinator.playUrl
        vlc.setPlaybackRate(coordinator.playbackRate)

        context.coordinator.player = vlc
        return vlc
    }

    func updateUIViewController(_: UIViewControllerType, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        coordinator
    }

    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }

    func onPropertyChange(_ handler: @escaping (VLCPlayerViewController, PlayerProperty, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }

    func onPlaybackEnded(_ handler: @escaping () -> Void) -> Self {
        coordinator.onPlaybackEnded = handler
        return self
    }

    func onMediaLoaded(_ handler: @escaping () -> Void) -> Self {
        coordinator.onMediaLoaded = handler
        return self
    }

    @MainActor
    @Observable
    final class Coordinator: VLCPlayerDelegate, PlayerCoordinating {
        weak var player: VLCPlayerViewController?
        /// Strong reference kept when player runs in background (dismissed but still playing)
        private var retainedPlayer: VLCPlayerViewController?

        @ObservationIgnored var playUrl: URL?
        @ObservationIgnored var options = PlayerOptions()
        @ObservationIgnored var playbackRate: Float = 1.0
        @ObservationIgnored var onPropertyChange: ((VLCPlayerViewController, PlayerProperty, Any?) -> Void)?
        @ObservationIgnored var onPlaybackEnded: (() -> Void)?
        @ObservationIgnored var onMediaLoaded: (() -> Void)?

        var isPaused: Bool {
            player?.isPaused ?? false
        }

        func play(_ url: URL) {
            player?.loadFile(url)
        }

        func togglePlayback() {
            player?.togglePause()
        }

        func pause() {
            player?.pause()
        }

        func resume() {
            player?.play()
        }

        func seek(to time: Double) {
            player?.seek(to: time)
        }

        func seek(by delta: Double) {
            player?.seek(by: delta)
        }

        func setPlaybackRate(_ rate: Float) {
            playbackRate = rate
            player?.setPlaybackRate(rate)
        }

        func selectAudioTrack(id: Int?) {
            player?.setAudioTrack(id: id)
        }

        func selectSubtitleTrack(id: Int?) {
            player?.setSubtitleTrack(id: id)
        }

        func trackList() -> [PlayerTrack] {
            player?.trackList() ?? []
        }

        func retainForBackground() {
            retainedPlayer = player
            NSLog("[VLC Coordinator] retainForBackground — player retained")
        }

        func releaseFromBackground() {
            retainedPlayer = nil
            NSLog("[VLC Coordinator] releaseFromBackground")
        }

        /// Return the retained VC for reuse in makeUIViewController, transferring ownership back to the weak reference.
        func reuseRetainedPlayer() -> VLCPlayerViewController? {
            guard let retained = retainedPlayer else { return nil }
            retainedPlayer = nil
            player = retained
            NSLog("[VLC Coordinator] reuseRetainedPlayer — reattached existing VC")
            return retained
        }

        func destruct() {
            NSLog("[VLC Coordinator] destruct() called")
            // Destruct the player BEFORE releasing the strong reference,
            // so VLC cleanup (audio bridge, PiP, etc.) happens while the VC is still alive.
            let playerToDestruct = retainedPlayer ?? player
            playerToDestruct?.destruct()
            retainedPlayer = nil
        }

        #if os(iOS)
        func startPictureInPicture() {
            player?.startPiP()
        }

        func stopPictureInPicture() {
            player?.stopPiP()
        }

        var isPictureInPictureSupported: Bool {
            AVPictureInPictureController.isPictureInPictureSupported()
        }

        var isPictureInPictureActive: Bool {
            player?.isPipActive ?? false
        }

        var spectrumData: SpectrumData? {
            player?.spectrumData
        }

        func enableAudioVisualization() {
            player?.enableAudioVisualization()
        }

        var discoveredRenderers: [RendererDevice] = []
        var activeRendererName: String?

        func startRendererDiscovery() {
            player?.onRenderersChanged = { [weak self] in
                guard let self else { return }
                self.discoveredRenderers = self.player?.rendererDevices ?? []
                self.activeRendererName = self.player?.activeRendererDeviceName
            }
            player?.startRendererDiscovery()
        }

        func stopRendererDiscovery() {
            player?.stopRendererDiscovery()
            discoveredRenderers = []
        }

        func selectRenderer(id: String?) {
            player?.selectRendererByName(id)
            activeRendererName = id
        }
        #endif

        func propertyChange(player: VLCPlayerViewController, property: PlayerProperty, data: Any?) {
            onPropertyChange?(player, property, data)
        }

        func playbackEnded() {
            onPlaybackEnded?()
        }

        func fileLoaded() {
            player?.setPlaybackRate(playbackRate)
            onMediaLoaded?()
        }
    }
}
