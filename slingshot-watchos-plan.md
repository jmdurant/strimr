# Slingshot watchOS Port — Implementation Plan

## Project Summary

Fork [wunax/slingshot](https://github.com/wunax/slingshot) and add a watchOS target to create a native Plex client for Apple Watch. The existing codebase is exceptionally well-structured for this: 100% Swift, SwiftUI throughout, a clean `Shared/` layer containing all networking, models, view models, session management, and Plex API logic, with platform-specific UI isolated in `Slingshot-iOS/` and `Slingshot-tvOS/`.

**Playback strategy: dual-engine.** watchOS playback requires two engines working together:
- **VLCKit 4.x** for **audio direct play** — VLCKit on watchOS is audio-only by design (video decoders/outputs are deliberately stripped from the watchOS build). It handles codecs AVPlayer can't: FLAC, Opus, DTS, AC3, Vorbis, WMA, etc. This is critical for music libraries and TV show audio tracks in exotic formats.
- **AVPlayer/AVKit** for **video playback** — SwiftUI's `VideoPlayer` view (watchOS 7+) renders HLS streams via hardware-accelerated decode. Since VLCKit can't render video on watchOS, video requires Plex server-side transcoding to HLS. The current app does direct play only (no transcode support), so **adding the Plex transcode endpoint is new shared-layer work**.

AVPlayer can also direct play audio in standard formats (AAC, MP3, ALAC in MP4/MOV containers), so for common audio formats either engine works. VLCKit covers the long tail.

**Audio-first design:** Music and audio content are the primary use cases — listening to your Plex library on AirPods from your wrist without your phone. Video browsing and playback are supported but secondary, given the Watch's 2-inch screen and battery constraints. No official Plex watchOS app exists, and NebuPlay (the only known third-party Plex Watch client) hasn't shipped yet — there's a real first-mover opportunity.

**Target: watchOS 26.2** (Apple's year-based versioning). Requires building for both `arm64` (Series 9+) and `arm64_32` (older models) architectures.

---

## Repository Overview

### Slingshot Architecture (what we're forking)

```
slingshot/
├── Shared/                          ← REUSE ALL OF THIS
│   ├── Extensions/                  Color+Hex, TimeInterval formatting
│   ├── Features/
│   │   ├── Auth/                    Sign-in, profile/server selection VMs
│   │   ├── Home/                    HomeViewModel (continue watching, recently added hubs)
│   │   ├── Library/                 LibraryViewModel, LibraryDetailViewModel, browse/collections/playlists VMs
│   │   ├── MediaDetail/             MediaDetailViewModel (metadata, seasons, episodes)
│   │   ├── Player/                  PlayerViewModel, PlayQueueState, PlaybackLauncher, PlayQueueManager
│   │   ├── Search/                  SearchViewModel
│   │   ├── Settings/                SettingsManager
│   │   ├── MainCoordinator.swift    Tab enum (home/search/library/more/seerrDiscover/libraryDetail)
│   │   │                            Route enum (mediaDetail/collectionDetail/playlistDetail)
│   │   │                            NavigationPath management per tab
│   │   ├── CollectionDetail/        CollectionDetailViewModel
│   │   ├── PlaylistDetail/          PlaylistDetailViewModel
│   │   ├── Seerr/                   Overseerr integration (EXCLUDE from watchOS v1)
│   │   └── WatchTogether/           Co-watching feature (EXCLUDE from watchOS v1)
│   ├── Library/
│   │   ├── Player/
│   │   │   ├── PlayerCoordinating.swift   Protocol: play/pause/seek/tracks/destruct
│   │   │   ├── PlayerFactory.swift        Creates VLC or MPV coordinator + view
│   │   │   ├── PlayerOptions.swift        Subtitle scale config
│   │   │   ├── PlayerProperty.swift       Enum: pause, timePos, duration, etc.
│   │   │   └── PlayerTrack.swift          Audio/subtitle track model
│   │   ├── VLC/
│   │   │   ├── VLCPlayerViewController.swift   UIViewController wrapping VLCMediaPlayer
│   │   │   ├── VLCPlayerView.swift              UIViewControllerRepresentable + Coordinator
│   │   │   └── VLCPlayerDelegate.swift          Protocol for property/playback callbacks
│   │   └── MPV/                     MPV engine (EXCLUDE — no watchOS support)
│   ├── Models/
│   │   ├── Plex/                    PlexCloudModels, PlexMediaModels, PlexPlayQueueModels, PlexTimelineModels
│   │   ├── Seerr/                   (EXCLUDE from watchOS v1)
│   │   ├── MediaItem.swift          Core media model
│   │   ├── PlayableMediaItem.swift  Playable wrapper
│   │   ├── MediaDisplayItem.swift   Display model (playable/collection/playlist)
│   │   ├── Library.swift            Library model
│   │   ├── Hub.swift                Hub model for home sections
│   │   ├── PlaybackPlayer.swift     Enum: vlc/mpv/infuse + InternalPlaybackPlayer
│   │   ├── AppSettings.swift        PlaybackSettings, InterfaceSettings, DownloadSettings
│   │   └── CollectionMediaItem.swift / PlaylistMediaItem.swift
│   ├── Networking/
│   │   ├── Plex/                    PlexAPI, PlexAPIContext, PlexCloudNetworkClient, PlexServerNetworkClient
│   │   └── PlexEndpoint.swift       Endpoint definitions
│   ├── Repository/
│   │   └── Plex/                    MetadataRepository, MediaRepository, PlaybackRepository, etc.
│   ├── Session/
│   │   └── SessionManager.swift     Auth state machine: hydrating→signedOut→needsProfile→needsServer→ready
│   ├── Storage/
│   │   └── Keychain.swift           Generic keychain helper (works on watchOS)
│   ├── Store/
│   │   ├── LibraryStore.swift       Library list management
│   │   └── SettingsManager.swift    UserDefaults-backed settings
│   └── Views/                       Shared SwiftUI components (media cards, carousels, badges)
│
├── Slingshot-iOS/                      ← REFERENCE FOR UI PATTERNS, DON'T INCLUDE
│   ├── SlingshotApp.swift              App entry: injects PlexAPIContext, SessionManager, etc. as @Environment
│   ├── Features/
│   │   ├── ContentView.swift        Auth state switch → MainTabView when ready
│   │   ├── Tab/MainTabView.swift    TabView with home/discover/search/libraries + pinned library tabs
│   │   ├── Home/HomeView.swift      ScrollView of MediaHubSections (continue watching + recently added)
│   │   ├── Library/
│   │   │   ├── LibraryView.swift            List of library rows with artwork cards
│   │   │   └── Detail/
│   │   │       ├── LibraryDetailView.swift   Segmented picker: recommended/browse/collections/playlists
│   │   │       ├── LibraryBrowseView.swift   Grid/list of all media in library
│   │   │       ├── LibraryRecommendedView.swift
│   │   │       ├── LibraryCollectionsView.swift
│   │   │       └── LibraryPlaylistsView.swift
│   │   ├── MediaDetail/             Hero image, metadata, play buttons, seasons/episodes, cast, related
│   │   ├── Search/SearchView.swift  Search field + filtered results
│   │   ├── Player/                  Full-screen player with controls overlay
│   │   └── Settings/, Auth/, Downloads/, Seerr/, WatchTogether/
│   └── AppDelegate.swift
│
└── Slingshot-tvOS/                     ← Second platform reference (shows multiplatform pattern)
```

### Playback Engines: VLCKit 4.x (audio) + AVPlayer (video)

watchOS playback requires a dual-engine approach because of a fundamental platform constraint: **VLCKit 4.x on watchOS is audio-only by design.**

Verified against current VLCKit master and VLC core source:
- FFmpeg is built with `--disable-everything`, then only audio decoders/demuxers/parsers are re-enabled (`aac,flac,dts,ac3,opus,vorbis,mp3,alac,wma,...`). No video decoders.
- ~90 modules are stripped via `VLC_MODULE_REMOVAL_LIST_WATCHOS`, including `vmem` (callback-based video output), all chroma converters (`swscale`, `i420_rgb`, etc.), and all video processing modules.
- The `VLCSampleBufferDisplay` video output module (the primary Apple vout) is explicitly guarded with `if !HAVE_WATCHOS`.
- VLCKit's official watchOS example app plays an `.m4a` file — pure audio.

This is a deliberate design choice by VideoLAN, not a bug or limitation to work around.

**Dual-engine strategy:**

| Use Case | Engine | How it works |
|---|---|---|
| Audio direct play (FLAC, DTS, AC3, Opus, etc.) | VLCKit 4.x | Direct play URL from Plex server → VLCKit decodes client-side. No transcoding needed. |
| Audio direct play (AAC, MP3, ALAC in MP4/MOV) | AVPlayer or VLCKit | Either engine works for common formats. |
| Video playback | AVPlayer + `VideoPlayer` (SwiftUI) | Plex server transcodes to HLS → AVPlayer renders via hardware decode. |
| Background audio | `AVAudioSession(.playback, policy: .longFormAudio)` | Routes to AirPods/speaker, system audio picker. |
| Now Playing | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` | Full support on watchOS. |

**New shared-layer work required: Plex transcode endpoint.**

The current app does direct play only — `PlayerViewModel.resolvePlaybackURL()` builds a raw file URL (`/library/parts/{id}/file.mkv?X-Plex-Token=...`) and hands it to VLCKit/MPV. There is no HLS transcode path anywhere in the codebase.

For watchOS video, we need to add the Plex transcode endpoint:
- `Shared/Repository/Plex/TranscodeRepository.swift` — New repository wrapping `/video/:/transcode/universal/start.m3u8` with appropriate quality/bitrate/codec parameters.
- `Shared/Features/Player/PlayerViewModel.swift` — Logic to choose direct play vs transcode based on platform capability. On iOS/tvOS, always direct play (VLCKit/MPV handle everything). On watchOS, direct play for audio (VLCKit), transcode to HLS for video (AVPlayer).

This transcode support is useful beyond watchOS — it enables a future "low bandwidth" mode on iOS, or playback on devices where the client can't decode the source format. It's a clean upstream contribution candidate.

---

## Existing Platform Patterns

The codebase already has a platform conditional pattern for iOS vs tvOS:

```swift
// In VLCPlayerViewController.swift:
#if os(tvOS)
    import TVVLCKit
#else
    import MobileVLCKit
#endif
```

**We do NOT extend this with `#if os(watchOS)`.** Instead, `VLCPlayerViewController.swift` is simply excluded from the watchOS target membership. The watchOS target gets its own player controllers:

```swift
// In WatchVLCPlayerController.swift (watchOS target only — audio direct play):
import VLCKit  // Unified VLCKit 4.x framework, audio-only on watchOS

// In WatchAVPlayerController.swift (watchOS target only — video via HLS transcode):
import AVFoundation
import AVKit
```

This approach means the existing file is untouched and upstream merges are always clean.

---

## Implementation Plan

### Phase 0: Fork & Dependency Setup

1. **Fork** `wunax/slingshot`
2. **Set up upstream remote** for ongoing sync:
   ```bash
   git remote add upstream https://github.com/wunax/slingshot.git
   ```
3. **Add watchOS target** in Xcode:
   - File → New → Target → watchOS App
   - Name: `Slingshot-watchOS`
   - Deployment target: watchOS 26.2 (Apple uses year-based versioning starting with watchOS 26)
   - Interface: SwiftUI, lifecycle: SwiftUI App
4. **Add VLCKit 4.x dependency for watchOS (audio direct play):**
   - Slingshot currently uses **Carthage** (see `Cartfile`). VLCKit 4.x watchOS binaries are distributed via **CocoaPods**.
   - **Option A (recommended):** Add a `Podfile` for the watchOS target only. CocoaPods and Carthage can coexist — the iOS/tvOS targets keep using Carthage, the watchOS target uses CocoaPods for VLCKit.
   - **Option B:** Build VLCKit 4.x from source via its build script (`compileAndBuildVLCKit.sh -w`) and link the resulting xcframework manually.
   - The iOS/tvOS targets continue using Carthage for VLCKit 3.x — completely unaffected.
   - Also link system frameworks to the watchOS target: `AVFoundation`, `AVKit`, `MediaPlayer`, `WatchKit`.
5. **Configure target membership for `Shared/` files:**
   - Add all compatible `Shared/` files to the watchOS target (see "Files INCLUDED in watchOS target as-is" table below)
   - Do NOT add UIKit-dependent files or v1 scope cuts (see "Files EXCLUDED from watchOS target membership" table below)
   - **Do NOT modify any existing files** — all incompatibilities are handled by exclusion, not `#if` guards

### Phase 1: Authentication

watchOS 26 introduces a system browser (`WebAuthenticationSession`) and a full keyboard, making standalone authentication viable directly on the Watch. This gives us three auth strategies — all supported in v1.

**Strategy A: On-Watch OAuth (primary — standalone capable)**

watchOS 26 supports `ASWebAuthenticationSession`, which allows the standard Plex OAuth flow directly on the Watch. The user taps "Sign In," the system browser opens plex.tv/auth, they authenticate, and the callback returns the auth token — the same flow as iOS.

This means the existing `AuthRepository` and `SessionManager` work as-is on watchOS. No WatchConnectivity needed for auth. The Watch app is fully standalone from day one.

**Strategy B: WatchConnectivity token transfer (convenience)**

For users who already have the iPhone app signed in, auto-transfer the auth token to the Watch for zero-tap setup.

- `Slingshot-watchOS/Connectivity/WatchSessionManager.swift` — `WCSessionDelegate` on the Watch side. Receives auth token + server identifier from the iPhone via `transferUserInfo` or `sendMessage`.
- `Slingshot-iOS/Connectivity/PhoneSessionManager.swift` — Companion code on the iOS side. When the user is authenticated (SessionManager.status == .ready), sends the Plex auth token and selected server identifier to the Watch.

How it works:
1. iPhone app activates `WCSession`, sends `["authToken": token, "serverIdentifier": serverId]` whenever auth state changes
2. Watch receives it, stores in Keychain using the existing `Keychain.swift` helper
3. Watch's `SessionManager.hydrate()` picks up the token from Keychain and proceeds through `bootstrapAuthenticatedSession` → `selectServer` → `.ready`

**Strategy C: Plex PIN auth (fallback)**

Display a 4-character code on the Watch, user enters it at plex.tv/link on any device. The Plex API supports this flow natively. This works even if `ASWebAuthenticationSession` has issues on watchOS 26 and there's no paired iPhone.

**Auth flow in `WatchSignInView`:**
1. If a token arrives via WatchConnectivity, auto-sign-in (Strategy B)
2. Otherwise, show "Sign In" button that opens on-Watch OAuth (Strategy A)
3. Below that, "Use Code" option for PIN auth (Strategy C)

The entire existing `SessionManager.swift` works as-is on watchOS — it uses `Keychain`, `PlexAPIContext`, `UserDefaults`, all of which are watchOS-compatible. Profile and server selection can also happen directly on the Watch using the keyboard.

### Phase 2: Core Navigation Shell

**File: `Slingshot-watchOS/SlingshotWatchApp.swift`**

Mirror the iOS `SlingshotApp.swift` entry point. Inject the same `@Environment` objects: `PlexAPIContext`, `SessionManager`, `SettingsManager`, `LibraryStore`. Omit `DownloadManager`, `SeerrStore`, `WatchTogetherViewModel`.

```swift
@main
struct SlingshotWatchApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
        }
    }
}
```

**File: `Slingshot-watchOS/Features/WatchContentView.swift`**

Same auth state machine as iOS `ContentView.swift`, minus the download offline mode:

```swift
struct WatchContentView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        switch sessionManager.status {
        case .hydrating:
            ProgressView()
        case .signedOut:
            WatchSignInView()  // On-Watch OAuth, PIN auth, or auto-transfer from iPhone
        case .needsProfileSelection:
            WatchProfileSelectionView()
        case .needsServerSelection:
            WatchServerSelectionView()
        case .ready:
            WatchMainTabView()
        }
    }
}
```

**File: `Slingshot-watchOS/Features/WatchMainTabView.swift`**

watchOS 26+ supports `TabView` with vertical pages. Map the iOS tabs:

```swift
struct WatchMainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchHomeView().tag(0)
            WatchLibrariesView().tag(1)
            WatchSearchView().tag(2)
        }
        .tabViewStyle(.verticalPage)  // or use NavigationSplitView on watchOS 26+
    }
}
```

The iOS `MainCoordinator` can be reused with a simplified tab set, or replaced with a lighter watchOS-specific coordinator since the navigation is simpler (no pinned library tabs, no Seerr tab).

### Phase 3: Browse Views

Each view is a thin SwiftUI wrapper over the existing shared view models.

**File: `Slingshot-watchOS/Features/Home/WatchHomeView.swift`**

The iOS `HomeView` renders `MediaHubSection` → `MediaCarousel` for continue watching and recently added. On watchOS, simplify to a `List`:

- Uses `HomeViewModel` directly (already in `Shared/Features/Home/`)
- "Continue Watching" section: `List` rows with title + progress indicator
- "Recently Added" sections: `List` rows with title + thumbnail
- Tapping a row pushes `WatchMediaDetailView`

**File: `Slingshot-watchOS/Features/Library/WatchLibrariesView.swift`**

The iOS `LibraryView` shows artwork cards. On watchOS, simplify to:

- `List` of library names with SF Symbol icons
- Tapping pushes `WatchLibraryDetailView`
- Uses `LibraryViewModel` directly

**File: `Slingshot-watchOS/Features/Library/WatchLibraryDetailView.swift`**

The iOS version uses a segmented picker for recommended/browse/collections/playlists. On watchOS:

- Default to browse view (grid/list of all items in the library)
- `List` of media items with poster thumbnails
- Uses `LibraryBrowseViewModel` or `LibraryDetailViewModel` directly
- Optional: add a picker at the top to switch between recommended/browse

**File: `Slingshot-watchOS/Features/Search/WatchSearchView.swift`**

- watchOS `TextField` for search input (dictation/scribble)
- Results as a `List`
- Uses `SearchViewModel` directly

**File: `Slingshot-watchOS/Features/MediaDetail/WatchMediaDetailView.swift`**

The iOS version has a hero image, metadata, play buttons, season/episode picker, cast, related content. On watchOS, condense to:

- Poster thumbnail at top
- Title, year, rating, duration
- Play button (prominent) + Resume button if applicable
- For TV shows: season picker → episode list
- Uses `MediaDetailViewModel` directly

### Phase 4: Playback (Dual-Engine)

watchOS playback uses two engines: **VLCKit for audio direct play**, **AVPlayer for video (HLS transcode)**. Both conform to `PlayerCoordinating`, so `PlayerViewModel` works unchanged.

**File: `Slingshot-watchOS/Library/WatchVLCPlayerController.swift`** — Audio direct play

```swift
import VLCKit

@MainActor
final class WatchVLCPlayerController: PlayerCoordinating {
    private let mediaPlayer: VLCMediaPlayer
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onMediaLoaded: (() -> Void)?

    init(options: PlayerOptions) {
        mediaPlayer = VLCMediaPlayer()
        // Set up delegate for state changes
    }

    func play(_ url: URL) {
        mediaPlayer.media = VLCMedia(url: url)
        mediaPlayer.play()
    }

    func togglePlayback() { /* ... */ }
    func pause() { mediaPlayer.pause() }
    func resume() { mediaPlayer.play() }
    func seek(to time: Double) { /* ... */ }
    func seek(by delta: Double) { /* ... */ }
    func setPlaybackRate(_ rate: Float) { mediaPlayer.rate = max(0.1, rate) }
    func selectAudioTrack(id: Int?) { /* ... */ }
    func selectSubtitleTrack(id: Int?) { /* N/A — audio only */ }
    func trackList() -> [PlayerTrack] { /* ... */ }
    func destruct() { mediaPlayer.stop() }
}
```

**File: `Slingshot-watchOS/Library/WatchAVPlayerController.swift`** — Video via HLS transcode

```swift
import AVFoundation
import AVKit
import MediaPlayer

@MainActor
final class WatchAVPlayerController: PlayerCoordinating {
    private(set) var player: AVPlayer?
    var onPropertyChange: ((PlayerProperty, Any?) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onMediaLoaded: (() -> Void)?

    init(options: PlayerOptions) {
        configureAudioSession()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
    }

    func play(_ url: URL) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        player = AVPlayer(playerItem: item)
        player?.play()
    }

    // ... remaining PlayerCoordinating methods using AVPlayer APIs
    func destruct() {
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
```

Both conform to `PlayerCoordinating`, so `PlayerViewModel` works without changes.

**File: `Slingshot-watchOS/Features/Player/WatchPlayerView.swift`**

- **Audio content:** Now Playing screen with album art/poster, title, play/pause/skip controls. Digital Crown for volume.
- **Video content:** SwiftUI `VideoPlayer` view (AVKit) wrapping the AVPlayer instance from `WatchAVPlayerController`. Renders Plex-transcoded HLS streams.
- Uses `PlayerViewModel` directly for state.

**File: `Slingshot-watchOS/Library/WatchPlayerFactory.swift`**

watchOS-specific factory that selects the appropriate engine:

```swift
enum WatchPlayerFactory {
    static func makeCoordinator(options: PlayerOptions, isVideo: Bool) -> any PlayerCoordinating {
        if isVideo {
            // Video: AVPlayer with HLS transcode URL
            return WatchAVPlayerController(options: options)
        } else {
            // Audio: VLCKit direct play for full codec support
            return WatchVLCPlayerController(options: options)
        }
    }
}
```

The original `Shared/Library/Player/PlayerFactory.swift` is excluded from the watchOS target membership — not modified.

**New shared-layer work: Plex transcode endpoint**

The current app has no transcode/HLS support — it always direct plays. For watchOS video, we need:

- **`Shared/Repository/Plex/TranscodeRepository.swift`** — Wraps the Plex transcode endpoint (`/video/:/transcode/universal/start.m3u8`). Parameters include target resolution, bitrate, video/audio codec, subtitle mode, and session ID. Returns an HLS playlist URL that AVPlayer can consume.
- **`Shared/Features/Player/PlaybackURLResolver.swift`** — Logic to choose direct play vs transcode. On iOS/tvOS, always direct play. On watchOS, direct play for audio, transcode to HLS for video. This replaces the inline `resolvePlaybackURL` in `PlayerViewModel` with a pluggable strategy.

This transcode support benefits all platforms — it enables a future "low bandwidth" mode on iOS/tvOS, or playback on constrained connections. Clean upstream contribution candidate.

### Phase 5: Now Playing & Background Audio

**This is critical infrastructure — without it, audio stops when the screen turns off.**

**Background audio setup:**
- Enable the **Audio** background mode in the watchOS target capabilities.
- Configure `AVAudioSession` with `.playback` category and `.longFormAudio` route sharing policy. When activated, watchOS automatically presents an audio route picker (AirPods, speaker, Bluetooth headphones).
- Use `WKExtendedRuntimeSession` with `.mindfulness` type for background playback. This allows up to **~1 hour** of continuous background audio per session. Sessions can be restarted for longer listening, but there may be a brief interruption at the boundary.

**Now Playing integration:**
- `MPNowPlayingInfoCenter.default().nowPlayingInfo` — set title, artist, album art, duration, elapsed time, playback rate. Update only when state actually changes.
- `MPRemoteCommandCenter.shared()` — register handlers for play, pause, toggle, next track, previous track, skip forward, skip backward, change playback position.
- These commands are triggered from: the system Now Playing app, AirPods controls (tap/squeeze), Control Center, and connected Bluetooth headphone buttons.

**watchOS 26 Controls API (new):**
- WidgetKit Controls can be placed in **Control Center**, **Smart Stack**, and **Action Button** (Apple Watch Ultra).
- Create controls for play/pause, "Continue Watching" quick resume, and Now Playing shortcut.
- If the iOS app already has WidgetKit controls, they are automatically shared with watchOS 26.

**Limitation: ~1 hour per background session.** Apple Music and system apps get unlimited background time, but third-party apps are capped via `WKExtendedRuntimeSession`. For most listening sessions this is fine. For very long content (audiobooks, long playlists), the app will need to restart the session. This is the same constraint Spotify and other third-party audio apps face on watchOS.

### Phase 6: Live TV & Channel Browsing

Slingshot currently has no Live TV/DVR support — the `PlexItemType` enum only covers movie, show, season, episode, collection, and playlist. No channel, tuner, EPG, or guide models exist. This is new shared-layer work that benefits all platforms.

However, Live TV is arguably a stronger use case on the Watch than library browsing. Glancing at what's on and tapping to watch is a very Watch-native interaction, and the watchOS UI for it is simpler than the iOS version (no full EPG grid needed).

**Shared layer work (benefits all platforms, potential upstream contribution):**

New files in `Shared/`:

- `Shared/Models/Plex/PlexLiveTVModels.swift` — Channel, Program/EPGItem, Tuner, Recording models. Plex exposes channels at `/livetv/sessions` and guide data at `/livetv/guide` with XMLTV/Gracenote-sourced EPG.
- `Shared/Networking/Plex/PlexLiveTVEndpoints.swift` — Endpoint definitions for the `/livetv/` API namespace: channel list, EPG grid, stream initiation, recording management.
- `Shared/Repository/Plex/LiveTVRepository.swift` — Repository wrapping the live TV API calls. Key methods: `getChannels()`, `getCurrentPrograms()`, `getGuide(start:end:)`, `tuneChannel(channelId:)` → returns HLS stream URL, `getRecordings()`, `scheduleRecording(programId:)`.
- `Shared/Features/LiveTV/LiveTVViewModel.swift` — View model exposing channel list with current program info, loading/error states. Periodically refreshes current program data since it changes in real time.
- `Shared/Features/LiveTV/ChannelModels.swift` — Display models mapping Plex channel/program data to UI-friendly structs (channel name, number, current show title, time remaining, thumbnail).

This shared layer follows the exact same patterns as the existing library/media code — models decode from Plex JSON, repository handles API calls, view model provides observable state. The existing `PlexServerNetworkClient` and `PlexAPIContext` handle the authenticated requests.

**watchOS UI (fork only):**

- `Slingshot-watchOS/Features/LiveTV/WatchLiveTVView.swift` — Simple `List` of channels showing: channel number/logo, current program title, time remaining with a progress bar. Tap to tune. This is the same pattern as `WatchLibrariesView` — a list backed by a view model with navigation pushes.
- `Slingshot-watchOS/Features/LiveTV/WatchLivePlayerView.swift` — Live playback view, similar to `WatchPlayerView` but without seek/duration (continuous stream). Shows channel name, current program, and basic play/pause/channel-up/channel-down controls. Digital Crown for volume.
- Add a "Live TV" tab to `WatchMainTabView` (conditional on the server having tuners configured).

**Playback flow:**

1. `LiveTVViewModel` fetches channels + current programs
2. User taps a channel
3. `LiveTVRepository.tuneChannel()` tells Plex server to start tuning → returns an HLS stream URL
4. HLS URL is handed to `WatchAVPlayerController.play()` via the same `PlayerCoordinating` protocol (live TV is always HLS)
5. AVPlayer handles the HLS live stream natively — this is exactly what AVPlayer is optimized for
6. `PlayerViewModel` handles state, but timeline reporting behaves differently (no fixed duration, no resume position)

**What about DVR/recordings?**

Recording management (scheduling, viewing completed recordings) can be a later addition. Completed recordings are just regular media items on the Plex server, so they'd show up in library browsing once recorded. Scheduling from the Watch could work but is lower priority.

**Upstream contribution strategy:**

The shared layer (`Models`, `Networking`, `Repository`, `ViewModel`) is a clean PR candidate for upstream Slingshot. It adds Live TV capability without changing any existing code, following the established architecture patterns. The iOS app could then build a full EPG grid UI on top of it. The watchOS views stay in the fork.

### Phase 7: Music Library Support

Music is arguably the single strongest use case for a Plex watchOS client — listening to your library on AirPods from your wrist without your phone. However, Slingshot has zero music support today. The `PlexItemType` enum lacks `artist`, `album`, and `track` types (they decode as `.unknown` and are treated as unsupported), playlists are hardcoded to `playlistType: "video"`, and there's no artist → album → track browsing hierarchy anywhere.

NebuPlay ([nebuplay.app](https://nebuplay.app)) is an upcoming music-only Plex client for Apple Watch that validates this use case. Their feature set and terminology is a good reference for how we frame our music support. Our advantage is that music is one feature within a full Plex client, not a standalone app.

This is shared layer work that benefits all platforms, similar to Live TV.

**Feature set (adopting watch-first terminology from NebuPlay):**

- **Standalone playback** — after initial server setup, music works without the iPhone. Stream over Wi-Fi/LTE or play synced content directly on Apple Watch.
- **Fast library browsing** — browse views for artists, albums, and songs with jump-to-letter navigation.
- **Streaming and offline sync** — stream instantly when connected or sync albums, playlists, and individual tracks for offline listening. Manage downloads and storage on the watch.
- **Compact search** — optimized for dictation and Scribble input on the small screen.
- **Queue management** — play next, add to queue, clear queue.
- **Watch-first player** — clean Now Playing screen with album art, haptics, large tap targets, Digital Crown volume, AirPods integration.
- **Cellular and Wi-Fi** — supports both cellular watches streaming over LTE and Wi-Fi-only models.

**Shared layer work (upstream contribution candidate):**

Extend `PlexItemType`:
```swift
// Add to existing enum in Shared/Models/Plex/PlexMediaModels.swift
case artist
case album
case track
```

Update `isPlayable` to return `true` for `.track`, and add an `isAudio` computed property. Update `Library.iconName` to return `"music.note"` or `"music.mic"` for artist type libraries. These are small changes to existing shared files — the one place where modifying upstream files is justified, since music support benefits all platforms and would be part of an upstream PR.

New files in `Shared/`:

- `Shared/Models/Plex/PlexMusicModels.swift` — Music-specific metadata extensions: track number, disc number, artist name, album title, album year, genre, duration (mm:ss display vs film-style runtime). These can extend `PlexItem` or be standalone models mapped from the same Plex JSON — the Plex API returns music metadata in the same `/library/sections/{id}/all` structure, just with different fields populated.
- `Shared/Features/Music/MusicArtistListViewModel.swift` — Fetches artists for a music library section. Same pattern as `LibraryBrowseViewModel` but filtered to artist type.
- `Shared/Features/Music/MusicAlbumListViewModel.swift` — Fetches albums for a given artist (or all albums in a library). Plex API: `/library/metadata/{artistRatingKey}/children`.
- `Shared/Features/Music/MusicTrackListViewModel.swift` — Fetches tracks for an album. Plex API: `/library/metadata/{albumRatingKey}/children`.
- `Shared/Features/Music/MusicPlaybackHelper.swift` — Handles creating play queues for music (single track, full album, shuffle artist). The existing `PlayQueueManager` should work but may need the URI format extended for music types.

Update `PlaylistRepository.getPlaylists()` to accept audio playlist types — currently hardcoded to `playlistType: "video"`. The `LibraryPlaylistsViewModel` (or a new music equivalent) passes `"audio"` for music libraries.

**watchOS UI:**

- `Slingshot-watchOS/Features/Music/WatchArtistListView.swift` — `List` of artists with thumbnails and jump-to-letter index. Tapping pushes to album list.
- `Slingshot-watchOS/Features/Music/WatchAlbumListView.swift` — `List` of albums with cover art, year. Tapping pushes to track list. Shuffle and play-all actions.
- `Slingshot-watchOS/Features/Music/WatchTrackListView.swift` — `List` of tracks with track number, title, duration. Tap to play. Play next / add to queue context actions.
- `Slingshot-watchOS/Features/Music/WatchNowPlayingView.swift` — Dedicated audio Now Playing screen: album art, track title, artist, play/pause, skip forward/back, Digital Crown for volume. Large tap targets, haptic feedback, accessibility-friendly layout. Integrates with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` for system-level controls and AirPods integration.
- `Slingshot-watchOS/Features/Music/WatchMusicQueueView.swift` — Current queue display with reorder/remove support.

The music browse flow (artist → album → track) maps perfectly to watchOS `NavigationStack` push navigation. It's the same drill-down pattern as library → media detail, just with three levels instead of two.

**watchOS performance patterns (inspired by NebuPlay's approach):**

These are watchOS-specific UX optimizations that make the app feel responsive despite the Watch's constrained hardware:

- **Prefetch recently played** — on app launch, immediately load the user's recently played artists/albums/tracks so lists are instant. Don't wait for the user to navigate there.
- **Remember scroll position per view** — persist scroll offset for each screen (artist list, album list, track list) so the user never loses context when navigating back. Use `ScrollViewReader` with `@SceneStorage` or a lightweight in-memory cache.
- **Queue actions locally, sync in bursts** — when the user taps "play next" or "add to queue," apply the action immediately in the local UI. Batch sync queue state to the Plex server efficiently rather than making a network call per action. This keeps interactions feeling instant even on slow connections.
- **Jump-to-letter index** — for large artist/album lists, use a side alphabet index for fast scrolling. watchOS supports this natively with `List` and section headers.

**Workout-focused design:**

The primary music-on-Watch use case is working out without a phone — running, gym, commuting. The UI should be designed for this context:

- **Large tap targets** — play/pause and skip buttons sized for sweaty fingers and arm movement. Minimum 44pt touch targets, ideally larger.
- **Strong, precise haptics** — confirm every action (play, pause, skip, add to queue) with haptic feedback so the user knows the tap registered without looking at the screen.
- **High-contrast Now Playing** — optimized for bright outdoor visibility. Bold typography, high contrast between text and background, album art as ambient background rather than detail-critical element.
- **Offline-first playback** — when synced content is available, prefer local playback over streaming to avoid network drops during movement. Seamlessly fall back to streaming when local content isn't available.
- **Battery-friendly networking** — batch API calls, avoid polling, use efficient image caching for album art. The Watch has limited battery and aggressive network power management.

Music playback on watchOS is actually simpler than video:
- No video rendering surface needed — VLCKit decodes and outputs directly to the audio route
- VLCKit handles codecs AVPlayer can't (FLAC, DTS, AC3, Opus) — critical for music libraries in non-standard formats
- Background audio via `WKExtendedRuntimeSession` (`.mindfulness`, ~1 hour per session) lets playback continue when the screen is off
- Now Playing integration is critical here — album art, track metadata, and remote commands all feed through `MPNowPlayingInfoCenter`
- AirPods controls (play/pause, skip, volume) work automatically via `MPRemoteCommandCenter`
- `AVQueuePlayer` (subclass of AVPlayer) supports gapless playback natively for sequential tracks — a nice-to-have that comes free with AVFoundation

**Offline sync (watch-first feature):**

Offline sync is more important for music than for video on the Watch — the primary use case is running/working out without a phone. Implementation:
- Sync selected albums, playlists, or individual tracks to Watch storage
- Plex server transcodes to a Watch-friendly bitrate/format during sync (128-256kbps AAC is typical)
- Manage downloads and storage directly on the Watch
- Playback works anywhere once content is synced
- Background downloads via `WKURLSessionRefreshBackgroundTask` — system performs downloads and wakes the app with completed files. Budget: ~1 background refresh per hour (more if the app has a complication on the active watch face). Large syncs need to be chunked across multiple background task windows.

**Storage constraints:** Apple Watch has 32-64GB total storage, but Apple imposes an **~8GB media storage cap** for apps. At 256kbps AAC, that's roughly 60-70 hours of music — enough for a generous workout playlist library but not an entire music collection. The sync UI should show available/used storage clearly.

**Upstream contribution strategy:**

The `PlexItemType` extension and music models/view models are a clean upstream PR. The playlist type fix (`"video"` → configurable) is a small but valuable bug fix PR on its own. The iOS app could then build a proper music browsing UI (album grid, artist pages, queue management) on top of the shared layer.

### Phase 7b: Photo Library Support

Photo libraries in Plex return `type: "photo"` for sections. Before this phase, `PlexItemType` lacked a `.photo` case so photo libraries decoded as `.unknown` and were filtered out by `LibraryStore`.

**Key insight:** The same `ImageRepository.transcodeImageURL` endpoint (`/photo/:/transcode`) already used for all artwork thumbnails is the exact mechanism for displaying photos at any resolution. No new networking code needed.

**Plex Photo API:**
- `GET /library/sections/{sectionId}/all?type=14` — photo albums
- `GET /library/metadata/{albumRatingKey}/children` — photos within an album
- Photo albums have `childCount`/`leafCount`; individual photos have `media` arrays
- Video clips (`type: "clip"`) can appear within photo libraries

**Shared layer changes:**
- `PlexItemType` — `.photo` (not playable in video player), `.clip` (playable)
- Exhaustive switch fixes across ~8 shared files (same pattern as music)
- `SearchResultCard` — "Photo"/"Clip" badges with `.cyan`/`.orange` colors

**watchOS views:**
- `PhotoBrowseViewModel` — two-level: albums (section type=14) → photos (metadata children)
- `WatchPhotoBrowseView` — album list with square thumbnails
- `WatchPhotoAlbumView` — 2-column grid of photo thumbnails
- `WatchPhotoDetailView` — full-screen viewer with `TabView(.verticalPage)` for swiping between photos, auto-hiding controls, dismiss button, photo counter

**Navigation:** `WatchLibrariesView` routes `.photo` libraries to `WatchPhotoBrowseView`.

### Phase 8: Polish & Additional Enhancements

- **Complications** showing currently playing, continue watching, or live TV "what's on now"
- **Streaming to AirPods** directly from Watch for audio content (built into Phase 7)
- **Seerr integration** (request movies/shows from your wrist)
- **Remote control mode** — control playback on Apple TV/iPhone from the Watch
- **Music offline sync** — download albums/playlists for phone-free listening during workouts
- **DVR recording management** — schedule recordings from the Watch, view upcoming/completed
- **Photo viewer enhancements** — pinch-to-zoom, EXIF metadata display (camera, lens, aperture, ISO), clip video playback within photo libraries
- **Photo sharing** — share photos from Plex to contacts or save to Watch Photos

---

## Upstream Merge Strategy: Zero Modifications to Existing Files

A critical design goal is that **no existing files in the repo are modified**. The watchOS target is purely additive. This means upstream pulls from `wunax/slingshot` are always clean merges with no conflicts, regardless of how actively the project is being developed.

### How it works

Instead of adding `#if os(watchOS)` guards to shared files, we use **Xcode target membership** to control what compiles for watchOS. Files that are incompatible with watchOS are simply not added to the watchOS target. watchOS-specific replacements live in `Slingshot-watchOS/` and are only members of the watchOS target.

### Files EXCLUDED from watchOS target membership (not modified, just unchecked)

| File/Folder | Reason |
|-------------|--------|
| `Shared/Library/VLC/VLCPlayerViewController.swift` | `UIViewController`, `import UIKit` |
| `Shared/Library/VLC/VLCPlayerView.swift` | `UIViewControllerRepresentable` |
| `Shared/Library/VLC/VLCPlayerDelegate.swift` | References `VLCPlayerViewController` |
| `Shared/Library/Player/PlayerFactory.swift` | Creates UIKit-based VLC/MPV views |
| `Shared/Library/MPV/` (entire folder) | No watchOS support |
| `Shared/Features/Seerr/` (entire folder) | v1 scope cut |
| `Shared/Features/WatchTogether/` (entire folder) | v1 scope cut |
| `Shared/Models/Seerr/` | v1 scope cut |
| `Shared/Networking/Seerr/` | v1 scope cut |
| `Shared/Repository/Seerr/` | v1 scope cut |
| `Shared/Views/` | iOS-specific card/carousel components |
| `Shared/Extensions/ImageCornerColorSampler.swift` | UIKit image APIs |
| `Shared/Features/Player/ExternalPlaybackLauncher.swift` | iOS-specific (Infuse launch via `openURL`) |
| `Shared/Features/Player/PlaybackLauncher.swift` | References `ExternalPlaybackLauncher` and iOS player presentation; replaced by `WatchPlaybackLauncher` |

### Files INCLUDED in watchOS target as-is (no changes needed)

| File/Folder | Notes |
|-------------|-------|
| `Shared/Models/` (except Seerr) | Pure Swift, no UIKit |
| `Shared/Networking/Plex/` | URLSession-based, watchOS-compatible |
| `Shared/Networking/PlexEndpoint.swift` | Pure Swift |
| `Shared/Repository/Plex/` | Pure Swift |
| `Shared/Session/SessionManager.swift` | Keychain + PlexAPIContext, works as-is |
| `Shared/Storage/Keychain.swift` | Security framework, watchOS-compatible |
| `Shared/Store/LibraryStore.swift` | Pure Swift |
| `Shared/Store/SettingsManager.swift` | UserDefaults-based |
| `Shared/Features/Home/HomeViewModel.swift` | Pure Swift |
| `Shared/Features/Library/` | All view models, pure Swift |
| `Shared/Features/Search/SearchViewModel.swift` | Pure Swift |
| `Shared/Features/MediaDetail/MediaDetailViewModel.swift` | Pure Swift |
| `Shared/Features/Player/PlayerViewModel.swift` | Uses `PlayerCoordinating` protocol only |
| `Shared/Features/Player/PlayQueue/` | Pure Swift |
| `Shared/Features/Player/PlaybackSettingsTrack.swift` | Pure Swift |
| `Shared/Features/Player/PlaybackSpeedOption.swift` | Pure Swift |
| `Shared/Features/CollectionDetail/` | Pure Swift VM |
| `Shared/Features/PlaylistDetail/` | Pure Swift VM |
| `Shared/Features/Auth/` | View models for profile/server selection |
| `Shared/Features/Settings/SettingsManager` | Pure Swift |
| `Shared/Library/Player/PlayerCoordinating.swift` | Protocol only |
| `Shared/Library/Player/PlayerOptions.swift` | Pure struct |
| `Shared/Library/Player/PlayerProperty.swift` | Pure enum |
| `Shared/Library/Player/PlayerTrack.swift` | Pure struct |
| `Shared/Monitoring/ErrorReporter.swift` | Check — may need exclusion if UIKit-dependent |

### watchOS replacements (new files, watchOS target only)

| Excluded file | watchOS replacement |
|---------------|-------------------|
| `PlayerFactory.swift` | `Slingshot-watchOS/Library/WatchPlayerFactory.swift` |
| `VLCPlayerViewController.swift` | `Slingshot-watchOS/Library/WatchVLCPlayerController.swift` (audio) + `WatchAVPlayerController.swift` (video) |
| `VLCPlayerView.swift` | SwiftUI `VideoPlayer` (AVKit) inside `WatchPlayerView.swift` for video; Now Playing UI for audio |
| `VLCPlayerDelegate.swift` | VLCKit delegate on `WatchVLCPlayerController`, AVPlayer KVO on `WatchAVPlayerController` |
| `PlaybackLauncher.swift` | `Slingshot-watchOS/Features/Player/WatchPlaybackLauncher.swift` (dual-engine, no Infuse) |
| `ExternalPlaybackLauncher.swift` | Not needed (no external player support on watchOS) |

### What about `PlaybackPlayer.swift` and the `.mpv` enum case?

The `PlaybackPlayer` enum (vlc/mpv/infuse) and `InternalPlaybackPlayer` enum (vlc/mpv) remain unmodified. The enum compiles fine on watchOS — it's just data. The watchOS code simply never selects `.mpv` at runtime. `WatchPlayerFactory` selects VLCKit for audio or AVPlayer for video automatically — no user-facing player choice needed. No `#if` needed.

### What about `MainCoordinator.swift`?

It references `NavigationPath` and tab enums — all pure SwiftUI, no UIKit. It can be included as-is in the watchOS target. Alternatively, if the watchOS navigation is simpler and doesn't need all the tab/path management, exclude it and use a lighter watchOS-specific coordinator. Either approach requires zero changes to the original file.

### Keeping the fork in sync

```bash
# One-time setup
git remote add upstream https://github.com/wunax/slingshot.git

# Regular sync
git fetch upstream
git merge upstream/main
# Zero conflicts — all watchOS code is in Slingshot-watchOS/ and .xcodeproj changes
```

The only merge friction will be `.xcodeproj/project.pbxproj` if upstream adds/removes files, since it's the same project file. This is inherent to adding any target to a shared Xcode project and is easily resolved (Xcode's merge format is predictable). To minimize even this, consider using an `.xcodeproj` generator like `xcodegen` or Tuist — but that's optional and probably overkill for this.

---

## Dependency Strategy

### Current state (Slingshot)
- **Carthage** for VLCKit 3.x (`MobileVLCKit` / `TVVLCKit`)
- `Cartfile` references VLC binaries

### Required for watchOS
- **VLCKit 4.x** (unified framework with watchOS support) — for audio direct play
- Distributed via **CocoaPods** as `VLCKit` pod (4.0.0a18 latest, alpha channel)
- Plus system frameworks: `AVFoundation`, `AVKit`, `MediaPlayer`, `WatchKit`

### Recommended approach

Create a `Podfile` targeting only the watchOS target:

```ruby
platform :watchos, '26.2'

target 'Slingshot-watchOS' do
  use_frameworks!
  pod 'VLCKit', '~> 4.0.0-alpha'
end
```

The iOS and tvOS targets continue using Carthage for VLCKit 3.x. This avoids disrupting the existing build.

Alternatively, build VLCKit 4.x from source via `compileAndBuildVLCKit.sh -w` and link the resulting xcframework manually to the watchOS target.

---

## Scope Summary

### v1 (MVP) — COMPLETE
- Standalone auth via on-Watch OAuth (watchOS 26 browser), WatchConnectivity token transfer, or Plex PIN fallback
- Home screen (continue watching + recently added)
- Library browsing
- Media detail with play button
- Search
- Audio direct play via VLCKit 4.x (FLAC, DTS, AC3, Opus, etc.)
- Video playback via AVPlayer + Plex HLS transcode via local HTTP proxy (NWListener TLS bypass)
- Now Playing integration + background audio
- Player UI: landscape rotation toggle, playback speed control, overlay controls with auto-fade, aspect-fill video
- Detail view: landscape backdrop art with caching, season picker
- Downloads & offline playback: download button on detail view, Downloads tab, transcoded 720kbps progressive download, local file playback

### v2 (Live TV)
- Shared layer: Plex Live TV API client, channel/program models, LiveTVRepository, LiveTVViewModel
- watchOS: Channel list with current programs, tap-to-tune live playback (HLS via AVPlayer)
- Potential upstream contribution: shared layer PR to wunax/slingshot

### v3 (Music)
- Shared layer: Extend PlexItemType with artist/album/track, music models, music browse view models, audio playlist support
- watchOS: Artist → album → track browsing, dedicated Now Playing view, AirPods/background audio integration, AVQueuePlayer for gapless playback
- Potential upstream contributions: PlexItemType extension, music shared layer, playlist type fix

### Excluded from v1/v2/v3
- Seerr/Overseerr integration
- WatchTogether
- ~~Downloads/offline playback~~ → **DONE** (added in v1, commit `e92f75d`)
- Complications
- Settings UI (inherit from iPhone)
- DVR recording management

### New files to create

**v1 (~19 files):**
1. `Slingshot-watchOS/SlingshotWatchApp.swift`
2. `Slingshot-watchOS/Features/WatchContentView.swift`
3. `Slingshot-watchOS/Features/WatchMainTabView.swift`
4. `Slingshot-watchOS/Features/Auth/WatchSignInView.swift` (on-Watch OAuth + PIN auth + WatchConnectivity auto-transfer)
5. `Slingshot-watchOS/Features/Home/WatchHomeView.swift`
6. `Slingshot-watchOS/Features/Library/WatchLibrariesView.swift`
7. `Slingshot-watchOS/Features/Library/WatchLibraryDetailView.swift`
8. `Slingshot-watchOS/Features/Search/WatchSearchView.swift`
9. `Slingshot-watchOS/Features/MediaDetail/WatchMediaDetailView.swift`
10. `Slingshot-watchOS/Features/Player/WatchPlayerView.swift`
11. `Slingshot-watchOS/Features/Player/WatchPlaybackLauncher.swift`
12. `Slingshot-watchOS/Library/WatchVLCPlayerController.swift` (audio direct play via VLCKit)
13. `Slingshot-watchOS/Library/WatchAVPlayerController.swift` (video via HLS transcode)
14. `Slingshot-watchOS/Library/WatchPlayerFactory.swift` (selects engine: VLCKit for audio, AVPlayer for video)
15. `Slingshot-watchOS/Connectivity/WatchSessionManager.swift`
16. `Slingshot-iOS/Connectivity/PhoneSessionManager.swift` (addition to iOS target)
17. `Slingshot-watchOS/Assets.xcassets` (watch app icon)
18. `Shared/Repository/Plex/TranscodeRepository.swift` (new — Plex HLS transcode endpoint, upstream candidate)
19. `Shared/Features/Player/PlaybackURLResolver.swift` (new — direct play vs transcode strategy, upstream candidate)

**v2 — Live TV shared layer (~5 files, upstream contribution candidate):**
20. `Shared/Models/Plex/PlexLiveTVModels.swift`
21. `Shared/Networking/Plex/PlexLiveTVEndpoints.swift`
22. `Shared/Repository/Plex/LiveTVRepository.swift`
23. `Shared/Features/LiveTV/LiveTVViewModel.swift`
24. `Shared/Features/LiveTV/ChannelModels.swift`

**v2 — Live TV watchOS UI (~2 files):**
25. `Slingshot-watchOS/Features/LiveTV/WatchLiveTVView.swift`
26. `Slingshot-watchOS/Features/LiveTV/WatchLivePlayerView.swift`

**v3 — Music shared layer (~5 files, upstream contribution candidate):**
27. `Shared/Models/Plex/PlexMusicModels.swift`
28. `Shared/Features/Music/MusicArtistListViewModel.swift`
29. `Shared/Features/Music/MusicAlbumListViewModel.swift`
30. `Shared/Features/Music/MusicTrackListViewModel.swift`
31. `Shared/Features/Music/MusicPlaybackHelper.swift`

**v3 — Music watchOS UI (~5 files):**
32. `Slingshot-watchOS/Features/Music/WatchArtistListView.swift`
33. `Slingshot-watchOS/Features/Music/WatchAlbumListView.swift`
34. `Slingshot-watchOS/Features/Music/WatchTrackListView.swift`
35. `Slingshot-watchOS/Features/Music/WatchNowPlayingView.swift`
36. `Slingshot-watchOS/Features/Music/WatchMusicQueueView.swift`

**v3 — Minor modifications to existing shared files (upstream PR):**
- `Shared/Models/Plex/PlexMediaModels.swift` — add `artist`, `album`, `track` to `PlexItemType` enum
- `Shared/Models/Library.swift` — add icon cases for music library types
- `Shared/Repository/Plex/PlaylistRepository.swift` — make `playlistType` parameter configurable instead of hardcoded `"video"`

### Existing files modified in v1: ONE

`Shared/Features/Player/PlayerViewModel.swift` — refactor `resolvePlaybackURL` to use the new `PlaybackURLResolver` for direct play vs transcode strategy. This is a small, clean change that benefits all platforms (enables future low-bandwidth mode on iOS/tvOS). All other watchOS support is achieved through Xcode target membership (include/exclude) and additive new files. No `#if os(watchOS)` guards. See "Upstream Merge Strategy" section for full details.

---

## Implementation Status

### Phase 0: COMPLETE

**Directory structure created:** `Slingshot-watchOS/` with all subdirectories matching the plan.

**watchOS target added to Xcode project (`project.pbxproj`):**
- Target UUID: `E9AA00012F5A000100000001`
- Product: `Slingshot-watchOS.app`
- SDKROOT: watchos, WATCHOS_DEPLOYMENT_TARGET: 26.2, TARGETED_DEVICE_FAMILY: 4
- Uses `fileSystemSynchronizedGroups` for Slingshot-watchOS/, Shared/, and Config/ (same pattern as iOS target)
- Sentry SPM dependency linked
- Config.xcconfig referenced for DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER
- pbxproj validated with `plutil -lint` — OK

**Shared/ target membership configured via exception set:**
- Exception UUID: `E9AA000E2F5A000100000001`
- Excludes: Library/VLC/*, Library/MPV/*, Library/Player/PlayerFactory.swift, Features/Seerr/*, Features/WatchTogether/*, Features/Integrations/*, Models/Seerr/*, Networking/Seerr/*, Repository/Seerr/*, Store/SeerrStore.swift, Views/* (except MediaBackdropGradient.swift), Extensions/ImageCornerColorSampler.swift, Features/Player/ExternalPlaybackLauncher.swift, Features/Player/PlaybackLauncher.swift, Features/Player/Controls/*, Features/Settings/*, Features/Search/SearchResultCard.swift, Features/MediaDetail/CastSection.swift, Features/MediaDetail/RelatedHubsSection.swift, Features/Library/LibraryBrowseControlsView.swift, Features/MainCoordinator.swift
- Includes everything else: all Models (except Seerr), all Networking/Plex, all Repository/Plex, SessionManager, Keychain, LibraryStore, SettingsManager, all Feature ViewModels (Home, Library, Search, MediaDetail, Player, Auth, CollectionDetail, PlaylistDetail), PlayerCoordinating protocol, PlayerOptions, PlayerProperty, PlayerTrack, Color+Hex, TimeInterval+MediaFormat, ErrorReporter, MediaBackdropGradient

**Source files created (22 files):**

| # | File | Status |
|---|------|--------|
| 1 | `Slingshot-watchOS/SlingshotWatchApp.swift` | Done — mirrors iOS SlingshotApp.swift, injects PlexAPIContext/SessionManager/SettingsManager/LibraryStore |
| 2 | `Slingshot-watchOS/Features/WatchContentView.swift` | Done — auth state switch matching iOS ContentView pattern |
| 3 | `Slingshot-watchOS/Features/WatchMainTabView.swift` | Done — 3-tab TabView (Home/Libraries/Search) |
| 4 | `Slingshot-watchOS/Features/Auth/WatchSignInView.swift` | Done — uses real AuthRepository API (requestPin/pollToken), supports OAuth browser + PIN code auth |
| 5 | `Slingshot-watchOS/Features/Auth/WatchProfileSelectionView.swift` | Done — uses ProfileSwitcherViewModel |
| 6 | `Slingshot-watchOS/Features/Auth/WatchServerSelectionView.swift` | Done — uses ServerSelectionViewModel |
| 7 | `Slingshot-watchOS/Features/Home/WatchHomeView.swift` | Done — uses HomeViewModel, List-based, continue watching + recently added |
| 8 | `Slingshot-watchOS/Features/Library/WatchLibrariesView.swift` | Done — uses LibraryViewModel, NavigationLink to detail |
| 9 | `Slingshot-watchOS/Features/Library/WatchLibraryDetailView.swift` | Done — uses LibraryRecommendedViewModel |
| 10 | `Slingshot-watchOS/Features/Search/WatchSearchView.swift` | Done — uses SearchViewModel with .searchable modifier |
| 11 | `Slingshot-watchOS/Features/MediaDetail/WatchMediaDetailView.swift` | Done — uses MediaDetailViewModel, play/resume buttons, season/episode picker for shows |
| 12 | `Slingshot-watchOS/Features/Player/WatchPlayerView.swift` | Done — dual-engine: VideoPlayer(AVKit) for video, custom audio UI for audio, uses PlayerViewModel |
| 13 | `Slingshot-watchOS/Features/Player/WatchPlaybackLauncher.swift` | Done — simplified launcher using PlayQueueManager |
| 14 | `Slingshot-watchOS/Features/WatchMediaRow.swift` | Done — reusable row component with thumbnail/labels/progress, NavigationLink for playable items |
| 15 | `Slingshot-watchOS/Library/WatchAVPlayerController.swift` | Done — full PlayerCoordinating implementation using AVPlayer, KVO observers, time observer, audio session activation in play() with async activate(options:) |
| 16 | `Slingshot-watchOS/Library/WatchVLCPlayerController.swift` | Done — full VLCKit 4.x implementation: play/pause/seek/tracks/destruct, VLCMediaPlayerDelegate callbacks, audio session activation |
| 17 | `Slingshot-watchOS/Library/WatchPlayerFactory.swift` | Done — selects AVPlayer for video, VLCKit for audio |
| 18 | `Slingshot-watchOS/Connectivity/WatchSessionManager.swift` | Done — WCSessionDelegate, receives auth token from iPhone |
| 19 | `Slingshot-iOS/Connectivity/PhoneSessionManager.swift` | Done — WCSession companion on iOS side, sends auth token to Watch |
| 20 | `Slingshot-watchOS/Info.plist` | Done — NSAllowsArbitraryLoads, UIBackgroundModes audio, WKApplication, URL scheme |
| 21 | `Slingshot-watchOS/Assets.xcassets/` | Done — AppIcon.appiconset with watch icon sizes, Contents.json |
| 22 | `Slingshot-watchOS/Library/WatchNowPlayingManager.swift` | Done — MPRemoteCommandCenter + MPNowPlayingInfoCenter, artwork loading, playback state updates |
| 23 | `Slingshot-watchOS/Slingshot-watchOS.entitlements` | Done — `com.apple.security.network.client` for real device networking |
| 24 | `Slingshot-watchOS/Features/Music/MusicBrowseViewModel.swift` | Done — three-level browsing (artists/albums/tracks) |
| 25 | `Slingshot-watchOS/Features/Music/WatchMusicBrowseView.swift` | Done — artist list → album list → track list with play all/shuffle |
| 26 | `Slingshot-watchOS/Features/Photos/PhotoBrowseViewModel.swift` | Done — two-level browsing (albums/photos) |
| 27 | `Slingshot-watchOS/Features/Photos/WatchPhotoBrowseView.swift` | Done — album list + photo grid (WatchPhotoAlbumView) |
| 28 | `Slingshot-watchOS/Features/Photos/WatchPhotoDetailView.swift` | Done — full-screen viewer with vertical page swiping |

**Build fixes applied during Phase 0:**
- Added `import AVFoundation` to `WatchPlayerView.swift` (AVPlayer type not in scope with just AVKit on watchOS)
- Excluded `MainCoordinator.swift` from watchOS (references SeerrMedia; watchOS uses WatchMainTabView instead)
- Included `ErrorReporter.swift` in watchOS (already guarded with `#if canImport(Sentry)`)
- Added `#if !os(watchOS)` guard around `MediaBackdropGradient.colors()` in `MediaDetailViewModel` (gradient view depends on iOS/tvOS asset catalog colors)
- Fixed `.accent` → `Color.accentColor` across watchOS views (`.accent` not a valid color reference)
- Fixed optional chaining in `WatchProfileSelectionView` (non-optional inside `if let`)
- Moved `navigationDestination` outside `Group` in `WatchHomeView`/`WatchLibraryDetailView`

**Bundle ID & Simulator setup:**
- `Config.xcconfig` updated: `IOS_BUNDLE_IDENTIFIER` + `PRODUCT_BUNDLE_IDENTIFIER = $(IOS_BUNDLE_IDENTIFIER)`
- watchOS build settings: `PRODUCT_BUNDLE_IDENTIFIER = $(IOS_BUNDLE_IDENTIFIER).watchos`, `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = $(IOS_BUNDLE_IDENTIFIER)`
- `Config-example.xcconfig` updated with matching pattern
- App installs and launches on watchOS simulator, auth flow works through to server selection

### Phase 1 (HLS Transcode): COMPLETE

**Created:** `Shared/Repository/Plex/TranscodeRepository.swift`
- Builds HLS transcode URLs for the Plex universal transcode endpoint (`/video/:/transcode/universal/start.m3u8`)
- Parameters: path, session, protocol=hls, directPlay=0, directStream=1, videoCodec=h264, audioCodec=aac, maxVideoBitrate=2000, videoResolution=480x360
- `stopSession(id:)` sends DELETE to `/video/:/transcode/universal/stop` for cleanup

**Modified:** `Shared/Features/Player/PlayerViewModel.swift`
- `resolvePlaybackURL(from:)`: Added `#if os(watchOS)` branch — video content (movie/episode) uses `TranscodeRepository.transcodeURL()` with the existing `sessionIdentifier`; non-video falls back to direct play
- `handleStop()` and `markPlaybackFinished()`: Added `stopTranscodeSession()` call — on watchOS, sends stop request to Plex server to end transcode session
- Resume offset passed to transcode URL from `metadata.viewOffset`

**Modified:** `Shared/Networking/Plex/PlexServerNetworkClient.swift`
- Added `#elseif os(watchOS)` to platform string so Plex server identifies client correctly as "watchOS"

**No changes needed** to WatchPlayerView or WatchAVPlayerController — AVPlayer natively handles M3U8/HLS playlists returned by the transcode endpoint.

### Phase 5 (Now Playing & Background Audio): COMPLETE

**Created:** `Slingshot-watchOS/Library/WatchNowPlayingManager.swift`
- Configures `MPRemoteCommandCenter` handlers: play, pause, togglePlayPause, skipForward (30s), skipBackward (15s), changePlaybackPosition (seek scrubber)
- Routes all remote commands to the `PlayerCoordinating` coordinator via weak reference
- `updateMetadata(from:context:)` sets MPNowPlayingInfoCenter with title, artist (show name for episodes, year for movies), album title (season info), duration, and media type
- Asynchronously downloads artwork via `ImageRepository.transcodeImageURL()` (300x300) and sets `MPMediaItemPropertyArtwork`
- `updatePlaybackState(position:duration:rate:)` updates elapsed time, duration, and playback rate (0.0 paused, 1.0 playing)
- `invalidate()` removes all command targets and clears nowPlayingInfo

**Modified:** `Slingshot-watchOS/Features/Player/WatchPlayerView.swift`
- Added `PlayerCallbackProviding` protocol to bridge `onPropertyChange`/`onPlaybackEnded`/`onMediaLoaded` (these callbacks are on concrete player classes, not the `PlayerCoordinating` protocol)
- Both `WatchAVPlayerController` and `WatchVLCPlayerController` conform via extensions
- `setupPropertyCallbacks()` now creates `WatchNowPlayingManager`, sets metadata, and forwards `.timePos`, `.duration`, `.pause` property changes to update Now Playing state
- Wires up `onPlaybackEnded` → `viewModel.markPlaybackFinished()`
- `teardown()` invalidates the Now Playing manager before stopping playback

**Modified:** `Slingshot-watchOS/Library/WatchAVPlayerController.swift`
- Moved `configureAudioSession()` from `init` to `play(_:)` — audio session activates only when ready to stream (per Apple guidance)
- Changed `setActive(true)` to `session.activate(options: [])` for watchOS best practices (async activation with route picker support)

**Build verified:** `xcodebuild -scheme Slingshot-watchOS -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build` — BUILD SUCCEEDED

### VLCKit 4.x Integration: COMPLETE

**Added:** `Carthage/Build/VLCKit.xcframework` — VLCKit 4.0.0a18 unified xcframework
- Downloaded from official VideoLAN CDN (`VLCKit-4.0.0a18-844dff57e-c833c4be0.tar.xz`)
- Contains watchOS slices: `watchos-arm64_arm64_32` (device), `watchos-arm64_x86_64-simulator` (sim)
- Placed alongside existing Carthage xcframeworks (MobileVLCKit, TVVLCKit)

**Modified:** `Slingshot.xcodeproj/project.pbxproj`
- Added PBXFileReference for VLCKit.xcframework
- Added to watchOS target's Frameworks build phase (link)
- Added Embed Frameworks copy build phase with CodeSignOnCopy + RemoveHeadersOnCopy

**Rewritten:** `Slingshot-watchOS/Library/WatchVLCPlayerController.swift`
- Full VLCKit 4.x implementation replacing the `#if canImport(VLCKit)` skeleton
- Uses VLCKit 4.x API: `VLCMediaPlayer`, `VLCMedia(url:)`, `VLCTime(int:)`, `VLCMediaPlayerDelegate`
- Track management via `mediaPlayer.audioTracks` → `[VLCMediaPlayerTrack]` (4.x API; 3.x used `audioTrackNames`/`audioTrackIndexes`)
- State handling: `.playing`, `.paused`, `.stopped`, `.stopping`, `.opening`, `.buffering` (4.x has no `.ended`)
- Delegate: `mediaPlayerStateChanged(_ newState: VLCMediaPlayerState)` (4.x passes state directly; 3.x used Notification)
- Audio session: `.playback` category, `.longFormAudio` policy, async `activate(options:)` — same pattern as WatchAVPlayerController

**VLCKit 4.x API differences from 3.x (for reference):**
- `selectedExclusively` → `isSelectedExclusively` (Swift property rename)
- `currentAudioTrackIndex` / `audioTrackNames` / `audioTrackIndexes` → `audioTracks: [VLCMediaPlayerTrack]` with `.trackName`, `.isSelected`, `.isSelectedExclusively`
- `VLCMediaPlayerState.ended` removed → use `.stopped` with guard
- `mediaPlayerStateChanged(_: Notification)` → `mediaPlayerStateChanged(_ newState: VLCMediaPlayerState)`

**Build verified:** `xcodebuild -scheme Slingshot-watchOS` — BUILD SUCCEEDED

### WatchConnectivity Wiring: COMPLETE

**Modified:** `Slingshot-iOS/SlingshotApp.swift`
- Activates `PhoneSessionManager.shared` in `init()` with the `SessionManager` reference
- Added `.onChange(of: sessionManager.status, initial: true)` — sends auth token + server ID to the Watch whenever `SessionManager` reaches `.ready` status (including on initial app launch)
- Uses `PhoneSessionManager.shared.sendAuthToken(_:serverIdentifier:)` which calls `WCSession.transferUserInfo` (queued, reliable)

**Modified:** `Slingshot-watchOS/SlingshotWatchApp.swift`
- Activates `WatchSessionManager.shared` in `init()`
- Wires `onTokenReceived` callback to trigger `sessionManager.hydrate()` — re-reads token from keychain (already stored by WatchSessionManager) and bootstraps the session

**Flow:** iPhone signs in → SessionManager reaches `.ready` → token + server ID transferred to Watch via WCSession → WatchSessionManager stores in keychain + UserDefaults → triggers `hydrate()` → Watch session bootstraps automatically. No manual re-auth needed on Watch.

**Note:** `WatchSessionManager` and `SessionManager` use matching keychain keys (`slingshot.plex.authToken`) and UserDefaults keys (`slingshot.plex.serverIdentifier`), so `hydrate()` finds the token that WatchConnectivity stored.

### Real Device Deployment Fixes: COMPLETE

**Created:** `Slingshot-watchOS/Slingshot-watchOS.entitlements`
- Added `com.apple.security.network.client` entitlement — required for outgoing network connections on real watchOS devices (simulator doesn't enforce this)
- Without this, all network requests (including ASWebAuthenticationSession browser page loads) silently fail on device

**Modified:** `Slingshot.xcodeproj/project.pbxproj`
- Added `CODE_SIGN_ENTITLEMENTS = "Slingshot-watchOS/Slingshot-watchOS.entitlements"` to both Debug and Release build configurations
- Fixed `PRODUCT_BUNDLE_IDENTIFIER[sdk=watchos*]` — was literal `--IOS-BUNDLE-IDENTIFIER-.watchos`, changed to `$(IOS_BUNDLE_IDENTIFIER).watchos` so the xcconfig variable resolves correctly

**Modified:** `Config/Config.xcconfig`
- Set `DEVELOPMENT_TEAM = PHS5V2FW3J` (was empty, caused signing failures for device builds)

**Build + install verified:** Built for real Apple Watch Ultra 3 (watchOS 26.2), installed via `xcrun devicectl device install app`, app launches on device.

### Browser Auth Fix: COMPLETE

**Modified:** `Slingshot-watchOS/Features/Auth/WatchSignInView.swift`
- Changed `ASWebAuthenticationSession` initializer from `callback: .customScheme("slingshot")` to `callbackURLScheme: nil` — the Plex auth page uses a polling flow (not redirect), so the custom scheme callback caused the session to immediately cancel with error 1 (canceledLogin) on real devices. Simulator was more lenient about this.
- Added `@State private var authSession` to retain the session — was a local variable that got deallocated when `signInWithBrowser()` continued, killing the browser. iOS version stores it as a class property (`private var authSession`).
- Added debug logging (to be cleaned up in future pass)

**Known watchOS issue:** Safari/WebKit on watchOS has an intermittent rendering bug where web pages show only the address bar with black content area. Affected by Screen Time settings and possibly watchOS version. Not specific to our app — affects all web content on the Watch. Workaround: disable Screen Time restrictions, update watchOS. The "Use Code" PIN flow and WatchConnectivity token transfer are unaffected alternatives.

**Device testing status:**
- App builds, installs, and launches on real Apple Watch Ultra 3 (watchOS 26.2)
- Browser sign-in works when watchOS WebKit rendering is functional
- Auth PIN request/polling works correctly
- WatchConnectivity token transfer wired up (untested on real devices pending simultaneous iOS+watchOS device run)

### PlexURLSession & Image Loading Fix: COMPLETE

**Created:** `Shared/Networking/Plex/PlexURLSession.swift`
- Shared URLSession with `TrustDelegate` that accepts `.plex.direct` server certificates
- `TrustDelegate` implements `urlSession(_:didReceive:completionHandler:)` — trusts any `.plex.direct` host via `URLCredential(trust:)`
- Used by `PlexServerNetworkClient` and `PlexAPIContext.isConnectionReachable()` (replaced `URLSession.shared`)

**Created:** `Slingshot-watchOS/Views/PlexAsyncImage.swift`
- Custom async image view that loads images via `PlexURLSession.shared` instead of `URLSession.shared`
- SwiftUI `AsyncImage` uses `URLSession.shared` internally with no way to inject custom TLS handling
- Replaced `AsyncImage` usage in `WatchMediaRow.swift` and `WatchMediaDetailView.swift`

**Modified:** `Shared/Features/Player/PlayQueue/PlayQueueState.swift`
- Added `Identifiable` conformance (already had `let id: Int`)

**Modified:** `Slingshot-watchOS/Features/MediaDetail/WatchMediaDetailView.swift`
- Fixed `fullScreenCover` state capture bug: changed from `fullScreenCover(isPresented:)` to `fullScreenCover(item: $presentedPlayQueue)` — the `isPresented` variant captures @State values at closure creation time, so `playQueue` was always nil when the player view rendered
- Added `.environment(plexApiContext)` to fullScreenCover content — fullScreenCover creates a separate view hierarchy that doesn't inherit parent environment values
- Replaced `AsyncImage` with `PlexAsyncImage`

**Device testing results:**
- Images load correctly on both simulator and real device
- Player view now presents correctly (fullScreenCover fix)
- API calls succeed via both relay and direct connections

### AVPlayer TLS Certificate Issue: RESOLVED

**Problem:** AVPlayer rejects `.plex.direct` TLS certificates when loading HLS transcode URLs on watchOS. Server sends only the leaf cert without the R12 intermediate — AVPlayer on watchOS does NOT do AIA chasing.

**Solution:** Local HTTP proxy via NWListener. AVPlayer connects to `http://localhost:PORT`, the proxy forwards requests to Plex via `PlexURLSession` (which has custom TLS trust).

**Created:** `Slingshot-watchOS/Library/HLSProxyServer.swift`
- NWListener-based local HTTP proxy on watchOS
- Rewrites HLS manifest URLs so all segment fetches also go through the proxy
- AVPlayer sees plain HTTP, proxy handles TLS via PlexURLSession
- Works on both simulator and real Apple Watch Ultra 3
- `start(baseURL:)` / `stop()` / `proxyURL(for:)` API

**Commits:** `68d81f7` (proxy + transcode), `a8c66b9` (aspect fill, bitrate, toolbar)

### Player UI Enhancements: COMPLETE

**Commit:** `5788d64`

**Landscape rotation toggle:**
- Manual toggle button (bottom-left overlay) rotates video 90° via `.rotationEffect(.degrees(90))` with swapped frame dimensions
- No CoreMotion auto-detect (walking causes constant rotation)

**Custom overlay controls (fade on 4s timer):**
- Close (X) button — top-left, dismisses player
- Rotate button — bottom-left, toggles landscape
- Speed button — bottom-right, cycles 1x→1.25x→1.5x→1.75x→2x via client-side `AVPlayer.rate`
- All controls fade together after 4 seconds, reappear on tap
- `.simultaneousGesture(TapGesture())` to coexist with VideoPlayer's built-in tap

**Video aspect-fill:**
- `GeometryReader` + `.scaleEffect(y: videoRatio/screenRatio)` + `.clipped()` — SwiftUI's `VideoPlayer` ignores `.scaledToFill()`

**Detail view improvements:**
- Switched from portrait poster to landscape backdrop art (200x112) via `media.artPath` with 16:9 aspect ratio, `.frame(maxHeight: 65)`
- Season picker fixed with `.pickerStyle(.navigationLink)`

**Image caching:**
- Added `NSCache<NSURL, UIImage>` (countLimit 60) to `PlexAsyncImage` for faster reload

**Background playback:**
- `player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible` in `WatchAVPlayerController`

**Transcode settings:**
- Lowered to 720kbps / 480x320 (from 2000kbps) — appropriate for watch screen size

### Downloads & Offline Playback: COMPLETE

**Commit:** `e92f75d`

**Moved:** `Slingshot-iOS/Features/Downloads/DownloadModels.swift` → `Shared/Models/DownloadModels.swift`
- `DownloadStatus`, `DownloadItem`, `DownloadedMediaMetadata`, `DownloadStorageSummary` — pure Codable structs, shared by iOS and watchOS

**Modified:** `Shared/Repository/Plex/TranscodeRepository.swift`
- Added `transcodeDownloadURL()` — progressive HTTP download URL (not HLS) at 720kbps/320p
- Uses `protocol=http`, path `/video/:/transcode/universal/start` (no `.m3u8`)

**Created:** `Slingshot-watchOS/Features/Downloads/WatchDownloadManager.swift`
- `@MainActor @Observable` class with URLSession + custom TLS delegate for `.plex.direct`
- `URLSessionDownloadDelegate` for progress tracking (throttled at 1% intervals)
- Persistence via `index.json` in `~/Library/Application Support/Downloads/`
- Key methods: `enqueueItem(ratingKey:context:)`, `delete(_:)`, `localVideoURL(for:)`, `localPosterURL(for:)`, `localMediaItem(for:)`
- Downloads poster thumbnails (160x240) alongside video
- On cold start, marks any previously-active downloads as failed (app was killed)

**Created:** `Slingshot-watchOS/Features/Downloads/WatchDownloadsView.swift`
- Downloads tab UI: empty state, storage summary (downloads size / available space), download rows with status indicators
- Tap completed item → `fullScreenCover` with `WatchPlayerView` using local file URLs
- Swipe to delete

**Modified:** `Slingshot-watchOS/Features/WatchMainTabView.swift`
- Added 4th tab for Downloads

**Modified:** `Slingshot-watchOS/Features/MediaDetail/WatchMediaDetailView.swift`
- Download button below Play buttons for movies, episodes, and shows (downloads next episode for shows)
- Button states: Download / Downloading X% / Downloaded (green checkmark) / Retry Download

**Modified:** `Slingshot-watchOS/SlingshotWatchApp.swift`
- Initialized `WatchDownloadManager` and injected via `.environment()`

**Modified:** `Slingshot-watchOS/Features/Player/WatchPlayerView.swift`
- Added optional `localMedia: MediaItem?` and `localPlaybackURL: URL?` params for offline playback
- Local files skip HLS proxy and server reporting

### Phase 6 (Live TV): COMPLETE

**Commit:** `f6e5689`

Live TV channel browsing and HLS playback on watchOS. Shared-layer models, repository, and view model for channel data. watchOS UI with channel list (current program + progress bar) and full-screen live player view with dismiss overlay and channel name badge. Tap-to-tune flow via HLS proxy.

### Phase 7 (Music Library): COMPLETE

Music library support added across shared and watchOS layers:

**Shared layer changes:**
- `PlexItemType` — added `.artist`, `.album`, `.track` cases with `isPlayable`, `isAudio`
- `Library.iconName` — `"music.note.list"` for artist libraries
- `MediaItem` — `secondaryLabel` for artists (album count), albums (artist + year), tracks (artist); `tertiaryLabel` for tracks
- `MediaDisplayItem` — maps `.artist`, `.album`, `.track` to `.playable()`
- `PlayableMediaItem` — added `.artist`, `.album`, `.track` to `PlayableItemType`
- All exhaustive switches updated across ~8 files
- `PlaybackLauncher` / `WatchPlaybackLauncher` — `continuous: true` for music types

**watchOS files created:**
- `MusicBrowseViewModel.swift` — three-level browsing (artists via section type=8, albums via metadata children, tracks via metadata children)
- `WatchMusicBrowseView.swift` — artist list → album list → track list with play all / shuffle / individual track playback
- Playlists link for audio playlists

**Navigation wiring:**
- `WatchLibrariesView` routes `.artist` libraries to `WatchMusicBrowseView`

### Photo Library Support: COMPLETE

Photo library support added across shared and watchOS layers.

**Shared layer changes:**
- `PlexItemType` — added `.photo` (not playable), `.clip` (playable, video clips in photo libraries)
- `Library.iconName` — `"photo.on.rectangle"` for photo libraries, `"video.fill"` for clip
- `MediaItem` — `secondaryLabel` for photos (photo count or year), clips (year); `tertiaryLabel` returns nil
- `MediaDisplayItem` — maps `.photo`, `.clip` to `.playable()` for display (thumbnails, labels)
- `PlayableMediaItem` — returns `nil` for `.photo`/`.clip` (photos don't go through video/audio player)
- All exhaustive switches updated across ~8 files (WatchStatus, DownloadModels, SearchResultCard, MediaDetailHeaderSection, WatchTogetherView iOS+tvOS)
- `SearchResultCard` — "Photo"/"Clip" labels, `.cyan`/`.orange` badge colors

**watchOS files created:**
- `PhotoBrowseViewModel.swift` — two-level browsing (albums via section type=14, photos via metadata children)
- `WatchPhotoBrowseView.swift` — album list with square thumbnails + photo count labels
- `WatchPhotoAlbumView` (same file) — 2-column grid of photo/clip thumbnails with video badge overlay on clips, tap photo → full-screen viewer, tap clip → HLS video playback via `WatchPlaybackLauncher`
- `WatchPhotoDetailView.swift` — full-screen photo viewer with vertical page swiping (TabView), auto-hiding dismiss button + photo counter overlay, high-res image loading (2x screen size)

**Clip (video) playback:**
- Plex classifies all video files in photo libraries as `type: "clip"` — Live Photos, home videos, any MP4/MOV
- Clips show a video icon badge in the album grid for visual distinction
- Tap a clip → `WatchPlaybackLauncher.createPlayQueue(type: .clip)` → HLS transcode → `WatchPlayerView`
- Photo detail viewer filters out clips so photo-only swiping stays clean

**Navigation wiring:**
- `WatchLibrariesView` routes `.photo` libraries to `WatchPhotoBrowseView`

**Build verified:** watchOS and iOS targets build cleanly.

### Audio Playback Architecture Fix: COMPLETE

**Discovery:** VLCKit 4.x on watchOS has **no HTTP access module** — it cannot stream any HTTP/HTTPS URLs. `VLCConsoleLogger` output showed `looking for access module matching "http": 0 candidates`. VLC on watchOS can only play local `file://` URLs.

**Architecture change:**
- **Before:** Video → AVPlayer+HLS proxy, Audio → VLC (streaming failed)
- **After:** Everything streaming → AVPlayer+HLS proxy, VLC only for offline/downloaded audio

**Branching logic in `WatchPlayerView.setupPlayer()`:**
- `useVLC = isLocal && !isVideo` — VLC only for downloaded audio files (with audio bridge for visualizations)
- All streaming (video + audio) → `WatchAVPlayerController` + `HLSProxyServer` for TLS termination
- Local video → `WatchAVPlayerController` directly (no proxy needed for `file://`)
- `avPlayer` state var only set for video (controls whether VideoPlayer or audio UI renders)

**Crash fix:** Reordered `destruct()` in `WatchVLCPlayerController` — media player must stop before audio bridge frees its context, otherwise VLC's flush callback fires on freed memory (`EXC_BAD_ACCESS` in `flush_cb`).

### Audio Visualizations (Milkdrop): COMPLETE

**Pipeline:** VLC audio callbacks → FFT (vDSP, 1024-sample window) → 32 logarithmic bins → SpectrumData → SwiftUI Canvas at 60fps

**Files created:**
- `Slingshot-watchOS/Library/VLCAudioBridge.h` + `.m` — ObjC bridge to libvlc audio callbacks, AVAudioEngine re-injection, real-time FFT
- `Slingshot-watchOS/Library/SpectrumData.swift` — thread-safe spectrum bin storage with temporal smoothing (rise fast 0.6, fall slow 0.15)
- `Slingshot-watchOS/Features/Player/WatchVisualizationView.swift` — fullscreen Canvas visualization with 11 Milkdrop-inspired presets
- `Slingshot-watchOS/Slingshot-watchOS-Bridging-Header.h` — imports VLCAudioBridge.h

**11 visualization presets** (ported from [winamp-macos](https://github.com/mbrukman/winamp-macos)):
1. Classic Bars — green→red gradient bars with glow + peak hold dots (the Winamp look)
2. Frequency Rings — glowing concentric pulsing rings
3. LFO Morph — organic morphing closed paths with glow strokes
4. Oscillator Grid — 6×8 grid of pulsing colored dots with halos
5. Spiral Galaxy — 3-arm spiral + energy rings + waveforms + floating particles
6. Plasma Field — procedural 4-layer sine plasma
7. Particle Storm — radial burst particles with glow
8. Waveform Tunnel — 20-layer concentric depth rings
9. Kaleidoscope — 8-segment rotational symmetry
10. Nebula Galaxy — stars + blur nebula clouds + glowing core + spiral arms
11. Starfield Flight — 3D perspective stars with motion trails + glow + distant nebula

**FFT tuning:**
- Logarithmic bin mapping with pow(2.5) for better resolution in musically active range
- Frequency-dependent gain: 12× at bass, 32× at treble (compensates for music's natural energy dropoff)
- Temporal smoothing in SpectrumData: rise 0.6 / fall 0.15 blend for responsive but flowing visualization

**UI integration:**
- Waveform button on audio player (only visible for VLC/offline playback)
- `.fullScreenCover` presentation
- Digital Crown cycles presets with haptic feedback
- Auto-advance every 60 seconds with fade transition
- Tap to dismiss

**Rendering techniques:** Canvas blur/glow layers, 3D perspective projection, motion trails, procedural textures, context transforms for kaleidoscope symmetry — all running at 60fps on S10 chip.

### Next Steps

1. **Clean up debug logging** — remove writeDebug calls
2. **Test downloads on real device** — verify download progress, completion, and offline playback on Apple Watch Ultra 3
3. **Photo viewer enhancements** — pinch-to-zoom, EXIF metadata display
4. **Music offline sync** — download albums/playlists for phone-free listening during workouts
5. **Complications** — currently playing, continue watching
6. **Remote control mode** — control playback on Apple TV/iPhone from the Watch

## Claude Code Workflow

When resuming this project in Claude Code:

1. Read this plan document (especially Implementation Status above)
2. Build the watchOS target: `xcodebuild -scheme Slingshot-watchOS -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build`
3. The approach for fixing compile errors: exclude files from target membership (add to exception set in pbxproj), NOT by adding `#if os(watchOS)` guards (exception: `resolveGradient()` and `resolvePlaybackURL()` where minimal `#if os(watchOS)` was cleaner)
4. If a shared ViewModel references an excluded type, consider: (a) including the dependency, (b) creating a watchOS stub, or (c) excluding the ViewModel too
5. Key files for playback: `TranscodeRepository.swift` (URL builder), `PlayerViewModel.swift` (URL resolution + session cleanup), `WatchPlayerView.swift` (player UI), `WatchAVPlayerController.swift` (AVPlayer wrapper)
