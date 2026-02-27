import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: String
    let guid: String
    let summary: String?
    let title: String
    let type: PlexItemType
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let genres: [String]
    let year: Int?
    let duration: TimeInterval?
    let videoResolution: String?
    let rating: Double?
    let contentRating: String?
    let studio: String?
    let tagline: String?
    let thumbPath: String?
    let artPath: String?
    let ultraBlurColors: PlexUltraBlurColors?
    let viewOffset: TimeInterval?
    let viewCount: Int?
    let childCount: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let grandparentThumbPath: String?
    let grandparentArtPath: String?
    let parentThumbPath: String?

    var primaryLabel: String {
        grandparentTitle ?? parentTitle ?? title
    }

    var plexGuidID: String? {
        guid.split(separator: "/").last.map(String.init)
    }

    var preferredThumbPath: String? {
        grandparentThumbPath ?? parentThumbPath ?? thumbPath
    }

    var preferredArtPath: String? {
        grandparentArtPath ?? artPath
    }

    var secondaryLabel: String? {
        switch type {
        case .movie:
            return year.map(String.init)

        case .show:
            guard let childCount else { return nil }
            return String(localized: "media.labels.seasonsCount \(childCount)")

        case .season, .episode:
            return title

        case .artist:
            return childCount.map { "\($0) albums" }

        case .album:
            let parts = [grandparentTitle, year.map(String.init)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")

        case .track:
            return grandparentTitle

        case .collection:
            guard let childCount else { return nil }
            return String(localized: "media.labels.elementsCount \(childCount)")

        case .photo:
            return childCount.map { "\($0) photos" } ?? year.map(String.init)

        case .clip:
            return year.map(String.init)

        case .playlist, .unknown:
            return nil
        }
    }

    var tertiaryLabel: String? {
        switch type {
        case .episode:
            guard let parentIndex, let index else { return nil }
            return String(localized: "media.labels.seasonEpisode \(parentIndex) \(index)")
        case .track:
            if let index { return "Track \(index)" }
            return parentTitle
        case .photo, .clip:
            return nil
        default:
            return nil
        }
    }

    var metadataRatingKey: String {
        switch type {
        case .episode:
            grandparentRatingKey ?? parentRatingKey ?? id
        case .season:
            parentRatingKey ?? id
        case .track:
            grandparentRatingKey ?? parentRatingKey ?? id
        case .album:
            parentRatingKey ?? id
        case .movie, .show, .artist, .photo, .clip:
            id
        case .collection, .playlist, .unknown:
            id
        }
    }

    var viewProgressPercentage: Double? {
        guard let viewOffset, let duration, duration > 0 else {
            return nil
        }

        return min(100, (viewOffset / duration) * 100)
    }

    var playbackResolutionLabel: String? {
        guard var value = videoResolution?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        value = value.lowercased()

        if Int(value) != nil {
            return "\(value)p"
        }

        if value.hasSuffix("k") || value == "sd" || value == "uhd" {
            return value.uppercased()
        }

        return value
    }
}
