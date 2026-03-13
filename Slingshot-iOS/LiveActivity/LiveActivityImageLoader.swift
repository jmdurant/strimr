import UIKit

enum LiveActivityImageLoader {
    /// ActivityKit limits total attributes + state to ~4KB.
    /// Reserve ~1.5KB for text fields and overhead; artwork gets the rest.
    static func loadCompressedThumbnail(
        path: String?,
        context: PlexAPIContext,
        maxBytes: Int = 2500
    ) async -> Data? {
        guard let path else { return nil }
        guard let imageRepo = try? ImageRepository(context: context),
              let url = imageRepo.transcodeImageURL(path: path, width: 60, height: 60)
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            // Try progressively smaller sizes and lower quality to fit budget
            for dimension in [60, 48, 36] as [CGFloat] {
                let size = CGSize(width: dimension, height: dimension)
                let renderer = UIGraphicsImageRenderer(size: size)
                let resized = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }

                for q in stride(from: 0.5, through: 0.05, by: -0.05) {
                    if let jpeg = resized.jpegData(compressionQuality: q),
                       jpeg.count <= maxBytes {
                        return jpeg
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}
