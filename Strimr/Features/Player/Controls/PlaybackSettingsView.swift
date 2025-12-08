import SwiftUI

struct PlaybackSettingsView: View {
    var audioTracks: [PlaybackSettingsTrack]
    var subtitleTracks: [PlaybackSettingsTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Audio") {
                    if audioTracks.isEmpty {
                        Text("No audio tracks available")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(audioTracks) { track in
                        TrackSelectionRow(
                            title: track.title,
                            subtitle: track.subtitle,
                            isSelected: selectedAudioTrackID == track.id
                        ) {
                            onSelectAudio(track.track.id)
                        }
                    }
                }

                Section("Subtitles") {
                    TrackSelectionRow(
                        title: "Off",
                        subtitle: "Disable subtitles",
                        isSelected: selectedSubtitleTrackID == nil
                    ) {
                        onSelectSubtitle(nil)
                    }

                    ForEach(subtitleTracks) { track in
                        TrackSelectionRow(
                            title: track.title,
                            subtitle: track.subtitle,
                            isSelected: selectedSubtitleTrackID == track.id
                        ) {
                            onSelectSubtitle(track.track.id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct PlaybackSettingsTrack: Identifiable, Hashable {
    let track: MPVTrack
    let plexStream: PlexPartStream?

    var id: Int { track.id }
    private var plexCodec: String? { plexStream?.codec.uppercased() }

    var title: String {
        guard plexStream != nil else { return track.displayName }
        
        if let plexDisplayTitle = plexStream?.displayTitle, !plexDisplayTitle.isEmpty {
            switch track.type {
            case .subtitle:
                if let plexCodec {
                    return "\(plexDisplayTitle) (\(plexCodec))"
                }
                return plexDisplayTitle
            default:
                return plexDisplayTitle
            }
        }
        
        return track.displayName
    }

    var subtitle: String? {
        guard plexStream != nil else { return track.codec?.uppercased() }

        if let plexTitle = plexStream?.title, !plexTitle.isEmpty {
            return plexTitle
        }

        return plexCodec ?? track.codec?.uppercased()
    }
}

private struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
