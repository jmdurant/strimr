import ActivityKit
import Foundation
import Observation

@MainActor
final class NowPlayingActivityBridge {
    private let viewModel: PlayerViewModel
    private let context: PlexAPIContext
    private var activity: Activity<NowPlayingAttributes>?
    private var updateTimer: Timer?
    private var isStarted = false

    private let updateInterval: TimeInterval = 3.0

    init(viewModel: PlayerViewModel, context: PlexAPIContext) {
        self.viewModel = viewModel
        self.context = context
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeMediaLoad()
    }

    func stop() {
        isStarted = false
        updateTimer?.invalidate()
        updateTimer = nil

        let position = viewModel.position
        Task {
            let finalState = NowPlayingAttributes.ContentState(
                positionSeconds: position,
                isPaused: true,
                isBuffering: false,
                playbackRate: 0,
                timestamp: .now
            )
            await activity?.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            activity = nil
        }
    }

    private func observeMediaLoad() {
        withObservationTracking {
            _ = viewModel.media
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if self.viewModel.media != nil {
                    await self.createActivity()
                } else {
                    self.observeMediaLoad()
                }
            }
        }
    }

    private func createActivity() async {
        guard let media = viewModel.media else { return }

        let artworkData = await LiveActivityImageLoader.loadCompressedThumbnail(
            path: media.preferredThumbPath ?? media.thumbPath,
            context: context
        )

        let title: String
        let subtitle: String?

        switch media.type {
        case .episode:
            title = media.grandparentTitle ?? media.title
            var parts: [String] = []
            if let parentIndex = media.parentIndex, let index = media.index {
                parts.append("S\(parentIndex) E\(index)")
            }
            parts.append(media.title)
            subtitle = parts.joined(separator: " - ")
        case .track:
            title = media.title
            subtitle = media.grandparentTitle
        default:
            title = media.title
            subtitle = media.year.map(String.init)
        }

        let durationSeconds = (media.duration ?? viewModel.duration ?? 0) / 1000

        let attributes = NowPlayingAttributes(
            title: title,
            subtitle: subtitle,
            mediaType: media.type.rawValue,
            durationSeconds: durationSeconds,
            artworkData: artworkData
        )

        let initialState = NowPlayingAttributes.ContentState(
            positionSeconds: viewModel.position,
            isPaused: viewModel.isPaused,
            isBuffering: viewModel.isBuffering,
            playbackRate: viewModel.isPaused ? 0 : 1.0,
            timestamp: .now
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            startPeriodicUpdates()
        } catch {
            debugPrint("Failed to start Live Activity:", error)
        }
    }

    private func startPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendUpdate()
            }
        }
    }

    private func sendUpdate() {
        guard let activity, isStarted else { return }

        let state = NowPlayingAttributes.ContentState(
            positionSeconds: viewModel.position,
            isPaused: viewModel.isPaused,
            isBuffering: viewModel.isBuffering,
            playbackRate: viewModel.isPaused ? 0 : 1.0,
            timestamp: .now
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
