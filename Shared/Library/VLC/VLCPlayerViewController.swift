import Foundation
import UIKit

#if os(tvOS)
    import TVVLCKit
#else
    import VLCKit
#endif

final class VLCPlayerViewController: UIViewController, VLCMediaPlayerDelegate {
    private let options: PlayerOptions
    private lazy var mediaPlayer: VLCMediaPlayer = {
        let scaledValue = Int(round(Double(options.subtitleScale) * 0.5))
        return VLCMediaPlayer(options: ["--sub-text-scale=\(scaledValue)"])
    }()

    var playDelegate: VLCPlayerDelegate?
    var playUrl: URL?
    private var lastReportedTimeSeconds = -1.0
    private var hasNotifiedFileLoaded = false
    #if os(iOS)
    private var pipDrawableView: VLCPiPDrawableView?
    private(set) var pipWindowController: (any VLCPictureInPictureWindowControlling)?
    private(set) var isPipActive = false
    private(set) var spectrumData: SpectrumData?
    private var audioBridge: VLCAudioBridge?
    #endif

    init(options: PlayerOptions) {
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        updateIdleTimer(isPlaying: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        mediaPlayer.delegate = self

        #if os(iOS)
        let drawableView = VLCPiPDrawableView(frame: view.bounds)
        drawableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        drawableView.controller = self
        drawableView.onPipReady = { [weak self] windowController in
            guard let self else { return }
            self.pipWindowController = windowController
            windowController.stateChangeEventHandler = { [weak self] isStarted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isPipActive = isStarted
                    self.playDelegate?.propertyChange(
                        player: self,
                        property: .pipActive,
                        data: isStarted,
                    )
                }
            }
        }
        view.addSubview(drawableView)
        pipDrawableView = drawableView
        mediaPlayer.drawable = drawableView
        #else
        mediaPlayer.drawable = view
        #endif

        if let url = playUrl {
            loadFile(url)
        }
    }

    func loadFile(_ url: URL) {
        hasNotifiedFileLoaded = false
        mediaPlayer.media = VLCMedia(url: url)
        #if os(iOS)
        installAudioBridgeIfNeeded()
        #endif
        mediaPlayer.play()
    }

    func togglePause() {
        mediaPlayer.isPlaying ? pause() : play()
    }

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        mediaPlayer.pause()
    }

    func seek(to time: Double) {
        let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0
        let clampedTime = clampSeekTime(time, durationSeconds: durationSeconds)
        let milliseconds = max(0, Int32(clampedTime * 1000.0))
        mediaPlayer.time = VLCTime(int: milliseconds)
    }

    func seek(by delta: Double) {
        let currentMilliseconds = Double(mediaPlayer.time.intValue)
        let nextTime = (currentMilliseconds / 1000.0) + delta
        seek(to: nextTime)
    }

    func setPlaybackRate(_ rate: Float) {
        mediaPlayer.rate = max(0.1, rate)
    }

    func setAudioTrack(id: Int?) {
        #if os(tvOS)
        let trackID = id ?? -1
        mediaPlayer.currentAudioTrackIndex = Int32(trackID)
        #else
        if let id, id >= 0, id < mediaPlayer.audioTracks.count {
            mediaPlayer.audioTracks[id].isSelectedExclusively = true
        } else {
            mediaPlayer.deselectAllAudioTracks()
        }
        #endif
    }

    func setSubtitleTrack(id: Int?) {
        #if os(tvOS)
        let trackID = id ?? -1
        mediaPlayer.currentVideoSubTitleIndex = Int32(trackID)
        #else
        if let id, id >= 0, id < mediaPlayer.textTracks.count {
            mediaPlayer.textTracks[id].isSelectedExclusively = true
        } else {
            mediaPlayer.deselectAllTextTracks()
        }
        #endif
    }

    func trackList() -> [PlayerTrack] {
        #if os(tvOS)
        let audioTracks = makeTracks(
            names: mediaPlayer.audioTrackNames,
            indexes: mediaPlayer.audioTrackIndexes,
            type: .audio,
            selectedIndex: Int(mediaPlayer.currentAudioTrackIndex),
        )
        let subtitleTracks = makeTracks(
            names: mediaPlayer.videoSubTitlesNames,
            indexes: mediaPlayer.videoSubTitlesIndexes,
            type: .subtitle,
            selectedIndex: Int(mediaPlayer.currentVideoSubTitleIndex),
        )
        return audioTracks + subtitleTracks
        #else
        let audio = mediaPlayer.audioTracks.enumerated().map { index, track in
            PlayerTrack(
                id: index,
                ffIndex: index,
                type: .audio,
                title: track.trackName,
                language: nil,
                codec: nil,
                isDefault: false,
                isSelected: track.isSelected,
            )
        }
        let subtitles = mediaPlayer.textTracks.enumerated().map { index, track in
            PlayerTrack(
                id: index,
                ffIndex: index,
                type: .subtitle,
                title: track.trackName,
                language: nil,
                codec: nil,
                isDefault: false,
                isSelected: track.isSelected,
            )
        }
        return audio + subtitles
        #endif
    }

    func destruct() {
        #if os(iOS)
        pipWindowController?.stopPictureInPicture()
        pipWindowController = nil
        // Detach audio callbacks before stopping the player so VLC's
        // teardown thread doesn't invoke freed callback context.
        audioBridge?.stop()
        audioBridge = nil
        spectrumData?.reset()
        #endif
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        mediaPlayer.drawable = nil
        updateIdleTimer(isPlaying: false)
    }

    #if os(iOS)
    func startPiP() {
        pipWindowController?.startPictureInPicture()
    }

    func stopPiP() {
        pipWindowController?.stopPictureInPicture()
    }

    func enableAudioVisualization() {
        // No-op: audio bridge is installed upfront in loadFile().
    }

    private func installAudioBridgeIfNeeded() {
        guard audioBridge == nil else { return }
        let spectrum = SpectrumData()
        spectrumData = spectrum
        audioBridge = VLCAudioBridge(player: mediaPlayer, spectrumData: spectrum)
    }
    #endif

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateIdleTimer(isPlaying: false)
    }

    #if os(tvOS)
    func mediaPlayerStateChanged(_: Notification) {
        let state = mediaPlayer.state
        let isBuffering = state == .opening || state == .buffering
        let isPaused = state == .paused || state == .stopped || state == .ended

        DispatchQueue.main.async {
            self.playDelegate?.propertyChange(player: self, property: .pause, data: isPaused)
            self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: isBuffering)
        }

        if !hasNotifiedFileLoaded, state == .playing || state == .paused {
            hasNotifiedFileLoaded = true
            DispatchQueue.main.async {
                self.playDelegate?.fileLoaded()
            }
        }

        if state == .ended {
            updateIdleTimer(isPlaying: false)
            DispatchQueue.main.async {
                self.playDelegate?.playbackEnded()
            }
        } else {
            updateIdleTimer(isPlaying: !isPaused)
        }
    }
    #else
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        let isBuffering = newState == .opening || newState == .buffering
        let isStopped = newState == .stopped || newState == .stopping
        let isPaused = newState == .paused || isStopped

        DispatchQueue.main.async {
            self.playDelegate?.propertyChange(player: self, property: .pause, data: isPaused)
            self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: isBuffering)
            self.pipWindowController?.invalidatePlaybackState()
        }

        if !hasNotifiedFileLoaded, newState == .playing || newState == .paused {
            hasNotifiedFileLoaded = true
            DispatchQueue.main.async {
                self.playDelegate?.fileLoaded()
            }
        }

        if isStopped {
            updateIdleTimer(isPlaying: false)
            // Only report playback ended when the file was actually loaded and playing.
            // VLC may enter .stopped during initial load or when switching files.
            if hasNotifiedFileLoaded {
                hasNotifiedFileLoaded = false
                DispatchQueue.main.async {
                    self.playDelegate?.playbackEnded()
                }
            }
        } else {
            updateIdleTimer(isPlaying: !isPaused)
        }
    }
    #endif

    func mediaPlayerTimeChanged(_: Notification) {
        let timeSeconds = Double(mediaPlayer.time.intValue) / 1000.0
        let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0

        DispatchQueue.main.async {
            // VLC can remain in `.buffering` even while playback advances; time ticks are the most reliable signal.
            if timeSeconds != self.lastReportedTimeSeconds {
                self.lastReportedTimeSeconds = timeSeconds
                self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: false)
                self.updateIdleTimer(isPlaying: true)
            }
            self.playDelegate?.propertyChange(player: self, property: .timePos, data: timeSeconds)
            if durationSeconds > 0 {
                self.playDelegate?.propertyChange(player: self, property: .duration, data: durationSeconds)
            }
            #if os(iOS)
            self.pipWindowController?.invalidatePlaybackState()
            #endif
        }
    }

    private func updateIdleTimer(isPlaying: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
    }

    #if os(tvOS)
    private func makeTracks(
        names: [Any],
        indexes: [Any],
        type: PlayerTrack.TrackType,
        selectedIndex: Int,
    ) -> [PlayerTrack] {
        let paired = zip(names, indexes)
        return paired.compactMap { name, index in
            let id: Int
            if let number = index as? NSNumber {
                id = number.intValue
            } else if let intValue = index as? Int {
                id = intValue
            } else {
                return nil
            }
            let title = name as? String
            return PlayerTrack(
                id: id,
                ffIndex: id,
                type: type,
                title: title,
                language: nil,
                codec: nil,
                isDefault: false,
                isSelected: id == selectedIndex,
            )
        }
    }
    #endif

    private func clampSeekTime(_ time: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return max(0, time)
        }
        // Avoid seeking to the exact end, which can trigger VLC edge-case behavior.
        let maxSeekTime = max(0, durationSeconds - 0.1)
        return min(max(0, time), maxSeekTime)
    }
}

// MARK: - Picture in Picture (iOS)

#if os(iOS)
extension VLCPlayerViewController: VLCPictureInPictureMediaControlling {
    func seek(by offset: Int64, completion: (() -> Void)!) {
        let currentMs = Int64(mediaPlayer.time.intValue)
        let targetMs = currentMs + offset
        let clampedMs = Int32(clamping: max(0, targetMs))
        mediaPlayer.time = VLCTime(int: clampedMs)
        completion?()
    }

    func mediaLength() -> Int64 {
        Int64(mediaPlayer.media?.length.intValue ?? 0)
    }

    func mediaTime() -> Int64 {
        Int64(mediaPlayer.time.intValue)
    }

    func isMediaSeekable() -> Bool {
        true
    }

    func isMediaPlaying() -> Bool {
        mediaPlayer.isPlaying
    }
}

private final class VLCPiPDrawableView: UIView, VLCPictureInPictureDrawable {
    weak var controller: VLCPlayerViewController?
    var onPipReady: ((any VLCPictureInPictureWindowControlling) -> Void)?

    func mediaController() -> any VLCPictureInPictureMediaControlling {
        controller!
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        { [weak self] windowController in
            guard let windowController else { return }
            self?.onPipReady?(windowController)
        }
    }
}
#endif
