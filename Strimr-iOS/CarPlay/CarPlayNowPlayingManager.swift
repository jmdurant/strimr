import AVFoundation
import CarPlay
import MediaPlayer

@MainActor
final class CarPlayNowPlayingManager {
    static let shared = CarPlayNowPlayingManager()

    private var player: AVPlayer?
    private var playQueueState: PlayQueueState?
    private var currentItem: PlexItem?
    private var context: PlexAPIContext?
    private var timelineTimer: Timer?
    private var sessionIdentifier = UUID().uuidString
    private var timeObserver: Any?

    private init() {}

    func play(item: PlexItem, queue: PlayQueueState, context: PlexAPIContext) {
        self.context = context
        playQueueState = queue
        currentItem = item
        sessionIdentifier = UUID().uuidString

        guard let mediaRepo = try? MediaRepository(context: context),
              let part = item.media?.first?.parts.first,
              let url = mediaRepo.mediaURL(path: part.key)
        else { return }

        configureAudioSession()
        setupPlayer(with: url)
        setupRemoteCommands()
        updateNowPlayingInfo()
        startTimelineReporting()
        loadNowPlayingArtwork()
    }

    var isPlaying: Bool {
        player?.rate != 0
    }

    func stop() {
        player?.pause()
        cleanupTimeObserver()
        timelineTimer?.invalidate()
        timelineTimer = nil
        reportTimeline(state: .stopped)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {}
    }

    // MARK: - Player Setup

    private func setupPlayer(with url: URL) {
        cleanupTimeObserver()
        let playerItem = AVPlayerItem(url: url)

        if let player {
            player.replaceCurrentItem(with: playerItem)
        } else {
            player = AVPlayer(playerItem: playerItem)
        }

        player?.play()

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingProgress()
            }
        }
    }

    private func cleanupTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.play() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying {
                    self.player?.pause()
                } else {
                    self.player?.play()
                }
            }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.removeTarget(nil)
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.removeTarget(nil)
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.player?.seek(to: CMTime(seconds: positionEvent.positionTime, preferredTimescale: 1))
            }
            return .success
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let item = currentItem else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyPlaybackDuration: Double(item.duration ?? 0) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTimeSeconds(),
            MPNowPlayingInfoPropertyPlaybackRate: player?.rate ?? 0,
        ]

        if let artist = item.grandparentTitle {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = item.parentTitle {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let index = item.index {
            info[MPMediaItemPropertyAlbumTrackNumber] = index
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingProgress() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTimeSeconds()
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadNowPlayingArtwork() {
        guard let item = currentItem, let context else { return }
        let thumbPath = item.thumb ?? item.parentThumb ?? item.grandparentThumb
        guard let path = thumbPath else { return }

        Task {
            guard let image = await CarPlayImageLoader.shared.loadImage(path: path, context: context) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    // MARK: - Skip Controls

    private func skipToNext() {
        guard let currentItem, let queue = playQueueState,
              let nextItem = queue.item(after: currentItem.ratingKey),
              let context
        else { return }

        reportTimeline(state: .stopped)
        play(item: nextItem, queue: queue, context: context)
    }

    private func skipToPrevious() {
        let currentTime = currentTimeSeconds()
        if currentTime > 3 {
            player?.seek(to: .zero)
            return
        }

        guard let currentItem, let queue = playQueueState, let context else { return }
        guard let currentIndex = queue.items.firstIndex(where: { $0.ratingKey == currentItem.ratingKey }),
              currentIndex > 0
        else {
            player?.seek(to: .zero)
            return
        }

        let prevItem = queue.items[currentIndex - 1]
        reportTimeline(state: .stopped)
        play(item: prevItem, queue: queue, context: context)
    }

    @objc private func playerItemDidFinish() {
        skipToNext()
    }

    // MARK: - Timeline Reporting

    private func startTimelineReporting() {
        timelineTimer?.invalidate()
        timelineTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reportTimeline(state: self.isPlaying ? .playing : .paused)
            }
        }
    }

    private func reportTimeline(state: PlaybackRepository.PlaybackState) {
        guard let item = currentItem, let context else { return }
        let time = Int(currentTimeSeconds() * 1000)
        let duration = item.duration ?? 0
        let sid = sessionIdentifier
        let queueItemID = item.playQueueItemID
        let repo = try? PlaybackRepository(context: context)

        Task.detached {
            _ = try? await repo?.updateTimeline(
                ratingKey: item.ratingKey,
                state: state,
                time: time,
                duration: duration,
                sessionIdentifier: sid,
                playQueueItemID: queueItemID
            )
        }
    }

    // MARK: - Helpers

    private func currentTimeSeconds() -> Double {
        player?.currentTime().seconds ?? 0
    }
}
