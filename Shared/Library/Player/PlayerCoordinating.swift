import Foundation

struct RendererDevice: Identifiable {
    let id: String
    let name: String
    let type: String
}

@MainActor
protocol PlayerCoordinating: AnyObject {
    func play(_ url: URL)
    func togglePlayback()
    func pause()
    func resume()
    func seek(to time: Double)
    func seek(by delta: Double)
    func setPlaybackRate(_ rate: Float)
    func selectAudioTrack(id: Int?)
    func selectSubtitleTrack(id: Int?)
    func trackList() -> [PlayerTrack]
    func destruct()
    func startPictureInPicture()
    func stopPictureInPicture()
    var isPictureInPictureSupported: Bool { get }
    var isPictureInPictureActive: Bool { get }
    var spectrumData: SpectrumData? { get }
    func enableAudioVisualization()

    // Renderer / Chromecast
    var discoveredRenderers: [RendererDevice] { get }
    var activeRendererName: String? { get }
    func startRendererDiscovery()
    func stopRendererDiscovery()
    func selectRenderer(id: String?)

    /// Whether the player is currently paused
    var isPaused: Bool { get }

    /// Keep the underlying player alive when the view is dismissed
    func retainForBackground()
    /// Release the strong reference when re-attaching to a view or destructing
    func releaseFromBackground()
}

extension PlayerCoordinating {
    func startPictureInPicture() {}
    func stopPictureInPicture() {}
    var isPictureInPictureSupported: Bool { false }
    var isPictureInPictureActive: Bool { false }
    var spectrumData: SpectrumData? { nil }
    func enableAudioVisualization() {}

    var discoveredRenderers: [RendererDevice] { [] }
    var activeRendererName: String? { nil }
    func startRendererDiscovery() {}
    func stopRendererDiscovery() {}
    func selectRenderer(id: String?) {}
    var isPaused: Bool { false }
    func retainForBackground() {}
    func releaseFromBackground() {}
}
