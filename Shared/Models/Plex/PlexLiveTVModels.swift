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

// MARK: - GET /livetv/dvrs/{dvrKey}/channels

struct PlexChannelListResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let metadata: [PlexChannel]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexChannel: Codable, Identifiable {
    let ratingKey: String?
    let key: String
    let title: String?
    let thumb: String?
    let year: Int?

    var id: String { ratingKey ?? key }
    var displayName: String { title ?? key }
}

// MARK: - POST /livetv/dvrs/{dvrKey}/channels/{channelKey}/tune

struct PlexTuneResponse: Codable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable {
        let metadata: [PlexTuneMetadata]?

        private enum CodingKeys: String, CodingKey {
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
