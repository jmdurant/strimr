import SwiftUI

enum VisualizationPreset: Int, CaseIterable {
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

    var next: VisualizationPreset {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? all.startIndex
        let next = all.index(after: idx)
        return next < all.endIndex ? all[next] : all[all.startIndex]
    }

    var previous: VisualizationPreset {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? all.startIndex
        if idx == all.startIndex {
            return all[all.index(before: all.endIndex)]
        }
        return all[all.index(before: idx)]
    }
}
