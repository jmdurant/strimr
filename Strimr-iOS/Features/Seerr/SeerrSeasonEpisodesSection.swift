import Observation
import SwiftUI

struct SeerrSeasonEpisodesSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

    var body: some View {
        Section {
            sectionContent
        }
        .textCase(nil)
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                seasonSelector
                episodesCountTitle
                episodesContent
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var episodesCountTitle: some View {
        Text("media.labels.countEpisode \(viewModel.episodeCountDisplay)")
            .font(.headline)
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        } else if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .center, spacing: 10) {
                seasonPickerControl
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var seasonPickerControl: some View {
        Picker("media.detail.season", selection: Binding(
            get: { viewModel.selectedSeasonNumber ?? viewModel.seasons.first?.seasonNumber ?? 0 },
            set: { seasonNumber in
                Task {
                    await viewModel.selectSeason(number: seasonNumber)
                }
            },
        )) {
            ForEach(viewModel.seasons, id: \.id) { season in
                Text(viewModel.seasonTitle(for: season))
                    .tag(season.seasonNumber ?? 0)
            }
        }
        .pickerStyle(.menu)
        .tint(.brandSecondaryForeground)
        .background(.brandSecondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var episodesContent: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        } else if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            ProgressView("media.detail.loadingSeasons")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasonsYet")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let error = viewModel.episodesErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
                    ProgressView("media.detail.loadingEpisodes")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if viewModel.episodes.isEmpty {
                    Text("media.detail.noEpisodes")
                        .foregroundStyle(.secondary)
                } else {
                    episodeList
                }
            }
        }
    }

    @ViewBuilder
    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                SeerrEpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.episodeImageURL(for: episode, width: 640),
                    label: viewModel.episodeLabel(for: episode),
                    airDateText: viewModel.episodeAirDateText(for: episode),
                )
                if index < viewModel.episodes.count - 1 {
                    Divider()
                        .background(.brandSecondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
