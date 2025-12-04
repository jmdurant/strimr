import Foundation

enum PlexAPIError: Error {
    case invalidURL
    case missingAuthToken
    case missingConnection
    case unreachableServer
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
}

enum PlexQueryValue {
    case string(String)
    case int(Int)
    case stringArray([String])
    case intArray([Int])

    func asQueryItem(key: String) -> URLQueryItem {
        switch self {
        case let .string(value):
            return URLQueryItem(name: key, value: value)
        case let .int(value):
            return URLQueryItem(name: key, value: String(value))
        case let .stringArray(values):
            return URLQueryItem(name: key, value: values.joined(separator: ","))
        case let .intArray(values):
            return URLQueryItem(name: key, value: values.map(String.init).joined(separator: ","))
        }
    }
}

struct PlexPagination {
    let start: Int
    let size: Int

    init(start: Int = 0, size: Int = 20) {
        self.start = start
        self.size = size
    }
}
