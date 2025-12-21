import Foundation

extension TimeInterval {
    func mediaDurationText() -> String {
        let minutes = Int(self / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return String(localized: "media.detail.duration.hoursMinutes \(hours) \(remainingMinutes)")
        }
        return String(localized: "media.detail.duration.minutes \(remainingMinutes)")
    }
}
