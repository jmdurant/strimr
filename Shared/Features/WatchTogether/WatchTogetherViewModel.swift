import Foundation
import Observation

@MainActor
@Observable
final class WatchTogetherViewModel {
    private static let minimumParticipantsToStartPlayback = 2

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    enum Role {
        case none
        case host
        case guest
    }

    var connectionState: ConnectionState = .disconnected
    var role: Role = .none
    var code: String = ""
    var joinCode: String = ""
    var participants: [WatchTogetherParticipant] = []
    var selectedMedia: WatchTogetherSelectedMedia?
    var readyMap: [String: Bool] = [:]
    var mediaAccessMap: [String: Bool] = [:]
    var errorMessage: String?
    var toasts: [ToastMessage] = []
    var isSessionStarted = false
    var sessionEndedSignal: UUID?
    var playbackStoppedSignal: UUID?
    var participantId: String?
    var chatMessages: [WatchTogetherChatMessage] = []
    var chatInput: String = ""
    var selectedLiveTVChannel: WatchTogetherLiveTVChannel?

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let client = WatchTogetherWebSocketClient()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var playbackLauncher: PlaybackLauncher?
    @ObservationIgnored private var showLiveTVPlayer: ((URL, String) -> Void)?
    @ObservationIgnored private var lastMediaAccessRatingKey: String?
    @ObservationIgnored private var lastKnownHostId: String?
    @ObservationIgnored private var pendingLateJoinSeek: Double?
    @ObservationIgnored private var pendingLateJoinPaused: Bool = false
    @ObservationIgnored private lazy var playbackSyncEngine: WatchTogetherPlaybackSyncEngine = .init(
        sendEvent: { [weak self] event in
            Task { await self?.sendPlayerEvent(event) }
        },
        showToast: { [weak self] message in
            self?.showToast(message)
        },
        currentParticipantId: { [weak self] in
            self?.currentParticipantId
        },
    )

    init(sessionManager: SessionManager, context: PlexAPIContext, settingsManager: SettingsManager) {
        self.sessionManager = sessionManager
        self.context = context

        client.serverResolver = WatchTogetherServerResolver(
            settingsManager: settingsManager,
            context: context
        )

        client.onMessage = { [weak self] message in
            self?.handle(message)
        }

        client.onDisconnect = { [weak self] error in
            self?.handleDisconnect(error)
        }
    }

    var isInSession: Bool {
        !code.isEmpty && role != .none
    }

    var isHost: Bool {
        role == .host
    }

    var currentUserId: String? {
        sessionManager.user?.uuid
    }

    var currentParticipantId: String? {
        participantId ?? currentUserId
    }

    var currentDisplayName: String? {
        sessionManager.user?.friendlyName
            ?? sessionManager.user?.title
            ?? sessionManager.user?.username
    }

    var plexServerId: String? {
        sessionManager.plexServer?.clientIdentifier
    }

    var resolvedServerURL: URL? {
        client.resolvedURL
    }

    var canStartPlayback: Bool {
        guard isHost else { return false }
        guard selectedMedia != nil || selectedLiveTVChannel != nil else { return false }
        guard participants.count >= Self.minimumParticipantsToStartPlayback else { return false }
        if selectedLiveTVChannel != nil {
            return participants.allSatisfy(\.isReady)
        }
        return participants.allSatisfy { $0.isReady && $0.hasMediaAccess }
    }

    var requiresMoreParticipantsToStartPlayback: Bool {
        participants.count < Self.minimumParticipantsToStartPlayback
    }

    func configurePlaybackLauncher(_ launcher: PlaybackLauncher) {
        playbackLauncher = launcher
    }

    func configureLiveTVPlayer(_ handler: @escaping (URL, String) -> Void) {
        showLiveTVPlayer = handler
    }

    func createSession() {
        guard let identity = makeIdentityPayload() else { return }
        client.disconnect()
        resetSessionState(clearJoinCode: false)
        role = .host
        connectAndSend(.createSession(identity))
    }

    func joinSession() {
        let trimmed = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            showToast(String(localized: "watchTogether.error.missingCode"))
            return
        }

        guard let identity = makeIdentityPayload(code: trimmed) else { return }
        joinCode = trimmed
        client.disconnect()
        resetSessionState(clearJoinCode: false)
        role = .guest
        connectAndSend(.joinSession(identity))
    }

    func leaveSession(endForAll: Bool) {
        Task {
            await sendMessage(.leaveSession(LeaveSessionRequest(endForAll: endForAll)))
            client.disconnect()
            resetSessionState(clearJoinCode: false)
        }
    }

    func toggleReady() {
        guard let participantId = currentParticipantId else { return }
        let isReady = !(readyMap[participantId] ?? false)
        Task {
            await sendMessage(.setReady(SetReadyRequest(isReady: isReady)))
        }
    }

    func setSelectedMedia(_ media: MediaDisplayItem) {
        guard isHost else { return }
        Task {
            let selected = WatchTogetherSelectedMedia(media: media)
            let hasAccess = await verifyMediaAccess(for: selected)
            guard hasAccess else {
                showToast(String(localized: "watchTogether.error.mediaUnavailable"))
                return
            }

            selectedMedia = selected
            isSessionStarted = false
            playbackSyncEngine.setEnabled(false)
            await sendMessage(.setSelectedMedia(SetSelectedMediaRequest(media: selected)))
            await sendMessage(.mediaAccess(MediaAccessRequest(hasAccess: true)))
        }
    }

    func startPlayback() {
        guard canStartPlayback else { return }
        if let selectedMedia {
            Task {
                await sendMessage(
                    .startPlayback(
                        StartPlaybackRequest(
                            ratingKey: selectedMedia.ratingKey,
                            type: selectedMedia.type,
                        ),
                    ),
                )
            }
        } else if let channel = selectedLiveTVChannel {
            Task {
                await sendMessage(
                    .startPlayback(
                        StartPlaybackRequest(
                            ratingKey: channel.channelId,
                            type: .clip,
                        ),
                    ),
                )
            }
        }
    }

    func stopPlaybackForEveryone() {
        guard isHost else { return }
        Task {
            await sendMessage(.stopPlayback(StopPlaybackRequest(reason: nil)))
        }
    }

    func attachPlayerCoordinator(_ coordinator: any PlayerCoordinating) {
        playbackSyncEngine.attachCoordinator(coordinator)

        if let seekPosition = pendingLateJoinSeek {
            pendingLateJoinSeek = nil
            let shouldPause = pendingLateJoinPaused
            pendingLateJoinPaused = false
            // Small delay to let the player initialize before seeking
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                coordinator.seek(to: seekPosition)
                if shouldPause {
                    coordinator.pause()
                }
            }
        }
    }

    func detachPlayerCoordinator() {
        playbackSyncEngine.detachCoordinator()
    }

    func sendPlayPause(isCurrentlyPaused: Bool, positionSeconds: Double? = nil) {
        playbackSyncEngine.emitPlayPause(isCurrentlyPaused: isCurrentlyPaused, positionSeconds: positionSeconds)
    }

    func sendSeek(to positionSeconds: Double) {
        playbackSyncEngine.emitSeek(to: positionSeconds)
    }

    func sendRateChange(_ rate: Float) {
        playbackSyncEngine.emitSetRate(rate)
    }

    func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatInput = ""
        Task {
            await sendMessage(.chatMessage(ChatMessageRequest(text: text)))
        }
    }

    func setLiveTVChannel(channelId: String, channelName: String, thumb: String?) {
        guard isHost else { return }
        Task {
            await sendMessage(.setLiveTVChannel(SetLiveTVChannelRequest(
                channelId: channelId,
                channelName: channelName,
                thumb: thumb
            )))
        }
    }

    private func connectAndSend(_ message: WatchTogetherClientMessage) {
        Task {
            do {
                connectionState = .connecting
                try await client.connect()
                connectionState = .connected
                await sendMessage(message)
            } catch {
                connectionState = .disconnected
                showToast(String(localized: "watchTogether.error.connection"))
            }
        }
    }

    private func sendMessage(_ message: WatchTogetherClientMessage) async {
        do {
            try await client.send(message)
        } catch {
            showToast(String(localized: "watchTogether.error.send"))
        }
    }

    private func sendPlayerEvent(_ event: WatchTogetherPlayerEvent) async {
        await sendMessage(.playerEvent(PlayerEventRequest(event: event)))
    }

    private func handle(_ message: WatchTogetherServerMessage) {
        switch message {
        case let .created(payload):
            code = payload.code
            participantId = payload.participantId
            role = payload.hostId == payload.participantId ? .host : .guest
            lastKnownHostId = payload.hostId
            showToast(String(localized: "watchTogether.toast.created \(payload.code)"))
        case let .joined(payload):
            code = payload.code
            participantId = payload.participantId
            role = payload.hostId == payload.participantId ? .host : .guest
            lastKnownHostId = payload.hostId
            showToast(String(localized: "watchTogether.toast.joined \(payload.code)"))
        case let .lobbySnapshot(snapshot):
            apply(snapshot: snapshot)
        case let .participantUpdate(payload):
            updateParticipant(payload.participant)
        case let .sessionEnded(payload):
            handleSessionEnded(reason: payload.reason)
        case let .error(payload):
            let message = serverErrorMessage(for: payload)
            showToast(message)
            if shouldDisconnectAfterError(payload) {
                client.disconnect()
                resetSessionState(clearJoinCode: false)
            }
            errorMessage = message
        case .pong:
            break
        case let .startPlayback(payload):
            handleStartPlayback(payload)
        case let .playbackStopped(payload):
            handlePlaybackStopped(payload)
        case let .playerEvent(event):
            let senderName = participants.first(where: { $0.id == event.senderId })?.displayName
            playbackSyncEngine.handleRemoteEvent(event, senderName: senderName)
        case let .chatMessage(message):
            if !chatMessages.contains(where: { $0.id == message.id }) {
                chatMessages.append(message)
                // Keep last 50 locally
                if chatMessages.count > 50 {
                    chatMessages.removeFirst(chatMessages.count - 50)
                }
            }
        }
    }

    private func handleDisconnect(_: Error?) {
        guard isInSession else {
            connectionState = .disconnected
            return
        }

        connectionState = .reconnecting
        showToast(String(localized: "watchTogether.toast.reconnecting"))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0

            while isInSession {
                let delay = min(16.0, pow(2.0, Double(attempt)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                do {
                    try await client.connect()
                    connectionState = .connected
                    let targetCode = code.isEmpty ? joinCode : code
                    if !targetCode.isEmpty, let identity = makeIdentityPayload(code: targetCode) {
                        await sendMessage(.joinSession(identity))
                    }
                    return
                } catch {
                    attempt += 1
                }
            }
        }
    }

    private func apply(snapshot: WatchTogetherLobbySnapshot) {
        let previousParticipantsById = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })
        let previousHostId = lastKnownHostId
        let wasStarted = isSessionStarted

        code = snapshot.code
        role = snapshot.hostId == currentParticipantId ? .host : .guest
        participants = snapshot.participants
        selectedMedia = snapshot.selectedMedia
        isSessionStarted = snapshot.started
        // Only enable playback sync for VOD, not live TV
        playbackSyncEngine.setEnabled(snapshot.started && snapshot.liveTVChannel == nil)

        readyMap = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.isReady) })
        mediaAccessMap = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.hasMediaAccess) })
        lastKnownHostId = snapshot.hostId

        let participantIds = Set(snapshot.participants.map(\.id))
        let departedParticipants = previousParticipantsById.values.filter { !participantIds.contains($0.id) }
        for participant in departedParticipants where participant.id != currentParticipantId {
            showToast(String(localized: "watchTogether.toast.left \(participant.displayName)"))
        }

        if let previousHostId, previousHostId != snapshot.hostId,
           let newHost = snapshot.participants.first(where: { $0.id == snapshot.hostId })
        {
            showToast(String(localized: "watchTogether.toast.newHost \(newHost.displayName)"))
        }

        handleSelectedMediaChange(snapshot.selectedMedia)

        let previousLiveTVChannel = selectedLiveTVChannel
        selectedLiveTVChannel = snapshot.liveTVChannel

        // Auto-report media access for live TV (all participants on same server can tune)
        if snapshot.liveTVChannel != nil, previousLiveTVChannel?.channelId != snapshot.liveTVChannel?.channelId {
            Task {
                await sendMessage(.mediaAccess(MediaAccessRequest(hasAccess: true)))
            }
        }

        if let serverMessages = snapshot.chatMessages {
            chatMessages = serverMessages
        }

        // Late-join: session is playing but we weren't in playback yet
        if snapshot.started, !wasStarted {
            if let channel = snapshot.liveTVChannel {
                Task {
                    await tuneLiveTV(channelId: channel.channelId, channelName: channel.channelName)
                }
            } else if let media = snapshot.selectedMedia {
                handleLateJoinPlayback(
                    media: media,
                    positionSeconds: snapshot.currentPositionSeconds,
                    isPaused: snapshot.isPaused ?? false,
                )
            }
        }
    }

    private func handleSelectedMediaChange(_ media: WatchTogetherSelectedMedia?) {
        guard let media else {
            lastMediaAccessRatingKey = nil
            return
        }

        guard media.ratingKey != lastMediaAccessRatingKey else { return }
        lastMediaAccessRatingKey = media.ratingKey

        Task {
            let hasAccess = await verifyMediaAccess(for: media)
            await sendMessage(.mediaAccess(MediaAccessRequest(hasAccess: hasAccess)))
            if !hasAccess {
                showToast(String(localized: "watchTogether.toast.noAccess"))
            }
        }
    }

    private func updateParticipant(_ participant: WatchTogetherParticipant) {
        if let index = participants.firstIndex(where: { $0.id == participant.id }) {
            participants[index] = participant
        } else {
            participants.append(participant)
        }

        readyMap[participant.id] = participant.isReady
        mediaAccessMap[participant.id] = participant.hasMediaAccess
    }

    private func handleSessionEnded(reason: String?) {
        if let reason {
            showToast(reason)
        } else {
            showToast(String(localized: "watchTogether.toast.ended"))
        }

        sessionEndedSignal = UUID()
        client.disconnect()
        resetSessionState(clearJoinCode: false)
    }

    private func handlePlaybackStopped(_ payload: PlaybackStopped) {
        isSessionStarted = false
        playbackSyncEngine.setEnabled(false)
        playbackStoppedSignal = UUID()
        let reason = payload.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty {
            showToast(reason)
            return
        }

        showToast(String(localized: "watchTogether.toast.playbackStopped"))
    }

    private func serverErrorMessage(for payload: WatchTogetherServerError) -> String {
        if payload.code == "unsupported_protocol_version" {
            return String(localized: "watchTogether.error.updateRequired")
        }

        if payload.code == "not_enough_participants" {
            return String(localized: "watchTogether.error.minimumParticipants")
        }

        return payload.message
    }

    private func shouldDisconnectAfterError(_ payload: WatchTogetherServerError) -> Bool {
        payload.code == "unsupported_protocol_version" || !isInSession
    }

    private func resetSessionState(clearJoinCode: Bool) {
        reconnectTask?.cancel()
        connectionState = .disconnected
        role = .none
        code = ""
        if clearJoinCode {
            joinCode = ""
        }
        participants = []
        selectedMedia = nil
        readyMap = [:]
        mediaAccessMap = [:]
        errorMessage = nil
        isSessionStarted = false
        participantId = nil
        playbackSyncEngine.setEnabled(false)
        lastMediaAccessRatingKey = nil
        lastKnownHostId = nil
        pendingLateJoinSeek = nil
        pendingLateJoinPaused = false
        chatMessages = []
        chatInput = ""
        selectedLiveTVChannel = nil
    }

    private func verifyMediaAccess(for media: WatchTogetherSelectedMedia) async -> Bool {
        do {
            let repository = try MetadataRepository(context: context)
            let container = try await repository.getMetadata(
                ratingKey: media.ratingKey,
                params: MetadataRepository.PlexMetadataParams(checkFiles: true),
            )
            return !(container.mediaContainer.metadata?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    private func handleStartPlayback(_ payload: WatchTogetherStartPlayback) {
        isSessionStarted = true

        Task {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let delayMs = max(0, payload.startAtEpochMs - nowMs)
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }

            if let channel = selectedLiveTVChannel {
                await tuneLiveTV(channelId: channel.channelId, channelName: channel.channelName)
            } else {
                playbackSyncEngine.setEnabled(true)

                guard let playbackLauncher else {
                    showToast(String(localized: "watchTogether.error.playbackLauncher"))
                    return
                }

                await playbackLauncher.play(
                    ratingKey: payload.ratingKey,
                    type: payload.type,
                    shouldResumeFromOffset: false,
                )
            }
        }
    }

    private func handleLateJoinPlayback(
        media: WatchTogetherSelectedMedia,
        positionSeconds: Double?,
        isPaused: Bool,
    ) {
        if let positionSeconds {
            pendingLateJoinSeek = positionSeconds
            pendingLateJoinPaused = isPaused
        }

        Task {
            guard let playbackLauncher else {
                showToast(String(localized: "watchTogether.error.playbackLauncher"))
                return
            }

            await playbackLauncher.play(
                ratingKey: media.ratingKey,
                type: media.type,
                shouldResumeFromOffset: false,
            )
        }
    }

    private func tuneLiveTV(channelId: String, channelName: String) async {
        guard let showLiveTVPlayer else {
            showToast(String(localized: "watchTogether.error.playbackLauncher"))
            return
        }

        do {
            let repo = try LiveTVRepository(context: context)
            let dvrResponse = try await repo.getDVRs()
            guard let dvr = dvrResponse.mediaContainer.dvr?.first else {
                showToast("No DVR configured on this server")
                return
            }

            let response = try await repo.tuneChannel(dvrKey: dvr.key, channelIdentifier: channelId)
            guard let sessionPath = response.sessionPath else {
                showToast("Failed to tune channel")
                return
            }

            let clientSession = UUID().uuidString
            try await repo.startLiveTVSession(sessionPath: sessionPath, session: clientSession)
            guard let url = repo.liveTVStreamURL(sessionPath: sessionPath, session: clientSession) else {
                showToast("Failed to build stream URL")
                return
            }

            showLiveTVPlayer(url, channelName)
        } catch {
            showToast("Failed to tune live TV")
        }
    }

    private func makeIdentityPayload() -> CreateSessionRequest? {
        guard let plexServerId, let participantId = currentUserId, let displayName = currentDisplayName else {
            showToast(String(localized: "watchTogether.error.identity"))
            return nil
        }

        return CreateSessionRequest(
            plexServerId: plexServerId,
            participantId: participantId,
            displayName: displayName,
        )
    }

    private func makeIdentityPayload(code: String) -> JoinSessionRequest? {
        guard let plexServerId, let participantId = currentUserId, let displayName = currentDisplayName else {
            showToast(String(localized: "watchTogether.error.identity"))
            return nil
        }

        return JoinSessionRequest(
            code: code,
            plexServerId: plexServerId,
            participantId: participantId,
            displayName: displayName,
        )
    }

    private func showToast(_ message: String) {
        let toast = ToastMessage(title: message)
        toasts.append(toast)
        scheduleToastRemoval(id: toast.id)
    }

    private func scheduleToastRemoval(id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.toasts.removeAll { $0.id == id }
            }
        }
    }
}
