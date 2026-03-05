import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct NowPlayingLiveActivity: Widget {
    let kind = "NowPlayingLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(URL(string: "strimr://nowplaying"))
                .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    artworkImage(data: context.attributes.artworkData)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        if let subtitle = context.attributes.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: TogglePlaybackIntent()) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.durationSeconds > 0 {
                        VStack(spacing: 2) {
                            ProgressView(
                                value: context.state.positionSeconds,
                                total: context.attributes.durationSeconds
                            )
                            .tint(.white)

                            HStack {
                                Text(NowPlayingLiveActivity.formatTime(context.state.positionSeconds))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("-" + NowPlayingLiveActivity.formatTime(max(0, context.attributes.durationSeconds - context.state.positionSeconds)))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                artworkImage(data: context.attributes.artworkData)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } compactTrailing: {
                if context.attributes.durationSeconds > 0 {
                    ProgressView(
                        value: context.state.positionSeconds,
                        total: context.attributes.durationSeconds
                    )
                    .progressViewStyle(.circular)
                    .tint(.blue)
                    .frame(width: 16, height: 16)
                } else {
                    Image(systemName: context.state.isPaused ? "pause.fill" : "play.fill")
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: "play.tv.fill")
                    .foregroundStyle(.blue)
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<NowPlayingAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                artworkImage(data: context.attributes.artworkData)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = context.attributes.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            if context.attributes.durationSeconds > 0 {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let fraction = context.state.positionSeconds / context.attributes.durationSeconds
                        let clampedFraction = min(max(fraction, 0), 1)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.2))
                                .frame(height: 4)

                            Capsule()
                                .fill(.white)
                                .frame(width: geo.size.width * clampedFraction, height: 4)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text(Self.formatTime(context.state.positionSeconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .contentTransition(.identity)
                        Spacer()
                        Text("-" + Self.formatTime(max(0, context.attributes.durationSeconds - context.state.positionSeconds)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .contentTransition(.identity)
                    }
                }
                .animation(.none, value: context.state.positionSeconds)
            }

            HStack(spacing: 32) {
                Button(intent: SkipBackwardIntent()) {
                    Image(systemName: "gobackward.10")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(intent: TogglePlaybackIntent()) {
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(intent: SkipForwardIntent()) {
                    Image(systemName: "goforward.10")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    static func formatTime(_ totalSeconds: Double) -> String {
        let total = Int(max(0, totalSeconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func artworkImage(data: Data?) -> some View {
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "play.tv.fill")
                .foregroundStyle(.blue)
        }
    }
}
