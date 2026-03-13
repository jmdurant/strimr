import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.doctordurant.slingshotplayer"

    static let network = Logger(subsystem: subsystem, category: "Network")
    static let player = Logger(subsystem: subsystem, category: "Player")
    static let liveTV = Logger(subsystem: subsystem, category: "LiveTV")
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let chromecast = Logger(subsystem: subsystem, category: "Chromecast")
    static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
    static let connection = Logger(subsystem: subsystem, category: "Connection")
    static let watchSync = Logger(subsystem: subsystem, category: "WatchSync")
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")

    /// File-based debug log for watchOS where os_log info/debug messages are suppressed.
    /// On other platforms this just forwards to os_log.
    static func fileLog(_ message: String, logger: Logger = network) {
        logger.warning("\(message)")
        #if os(watchOS)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = fileLogURL
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    static func clearFileLog() {
        #if os(watchOS)
        try? FileManager.default.removeItem(at: fileLogURL)
        #endif
    }

    #if os(watchOS)
    private static let fileLogURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("debug.log")
    }()
    #endif
}
