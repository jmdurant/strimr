import SwiftUI

struct MediaShellView<Content: View>: View {
    @Environment(MediaFocusModel.self) private var focusModel

    let media: MediaItem
    let content: Content

    init(media: MediaItem, @ViewBuilder content: () -> Content) {
        self.media = media
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MediaHeroView(media: focusModel.focusedMedia ?? media)

                content
                    .frame(height: proxy.size.height * 0.66)
            }
        }
    }
}
