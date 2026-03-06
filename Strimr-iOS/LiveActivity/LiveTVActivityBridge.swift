import ActivityKit
import Foundation
import os

@MainActor
final class LiveTVActivityBridge {
    private let channelName: String
    private let channelNumber: String
    private var activity: Activity<LiveTVAttributes>?
    private var isStarted = false

    init(channelName: String, channelNumber: String) {
        self.channelName = channelName
        self.channelNumber = channelNumber
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let authInfo = ActivityAuthorizationInfo()
        AppLogger.liveActivity.info("Starting — channel: \(self.channelName), activitiesEnabled: \(authInfo.areActivitiesEnabled)")

        let attributes = LiveTVAttributes(
            channelName: channelName,
            channelNumber: channelNumber
        )

        let initialState = LiveTVAttributes.ContentState(
            programTitle: nil,
            programEndsAt: nil,
            isBuffering: true
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            AppLogger.liveActivity.info("Started successfully — id: \(self.activity?.id ?? "?")")
        } catch {
            AppLogger.liveActivity.error("Failed to start: \(error)")
        }
    }

    func updateProgram(title: String?, endsAt: Date?) {
        guard let activity else { return }

        let state = LiveTVAttributes.ContentState(
            programTitle: title,
            programEndsAt: endsAt,
            isBuffering: false
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: endsAt))
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        Task {
            let finalState = LiveTVAttributes.ContentState(
                programTitle: nil,
                programEndsAt: nil,
                isBuffering: false
            )
            await activity?.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            activity = nil
        }
    }
}
