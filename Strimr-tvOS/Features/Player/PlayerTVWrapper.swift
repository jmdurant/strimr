import SwiftUI

struct PlayerTVWrapper: View {
    @Environment(SettingsManager.self) private var settingsManager
    let viewModel: PlayerViewModel
    let onExit: () -> Void

    var body: some View {
        PlayerTVView(
            viewModel: viewModel,
            initialPlayer: settingsManager.playback.player,
            options: PlayerOptions(subtitleScale: settingsManager.playback.subtitleScale),
            onExit: onExit
        )
    }
}
