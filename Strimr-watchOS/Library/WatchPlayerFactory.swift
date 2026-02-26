import Foundation

enum WatchPlayerFactory {
    static func makeCoordinator(options: PlayerOptions, isVideo: Bool) -> any PlayerCoordinating {
        if isVideo {
            return WatchAVPlayerController(options: options)
        } else {
            return WatchVLCPlayerController(options: options)
        }
    }
}
