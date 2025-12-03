import Observation
import SwiftUI

struct MediaDetailHeaderSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    @Binding var isSummaryExpanded: Bool
    let heroHeight: CGFloat
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackground

            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: heroHeight - 40)

                headerSection
                playButton
                badgesSection

                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if let summary = viewModel.media.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isSummaryExpanded ? nil : 3)

                        Button(action: { isSummaryExpanded.toggle() }) {
                            Text(isSummaryExpanded ? "Show less" : "Read more")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .tint(.brandSecondary)
                        }
                        .tint(.accentColor)
                    }
                }

                genresSection

                if let studio = viewModel.media.studio {
                    metaRow(label: "Studio", value: studio)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("Updating details")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.media.primaryLabel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let secondary = viewModel.media.secondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = viewModel.media.tertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badgesSection: some View {
        HStack(spacing: 8) {
            if let year = viewModel.yearText {
                badge(text: year)
            }

            if let runtime = viewModel.runtimeText {
                badge(text: runtime, systemImage: "clock")
            }

            if let rating = viewModel.ratingText {
                badge(text: rating, systemImage: "star.fill")
            }

            if let contentRating = viewModel.media.contentRating {
                badge(text: contentRating)
            }
        }
    }

    private var genresSection: some View {
        Group {
            if !viewModel.media.genres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Genres")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.media.genres, id: \.self) { genre in
                                badge(text: genre)
                            }
                        }
                    }
                }
            }
        }
    }

    private var heroBackground: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if let heroURL = viewModel.heroImageURL {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                                .clipped()
                                .overlay(Color.black.opacity(0.2))
                                .mask(heroMask)
                        case .empty:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        case .failure:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        @unknown default:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        }
                    }
                } else {
                    Color.gray.opacity(0.12)
                        .frame(width: proxy.size.width, height: heroHeight)
                        .mask(heroMask)
                }
            }
            .frame(height: heroHeight)
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
        .ignoresSafeArea(edges: .horizontal)
    }

    private func badge(text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Play")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
    }
}
