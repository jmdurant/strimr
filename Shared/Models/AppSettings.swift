import Foundation
import SwiftUI

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var player = PlaybackPlayer.vlc
    var subtitleScale = 100
    var streamQuality: StreamQuality = .q720
    var zoomVideo = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        player = try container.decodeIfPresent(PlaybackPlayer.self, forKey: .player) ?? .vlc
        subtitleScale = try container.decodeIfPresent(Int.self, forKey: .subtitleScale) ?? 100
        streamQuality = try container.decodeIfPresent(StreamQuality.self, forKey: .streamQuality) ?? .q720
        zoomVideo = try container.decodeIfPresent(Bool.self, forKey: .zoomVideo) ?? false
    }
}

struct InterfaceSettings: Codable, Equatable {
    var hiddenLibraryIds: [String] = []
    var navigationLibraryIds: [String] = []
    var displayCollections = true
    var displayPlaylists = true
    var displaySeerrDiscoverTab = true
    var offlineMode = false
    var favoriteChannelIds: [String] = []
    var accentColor: AccentColorOption = .blue
    var appearance: AppearanceMode = .system

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraryIds = try container.decodeIfPresent([String].self, forKey: .hiddenLibraryIds) ?? []
        navigationLibraryIds = try container.decodeIfPresent([String].self, forKey: .navigationLibraryIds) ?? []
        displayCollections = try container.decodeIfPresent(Bool.self, forKey: .displayCollections) ?? true
        displayPlaylists = try container.decodeIfPresent(Bool.self, forKey: .displayPlaylists) ?? true
        displaySeerrDiscoverTab = try container.decodeIfPresent(Bool.self, forKey: .displaySeerrDiscoverTab) ?? true
        offlineMode = try container.decodeIfPresent(Bool.self, forKey: .offlineMode) ?? false
        favoriteChannelIds = try container.decodeIfPresent([String].self, forKey: .favoriteChannelIds) ?? []
        accentColor = try container.decodeIfPresent(AccentColorOption.self, forKey: .accentColor) ?? .blue
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
    }
}

enum AccentColorOption: String, Codable, CaseIterable {
    case blue, purple, green, orange, red, pink

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum StreamQuality: String, Codable, CaseIterable, Identifiable {
    case q320 = "320x240"
    case q480 = "480x320"
    case q720_2 = "720x480"
    case q720 = "1280x720"
    case q1080 = "1920x1080"
    case q1440 = "2560x1440"
    case q4k = "3840x2160"
    case original = "original"

    var id: String { rawValue }

    var resolution: String { rawValue }

    var maxBitrate: String {
        switch self {
        case .q320: "500"
        case .q480: "720"
        case .q720_2: "1500"
        case .q720: "4000"
        case .q1080: "8000"
        case .q1440: "16000"
        case .q4k: "40000"
        case .original: "200000"
        }
    }

    var displayName: String {
        switch self {
        case .q320: "0.5 Mbps (320p)"
        case .q480: "0.7 Mbps (480p)"
        case .q720_2: "1.5 Mbps (480p)"
        case .q720: "4 Mbps (720p)"
        case .q1080: "8 Mbps (1080p)"
        case .q1440: "16 Mbps (1440p)"
        case .q4k: "40 Mbps (4K)"
        case .original: "Original"
        }
    }

    /// Subset suitable for watchOS (limited bandwidth/screen)
    static let watchCases: [StreamQuality] = [.q320, .q480, .q720_2]
}

enum AppearanceMode: String, Codable, CaseIterable {
    case system, dark, light

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct DownloadSettings: Codable, Equatable {
    var wifiOnly = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wifiOnly = try container.decodeIfPresent(Bool.self, forKey: .wifiOnly) ?? true
    }
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
    var interface = InterfaceSettings()
    var downloads = DownloadSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        interface = try container.decodeIfPresent(InterfaceSettings.self, forKey: .interface) ?? InterfaceSettings()
        downloads = try container.decodeIfPresent(DownloadSettings.self, forKey: .downloads) ?? DownloadSettings()
    }
}
