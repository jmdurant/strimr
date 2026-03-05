import UIKit

enum LiveActivityImageLoader {
    static func loadCompressedThumbnail(
        path: String?,
        context: PlexAPIContext,
        maxBytes: Int = 3000
    ) async -> Data? {
        guard let path else { return nil }
        guard let imageRepo = try? ImageRepository(context: context),
              let url = imageRepo.transcodeImageURL(path: path, width: 80, height: 80)
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            let size = CGSize(width: 80, height: 80)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }

            var quality: CGFloat = 0.5
            while quality > 0.1 {
                if let jpeg = resized.jpegData(compressionQuality: quality),
                   jpeg.count <= maxBytes {
                    return jpeg
                }
                quality -= 0.1
            }
            return resized.jpegData(compressionQuality: 0.1)
        } catch {
            return nil
        }
    }
}
