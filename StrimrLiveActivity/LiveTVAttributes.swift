import ActivityKit
import Foundation

struct LiveTVAttributes: ActivityAttributes {
    let channelName: String
    let channelNumber: String

    struct ContentState: Codable, Hashable {
        let programTitle: String?
        let programEndsAt: Date?
        let isBuffering: Bool
    }
}
