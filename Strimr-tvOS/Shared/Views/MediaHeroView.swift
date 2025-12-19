import SwiftUI

struct MediaHeroView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var imageURL: URL?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                MediaBackdropGradient(colors: MediaBackdropGradient.colors(for: media))
                    .ignoresSafeArea()
                
                heroImage
                    .frame(height: (proxy.size.height
                                    + proxy.safeAreaInsets.top
                                    + proxy.safeAreaInsets.bottom) * 0.66)
                    .clipped()
                    .mask(heroMask)
                    .ignoresSafeArea()

                heroContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task(id: media.id) {
            await loadImage()
        }
    }

    private var heroImage: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(media.primaryLabel)
                .font(.title2.bold())
                .lineLimit(2)

            if let secondary = media.secondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = media.tertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("media.placeholder.noArtwork")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath
        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: plexApiContext)
            imageURL = imageRepository.transcodeImageURL(
                path: path,
                width: 3840,
                height: 2160,
                minSize: 1,
                upscale: 1
            )
        } catch {
            imageURL = nil
        }
    }
}
