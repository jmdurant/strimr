import Foundation
import GroupActivities

struct SlingshotSharePlayActivity: GroupActivity {
    static let activityIdentifier = "com.slingshot.shareplay.watch"

    let ratingKey: String
    let type: PlexItemType
    let title: String
    let thumbPath: String?

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = title
        meta.type = .watchTogether
        return meta
    }
}
