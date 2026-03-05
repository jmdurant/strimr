import ActivityKit
import SwiftUI
import WidgetKit

struct LiveTVLiveActivity: Widget {
    let kind = "LiveTVLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveTVAttributes.self) { context in
            HStack(spacing: 12) {
                Text("LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.channelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let program = context.state.programTitle {
                        Text(program)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let endsAt = context.state.programEndsAt {
                    Text(endsAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                }
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("LIVE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.channelName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        if let program = context.state.programTitle {
                            Text(program)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if !context.attributes.channelNumber.isEmpty {
                        Text(context.attributes.channelNumber)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let endsAt = context.state.programEndsAt {
                        HStack {
                            Text("Ends in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(endsAt, style: .relative)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Text("LIVE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
            } compactTrailing: {
                Text(context.attributes.channelName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.red)
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
