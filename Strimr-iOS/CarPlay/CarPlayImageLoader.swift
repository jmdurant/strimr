import CarPlay
import UIKit

@MainActor
final class CarPlayImageLoader {
    static let shared = CarPlayImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session = URLSession.shared

    private init() {
        cache.countLimit = 100
    }

    func loadImage(
        path: String,
        context: PlexAPIContext,
        onto listItem: CPListItem
    ) {
        guard let imageRepo = try? ImageRepository(context: context),
              let url = imageRepo.transcodeImageURL(path: path, width: 90, height: 90)
        else { return }

        let cacheKey = url.absoluteString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            listItem.setImage(cached)
            return
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await session.data(from: url)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    self.cache.setObject(image, forKey: cacheKey)
                    listItem.setImage(image)
                }
            } catch {}
        }
    }

    func loadImage(path: String, context: PlexAPIContext) async -> UIImage? {
        guard let imageRepo = try? ImageRepository(context: context),
              let url = imageRepo.transcodeImageURL(path: path, width: 240, height: 240)
        else { return nil }

        let cacheKey = url.absoluteString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }
}
