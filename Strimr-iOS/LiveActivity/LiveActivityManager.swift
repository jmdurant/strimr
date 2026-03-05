import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var nowPlayingBridge: NowPlayingActivityBridge?
    private var liveTVBridge: LiveTVActivityBridge?

    /// The currently active player, exposed for Live Activity intents.
    private(set) var activePlayerViewModel: PlayerViewModel?
    private(set) var activePlayerCoordinator: (any PlayerCoordinating)?
    private(set) var activePlayer: InternalPlaybackPlayer?

    /// Whether the player is alive in the background (dismissed but still playing)
    var hasBackgroundPlayer: Bool {
        activePlayerCoordinator != nil && activePlayerViewModel != nil
    }

    private init() {}

    // MARK: - Now Playing (VOD)

    func startNowPlaying(viewModel: PlayerViewModel, coordinator: any PlayerCoordinating, player: InternalPlaybackPlayer, context: PlexAPIContext) {
        stopNowPlayingBridge()
        activePlayerViewModel = viewModel
        activePlayerCoordinator = coordinator
        activePlayer = player
        let bridge = NowPlayingActivityBridge(viewModel: viewModel, context: context)
        nowPlayingBridge = bridge
        bridge.start()
    }

    /// Stop the Live Activity bridge but keep the player alive
    func stopNowPlayingBridge() {
        nowPlayingBridge?.stop()
        nowPlayingBridge = nil
    }

    /// Fully stop and release the player
    func stopNowPlaying() {
        stopNowPlayingBridge()
        activePlayerCoordinator?.destruct()
        activePlayerCoordinator = nil
        activePlayerViewModel = nil
        activePlayer = nil
    }

    // MARK: - Live TV

    private(set) var liveTVCoordinator: (any PlayerCoordinating)?
    private(set) var liveTVChannelName: String?
    private(set) var liveTVStreamURL: URL?

    var hasBackgroundLiveTV: Bool {
        liveTVCoordinator != nil && liveTVStreamURL != nil
    }

    func startLiveTV(channelName: String, channelNumber: String = "", coordinator: any PlayerCoordinating, streamURL: URL) {
        stopLiveTVBridge()
        liveTVCoordinator = coordinator
        liveTVChannelName = channelName
        liveTVStreamURL = streamURL
        let bridge = LiveTVActivityBridge(channelName: channelName, channelNumber: channelNumber)
        liveTVBridge = bridge
        bridge.start()
    }

    func updateLiveTVProgram(title: String?, endsAt: Date?) {
        liveTVBridge?.updateProgram(title: title, endsAt: endsAt)
    }

    func stopLiveTVBridge() {
        liveTVBridge?.stop()
        liveTVBridge = nil
    }

    func stopLiveTV() {
        stopLiveTVBridge()
        liveTVCoordinator?.destruct()
        liveTVCoordinator = nil
        liveTVChannelName = nil
        liveTVStreamURL = nil
    }
}
