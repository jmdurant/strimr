import SwiftUI

struct MediaBackdropGradient: View {
    let colors: [Color]

    var body: some View {
        Group {
            if colors.count >= 2 {
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color("Background")
            }
        }
    }
}

extension MediaBackdropGradient {
    static func colors(for media: MediaItem) -> [Color] {
        guard let blur = media.ultraBlurColors else { return [] }
        return [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }
}
