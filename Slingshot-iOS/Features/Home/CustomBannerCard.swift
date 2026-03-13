import SwiftUI

struct CustomBannerCard: View {
    let bannerText: String
    let customImageData: Data?
    let libraries: [Library]
    let artworkURLForLibrary: (Library) -> URL?
    var hasLiveTV: Bool = false
    var onSelectLibrary: (Library) -> Void = { _ in }
    var onSelectLiveTV: () -> Void = {}

    private let cardHeight: CGFloat = 160
    private let scrollInterval: TimeInterval = 5.0

    @State private var currentPage = 0
    @State private var timerReset = 0

    private var slides: [BannerSlide] {
        var result: [BannerSlide] = []

        // Custom photo slide first if available
        if let customImageData {
            result.append(.customPhoto(customImageData))
        }

        // Always show a slide per library (artwork or gradient fallback)
        for library in libraries {
            result.append(.library(library, artworkURLForLibrary(library)))
        }

        // Live TV slide
        if hasLiveTV {
            result.append(.liveTV)
        }

        // Fallback if nothing available
        if result.isEmpty {
            result.append(.gradient)
        }

        return result
    }

    var body: some View {
        ZStack {
            ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                slideView(slide)
                    .opacity(index == currentPage ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6), value: currentPage)
            }

            // Page indicator
            if slides.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<slides.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            let currentSlides = slides
            guard currentPage < currentSlides.count else { return }
            switch currentSlides[currentPage] {
            case let .library(library, _):
                onSelectLibrary(library)
            case .liveTV:
                onSelectLiveTV()
            default:
                break
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    guard slides.count > 1 else { return }
                    if value.translation.width < -50 {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentPage = (currentPage + 1) % slides.count
                        }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentPage = (currentPage - 1 + slides.count) % slides.count
                        }
                    }
                    timerReset += 1
                }
        )
        .task(id: "\(slides.count)-\(timerReset)") {
            guard slides.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(scrollInterval))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.6)) {
                    currentPage = (currentPage + 1) % slides.count
                }
            }
        }
    }

    @ViewBuilder
    private func slideView(_ slide: BannerSlide) -> some View {
        ZStack(alignment: .topLeading) {
            switch slide {
            case let .customPhoto(data):
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: cardHeight)
                        .clipped()
                }

            case let .library(_, url):
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: cardHeight)
                                .clipped()
                                .transition(.opacity)
                        default:
                            Color.gray.opacity(0.15)
                                .frame(maxWidth: .infinity, maxHeight: cardHeight)
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(maxWidth: .infinity, maxHeight: cardHeight)
                }

            case .liveTV:
                LinearGradient(
                    colors: [.indigo.opacity(0.5), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: cardHeight)

            case .gradient:
                LinearGradient(
                    colors: [.blue.opacity(0.4), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: cardHeight)
            }

            // Gradient overlay for text readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.2),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: cardHeight)

            // Banner text and library subtitle
            VStack(alignment: .leading, spacing: 4) {
                if !bannerText.isEmpty {
                    Text(bannerText)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                if case let .library(library, _) = slide {
                    Text(library.title)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                } else if case .liveTV = slide {
                    Label("Live TV", systemImage: "tv")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(16)
        }
    }
}

private enum BannerSlide {
    case customPhoto(Data)
    case library(Library, URL?)
    case liveTV
    case gradient
}
