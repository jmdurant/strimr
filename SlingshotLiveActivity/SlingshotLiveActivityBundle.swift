import SwiftUI
import WidgetKit

@main
struct SlingshotLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
        LiveTVLiveActivity()
        LibraryWidget()
    }
}
