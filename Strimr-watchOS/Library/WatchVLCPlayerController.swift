import AVFoundation
import Foundation
import os
import VLCKit

@MainActor
final class WatchVLCPlayerController: NSObject, PlayerCoordinating {
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onMediaLoaded: (() -> Void)?

    private(set) var spectrumData = SpectrumData()
    private var audioBridge: VLCAudioBridge?
    private var mediaPlayer: VLCMediaPlayer?
    private var hasNotifiedFileLoaded = false
    private var lastReportedTimeSeconds = -1.0

    init(options: PlayerOptions) {
        super.init()
        // Enable VLC console logging to diagnose errors
        let logger = VLCConsoleLogger()
        logger.level = .debug
        VLCLibrary.shared().loggers = [logger]

        mediaPlayer = VLCMediaPlayer()
        mediaPlayer?.delegate = self
    }

    static func activateAudioSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            AppLogger.fileLog("setCategory failed: \(error)", logger: AppLogger.player)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.activate(options: []) { activated, error in
                if let error {
                    AppLogger.fileLog("audio session activation failed: \(error)", logger: AppLogger.player)
                } else {
                    AppLogger.fileLog("audio session activated: \(activated)", logger: AppLogger.player)
                }
                continuation.resume()
            }
        }
    }

    func play(_ url: URL) {
        AppLogger.fileLog("play called, url=\(url.absoluteString)", logger: AppLogger.player)
        hasNotifiedFileLoaded = false
        lastReportedTimeSeconds = -1.0
        mediaPlayer?.media = VLCMedia(url: url)

        // Install audio callbacks for visualization + AVAudioEngine re-injection.
        // Must happen before play() so VLC uses our callbacks from the first sample.
        if let mp = mediaPlayer {
            audioBridge = VLCAudioBridge(player: mp, spectrumData: spectrumData)
        }

        AppLogger.fileLog("media set, calling play()", logger: AppLogger.player)
        mediaPlayer?.play()
        AppLogger.fileLog("play() returned, isPlaying=\(mediaPlayer?.isPlaying ?? false), state=\(mediaPlayer?.state.rawValue ?? -1)", logger: AppLogger.player)
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
        // Stop media player first — VLC's stop triggers flush_cb which
        // needs the audio bridge context to still be valid.
        mediaPlayer?.stop()
        mediaPlayer?.delegate = nil
        mediaPlayer = nil
        audioBridge?.stop()
        audioBridge = nil
        spectrumData.reset()
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
            let stateNames = ["stopped","stopping","opening","buffering","error","playing","paused"]
            let stateName = newState.rawValue < stateNames.count ? stateNames[Int(newState.rawValue)] : "unknown(\(newState.rawValue))"
            AppLogger.fileLog("stateChanged: \(stateName) (\(newState.rawValue))", logger: AppLogger.player)
            if newState == .error {
                AppLogger.fileLog("ERROR state!", logger: AppLogger.player)
            }
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
