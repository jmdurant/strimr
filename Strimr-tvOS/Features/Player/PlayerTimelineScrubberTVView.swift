import SwiftUI

struct PlayerTimelineScrubberTVView: View {
    @Binding var position: Double
    var upperBound: Double
    var duration: Double?
    var onEditingChanged: (Bool) -> Void

    @State private var consecutiveMoves = 0
    @FocusState private var isFocused: Bool


    private var playbackProgress: Double {
        guard upperBound > 0 else { return 0 }
        return min(max(position / upperBound, 0), 1)
    }

    private var scrubStep: Double {
        guard let duration else { return 10 }
        return min(max(duration / 300, 5), 60)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progressWidth = width * playbackProgress
            let thumbX = min(max(progressWidth, 0), width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 8, alignment: .center)
                
                Capsule()
                    .fill(Color.white)
                    .frame(width: progressWidth)
                    .frame(height: 8, alignment: .center)

                Circle()
                    .fill(Color.white)
                    .frame(width: isFocused ? 18 : 14, height: isFocused ? 18 : 14)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
                    .offset(x: max(0, thumbX - (isFocused ? 9 : 7)))
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }

            consecutiveMoves += 1
            let multiplier = min(Double(consecutiveMoves), 5)
            let delta = scrubStep * multiplier

            switch direction {
            case .left:
                position = max(0, position - delta)
            case .right:
                position = min(upperBound, position + delta)
            default:
                break
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                consecutiveMoves = 0
            }
        }
        .accessibilityHidden(true)
    }
}
