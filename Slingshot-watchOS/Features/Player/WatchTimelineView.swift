import SwiftUI

struct WatchTimelineView: View {
    let position: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragPosition: Double?

    private var displayPosition: Double {
        dragPosition ?? position
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayPosition / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))

                    Capsule()
                        .fill(dragPosition != nil ? Color.accentColor : Color.white.opacity(0.8))
                        .frame(width: geo.size.width * progress)
                }
                .frame(height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            dragPosition = fraction * duration
                        }
                        .onEnded { value in
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            let seekTo = fraction * duration
                            dragPosition = nil
                            onSeek(seekTo)
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTime(displayPosition))
                Spacer()
                Text("-" + formatTime(max(duration - displayPosition, 0)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
