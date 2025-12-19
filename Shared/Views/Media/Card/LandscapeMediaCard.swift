import SwiftUI

struct LandscapeMediaCard: View {
    let media: MediaItem
    let onTap: () -> Void

    var body: some View {
        MediaCard(
            layout: .landscape,
            media: media,
            artworkKind: .art,
            onTap: onTap
        )
    }
}
