import ActivityKit
import SwiftUI
import WidgetKit

struct NowPlayingLiveActivity: Widget {
    let kind = "NowPlayingLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            lockScreenView(context: context)
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
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.durationSeconds > 0 {
                        ProgressView(
                            value: context.state.positionSeconds,
                            total: context.attributes.durationSeconds
                        )
                        .tint(.white)
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
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<NowPlayingAttributes>) -> some View {
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

                if context.attributes.durationSeconds > 0 {
                    ProgressView(
                        value: context.state.positionSeconds,
                        total: context.attributes.durationSeconds
                    )
                    .tint(.white)
                }
            }

            Spacer()

            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .padding(16)
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
