import Foundation
import SwiftUI

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var player = PlaybackPlayer.mpv
    var subtitleScale = 100
    var liveTVQuality: LiveTVQuality = .low

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        player = try container.decodeIfPresent(PlaybackPlayer.self, forKey: .player) ?? .mpv
        subtitleScale = try container.decodeIfPresent(Int.self, forKey: .subtitleScale) ?? 100
        liveTVQuality = try container.decodeIfPresent(LiveTVQuality.self, forKey: .liveTVQuality) ?? .low
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

enum LiveTVQuality: String, Codable, CaseIterable, Identifiable {
    case low = "320x240"
    case medium = "480x320"
    case high = "640x360"

    var id: String { rawValue }

    var resolution: String { rawValue }

    var maxBitrate: String {
        switch self {
        case .low: "500"
        case .medium: "720"
        case .high: "1500"
        }
    }

    var displayName: String {
        switch self {
        case .low: "Low (320x240)"
        case .medium: "Medium (480x320)"
        case .high: "High (640x360)"
        }
    }
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
