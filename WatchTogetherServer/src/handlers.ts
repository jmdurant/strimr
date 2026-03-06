import { broadcast, sendJson } from './messaging.js';
import loggerBase from './logger.js';
import { MAX_SUPPORTED_PROTOCOL_VERSION, MIN_SUPPORTED_PROTOCOL_VERSION, PROTOCOL_VERSION } from './config.js';
import { MIN_PARTICIPANTS_TO_START_PLAYBACK } from './constants.js';
import {
  addParticipant,
  createSession,
  endSession,
  nowMs,
  removeParticipant,
  sessionForClient,
  snapshotFor,
} from './sessions.js';
import { sessions } from './state.js';
import type { ChatMessage, Client, LiveTVChannel, ProtocolMessage, SelectedMedia, Session } from './types.js';

const logger = loggerBase.child({ module: 'handlers' });

type Payload = Record<string, unknown>;

function asPayload(value: unknown): Payload {
  if (!value || typeof value !== 'object') return {};
  return value as Payload;
}

function getString(payload: Payload, key: string): string | null {
  const value = payload[key];
  return typeof value === 'string' ? value : null;
}

function getNumber(payload: Payload, key: string): number | null {
  const value = payload[key];
  return typeof value === 'number' ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

export function handleMessage(client: Client, message: ProtocolMessage): void {
  if (!message || !message.type) {
    logger.warn({ messageType: message?.type }, 'Unsupported protocol payload');
    sendJson(client, 'error', { message: 'Unsupported protocol payload.', code: 'bad_payload' });
    return;
  }

  const version = typeof message.v === 'number' ? message.v : NaN;
  if (
    !Number.isInteger(version) ||
    version < MIN_SUPPORTED_PROTOCOL_VERSION ||
    version > MAX_SUPPORTED_PROTOCOL_VERSION
  ) {
    logger.warn({ messageType: message.type, version }, 'Unsupported protocol version');
    sendJson(client, 'error', {
      message: 'Incompatible Watch Together protocol version. Please update the app.',
      code: 'unsupported_protocol_version',
      currentVersion: PROTOCOL_VERSION,
      minimumVersion: MIN_SUPPORTED_PROTOCOL_VERSION,
      maximumVersion: MAX_SUPPORTED_PROTOCOL_VERSION,
    });
    return;
  }

  const payload = asPayload(message.payload);

  switch (message.type) {
    case 'createSession':
      handleCreateSession(client, payload);
      break;
    case 'joinSession':
      handleJoinSession(client, payload);
      break;
    case 'leaveSession':
      handleLeaveSession(client, payload);
      break;
    case 'setReady':
      handleSetReady(client, payload);
      break;
    case 'setSelectedMedia':
      handleSetSelectedMedia(client, payload);
      break;
    case 'mediaAccess':
      handleMediaAccess(client, payload);
      break;
    case 'startPlayback':
      handleStartPlayback(client, payload);
      break;
    case 'stopPlayback':
      handleStopPlayback(client, payload);
      break;
    case 'playerEvent':
      handlePlayerEvent(client, payload);
      break;
    case 'chatMessage':
      handleChatMessage(client, payload);
      break;
    case 'setLiveTVChannel':
      handleSetLiveTVChannel(client, payload);
      break;
    case 'ping':
      handlePing(client, payload);
      break;
    default:
      logger.warn({ messageType: message.type }, 'Unknown message type');
      sendJson(client, 'error', { message: 'Unknown message type.', code: 'unknown_type' });
  }
}

function handleCreateSession(client: Client, payload: Payload): void {
  const plexServerId = getString(payload, 'plexServerId');
  const userId = getString(payload, 'participantId');
  const displayName = getString(payload, 'displayName');
  if (!plexServerId || !userId || !displayName) {
    sendJson(client, 'error', { message: 'Missing identity payload.', code: 'missing_identity' });
    return;
  }

  const session = createSession({
    plexServerId,
    hostUserId: userId,
    hostName: displayName,
    client,
  });

  const participantId = session.hostId;

  client.sessionCode = session.code;
  client.participantId = participantId;
  client.userId = userId;
  client.displayName = displayName;
  client.plexServerId = plexServerId;

  logger.info({ code: session.code, hostId: session.hostId, plexServerId, userId }, 'Session created');

  sendJson(client, 'created', { code: session.code, hostId: session.hostId, participantId });
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleJoinSession(client: Client, payload: Payload): void {
  const code = getString(payload, 'code');
  const plexServerId = getString(payload, 'plexServerId');
  const userId = getString(payload, 'participantId');
  const displayName = getString(payload, 'displayName');
  if (!code || !plexServerId || !userId || !displayName) {
    sendJson(client, 'error', { message: 'Missing identity payload.', code: 'missing_identity' });
    return;
  }

  const session = sessions.get(code);
  if (!session) {
    sendJson(client, 'error', { message: 'Session not found.', code: 'not_found' });
    return;
  }

  if (session.plexServerId !== plexServerId) {
    sendJson(client, 'error', { message: 'Server mismatch.', code: 'server_mismatch' });
    return;
  }

  const hasHost = session.participants.some((participant) => participant.isHost);
  const shouldBeHost = session.hostUserId === userId && !hasHost;
  const participant = addParticipant(session, {
    userId,
    displayName,
    isHost: shouldBeHost,
    client,
  });

  if (shouldBeHost) {
    session.hostId = participant.id;
  }

  client.sessionCode = session.code;
  client.participantId = participant.id;
  client.userId = userId;
  client.displayName = displayName;
  client.plexServerId = plexServerId;

  logger.info({ code: session.code, participantId: participant.id, userId }, 'Participant joined');

  sendJson(client, 'joined', { code: session.code, hostId: session.hostId, participantId: participant.id });
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleLeaveSession(client: Client, payload: Payload): void {
  if (!client.sessionCode || !client.participantId) return;
  const session = sessions.get(client.sessionCode);
  if (!session) return;

  const isHost = session.hostId === client.participantId;
  const endForAll = payload.endForAll === true;
  const participantId = client.participantId;

  removeParticipant(session, client.participantId);
  client.sessionCode = null;
  client.participantId = null;

  logger.info({ code: session.code, participantId, endForAll, isHost }, 'Participant left');

  if (endForAll) {
    endSession(session, 'Session ended by host.');
    return;
  }

  if (session.participants.length === 0) {
    sessions.delete(session.code);
    return;
  }

  if (isHost) {
    assignNewHost(session);
  }

  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleSetReady(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session || !client.participantId) return;
  session.readiness.set(client.participantId, payload.isReady === true);
  logger.debug({ code: session.code, participantId: client.participantId }, 'Participant readiness updated');
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleSetSelectedMedia(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, 'error', { message: 'Host only action.', code: 'forbidden' });
    return;
  }

  if (!payload.media) {
    return;
  }

  session.selectedMedia = payload.media as SelectedMedia;
  session.liveTVChannel = null;
  session.started = false;
  session.startAtEpochMs = null;
  session.currentPositionSeconds = null;
  session.lastPositionUpdatedAt = null;
  session.isPaused = false;
  session.mediaAccess = new Map();
  session.participants.forEach((participant) => {
    session.mediaAccess.set(participant.id, false);
  });

  logger.info({ code: session.code, hostId: session.hostId }, 'Selected media updated');

  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleMediaAccess(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session || !client.participantId) return;
  session.mediaAccess.set(client.participantId, payload.hasAccess === true);
  logger.debug({ code: session.code, participantId: client.participantId }, 'Media access updated');
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleStartPlayback(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, 'error', { message: 'Host only action.', code: 'forbidden' });
    return;
  }

  if (session.participants.length < MIN_PARTICIPANTS_TO_START_PLAYBACK) {
    sendJson(client, 'error', {
      message: `At least ${MIN_PARTICIPANTS_TO_START_PLAYBACK} participants are required to start playback.`,
      code: 'not_enough_participants',
    });
    return;
  }

  const ratingKey = getString(payload, 'ratingKey');
  const mediaType = getString(payload, 'type');
  if (!ratingKey || !mediaType) {
    return;
  }

  session.started = true;
  session.startAtEpochMs = nowMs() + 2000;
  session.currentPositionSeconds = 0;
  session.lastPositionUpdatedAt = session.startAtEpochMs;
  session.isPaused = false;

  const startPayload = {
    ratingKey,
    type: mediaType,
    startAtEpochMs: session.startAtEpochMs,
  };

  logger.info({ code: session.code, startAtEpochMs: session.startAtEpochMs }, 'Playback started');

  broadcast(session, 'startPlayback', startPayload);
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handleStopPlayback(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, 'error', { message: 'Host only action.', code: 'forbidden' });
    return;
  }

  session.started = false;
  session.startAtEpochMs = null;
  session.currentPositionSeconds = null;
  session.lastPositionUpdatedAt = null;
  session.isPaused = false;

  const reason = typeof payload.reason === 'string' ? payload.reason : null;
  broadcast(session, 'playbackStopped', { reason });
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handlePlayerEvent(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session || !session.started || !client.participantId) return;

  if (!isRecord(payload.event)) return;

  const eventType = typeof payload.event.type === 'string' ? payload.event.type : 'unknown';
  const now = nowMs();
  const event = {
    ...payload.event,
    senderId: client.participantId,
    serverReceivedAtMs: now,
  };

  // Track playback position from events
  const positionSeconds =
    typeof payload.event.positionSeconds === 'number' ? payload.event.positionSeconds : null;

  switch (eventType) {
    case 'play':
      session.isPaused = false;
      if (positionSeconds != null) {
        session.currentPositionSeconds = positionSeconds;
        session.lastPositionUpdatedAt = now;
      }
      break;
    case 'pause':
      session.isPaused = true;
      if (positionSeconds != null) {
        session.currentPositionSeconds = positionSeconds;
        session.lastPositionUpdatedAt = now;
      }
      break;
    case 'seek':
      if (positionSeconds != null) {
        session.currentPositionSeconds = positionSeconds;
        session.lastPositionUpdatedAt = now;
      }
      break;
  }

  logger.debug({ code: session.code, eventType }, 'Player event received');

  broadcast(session, 'playerEvent', event);
}

function handleChatMessage(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session || !client.participantId) return;

  const text = getString(payload, 'text');
  if (!text || text.trim().length === 0) return;

  const message: ChatMessage = {
    id: `${client.participantId}-${nowMs()}-${Math.random().toString(36).slice(2, 8)}`,
    senderId: client.participantId,
    senderName: client.displayName ?? 'Unknown',
    text: text.trim().slice(0, 500),
    sentAtMs: nowMs(),
  };

  session.chatMessages.push(message);
  // Keep only last 100 messages in memory
  if (session.chatMessages.length > 100) {
    session.chatMessages = session.chatMessages.slice(-100);
  }

  logger.debug({ code: session.code, senderId: client.participantId }, 'Chat message');

  broadcast(session, 'chatMessage', message);
}

function handleSetLiveTVChannel(client: Client, payload: Payload): void {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, 'error', { message: 'Host only action.', code: 'forbidden' });
    return;
  }

  const channelId = getString(payload, 'channelId');
  const channelName = getString(payload, 'channelName');
  if (!channelId || !channelName) return;

  const thumb = getString(payload, 'thumb');

  session.liveTVChannel = { channelId, channelName, thumb };
  // Clear regular media when live TV is selected
  session.selectedMedia = null;
  session.started = false;
  session.startAtEpochMs = null;
  session.currentPositionSeconds = null;
  session.lastPositionUpdatedAt = null;
  session.isPaused = false;
  session.mediaAccess = new Map();
  session.participants.forEach((participant) => {
    session.mediaAccess.set(participant.id, false);
  });

  logger.info({ code: session.code, channelId, channelName }, 'Live TV channel set');

  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function handlePing(client: Client, payload: Payload): void {
  const sentAtMs = getNumber(payload, 'sentAtMs') ?? 0;
  sendJson(client, 'pong', {
    sentAtMs,
    receivedAtMs: nowMs(),
  });
}

export function handleClientDisconnect(client: Client): void {
  if (!client.sessionCode || !client.participantId) return;
  const session = sessions.get(client.sessionCode);
  if (!session) return;

  const isHost = session.hostId === client.participantId;
  const participantId = client.participantId;

  removeParticipant(session, participantId);

  if (session.participants.length === 0) {
    logger.info({ code: session.code }, 'Session empty after disconnect; removing');
    sessions.delete(session.code);
    return;
  }

  if (isHost) {
    logger.info({ code: session.code, participantId }, 'Host disconnected; reassigning host');
    assignNewHost(session);
  }

  logger.info({ code: session.code, participantId }, 'Participant disconnected');
  broadcast(session, 'lobbySnapshot', snapshotFor(session));
}

function assignNewHost(session: Session): void {
  session.participants.forEach((participant) => {
    participant.isHost = false;
  });

  const nextHost = session.participants[0];
  if (!nextHost) return;

  nextHost.isHost = true;
  session.hostId = nextHost.id;
  session.hostUserId = nextHost.userId;
}
