import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var nowPlayingBridge: NowPlayingActivityBridge?
    private var liveTVBridge: LiveTVActivityBridge?

    private init() {}

    // MARK: - Now Playing (VOD)

    func startNowPlaying(viewModel: PlayerViewModel, context: PlexAPIContext) {
        stopNowPlaying()
        let bridge = NowPlayingActivityBridge(viewModel: viewModel, context: context)
        nowPlayingBridge = bridge
        bridge.start()
    }

    func stopNowPlaying() {
        nowPlayingBridge?.stop()
        nowPlayingBridge = nil
    }

    // MARK: - Live TV

    func startLiveTV(channelName: String, channelNumber: String = "") {
        stopLiveTV()
        let bridge = LiveTVActivityBridge(channelName: channelName, channelNumber: channelNumber)
        liveTVBridge = bridge
        bridge.start()
    }

    func updateLiveTVProgram(title: String?, endsAt: Date?) {
        liveTVBridge?.updateProgram(title: title, endsAt: endsAt)
    }

    func stopLiveTV() {
        liveTVBridge?.stop()
        liveTVBridge = nil
    }
}
