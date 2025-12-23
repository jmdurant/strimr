import SwiftUI

struct PlayerTrackSelectionView: View {
    var titleKey: LocalizedStringKey
    var tracks: [PlaybackSettingsTrack]
    var selectedTrackID: Int?
    var showOffOption: Bool
    var onSelect: (Int?) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if showOffOption {
                    TrackSelectionRow(
                        title: String(localized: "player.settings.subtitles.off"),
                        subtitle: String(localized: "player.settings.subtitles.offDescription"),
                        isSelected: selectedTrackID == nil
                    ) {
                        onSelect(nil)
                    }
                }

                if tracks.isEmpty {
                    if !showOffOption {
                        Text("player.settings.audio.empty")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(tracks) { track in
                        TrackSelectionRow(
                            title: track.title,
                            subtitle: track.subtitle,
                            isSelected: selectedTrackID == track.id
                        ) {
                            onSelect(track.track.id)
                        }
                    }
                }
            }
            .listStyle(.grouped)
            .navigationTitle(titleKey)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
