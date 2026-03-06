import Foundation

struct WatchTogetherParticipant: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    var displayName: String
    var isHost: Bool
    var isReady: Bool
    var hasMediaAccess: Bool
}

struct WatchTogetherSelectedMedia: Codable, Hashable {
    let ratingKey: String
    let type: PlexItemType
    let title: String
    let thumbPath: String?
}

extension WatchTogetherSelectedMedia {
    init(media: MediaDisplayItem) {
        ratingKey = media.id
        type = media.type
        title = media.title
        thumbPath = media.thumbPath
    }
}

struct WatchTogetherChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let sentAtMs: Int64
}

struct WatchTogetherLiveTVChannel: Codable, Hashable {
    let channelId: String
    let channelName: String
    let thumb: String?
}

struct WatchTogetherLobbySnapshot: Codable, Hashable {
    let code: String
    let hostId: String
    let participants: [WatchTogetherParticipant]
    let selectedMedia: WatchTogetherSelectedMedia?
    let started: Bool
    let startAtEpochMs: Int64?
    let currentPositionSeconds: Double?
    let isPaused: Bool?
    let chatMessages: [WatchTogetherChatMessage]?
    let liveTVChannel: WatchTogetherLiveTVChannel?
}

struct WatchTogetherStartPlayback: Codable, Hashable {
    let ratingKey: String
    let type: PlexItemType
    let startAtEpochMs: Int64
}

struct WatchTogetherServerError: Codable, Hashable {
    let message: String
    let code: String?
    let currentVersion: Int?
    let minimumVersion: Int?
    let maximumVersion: Int?
}
