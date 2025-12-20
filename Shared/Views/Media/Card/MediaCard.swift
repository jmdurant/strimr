import SwiftUI

struct MediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    enum Layout {
        case landscape
        case portrait

        var aspectRatio: CGFloat {
            switch self {
            case .landscape:
                return 16 / 9
            case .portrait:
                return 2 / 3
            }
        }
    }

    let layout: Layout
    let media: MediaItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let onTap: () -> Void

    private var progress: Double? {
        media.viewProgressPercentage.map { $0 / 100 }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: artworkKind,
                        media: media
                    )
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(layout.aspectRatio, contentMode: .fit)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(alignment: .topTrailing) {
                    WatchStatusBadge(media: media)
                }
                .overlay(alignment: .bottomLeading) {
                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
                    }
                }

                #if !os(tvOS)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(media.primaryLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Text(media.secondaryLabel ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(media.tertiaryLabel ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                #endif
            }
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isFocused ? Color.brandSecondary : .clear,
                        lineWidth: 4
                    )
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    focusModel.focusedMedia = media
                }
            }
        #endif
    }
}
