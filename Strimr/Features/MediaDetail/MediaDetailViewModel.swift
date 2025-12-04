import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext

    var media: MediaItem
    var heroImageURL: URL?
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []
    var seasons: [MediaItem] = []
    var episodes: [MediaItem] = []
    var selectedSeasonId: String?
    var isLoadingSeasons = false
    var isLoadingEpisodes = false
    var seasonsErrorMessage: String?
    var episodesErrorMessage: String?

    init(media: MediaItem, context: PlexAPIContext) {
        self.media = media
        self.context = context
        resolveArtwork()
    }

    func loadDetails() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = "Select a server to load details."
            if media.type == .show {
                seasonsErrorMessage = "Select a server to load seasons."
            }
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            if let item = response.mediaContainer.metadata?.first {
                media = MediaItem(plexItem: item)
                resolveArtwork()
                resolveGradient()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        await loadSeasonsIfNeeded(forceReload: true)
    }

    func loadSeasonsIfNeeded(forceReload: Bool = false) async {
        guard media.type == .show else { return }
        guard forceReload || seasons.isEmpty else { return }
        await fetchSeasons()
    }

    func selectSeason(id: String) async {
        guard selectedSeasonId != id else { return }
        selectedSeasonId = id
        episodes = []
        episodesErrorMessage = nil
        await fetchEpisodes(for: id)
    }

    func imageURL(for media: MediaItem, width: Int = 320, height: Int = 180) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }

        let path = media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: width, height: height) }
    }

    private func resolveArtwork() {
        guard let imageRepository = try? ImageRepository(context: context) else {
            heroImageURL = nil
            return
        }

        heroImageURL = media.artPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.thumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        }
        resolveGradient()
    }

    private func resolveGradient() {
        guard let blur = media.ultraBlurColors else {
            backdropGradient = []
            return
        }

        backdropGradient = [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }

    var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    var yearText: String? {
        media.year.map(String.init)
    }

    var ratingText: String? {
        media.rating.map { String(format: "%.1f", $0) }
    }

    var selectedSeason: MediaItem? {
        seasons.first(where: { $0.id == selectedSeasonId })
    }

    var selectedSeasonTitle: String {
        selectedSeason?.title ?? "Season"
    }

    func runtimeText(for item: MediaItem) -> String? {
        guard let duration = item.duration else { return nil }
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    func progressFraction(for item: MediaItem) -> Double? {
        guard let percentage = item.viewProgressPercentage else { return nil }
        return min(1, max(0, percentage / 100))
    }

    private func fetchSeasons() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            seasonsErrorMessage = "Select a server to load seasons."
            return
        }

        isLoadingSeasons = true
        seasonsErrorMessage = nil
        episodesErrorMessage = nil
        defer { isLoadingSeasons = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: media.metadataRatingKey)
            let fetchedSeasons = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
            seasons = fetchedSeasons
            episodes = []

            guard !fetchedSeasons.isEmpty else {
                selectedSeasonId = nil
                episodes = []
                return
            }

            let nextSeasonId = selectedSeasonId ?? fetchedSeasons.first?.id
            selectedSeasonId = nextSeasonId

            if let seasonId = nextSeasonId {
                await fetchEpisodes(for: seasonId)
            } else {
                episodes = []
            }
        } catch {
            seasons = []
            selectedSeasonId = nil
            episodes = []
            seasonsErrorMessage = error.localizedDescription
        }
    }

    private func fetchEpisodes(for seasonId: String) async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            episodesErrorMessage = "Select a server to load episodes."
            return
        }

        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: seasonId)
            let fetchedEpisodes = (response.mediaContainer.metadata ?? []).map(MediaItem.init)

            guard selectedSeasonId == seasonId else { return }
            episodes = fetchedEpisodes
        } catch {
            if selectedSeasonId == seasonId {
                episodes = []
                episodesErrorMessage = error.localizedDescription
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
