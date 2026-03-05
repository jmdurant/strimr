import SwiftUI

struct VisualizationOverlayView: View {
    let spectrumData: SpectrumData
    let onDismiss: () -> Void

    @State private var preset: VisualizationPreset = .classicBars
    @State private var fadeOpacity: Double = 1.0
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var presetNameOpacity: Double = 0
    @State private var peakHeights: [CGFloat] = Array(repeating: 0, count: 32)
    @State private var peakTimestamps: [TimeInterval] = Array(repeating: 0, count: 32)
    @State private var smoothedHeights: [CGFloat] = Array(repeating: 0, count: 32)

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                VisualizationCanvasView(
                    spectrumData: spectrumData,
                    preset: preset,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    peakHeights: $peakHeights,
                    peakTimestamps: $peakTimestamps,
                    smoothedHeights: $smoothedHeights
                )
            }
            .opacity(fadeOpacity)

            // Preset name overlay
            if presetNameOpacity > 0 {
                Text(preset.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(presetNameOpacity)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let horizontal = value.translation.width
                    if abs(horizontal) > abs(value.translation.height) {
                        if horizontal > 0 {
                            changePreset(to: preset.previous)
                        } else {
                            changePreset(to: preset.next)
                        }
                    }
                }
        )
        .onAppear {
            showPresetName()
            startAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
        }
    }

    private func changePreset(to newPreset: VisualizationPreset) {
        autoAdvanceTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            fadeOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            preset = newPreset
            withAnimation(.easeIn(duration: 0.3)) {
                fadeOpacity = 1
            }
            showPresetName()
        }
        startAutoAdvance()
    }

    private func showPresetName() {
        withAnimation(.easeIn(duration: 0.2)) {
            presetNameOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.5)) {
                presetNameOpacity = 0
            }
        }
    }

    private func startAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            changePreset(to: preset.next)
        }
    }
}
