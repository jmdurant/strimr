import AppIntents

struct SlingshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open \(\.$library) in \(.applicationName)",
                "Show \(\.$library) in \(.applicationName)",
                "Browse \(\.$library) in \(.applicationName)",
            ],
            shortTitle: "Open Library",
            systemImageName: "rectangle.stack.fill"
        )

        AppShortcut(
            intent: ShuffleLibraryIntent(),
            phrases: [
                "Shuffle \(\.$library) in \(.applicationName)",
                "Play \(\.$library) on shuffle in \(.applicationName)",
            ],
            shortTitle: "Shuffle Library",
            systemImageName: "shuffle"
        )

        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: [
                "Resume playback in \(.applicationName)",
                "Continue playing in \(.applicationName)",
            ],
            shortTitle: "Resume Playback",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause playback in \(.applicationName)",
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
    }
}
