# Background Playback Within App + Now Playing Tab

## Context

Playback already continues when leaving the app (audio session with `.longFormAudio`), but dismissing the player *within* the app tears everything down because the coordinator, viewModel, and nowPlayingManager are `@State` on `WatchPlayerView`. We need to hoist player state into a shared environment object so dismissing the player UI keeps audio playing, and add a "Now Playing" tab (like the Workout app) to the left of Home for controlling active playback.

## Design

### New: `ActivePlaybackManager` (`@Observable`, in environment)

Owns all player lifecycle state that currently lives as `@State` on `WatchPlayerView`:
- coordinator (`PlayerCoordinating`)
- viewModel (`PlayerViewModel`)
- nowPlayingManager (`WatchNowPlayingManager`)
- avPlayer (`AVPlayer?` — for video re-presentation)
- localMedia/localPlaybackURL (for save-on-switch)

Key methods:
- `startPlayback(...)` — saves position for any current item, tears down, sets up new playback
- `handlePlayerDismiss() -> Bool` — if playing: save position, return true (keep going). If paused: teardown, return false
- `saveAndTeardown()` — saves position, destroys coordinator, clears Now Playing
- `stop()` — explicit stop from Now Playing tab
- `togglePlayback()`, `seekForward()`, `seekBackward()` — convenience

Logic moved from `WatchPlayerView`: `setupPlayer()`, `setupPropertyCallbacks()`, `teardown()`

### Modified: `WatchPlayerView` → UI shell

- Removes `@State` for viewModel, coordinator, avPlayer, nowPlayingManager — reads from `ActivePlaybackManager`
- X button → `chevron.left` back button
- Dismiss calls `playbackManager.handlePlayerDismiss()` then `dismiss()`
- `onDisappear` no longer tears down
- New `resumeFromManager: Bool = false` param for re-opening from Now Playing tab (skips `startPlayback`)
- Keeps view-only `@State`: `isLandscape`, `showControls`, `playbackSpeed`, `showVisualization`

### Modified: `WatchMainTabView` — Now Playing tab

The Now Playing tab just shows `WatchPlayerView(resumeFromManager: true)` directly — same UI as the full player, no separate compact view. When playback is active, swiping left from Home reaches the Now Playing tab with the full player controls already there.

- Reads `ActivePlaybackManager` from environment
- Conditionally shows Now Playing tab at tag `-1` before Home when `playbackManager.isActive`
- `onChange(of: playbackManager.isActive)` auto-navigates to Now Playing when playback starts, back to Home when it stops

### Extract: `PlayerCallbackProviding`

Currently `private` in WatchPlayerView.swift (lines 20-27). Move to own file so `ActivePlaybackManager` can use it.

## Files

### New Files

| File | Purpose |
|------|---------|
| `Strimr-watchOS/Library/ActivePlaybackManager.swift` | Shared player lifecycle manager |
| `Strimr-watchOS/Library/PlayerCallbackProviding.swift` | Extracted protocol + conformance extensions |

### Modified Files

| File | Change |
|------|--------|
| `Strimr-watchOS/StrimrWatchApp.swift` | Add `@State activePlaybackManager`, inject into environment |
| `Strimr-watchOS/Features/WatchMainTabView.swift` | Add conditional Now Playing tab (tag -1), auto-nav onChange |
| `Strimr-watchOS/Features/Player/WatchPlayerView.swift` | Remove @State player objects, delegate to manager, X→chevron, new dismiss behavior |

### Unchanged

Launch sites (`WatchMediaDetailView`, `DownloadPlayerLauncher`, music/playlist/photo views) present `WatchPlayerView` via `fullScreenCover` which inherits the parent environment. `WatchPlayerView` internally delegates to `ActivePlaybackManager` — no call-site changes needed.

## Implementation Order

1. Create `PlayerCallbackProviding.swift` — extract protocol from WatchPlayerView
2. Create `ActivePlaybackManager.swift` — move setup/teardown/callback logic here
3. Update `StrimrWatchApp.swift` — create and inject into environment
4. Refactor `WatchPlayerView.swift` — remove state, read from manager, change dismiss behavior
5. Update `WatchMainTabView.swift` — conditional Now Playing tab showing `WatchPlayerView(resumeFromManager: true)`

## Key Behaviors

- **Tap back while playing** → UI dismisses, audio continues, Now Playing tab appears
- **Tap back while paused** → full teardown, Now Playing tab disappears
- **Play new item while one is active** → saves offset/lastViewedAt for previous, tears down, starts new
- **Playback ends naturally** → `onPlaybackEnded` triggers `saveAndTeardown()`, Now Playing tab disappears
- **Now Playing tab** → shows same WatchPlayerView directly, full controls
- **Video dismissed while playing** → audio from video continues via AVPlayer background policy

## Verification

1. Build and deploy to Watch Ultra 3 simulator
2. Start audio playback → tap back → verify audio continues
3. Verify Now Playing tab appears to the left of Home
4. Verify full player controls work on Now Playing tab
5. Start new item while playing → verify previous position saved
6. Pause → tap back → verify full teardown, Now Playing tab gone
7. Start streaming video → tap back → verify audio continues
8. Stop from Now Playing → verify teardown
9. Verify AirPods controls work during in-app background playback
