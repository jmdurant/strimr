import Foundation

enum PlaybackPlayer: String, Codable, CaseIterable, Identifiable {
    case vlc
    case mpv

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .mpv:
            return "settings.playback.player.mpv"
        case .vlc:
            return "settings.playback.player.vlc"
        }
    }
}
