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
    private var waitTask: Task<Void, Never>?

    private let updateInterval: TimeInterval = 1.0

    init(viewModel: PlayerViewModel, context: PlexAPIContext) {
        self.viewModel = viewModel
        self.context = context
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let authInfo = ActivityAuthorizationInfo()
        NSLog("[LiveActivity] Bridge start — activitiesEnabled: %d, media: %@",
              authInfo.areActivitiesEnabled ? 1 : 0,
              viewModel.media?.title ?? "nil")

        if viewModel.media != nil {
            Task { await createActivity() }
        } else {
            waitForMedia()
        }
    }

    func stop() {
        isStarted = false
        waitTask?.cancel()
        waitTask = nil
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

    private func waitForMedia() {
        waitTask = Task { [weak self] in
            NSLog("[LiveActivity] Waiting for media to load...")
            // Poll for media availability — more reliable than one-shot withObservationTracking
            for _ in 0..<150 { // Up to 15 seconds
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isStarted, !Task.isCancelled else { return }
                if self.viewModel.media != nil {
                    NSLog("[LiveActivity] Media became available: %@", self.viewModel.media?.title ?? "?")
                    await self.createActivity()
                    return
                }
            }
            NSLog("[LiveActivity] Timed out waiting for media")
        }
    }

    private func createActivity() async {
        guard let media = viewModel.media else { return }
        NSLog("[LiveActivity] Creating activity for: %@ type: %@", media.title, media.type.rawValue)

        let artworkData = await LiveActivityImageLoader.loadCompressedThumbnail(
            path: media.preferredThumbPath ?? media.thumbPath,
            context: context
        )
        NSLog("[LiveActivity] Artwork loaded: %d bytes", artworkData?.count ?? 0)

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

        let durationSeconds = media.duration ?? viewModel.duration ?? 0

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
            NSLog("[LiveActivity] Started successfully — id: %@, duration: %.0fs, position: %.0fs, artworkBytes: %d",
                  activity?.id ?? "?", durationSeconds, viewModel.position, artworkData?.count ?? 0)
            startPeriodicUpdates()
        } catch {
            NSLog("[LiveActivity] Failed to start: %@", String(describing: error))
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
