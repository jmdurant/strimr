import Foundation

enum SeerrMediaType: String, Hashable, Decodable {
    case movie
    case tv
    case person
}

struct SeerrMedia: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let mediaType: SeerrMediaType?
    let backdropPath: String?
    let posterPath: String?
    let profilePath: String?
    let releaseDate: String?
    let firstAirDate: String?
}
