import SwiftUI

// MARK: - Preset Enum

enum WatchVisualizationPreset: Int, CaseIterable {
    case classicBars = 0
    case frequencyRings = 1
    case lfoMorph = 2
    case oscillatorGrid = 3
    case spiralGalaxy = 4
    case plasmaField = 5
    case particleStorm = 6
    case waveformTunnel = 7
    case kaleidoscope = 8
    case nebulaGalaxy = 9
    case starfieldFlight = 10

    var name: String {
        switch self {
        case .classicBars:      return "Classic Bars"
        case .frequencyRings:   return "Frequency Rings"
        case .lfoMorph:         return "LFO Morph"
        case .oscillatorGrid:   return "Oscillator Grid"
        case .spiralGalaxy:     return "Spiral Galaxy"
        case .plasmaField:      return "Plasma Field"
        case .particleStorm:    return "Particle Storm"
        case .waveformTunnel:   return "Waveform Tunnel"
        case .kaleidoscope:     return "Kaleidoscope"
        case .nebulaGalaxy:     return "Nebula Galaxy"
        case .starfieldFlight:  return "Starfield Flight"
        }
    }

    var next: WatchVisualizationPreset {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? all.startIndex
        let next = all.index(after: idx)
        return next < all.endIndex ? all[next] : all[all.startIndex]
    }

    var previous: WatchVisualizationPreset {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? all.startIndex
        if idx == all.startIndex {
            return all[all.index(before: all.endIndex)]
        }
        return all[all.index(before: idx)]
    }
}

// MARK: - Fullscreen Visualization View

struct WatchVisualizationView: View {
    let spectrumData: SpectrumData
    @Environment(\.dismiss) private var dismiss

    @State private var preset: WatchVisualizationPreset = .classicBars
    @State private var fadeOpacity: Double = 1.0
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var crownValue: Double = 0
    @State private var lastCrownPreset: Int = 0
    @State private var peakHeights: [CGFloat] = Array(repeating: 0, count: 32)
    @State private var peakTimestamps: [TimeInterval] = Array(repeating: 0, count: 32)
    @State private var smoothedHeights: [CGFloat] = Array(repeating: 0, count: 32)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            WatchVisualizationCanvas(
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
            through: Double(WatchVisualizationPreset.allCases.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newVal in
            let idx = Int(newVal.rounded())
            guard idx != lastCrownPreset,
                  let p = WatchVisualizationPreset(rawValue: idx) else { return }
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

    private func changePreset(to newPreset: WatchVisualizationPreset) {
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

// MARK: - Canvas

private struct WatchVisualizationCanvas: View {
    let spectrumData: SpectrumData
    let preset: WatchVisualizationPreset
    let time: Double
    @Binding var peakHeights: [CGFloat]
    @Binding var peakTimestamps: [TimeInterval]
    @Binding var smoothedHeights: [CGFloat]

    var body: some View {
        Canvas { context, size in
            let bgGradient = Gradient(colors: [
                Color(red: 0.03, green: 0.03, blue: 0.06),
                Color.black,
            ])
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(bgGradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height))
            )

            let bins = spectrumData.bins
            let cx = size.width / 2
            let cy = size.height / 2

            switch preset {
            case .classicBars:
                drawClassicBars(context: &context, size: size, bins: bins)
            case .frequencyRings:
                drawFrequencyRings(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .lfoMorph:
                drawLFOMorph(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .oscillatorGrid:
                drawOscillatorGrid(context: &context, size: size, bins: bins, time: time)
            case .spiralGalaxy:
                drawSpiralGalaxy(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .plasmaField:
                drawPlasmaField(context: &context, size: size, bins: bins, time: time)
            case .particleStorm:
                drawParticleStorm(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .waveformTunnel:
                drawWaveformTunnel(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .kaleidoscope:
                drawKaleidoscope(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .nebulaGalaxy:
                drawNebulaGalaxy(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            case .starfieldFlight:
                drawStarfieldFlight(context: &context, cx: cx, cy: cy, size: size, bins: bins, time: time)
            }
        }
    }
}

// MARK: - Classic Bars

extension WatchVisualizationCanvas {
    private func drawClassicBars(
        context: inout GraphicsContext, size: CGSize, bins: [Float]
    ) {
        let columns = bins.count
        let spacing: CGFloat = 1
        let barWidth = (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let currentTime = Date().timeIntervalSince1970

        // Glow layer behind all bars
        var glowCtx = context
        glowCtx.addFilter(.blur(radius: 3))

        for col in 0..<columns {
            let rawHeight = CGFloat(bins[col]) * size.height * 0.95

            let current = col < smoothedHeights.count ? smoothedHeights[col] : 0
            let smoothed: CGFloat
            if rawHeight > current {
                smoothed = current + (rawHeight - current) * 0.5
            } else {
                smoothed = current + (rawHeight - current) * 0.25
            }
            if col < smoothedHeights.count {
                DispatchQueue.main.async {
                    smoothedHeights[col] = smoothed
                }
            }

            let barHeight = smoothed
            let x = CGFloat(col) * (barWidth + spacing)
            let y = size.height - barHeight
            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.0, green: 1.0, blue: 0.0), location: 0.0),
                .init(color: Color(red: 0.5, green: 1.0, blue: 0.0), location: 0.30),
                .init(color: Color(red: 1.0, green: 1.0, blue: 0.0), location: 0.50),
                .init(color: Color(red: 1.0, green: 0.65, blue: 0.0), location: 0.70),
                .init(color: Color(red: 1.0, green: 0.0, blue: 0.0), location: 0.85),
                .init(color: Color(red: 1.0, green: 0.0, blue: 0.0), location: 1.0),
            ])

            let shading = GraphicsContext.Shading.linearGradient(
                gradient,
                startPoint: CGPoint(x: x, y: size.height),
                endPoint: CGPoint(x: x, y: 0)
            )

            // Glow
            glowCtx.fill(Path(barRect), with: shading)
            // Sharp
            context.fill(Path(barRect), with: shading)

            // Peak hold dot
            if col < peakHeights.count {
                if barHeight > peakHeights[col] {
                    DispatchQueue.main.async {
                        peakHeights[col] = barHeight
                        peakTimestamps[col] = currentTime
                    }
                } else if currentTime - peakTimestamps[col] > 0.8 {
                    DispatchQueue.main.async {
                        peakHeights[col] = max(peakHeights[col] - 1.5, 0)
                    }
                }

                let peakY = size.height - peakHeights[col]
                if peakHeights[col] > 2 {
                    let peakRect = CGRect(x: x, y: peakY - 1.5, width: barWidth, height: 1.5)
                    context.fill(Path(peakRect), with: .color(Color(white: 0.85)))
                }
            }
        }
    }
}

// MARK: - Frequency Rings

extension WatchVisualizationCanvas {
    private func drawFrequencyRings(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let maxRadius = min(size.width, size.height) * 0.45

        for (index, level) in bins.prefix(20).enumerated() {
            let t = CGFloat(index) / 20.0
            let baseRadius = t * maxRadius * 0.6 + 8
            let pulse = CGFloat(level) * maxRadius * 0.25
            let radius = baseRadius + pulse
            let thickness: CGFloat = 1.5 + CGFloat(level) * 3

            let hue = Double(index) / 20.0
            let brightness = Double(level) * 0.8 + 0.2
            let color = Color(hue: hue, saturation: 1.0, brightness: brightness)

            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            var path = Path()
            path.addEllipse(in: rect)

            // Glow for brighter rings
            if level > 0.3 {
                var glowCtx = context
                glowCtx.addFilter(.blur(radius: 4))
                glowCtx.stroke(path, with: .color(color.opacity(0.3)), lineWidth: thickness + 2)
            }

            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: thickness)
        }
    }
}

// MARK: - LFO Morph

extension WatchVisualizationCanvas {
    private func drawLFOMorph(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let avgLevel = bins.reduce(0, +) / Float(max(bins.count, 1))
        let scale = min(size.width, size.height) * 0.35

        let lfo1 = sin(time * 0.5) * 0.5 + 0.5
        let lfo2 = sin(time * 0.7) * 0.5 + 0.5
        let lfo3 = sin(time * 1.1) * 0.5 + 0.5

        for layer in 0..<5 {
            let layerDepth = Double(layer) / 5.0
            let radius = scale * (0.3 + layerDepth * 0.7)

            var path = Path()
            let segments = 80

            for i in 0...segments {
                let angle = (Double(i) / Double(segments)) * .pi * 2
                let spectrumIndex = (i * bins.count) / segments
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : 0

                let morph1 = sin(angle * 3 + time * lfo1) * lfo2 * scale * 0.15
                let morph2 = cos(angle * 5 + time * lfo3) * lfo1 * scale * 0.1
                let audioMod = Double(level) * scale * 0.25

                let r = radius + morph1 + morph2 + audioMod
                let x = cx + cos(angle) * r
                let y = cy + sin(angle) * r

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

            let hue = (layerDepth + time * 0.1 + Double(avgLevel) * 0.5)
                .truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 0.9, brightness: 0.8)

            // Glow stroke
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 4))
            glowCtx.stroke(path, with: .color(color.opacity(0.3)), lineWidth: 4)

            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 2)
        }
    }
}

// MARK: - Oscillator Grid

extension WatchVisualizationCanvas {
    private func drawOscillatorGrid(
        context: inout GraphicsContext,
        size: CGSize, bins: [Float], time: Double
    ) {
        let rows = 6
        let cols = 8
        let cellWidth = size.width / CGFloat(cols)
        let cellHeight = size.height / CGFloat(rows)

        var glowCtx = context
        glowCtx.addFilter(.blur(radius: 5))

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * cellWidth + cellWidth / 2
                let y = CGFloat(row) * cellHeight + cellHeight / 2

                let spectrumIndex = (col * bins.count) / cols
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : Float(0)

                let phase = time + Double(row) * 0.5 + Double(col) * 0.3
                let wave = sin(phase * 3) * CGFloat(level) * 0.5 + 0.5

                let hue = (Double(col) / Double(cols) + time * 0.05)
                    .truncatingRemainder(dividingBy: 1.0)
                let color = Color(hue: hue, saturation: 0.9, brightness: Double(wave))

                let radius = min(cellWidth, cellHeight) * 0.35 * wave
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

                // Glow halo
                if wave > 0.4 {
                    let glowRadius = radius * 1.5
                    let glowRect = CGRect(x: x - glowRadius, y: y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                    glowCtx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.3)))
                }

                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.8)))
            }
        }
    }
}

// MARK: - Spiral Galaxy

extension WatchVisualizationCanvas {
    private func drawSpiralGalaxy(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let avgLevel = CGFloat(bins.reduce(0, +) / Float(max(bins.count, 1)))
        let intensity = avgLevel * 2 + 0.5

        // Spiral arms
        for arm in 0..<3 {
            for i in 0..<60 {
                let t = Double(i) / 60.0
                let angle = t * .pi * 6 + time * 0.5 + Double(arm) * .pi * 2 / 3
                let radius = t * min(size.width, size.height) * 0.4 * Double(intensity)
                let x = cx + cos(angle) * radius
                let y = cy + sin(angle) * radius

                let hue = (t + time * 0.1 + Double(arm) * 0.33).truncatingRemainder(dividingBy: 1.0)
                let brightness = (1.0 - t) * Double(avgLevel) * 1.2 + 0.3
                let color = Color(hue: hue, saturation: 0.9, brightness: brightness)

                let particleSize = (1.0 - t) * 4 + 1.5
                let rect = CGRect(x: x - particleSize / 2, y: y - particleSize / 2, width: particleSize, height: particleSize)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }

        // Energy rings
        for (index, level) in bins.prefix(10).enumerated() {
            let angle = Double(index) / 10.0 * .pi * 2 + time * 0.4
            let baseDist: CGFloat = 40
            let dist = baseDist + CGFloat(level) * 60
            let x = cx + cos(angle) * dist
            let y = cy + sin(angle) * dist

            for ring in 0..<2 {
                let radius = CGFloat(level) * 15 + CGFloat(ring) * 6 + 4
                let opacity = 0.6 - Double(ring) * 0.2
                let hue = Double(index) / 10.0
                let color = Color(hue: hue, saturation: 1.0, brightness: Double(level) * 0.7 + 0.4)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
            }
        }

        // Waveforms
        for layer in 0..<3 {
            var path = Path()
            let yOffset = size.height * (0.3 + Double(layer) * 0.2)
            let amplitude: CGFloat = 30

            path.move(to: CGPoint(x: 0, y: yOffset))
            for xPos in stride(from: CGFloat(0), through: size.width, by: 3) {
                let progress = xPos / size.width
                let spectrumIndex = Int(progress * Double(bins.count))
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : 0
                let wavePhase = time * (1.5 + Double(layer) * 0.5)
                let y = yOffset + amplitude * CGFloat(level) * sin(Double(xPos) / 15 + wavePhase)
                path.addLine(to: CGPoint(x: xPos, y: y))
            }

            let hue = (time * 0.1 + Double(layer) * 0.33).truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 0.9, brightness: 0.8)
            context.stroke(path, with: .color(color.opacity(0.5 - Double(layer) * 0.1)), lineWidth: 2 - CGFloat(layer) * 0.5)
        }

        // Floating particles
        for i in 0..<40 {
            let seed = Double(i) * 17.3
            let angle = time * 0.3 + seed
            let radius = sin(time * 0.5 + seed) * 80 + 50
            let x = cx + cos(angle) * radius
            let y = cy + sin(angle) * radius

            let dotSize = (sin(time * 2 + seed) + 1) * 1.2 + 0.5
            let hue = (seed / 50.0 + time * 0.05).truncatingRemainder(dividingBy: 1.0)
            let brightness = Double(avgLevel) * 0.8 + 0.3
            let color = Color(hue: hue, saturation: 0.8, brightness: brightness)
            let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.6)))
        }
    }
}

// MARK: - Plasma Field

extension WatchVisualizationCanvas {
    private func drawPlasmaField(
        context: inout GraphicsContext,
        size: CGSize, bins: [Float], time: Double
    ) {
        let avgLevel = Double(bins.reduce(0, +) / Float(max(bins.count, 1)))
        let speed = time * (0.5 + avgLevel)
        let blockSize: CGFloat = 6

        for y in stride(from: CGFloat(0), to: size.height, by: blockSize) {
            for x in stride(from: CGFloat(0), to: size.width, by: blockSize) {
                let nx = Double(x / size.width)
                let ny = Double(y / size.height)

                let plasma = sin(nx * 10 + speed)
                    + sin(ny * 10 + speed)
                    + sin((nx + ny) * 10 + speed)
                    + sin(sqrt(nx * nx + ny * ny) * 10 + speed)

                let normalized = (plasma + 4) / 8
                let brightness = 0.5 + avgLevel * 0.5

                let color = Color(hue: normalized, saturation: 1.0, brightness: brightness)
                let rect = CGRect(x: x, y: y, width: blockSize, height: blockSize)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - Particle Storm

extension WatchVisualizationCanvas {
    private func drawParticleStorm(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        var glowCtx = context
        glowCtx.addFilter(.blur(radius: 3))

        for i in 0..<100 {
            let seed = Double(i) * 23.7
            let spectrumIndex = i % bins.count
            let level = bins[spectrumIndex]

            let angle = time * 2 + seed
            let speed = 1.0 + Double(level) * 3
            let distance = (time * speed + seed).truncatingRemainder(dividingBy: 200)

            let x = cx + cos(angle) * distance
            let y = cy + sin(angle) * distance

            let particleSize = CGFloat(level) * 5 + 1.5
            let hue = (seed / 100 + time * 0.2).truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 1.0, brightness: Double(level) * 0.7 + 0.3)

            let rect = CGRect(x: x - particleSize / 2, y: y - particleSize / 2, width: particleSize, height: particleSize)

            // Glow on brighter particles
            if level > 0.4 {
                let glowSize = particleSize * 2
                let glowRect = CGRect(x: x - glowSize / 2, y: y - glowSize / 2, width: glowSize, height: glowSize)
                glowCtx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.3)))
            }

            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.7)))
        }
    }
}

// MARK: - Waveform Tunnel

extension WatchVisualizationCanvas {
    private func drawWaveformTunnel(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        for ring in 0..<20 {
            let depth = CGFloat(ring) / 20.0
            let radius = (1.0 - depth) * min(size.width, size.height) * 0.4 + 20

            var path = Path()
            let segments = 40

            for i in 0...segments {
                let angle = (Double(i) / Double(segments)) * .pi * 2
                let spectrumIndex = (i * bins.count) / segments
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : 0

                let wave = CGFloat(level) * 20 * (1.0 - depth)
                let r = radius + wave

                let x = cx + cos(angle + time + Double(ring) * 0.2) * r
                let y = cy + sin(angle + time + Double(ring) * 0.2) * r

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()

            let hue = (Double(ring) / 20.0 + time * 0.1).truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 0.9, brightness: 1.0 - Double(depth) * 0.5)

            // Glow on front rings
            if depth < 0.3 {
                var glowCtx = context
                glowCtx.addFilter(.blur(radius: 3))
                glowCtx.stroke(path, with: .color(color.opacity(0.2)), lineWidth: 3)
            }

            context.stroke(path, with: .color(color.opacity(0.5 - Double(depth) * 0.3)), lineWidth: 1.5)
        }
    }
}

// MARK: - Kaleidoscope

extension WatchVisualizationCanvas {
    private func drawKaleidoscope(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let numSegments = 8
        let angleStep = .pi * 2 / Double(numSegments)

        for segment in 0..<numSegments {
            let baseAngle = Double(segment) * angleStep

            var segmentContext = context
            segmentContext.translateBy(x: cx, y: cy)
            segmentContext.rotate(by: .radians(baseAngle))
            segmentContext.translateBy(x: -cx, y: -cy)

            for i in 0..<30 {
                let t = Double(i) / 30.0
                let spectrumIndex = (i * bins.count) / 30
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : 0

                let r = t * min(size.width, size.height) * 0.35
                let angle = t * .pi * 4 + time
                let x = cx + cos(angle) * r
                let y = cy + sin(angle) * r * CGFloat(level + 0.3)

                let hue = (t + time * 0.1).truncatingRemainder(dividingBy: 1.0)
                let color = Color(hue: hue, saturation: 1.0, brightness: Double(level) * 0.7 + 0.3)

                let dotSize = CGFloat(level) * 8 + 2
                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                segmentContext.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.6)))
            }
        }
    }
}

// MARK: - Nebula Galaxy

extension WatchVisualizationCanvas {
    private func drawNebulaGalaxy(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let avgLevel = Double(bins.reduce(0, +) / Float(max(bins.count, 1)))

        // Background star field
        for i in 0..<150 {
            let seed = Double(i) * 57.3
            let x = (sin(seed) * 0.5 + 0.5) * size.width
            let y = (cos(seed * 1.3) * 0.5 + 0.5) * size.height

            let twinkle = (sin(time * 2 + seed) + 1) * 0.5
            let brightness = 0.3 + twinkle * 0.4
            let starSize = (sin(seed * 2.7) + 1) * 0.3 + 0.3

            let rect = CGRect(x: x - starSize, y: y - starSize, width: starSize * 2, height: starSize * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(brightness)))
        }

        // Nebula clouds with blur
        var cloudCtx = context
        cloudCtx.addFilter(.blur(radius: 8))

        for layer in 0..<2 {
            let layerOffset = Double(layer) * 0.3
            for i in 0..<40 {
                let angle = Double(i) / 40.0 * .pi * 2 + time * 0.1 * Double(layer + 1)
                let distance = 30 + Double(i) * 2.5 + sin(time * 0.5 + Double(i) * 0.3) * 15
                let x = cx + cos(angle) * distance
                let y = cy + sin(angle) * distance * 0.7

                let spectrumIndex = i % bins.count
                let level = bins[spectrumIndex]
                let cloudSize: CGFloat = 8 + CGFloat(level) * 15 + CGFloat(layer) * 5

                let hue = 0.7 + layerOffset * 0.15 + sin(time * 0.2 + Double(i) * 0.1) * 0.1
                let saturation = 0.7 + Double(level) * 0.3
                let brightness = 0.3 + Double(level) * 0.5 + avgLevel * 0.3

                let color = Color(hue: hue, saturation: saturation, brightness: brightness)
                let rect = CGRect(x: x - cloudSize / 2, y: y - cloudSize / 2, width: cloudSize, height: cloudSize)
                cloudCtx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.4)))
            }
        }

        // Galaxy core with glow
        let coreSize: CGFloat = 20 + CGFloat(avgLevel) * 15
        var coreGlowCtx = context
        coreGlowCtx.addFilter(.blur(radius: 10))

        for i in 0..<4 {
            let scale = CGFloat(4 - i) / 4.0
            let glowSize = coreSize * scale * 1.5
            let brightness = 0.2 + Double(scale) * 0.6 + avgLevel * 0.2

            let color = Color(hue: 0.05, saturation: 0.9, brightness: brightness)
            let rect = CGRect(x: cx - glowSize / 2, y: cy - glowSize / 2, width: glowSize, height: glowSize)
            coreGlowCtx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.5)))
        }

        // Bright center
        let centerRect = CGRect(x: cx - coreSize / 4, y: cy - coreSize / 4, width: coreSize / 2, height: coreSize / 2)
        context.fill(Path(ellipseIn: centerRect), with: .color(Color(hue: 0.1, saturation: 0.7, brightness: 1.0).opacity(0.9)))

        // Spiral arms with stars
        let rotation = time * 0.15
        for arm in 0..<3 {
            let armAngleOffset = Double(arm) * (.pi * 2 / 3.0)
            for i in 0..<60 {
                let t = Double(i) / 60.0
                let spiralAngle = t * .pi * 4 + rotation + armAngleOffset
                let spiralDistance = t * min(size.width, size.height) * 0.42
                let noise = sin(Double(i) * 13.7 + Double(arm) * 7.3) * 4

                let spectrumIndex = (i * bins.count) / 60
                let level = spectrumIndex < bins.count ? bins[spectrumIndex] : 0

                let x = cx + cos(spiralAngle) * (spiralDistance + noise)
                let y = cy + sin(spiralAngle) * (spiralDistance + noise) * 0.7

                let starSize = (1.0 - t * 0.5) * 2 + CGFloat(level) * 2
                let brightness = (1.0 - t * 0.3) + Double(level) * 0.5
                let color = Color(hue: 0.55 + t * 0.1, saturation: 0.4, brightness: brightness)

                let rect = CGRect(x: x - starSize / 2, y: y - starSize / 2, width: starSize, height: starSize)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.8)))

                // Occasional bright star with glow
                if i % 12 == 0 {
                    var glowCtx = context
                    glowCtx.addFilter(.blur(radius: 2))
                    let glowRect = CGRect(x: x - starSize, y: y - starSize, width: starSize * 2, height: starSize * 2)
                    glowCtx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.4)))
                }
            }
        }
    }
}

// MARK: - Starfield Flight

extension WatchVisualizationCanvas {
    private func drawStarfieldFlight(
        context: inout GraphicsContext,
        cx: CGFloat, cy: CGFloat,
        size: CGSize, bins: [Float], time: Double
    ) {
        let avgLevel = Double(bins.reduce(0, +) / Float(max(bins.count, 1)))

        // Frequency-differential rotation
        let lowEnd = bins.count / 3
        let highStart = (bins.count * 2) / 3
        let lowAvg = Double(bins.prefix(lowEnd).reduce(0, +)) / Double(max(lowEnd, 1))
        let highAvg = Double(bins.suffix(bins.count - highStart).reduce(0, +)) / Double(max(bins.count - highStart, 1))
        let rotationAngle = (lowAvg - highAvg) * 1.5

        let baseSpeed = 3.0 + avgLevel * 6.0

        // Foreground stars
        for i in 0..<500 {
            let seed = Double(i) * 37.3

            let angle = seed * 2.5
            let initRadius = (sin(seed * 3.7) + 1) * 200 + 20
            let initX = cos(angle) * initRadius
            let initY = sin(angle) * initRadius

            let initZ = (seed * 80).truncatingRemainder(dividingBy: 1500) + 20
            let zProgress = (time * baseSpeed * 150).truncatingRemainder(dividingBy: 1500)
            let z = ((initZ - zProgress + 1500).truncatingRemainder(dividingBy: 1500)) + 5

            guard z > 5 else { continue }

            let rotatedX = initX * cos(rotationAngle) - initY * sin(rotationAngle)
            let rotatedY = initX * sin(rotationAngle) + initY * cos(rotationAngle)

            let perspective = 500.0 / z
            let screenX = cx + rotatedX * perspective
            let screenY = cy + rotatedY * perspective

            guard screenX > -30 && screenX < size.width + 30 &&
                  screenY > -30 && screenY < size.height + 30 else { continue }

            let starSize = CGFloat(perspective * 2)
            let brightness = min(1.0, perspective * 0.8)

            // Motion trail
            let directionX = screenX - cx
            let directionY = screenY - cy
            let distance = sqrt(directionX * directionX + directionY * directionY)

            let spectrumIndex = i % bins.count
            let level = bins[spectrumIndex]

            let hue = 0.55 + Double(level) * 0.35
            let saturation = 0.15 + Double(level) * 0.6
            let starColor = Color(hue: hue, saturation: saturation, brightness: brightness)

            if distance > 1 {
                let trailLength = starSize * 3 * CGFloat(baseSpeed) / 5
                let trailEndX = screenX - (directionX / distance) * trailLength
                let trailEndY = screenY - (directionY / distance) * trailLength

                var trailPath = Path()
                trailPath.move(to: CGPoint(x: trailEndX, y: trailEndY))
                trailPath.addLine(to: CGPoint(x: screenX, y: screenY))

                let trailWidth = max(1, starSize * 0.6)
                context.stroke(trailPath, with: .color(starColor.opacity(0.6)), lineWidth: trailWidth)
            }

            // Star point
            let rect = CGRect(x: screenX - starSize / 2, y: screenY - starSize / 2, width: starSize, height: starSize)
            context.fill(Path(ellipseIn: rect), with: .color(starColor.opacity(0.9)))

            // Glow for close stars
            if perspective > 1.5 {
                var glowCtx = context
                glowCtx.addFilter(.blur(radius: starSize * 0.5))
                let glowSize = starSize * 2
                let glowRect = CGRect(x: screenX - glowSize / 2, y: screenY - glowSize / 2, width: glowSize, height: glowSize)
                glowCtx.fill(Path(ellipseIn: glowRect), with: .color(starColor.opacity(0.4)))
            }
        }

        // Background stars (distant, subtle)
        for i in 0..<200 {
            let seed = Double(i) * 91.7 + 5000

            let angle = seed * 3.1
            let initRadius = (sin(seed * 2.3) + 1) * 150 + 40
            let initX = cos(angle) * initRadius
            let initY = sin(angle) * initRadius

            let initZ = 1000 + (seed * 50).truncatingRemainder(dividingBy: 500)
            let zProgress = (time * baseSpeed * 80).truncatingRemainder(dividingBy: 500)
            let z = ((initZ - zProgress + 500).truncatingRemainder(dividingBy: 500)) + 1000

            let rotatedX = initX * cos(rotationAngle * 0.5) - initY * sin(rotationAngle * 0.5)
            let rotatedY = initX * sin(rotationAngle * 0.5) + initY * cos(rotationAngle * 0.5)

            let perspective = 500.0 / z
            let screenX = cx + rotatedX * perspective
            let screenY = cy + rotatedY * perspective

            guard screenX > 0 && screenX < size.width &&
                  screenY > 0 && screenY < size.height else { continue }

            let starSize = CGFloat(perspective * 1.5)
            let starBrightness = min(0.5, perspective * 0.4)

            let rect = CGRect(x: screenX - starSize / 2, y: screenY - starSize / 2, width: starSize, height: starSize)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(starBrightness)))
        }

        // Distant nebula clouds
        var cloudCtx = context
        cloudCtx.addFilter(.blur(radius: 15))
        cloudCtx.opacity = 0.25

        for i in 0..<4 {
            let seed = Double(i) * 127.3
            let nebulaAngle = seed + time * 0.05
            let nebulaDist = 60 + sin(time * 0.1 + seed) * 20
            let x = cx + cos(nebulaAngle + rotationAngle * 0.2) * nebulaDist
            let y = cy + sin(nebulaAngle + rotationAngle * 0.2) * nebulaDist * 0.6

            let cloudSize: CGFloat = 30 + CGFloat(i) * 8
            let hue = (seed / 500.0 + time * 0.02).truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 0.7, brightness: 0.4)

            let rect = CGRect(x: x - cloudSize / 2, y: y - cloudSize / 2, width: cloudSize, height: cloudSize)
            cloudCtx.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
