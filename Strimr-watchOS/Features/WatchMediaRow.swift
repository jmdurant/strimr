import SwiftUI

struct WatchMediaRow: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let item: MediaDisplayItem

    var body: some View {
        switch item {
        case let .playable(mediaItem):
            if let playable = PlayableMediaItem(mediaItem: mediaItem) {
                NavigationLink(value: playable) {
                    rowContent
                }
            } else {
                rowContent
            }
        case .collection, .playlist:
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            if let thumbURL = thumbURL {
                AsyncImage(url: thumbURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 40, height: 56)
                .clipped()
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.primaryLabel)
                    .font(.caption)
                    .lineLimit(2)

                if let secondary = item.secondaryLabel {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let tertiary = item.tertiaryLabel {
                    Text(tertiary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let progress = item.viewProgressPercentage, progress > 0 {
                    ProgressView(value: min(1, progress / 100))
                        .tint(.accentColor)
                }
            }
        }
    }

    private var thumbURL: URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext) else { return nil }
        return item.preferredThumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 160, height: 240)
        }
    }
}
