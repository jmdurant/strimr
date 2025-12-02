import Observation
import SwiftUI

struct SeasonEpisodesSection: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        Section {
            episodesContent
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        } header: {
            seasonSelectorHeader
        }
        .textCase(nil)
    }

    private var seasonSelectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episodes")
                .font(.title2)
                .fontWeight(.bold)
            seasonSelector
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        } else if (viewModel.isLoadingSeasons || viewModel.isLoading) && viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading seasons…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("No seasons available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            seasonPickerControl
        }
    }

    @ViewBuilder
    private var seasonPickerControl: some View {
#if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.seasons, id: \.id) { season in
                    let isSelected = season.id == (viewModel.selectedSeasonId ?? viewModel.seasons.first?.id)
                    Button {
                        Task {
                            await viewModel.selectSeason(id: season.id)
                        }
                    } label: {
                        Text(season.title)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minWidth: 140)
                            .background(isSelected ? Color.brandSecondary : Color.white.opacity(0.18))
                            .foregroundStyle(isSelected ? .brandSecondaryForeground : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(true)
                }
            }
            .padding(.vertical, 4)
        }
#else
        Picker("Season", selection: Binding(
            get: { viewModel.selectedSeasonId ?? viewModel.seasons.first?.id ?? "" },
            set: { seasonId in
                guard !seasonId.isEmpty else { return }
                Task {
                    await viewModel.selectSeason(id: seasonId)
                }
            }
        )) {
            ForEach(viewModel.seasons, id: \.id) { season in
                Text(season.title)
                    .tag(season.id)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260, alignment: .leading)
#endif
    }

    @ViewBuilder
    private var episodesContent: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        } else if (viewModel.isLoadingSeasons || viewModel.isLoading) && viewModel.seasons.isEmpty {
            ProgressView("Loading seasons…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.seasons.isEmpty {
            Text("No seasons available yet.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let error = viewModel.episodesErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoadingEpisodes && viewModel.episodes.isEmpty {
                    ProgressView("Loading episodes…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if viewModel.episodes.isEmpty {
                    Text("No episodes for this season.")
                        .foregroundStyle(.secondary)
                } else {
                    episodeList
                }
            }
        }
    }

    @ViewBuilder
    private var episodeList: some View {
#if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(viewModel.episodes) { episode in
                    EpisodeCardView(
                        episode: episode,
                        imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                        runtime: viewModel.runtimeText(for: episode),
                        progress: viewModel.progressFraction(for: episode),
                        cardWidth: 520
                    )
                }
            }
            .padding(.horizontal, 4)
        }
#elseif os(macOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 420, maximum: 520), spacing: 16)], spacing: 16) {
            ForEach(viewModel.episodes) { episode in
                EpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                    runtime: viewModel.runtimeText(for: episode),
                    progress: viewModel.progressFraction(for: episode),
                    cardWidth: nil
                )
            }
        }
#else
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                    runtime: viewModel.runtimeText(for: episode),
                    progress: viewModel.progressFraction(for: episode),
                    cardWidth: nil
                )
                if index < viewModel.episodes.count - 1 {
                    Divider()
                        .background(.brandSecondary)
                        .padding(.vertical, 4)
                }
            }
        }
#endif
    }
}
