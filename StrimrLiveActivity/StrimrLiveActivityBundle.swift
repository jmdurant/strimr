import SwiftUI
import WidgetKit

@main
struct StrimrLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
        LiveTVLiveActivity()
        LibraryWidget()
    }
}
