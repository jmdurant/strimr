import Foundation

struct SeerrMedia: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let backdropPath: String?
    let posterPath: String?
}
