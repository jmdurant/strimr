import Foundation

// MARK: - GET /livetv/dvrs

struct PlexDVRResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let dvr: [PlexDVR]?

        private enum CodingKeys: String, CodingKey {
            case dvr = "Dvr"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDVR: Codable {
    let key: String
    let uuid: String
    let language: String?
    let lineup: String?
    let device: [PlexTunerDevice]?

    private enum CodingKeys: String, CodingKey {
        case key, uuid, language, lineup
        case device = "Device"
    }
}

struct PlexTunerDevice: Codable {
    let uri: String?
    let uuid: String?
    let make: String?
    let model: String?
    let tuners: String?

    private enum CodingKeys: String, CodingKey {
        case uri, uuid, make, model, tuners
    }
}

// MARK: - GET /livetv/epg/channels?lineup=...

struct PlexChannelListResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let channel: [PlexChannel]?

        private enum CodingKeys: String, CodingKey {
            case channel = "Channel"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    var channels: [PlexChannel] {
        mediaContainer.channel ?? []
    }
}

struct PlexChannel: Codable, Identifiable {
    let key: String?
    let identifier: String?
    let channelVcn: String?
    let title: String?
    let callSign: String?
    let thumb: String?
    let hd: Bool?
    let language: String?

    var id: String { identifier ?? key ?? UUID().uuidString }
    var displayName: String { title ?? callSign ?? "Unknown" }
    var channelNumber: String { channelVcn ?? identifier ?? "" }
    /// The identifier to pass to the tune endpoint.
    var tuneIdentifier: String { identifier ?? key ?? "" }
}

// MARK: - POST /livetv/dvrs/{dvrKey}/tune

struct PlexTuneResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let size: Int?
        let status: Int?
        let message: String?
        let metadata: [PlexTuneMetadata]?

        private enum CodingKeys: String, CodingKey {
            case size, status, message
            case metadata = "Metadata"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexTuneMetadata: Codable {
    let sessionKey: String?
    let key: String?
    let title: String?
    let media: [PlexTuneMedia]?

    private enum CodingKeys: String, CodingKey {
        case sessionKey, key, title
        case media = "Media"
    }
}

struct PlexTuneMedia: Codable {
    let channelCallSign: String?
    let channelIdentifier: String?
    let channelThumb: String?
    let channelTitle: String?
    let part: [PlexTunePart]?

    private enum CodingKeys: String, CodingKey {
        case channelCallSign, channelIdentifier, channelThumb, channelTitle
        case part = "Part"
    }
}

struct PlexTunePart: Codable {
    let key: String?
    let protocolType: String?

    private enum CodingKeys: String, CodingKey {
        case key
        case protocolType = "protocol"
    }
}

// MARK: - GET /tv.plex.providers.epg.cloud (EPG provider discovery)

struct PlexEPGProviderResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let directory: [PlexEPGDirectory]?

        private enum CodingKeys: String, CodingKey {
            case directory = "Directory"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexEPGDirectory: Codable {
    let title: String?
    let key: String?
}

// MARK: - GET /{epgKey}/grid (EPG grid / now playing)

struct PlexEPGGridResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let metadata: [PlexEPGProgram]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexEPGProgram: Codable, Identifiable {
    let ratingKey: String?
    let key: String?
    let guid: String?
    let type: String?
    let title: String?
    let grandparentTitle: String?
    let summary: String?
    let year: Int?
    let beginsAt: Int?
    let endsAt: Int?
    let onAir: Bool?
    let thumb: String?
    let media: [PlexEPGMedia]?

    var id: String { ratingKey ?? key ?? UUID().uuidString }

    /// Display title: "Show Name - Episode Title" for episodes, or just the title for movies.
    var displayTitle: String {
        if let show = grandparentTitle, let ep = title {
            return "\(show) - \(ep)"
        }
        return title ?? "Unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case ratingKey, key, guid, type, title, grandparentTitle, summary, year
        case beginsAt, endsAt, onAir, thumb
        case media = "Media"
    }
}

struct PlexEPGMedia: Codable {
    let channelCallSign: String?
    let channelIdentifier: String?
    let channelThumb: String?
    let channelTitle: String?
    let beginsAt: Int?
    let endsAt: Int?

    private enum CodingKeys: String, CodingKey {
        case channelCallSign, channelIdentifier, channelThumb, channelTitle
        case beginsAt, endsAt
    }
}

// MARK: - GET /media/subscriptions/template

struct PlexSubscriptionTemplateResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let mediaSubscription: [PlexMediaSubscription]?

        private enum CodingKeys: String, CodingKey {
            case mediaSubscription = "MediaSubscription"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexMediaSubscription: Codable {
    let type: String?
    let targetLibrarySectionID: String?
    let parameters: String?
}

// MARK: - NowPlaying (view-layer convenience)

struct NowPlaying {
    let title: String
    let endsAt: Date?

    var timeRemaining: String? {
        guard let endsAt else { return nil }
        let remaining = endsAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        let minutes = Int(remaining / 60)
        return "\(minutes)m left"
    }
}
