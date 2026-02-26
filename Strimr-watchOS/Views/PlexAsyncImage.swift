import SwiftUI

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
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await PlexURLSession.shared.data(from: url)
            #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    image = Image(uiImage: uiImage)
                }
            #endif
        } catch {
            image = nil
        }
    }
}
