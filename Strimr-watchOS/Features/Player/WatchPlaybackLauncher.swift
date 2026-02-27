import Foundation

struct WatchPlaybackLauncher {
    let context: PlexAPIContext

    func createPlayQueue(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false
    ) async throws -> PlayQueueState {
        let manager = try PlayQueueManager(context: context)
        return try await manager.createQueue(
            for: ratingKey,
            itemType: type,
            type: type.isAudio ? "audio" : "video",
            continuous: type == .episode || type == .show || type == .season
                     || type == .track || type == .album || type == .artist,
            shuffle: shuffle
        )
    }
}
