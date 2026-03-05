import ActivityKit
import Foundation

struct NowPlayingAttributes: ActivityAttributes {
    let title: String
    let subtitle: String?
    let mediaType: String
    let durationSeconds: Double
    let artworkData: Data?

    struct ContentState: Codable, Hashable {
        let positionSeconds: Double
        let isPaused: Bool
        let isBuffering: Bool
        let playbackRate: Float
        let timestamp: Date
    }
}
