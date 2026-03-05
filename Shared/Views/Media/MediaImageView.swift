import SwiftUI

struct MediaImageView: View {
    @State var viewModel: MediaImageViewModel

    var body: some View {
        Group {
            if let url = viewModel.imageURL {
                AsyncImage(url: url) { phase in
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
        .task {
            await viewModel.load()
        }
    }

    private var placeholder: some View {
        let iconName: String = switch viewModel.media.type {
        case .artist, .album, .track:
            "music.note"
        case .photo:
            "photo"
        default:
            "film"
        }

        return VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("media.placeholder.noArtwork")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
