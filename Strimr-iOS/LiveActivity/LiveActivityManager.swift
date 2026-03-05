import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var nowPlayingBridge: NowPlayingActivityBridge?
    private var liveTVBridge: LiveTVActivityBridge?

    /// The currently active player, exposed for Live Activity intents.
    private(set) var activePlayerViewModel: PlayerViewModel?
    private(set) var activePlayerCoordinator: (any PlayerCoordinating)?

    private init() {}

    // MARK: - Now Playing (VOD)

    func startNowPlaying(viewModel: PlayerViewModel, coordinator: any PlayerCoordinating, context: PlexAPIContext) {
        stopNowPlaying()
        activePlayerViewModel = viewModel
        activePlayerCoordinator = coordinator
        let bridge = NowPlayingActivityBridge(viewModel: viewModel, context: context)
        nowPlayingBridge = bridge
        bridge.start()
    }

    func stopNowPlaying() {
        nowPlayingBridge?.stop()
        nowPlayingBridge = nil
        activePlayerViewModel = nil
        activePlayerCoordinator = nil
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
