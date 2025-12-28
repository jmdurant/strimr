import Foundation

public enum PlayerProperty: String {
    case pause = "pause"
    case pausedForCache = "paused-for-cache"
    case timePos = "time-pos"
    case duration = "duration"
    case demuxerCacheDuration = "demuxer-cache-duration"
    case videoParamsSigPeak = "video-params/sig-peak"
}
