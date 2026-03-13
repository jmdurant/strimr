import Foundation

struct WidgetLibraryItem: Codable, Identifiable {
    let id: String
    let title: String
    let type: String // movie, show, artist, photo, etc.
    let sectionId: Int?

    var iconName: String {
        switch type {
        case "movie": "film.fill"
        case "show": "tv.fill"
        case "artist": "music.note.list"
        case "photo": "photo.on.rectangle"
        case "clip": "video.fill"
        default: "questionmark.square.fill"
        }
    }

    var deepLinkURL: URL {
        URL(string: "slingshot://library/\(id)")!
    }
}

struct WidgetData: Codable {
    let libraries: [WidgetLibraryItem]
    let hasLiveTV: Bool
    let bannerText: String
    let updatedAt: Date

    static let appGroupID = "group.com.doctordurant.slingshot"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var fileURL: URL? {
        containerURL?.appendingPathComponent("widget-data.json")
    }

    static func write(_ data: WidgetData) {
        guard let url = fileURL else { return }
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
        } catch {
            // Silently fail — widget will show fallback
        }
    }

    static func read() -> WidgetData? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
        else { return nil }
        return decoded
    }

    static let liveTVDeepLink = URL(string: "slingshot://livetv")!
}
