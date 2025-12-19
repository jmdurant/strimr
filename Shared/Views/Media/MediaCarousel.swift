import SwiftUI

struct MediaCarousel: View {
    enum Layout { case portrait, landscape }

    let layout: Layout
    let items: [MediaItem]
    let onSelectMedia: (MediaItem) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing(for: layout)) {
                ForEach(items, id: \.id) { item in
                    card(for: item)
                        .frame(
                            width: cardWidth(for: layout, sizeClass: sizeClass)
                        )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func card(for media: MediaItem) -> some View {
        switch layout {
        case .portrait:
            PortraitMediaCard(media: media) { onSelectMedia(media) }
        case .landscape:
            LandscapeMediaCard(media: media) { onSelectMedia(media) }
        }
    }

    private func cardWidth(
        for layout: Layout,
        sizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        switch layout {
        case .portrait:
            if sizeClass == .compact {
                return 120
            } else {
                return 160
            }

        case .landscape:
            if sizeClass == .compact {
                return 160
            } else {
                return 220
            }
        }
    }

    private func spacing(for layout: Layout) -> CGFloat {
        switch layout {
        case .portrait:
            return 12
        case .landscape:
            return 16
        }
    }
}
