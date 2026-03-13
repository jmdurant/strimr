import Foundation

enum WatchSyncStatus: String, Codable {
    case queued
    case downloading
    case transferring
    case completed
    case failed
}

struct WatchSyncItem: Codable, Identifiable, Hashable {
    var id: String
    var ratingKey: String
    var status: WatchSyncStatus
    var progress: Double
    var title: String
    var artistName: String?
    var albumName: String?
    var errorMessage: String?
    var createdAt: Date

    var isActive: Bool {
        switch status {
        case .queued, .downloading, .transferring:
            true
        case .completed, .failed:
            false
        }
    }
}
