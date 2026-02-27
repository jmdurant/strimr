import SwiftUI

private final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 60
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct PlexAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: Image?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                image.resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }

        if let cached = ImageCache.shared.image(for: url) {
            image = Image(uiImage: cached)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (remoteData, _) = try await PlexURLSession.shared.data(from: url)
                data = remoteData
            }
            #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    ImageCache.shared.store(uiImage, for: url)
                    image = Image(uiImage: uiImage)
                }
            #endif
        } catch {
            image = nil
        }
    }
}
