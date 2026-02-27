import Foundation
import MediaPlayer

@MainActor
final class WatchNowPlayingManager {
    private weak var coordinator: (any PlayerCoordinating)?
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()

    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    init(coordinator: any PlayerCoordinating) {
        self.coordinator = coordinator
        setupRemoteCommands()
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.coordinator?.resume() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.coordinator?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.coordinator?.togglePlayback() }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.coordinator?.seek(by: 30) }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.coordinator?.seek(by: -15) }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.coordinator?.seek(to: event.positionTime) }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextTrack?() }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousTrack?() }
            return .success
        }
    }

    private func removeRemoteCommands() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
    }

    // MARK: - Metadata

    func updateMetadata(from media: MediaItem, context: PlexAPIContext) {
        var info = infoCenter.nowPlayingInfo ?? [:]

        info[MPMediaItemPropertyTitle] = media.title

        switch media.type {
        case .episode:
            info[MPMediaItemPropertyArtist] = media.grandparentTitle
            if let parentIndex = media.parentIndex {
                info[MPMediaItemPropertyAlbumTitle] = "Season \(parentIndex)"
            }
        case .movie:
            info[MPMediaItemPropertyArtist] = media.year.map(String.init)
        default:
            break
        }

        if let duration = media.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration / 1000
        }

        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue

        infoCenter.nowPlayingInfo = info

        loadArtwork(from: media, context: context)
    }

    private func loadArtwork(from media: MediaItem, context: PlexAPIContext) {
        guard let thumbPath = media.preferredThumbPath else { return }

        guard let repo = try? ImageRepository(context: context),
              let artworkURL = repo.transcodeImageURL(path: thumbPath, width: 300, height: 300) else {
            return
        }

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data) else {
                return
            }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = self.infoCenter.nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            self.infoCenter.nowPlayingInfo = info
        }
    }

    // MARK: - Playback State

    func updatePlaybackState(position: Double, duration: Double, rate: Double) {
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Teardown

    func invalidate() {
        removeRemoteCommands()
        infoCenter.nowPlayingInfo = nil
    }
}
