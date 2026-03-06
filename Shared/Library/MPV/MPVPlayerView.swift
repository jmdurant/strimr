import Foundation
import os
import SwiftUI

struct MPVPlayerView: UIViewControllerRepresentable {
    var coordinator: Coordinator

    func makeUIViewController(context: Context) -> some UIViewController {
        // Reuse the retained player when resuming from background playback
        if let existing = coordinator.reuseRetainedPlayer() {
            existing.playDelegate = coordinator
            return existing
        }
        let mpv = MPVPlayerViewController(options: coordinator.options)
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        mpv.setPlaybackRate(coordinator.playbackRate)

        context.coordinator.player = mpv
        return mpv
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context _: Context) {
        (uiViewController as? MPVPlayerViewController)?.updateMetalLayerLayout()
    }

    func makeCoordinator() -> Coordinator {
        coordinator
    }

    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }

    func onPropertyChange(_ handler: @escaping (MPVPlayerViewController, PlayerProperty, Any?) -> Void) -> Self {
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
    final class Coordinator: MPVPlayerDelegate, PlayerCoordinating {
        weak var player: MPVPlayerViewController?
        private var retainedPlayer: MPVPlayerViewController?

        @ObservationIgnored var playUrl: URL?
        @ObservationIgnored var options = PlayerOptions()
        @ObservationIgnored var playbackRate: Float = 1.0
        @ObservationIgnored var onPropertyChange: ((MPVPlayerViewController, PlayerProperty, Any?) -> Void)?
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
            AppLogger.player.debug("retainForBackground — player retained")
        }

        func releaseFromBackground() {
            retainedPlayer = nil
            AppLogger.player.debug("releaseFromBackground")
        }

        func reuseRetainedPlayer() -> MPVPlayerViewController? {
            guard let retained = retainedPlayer else { return nil }
            retainedPlayer = nil
            player = retained
            AppLogger.player.debug("reuseRetainedPlayer — reattached existing VC")
            return retained
        }

        func destruct() {
            AppLogger.player.debug("destruct() called")
            let playerToDestruct = retainedPlayer ?? player
            playerToDestruct?.destruct()
            retainedPlayer = nil
        }

        func propertyChange(mpv _: OpaquePointer, property: PlayerProperty, data: Any?) {
            guard let player else { return }

            if property == .videoParamsSigPeak {
                let supportsHdr = (data as? Double ?? 1.0) > 1.0
                player.hdrEnabled = supportsHdr
            }
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
