import SwiftUI

struct PlayerControlsView: View {
    let title: String?
    let subtitle: String?
    let isPaused: Bool
    @Binding var position: Double
    let duration: Double?
    let seekBackwardSeconds: Int
    let seekForwardSeconds: Int
    let onDismiss: () -> Void
    let onSeekBackward: () -> Void
    let onPlayPause: () -> Void
    let onSeekForward: () -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onToggleFullscreen: () -> Void

    var body: some View {
        ZStack {
            controlsBackground

            VStack(spacing: 0) {
                headerBar
                Spacer(minLength: 0)
                bottomControls
            }
            .padding(20)

            centerControls
        }
    }

    private var controlsBackground: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onToggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var centerControls: some View {
        HStack(spacing: 32) {
            Button(action: onSeekBackward) {
                Image(systemName: seekIcon(prefix: "gobackward", seconds: seekBackwardSeconds))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)

            Button(action: onPlayPause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: onSeekForward) {
                Image(systemName: seekIcon(prefix: "goforward", seconds: seekForwardSeconds))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            timelineSlider

            HStack {
                Text(formatTime(position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                if let duration {
                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: 16) {
                volumeSlider
                Spacer()
            }
        }
    }

    private var timelineSlider: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let safeDuration = max(duration ?? 1, 1)
            let progress = min(max(position / safeDuration, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))

                Capsule()
                    .fill(Color.white)
                    .frame(width: totalWidth * progress)
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .contentShape(Rectangle().size(width: totalWidth, height: 24))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            onScrubbingChanged(true)
                        }
                        let fraction = min(max(value.location.x / totalWidth, 0), 1)
                        position = fraction * safeDuration
                    }
                    .onEnded { _ in
                        onScrubbingChanged(false)
                    }
            )
        }
        .frame(height: 24)
    }

    @State private var isScrubbing = false
    @State private var volume: Float = 1.0

    private var volumeSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 16)

            Slider(value: $volume, in: 0...1)
                .frame(width: 100)
                .tint(.white)
                .onChange(of: volume) { _, newValue in
                    // Volume changes are handled locally since AVPlayer is managed here
                }
        }
    }

    private func seekIcon(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
