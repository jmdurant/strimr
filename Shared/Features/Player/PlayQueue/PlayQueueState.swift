import Foundation

struct PlayQueueState: Equatable, Identifiable {
    let id: Int
    let selectedItemID: Int?
    let selectedMetadataItemID: String?
    let totalCount: Int?
    let version: Int?
    let shuffled: Bool?
    let sourceURI: String?
    let items: [PlexItem]

    init(response: PlexPlayQueueResponse) {
        let container = response.mediaContainer
        id = container.playQueueID
        selectedItemID = container.playQueueSelectedItemID
        selectedMetadataItemID = container.playQueueSelectedMetadataItemID
        totalCount = container.playQueueTotalCount
        version = container.playQueueVersion
        shuffled = container.playQueueShuffled
        sourceURI = container.playQueueSourceURI
        items = container.metadata ?? []
    }

    private init(
        id: Int,
        selectedItemID: Int?,
        selectedMetadataItemID: String?,
        totalCount: Int?,
        version: Int?,
        shuffled: Bool?,
        sourceURI: String?,
        items: [PlexItem]
    ) {
        self.id = id
        self.selectedItemID = selectedItemID
        self.selectedMetadataItemID = selectedMetadataItemID
        self.totalCount = totalCount
        self.version = version
        self.shuffled = shuffled
        self.sourceURI = sourceURI
        self.items = items
    }

    init(localRatingKey: String) {
        id = -1
        selectedItemID = nil
        selectedMetadataItemID = localRatingKey
        totalCount = 1
        version = nil
        shuffled = false
        sourceURI = nil
        items = []
    }

    var selectedRatingKey: String? {
        if let selectedMetadataItemID {
            return selectedMetadataItemID
        }
        if let selectedItemID {
            return items.first { $0.playQueueItemID == selectedItemID }?.ratingKey
        }
        return items.first?.ratingKey
    }

    func selecting(ratingKey: String) -> PlayQueueState {
        PlayQueueState(
            id: id,
            selectedItemID: items.first { $0.ratingKey == ratingKey }?.playQueueItemID ?? selectedItemID,
            selectedMetadataItemID: ratingKey,
            totalCount: totalCount,
            version: version,
            shuffled: shuffled,
            sourceURI: sourceURI,
            items: items
        )
    }

    func item(after ratingKey: String) -> PlexItem? {
        guard let index = items.firstIndex(where: { $0.ratingKey == ratingKey }) else { return nil }
        let nextIndex = items.index(after: index)
        guard nextIndex < items.endIndex else { return nil }
        return items[nextIndex]
    }

    func item(before ratingKey: String) -> PlexItem? {
        guard let index = items.firstIndex(where: { $0.ratingKey == ratingKey }) else { return nil }
        guard index > items.startIndex else { return nil }
        return items[items.index(before: index)]
    }
}
