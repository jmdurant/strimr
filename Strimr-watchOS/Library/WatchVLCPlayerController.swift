import AVFoundation
import Foundation
import VLCKit

@MainActor
final class WatchVLCPlayerController: NSObject, PlayerCoordinating {
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onMediaLoaded: (() -> Void)?

    private var mediaPlayer: VLCMediaPlayer?
    private var hasNotifiedFileLoaded = false
    private var lastReportedTimeSeconds = -1.0

    init(options: PlayerOptions) {
        super.init()
        mediaPlayer = VLCMediaPlayer()
        mediaPlayer?.delegate = self
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        session.activate(options: []) { activated, error in
            if let error {
                debugPrint("Audio session activation failed:", error)
            }
        }
    }

    func play(_ url: URL) {
        writeDebug("[VLC] play called, url=\(url.absoluteString)")
        configureAudioSession()
        hasNotifiedFileLoaded = false
        lastReportedTimeSeconds = -1.0
        mediaPlayer?.media = VLCMedia(url: url)
        writeDebug("[VLC] media set, calling play()")
        mediaPlayer?.play()
        writeDebug("[VLC] play() returned, isPlaying=\(mediaPlayer?.isPlaying ?? false), state=\(mediaPlayer?.state.rawValue ?? -1)")
    }

    func togglePlayback() {
        guard let mediaPlayer else { return }
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    func pause() {
        mediaPlayer?.pause()
    }

    func resume() {
        mediaPlayer?.play()
    }

    func seek(to time: Double) {
        let durationSeconds = Double(mediaPlayer?.media?.length.intValue ?? 0) / 1000.0
        let clampedTime = clampSeekTime(time, durationSeconds: durationSeconds)
        let milliseconds = max(0, Int32(clampedTime * 1000.0))
        mediaPlayer?.time = VLCTime(int: milliseconds)
    }

    func seek(by delta: Double) {
        guard let mediaPlayer else { return }
        let currentSeconds = Double(mediaPlayer.time.intValue) / 1000.0
        seek(to: currentSeconds + delta)
    }

    func setPlaybackRate(_ rate: Float) {
        mediaPlayer?.rate = max(0.1, rate)
    }

    func selectAudioTrack(id: Int?) {
        guard let mediaPlayer else { return }
        let tracks = mediaPlayer.audioTracks
        if let id, id < tracks.count {
            tracks[id].isSelectedExclusively = true
        } else {
            mediaPlayer.deselectAllAudioTracks()
        }
    }

    func selectSubtitleTrack(id: Int?) {
        // No subtitle support on watchOS audio-only player
    }

    func trackList() -> [PlayerTrack] {
        guard let mediaPlayer else { return [] }
        return mediaPlayer.audioTracks.enumerated().map { index, track in
            PlayerTrack(
                id: index,
                ffIndex: index,
                type: .audio,
                title: track.trackName,
                language: nil,
                codec: nil,
                isDefault: false,
                isSelected: track.isSelected
            )
        }
    }

    func destruct() {
        mediaPlayer?.stop()
        mediaPlayer?.delegate = nil
        mediaPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Private

    private func clampSeekTime(_ time: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else { return max(0, time) }
        let maxSeekTime = max(0, durationSeconds - 0.1)
        return min(max(0, time), maxSeekTime)
    }
}

// MARK: - VLCMediaPlayerDelegate

extension WatchVLCPlayerController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor in
            let isPaused = newState == .paused || newState == .stopped || newState == .stopping

            onPropertyChange?(.pause, isPaused)
            onPropertyChange?(.pausedForCache, newState == .opening || newState == .buffering)

            if !hasNotifiedFileLoaded, newState == .playing || newState == .paused {
                hasNotifiedFileLoaded = true
                onMediaLoaded?()
            }

            if newState == .stopped, hasNotifiedFileLoaded {
                onPlaybackEnded?()
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let mediaPlayer else { return }
            let timeSeconds = Double(mediaPlayer.time.intValue) / 1000.0
            let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0

            if timeSeconds != lastReportedTimeSeconds {
                lastReportedTimeSeconds = timeSeconds
                onPropertyChange?(.pausedForCache, false)
            }

            onPropertyChange?(.timePos, timeSeconds)
            if durationSeconds > 0 {
                onPropertyChange?(.duration, durationSeconds)
            }
        }
    }
}
