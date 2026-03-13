import SwiftUI

struct WatchVisualizationView: View {
    let spectrumData: SpectrumData
    @Environment(\.dismiss) private var dismiss

    @State private var preset: VisualizationPreset = .classicBars
    @State private var fadeOpacity: Double = 1.0
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var crownValue: Double = 0
    @State private var lastCrownPreset: Int = 0
    @State private var peakHeights: [CGFloat] = Array(repeating: 0, count: 32)
    @State private var peakTimestamps: [TimeInterval] = Array(repeating: 0, count: 32)
    @State private var smoothedHeights: [CGFloat] = Array(repeating: 0, count: 32)

    var body: some View {
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
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden)
        .persistentSystemOverlays(.hidden)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Double(VisualizationPreset.allCases.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newVal in
            let idx = Int(newVal.rounded())
            guard idx != lastCrownPreset,
                  let p = VisualizationPreset(rawValue: idx) else { return }
            lastCrownPreset = idx
            changePreset(to: p)
        }
        .onTapGesture {
            dismiss()
        }
        .onAppear {
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
        }
        startAutoAdvance()
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
