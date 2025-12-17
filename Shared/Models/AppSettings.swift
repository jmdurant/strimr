import Foundation

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
}
