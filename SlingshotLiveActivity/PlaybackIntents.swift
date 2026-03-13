import AppIntents

struct TogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Playback"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        LiveActivityManager.shared.activePlayerCoordinator?.togglePlayback()
        #endif
        return .result()
    }
}

struct SkipForwardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Forward"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let seconds = Double(AppDependencies.shared.settingsManager.playback.seekForwardSeconds)
        LiveActivityManager.shared.activePlayerCoordinator?.seek(by: seconds)
        #endif
        return .result()
    }
}

struct SkipBackwardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Backward"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let seconds = Double(AppDependencies.shared.settingsManager.playback.seekBackwardSeconds)
        LiveActivityManager.shared.activePlayerCoordinator?.seek(by: -seconds)
        #endif
        return .result()
    }
}
