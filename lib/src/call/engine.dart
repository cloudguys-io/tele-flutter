import 'package:livekit_client/livekit_client.dart' show VideoTrack;

import '../api/models.dart';

/// The media connection as [TeleCallController] sees it. [LiveKitCallEngine] is the real one; tests
/// use a fake. Everything LiveKit-specific stays behind this interface except [VideoTrack], which the
/// call screen hands to `VideoTrackRenderer`.
///
/// **Experimental:** this interface may gain members in minor releases. Implement it for tests; for
/// production use [LiveKitCallEngine].
abstract class CallEngine {
  /// Room events. A broadcast stream that stays open across [connect] calls.
  Stream<CallEngineEvent> get events;

  TeleConnectionState get connectionState;

  /// Everyone in the room, the local participant first. Empty before [connect].
  List<CallParticipant> get participants;

  /// Identities of the current active speakers, loudest first.
  List<String> get activeSpeakers;

  /// Whether the room is being recorded (as the media server reports it).
  bool get isRecording;

  bool get microphoneEnabled;
  bool get cameraEnabled;
  bool get screenShareEnabled;
  bool get speakerphoneOn;

  /// Whether this platform can choose audio outputs, flip cameras, share the screen.
  bool get canSelectAudioOutput;
  bool get canFlipCamera;
  bool get canShareScreen;

  /// False when the browser blocked autoplay; call [startAudio] from a user gesture.
  bool get canPlaybackAudio;

  /// Starts audio playback after a user gesture (web autoplay policy).
  Future<void> startAudio();

  /// The lobby's camera preview, before connecting.
  VideoTrack? get previewTrack;

  /// Opens (or closes) the lobby camera preview. Throws when the camera can't be opened.
  Future<void> setPreviewCamera(bool on);

  /// Microphones, cameras and audio outputs.
  Future<List<TeleMediaDevice>> devices();

  /// Uses [device] for capture or playback, now and for tracks created later.
  Future<void> selectDevice(TeleMediaDevice device);

  /// Connects with a join response. Media is published after connecting, as requested; failures
  /// to publish are reported as [CallEngineMediaError] events instead of failing the connect.
  /// A [disconnect] while connecting cancels it: the call returns without a connected room.
  Future<void> connect(TeleJoinResponse join, {required bool microphone, required bool camera});

  /// Leaves the room. Emits no [CallEngineDisconnected] for this disconnect.
  Future<void> disconnect();

  Future<void> setMicrophone(bool on);
  Future<void> setCamera(bool on);
  Future<void> setScreenShare(bool on);
  Future<void> flipCamera();
  Future<void> setSpeakerphone(bool on);

  /// Sends [text] on the `lk.chat` text stream topic and returns the stream id.
  Future<String> sendChat(String text);

  /// Releases everything, including the preview.
  Future<void> dispose();
}

enum TeleConnectionState { disconnected, connecting, connected, reconnecting }

enum TeleMediaKind { audioInput, videoInput, audioOutput }

class TeleMediaDevice {
  const TeleMediaDevice({required this.id, required this.label, required this.kind, this.selected = false});
  final String id;
  final String label;
  final TeleMediaKind kind;
  final bool selected;

  @override
  bool operator ==(Object other) => other is TeleMediaDevice && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

/// A snapshot of one participant.
class CallParticipant {
  const CallParticipant({
    required this.identity,
    required this.name,
    required this.userId,
    required this.isLocal,
    this.isSpeaking = false,
    this.microphoneEnabled = false,
    this.cameraEnabled = false,
    this.cameraTrack,
    this.screenShareTrack,
    this.hasScreenShare = false,
  });

  /// The media identity (`u:<uuid>`). Map it back to your user with [userId].
  final String identity;

  /// The display name, or the user id when none was set.
  final String name;

  /// The participant attribute `user_id`: your user id.
  final String userId;
  final bool isLocal;
  final bool isSpeaking;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final VideoTrack? cameraTrack;
  final VideoTrack? screenShareTrack;

  /// Set when a screen share can be shown: for others, once its track is subscribed.
  final bool hasScreenShare;
}

/// Why the media connection ended. The engine maps the SDK's reasons onto these.
enum CallDisconnectCause {
  /// The call ended or was cancelled (the room was deleted).
  roomDeleted,

  /// The same user joined from another device.
  duplicateIdentity,

  /// A host or the backend removed this participant.
  removed,

  /// The client couldn't connect fully.
  joinFailure,

  /// The SDK gave up reconnecting (long outage, expired TURN credentials). A fresh join can recover.
  connectionLost,
}

sealed class CallEngineEvent {
  const CallEngineEvent();
}

/// Something in the room changed (tracks, mutes, speakers, names): re-read the snapshots.
class CallEngineChanged extends CallEngineEvent {
  const CallEngineChanged();
}

class CallEngineParticipantJoined extends CallEngineEvent {
  const CallEngineParticipantJoined(this.identity, this.name);
  final String identity;
  final String name;
}

class CallEngineParticipantLeft extends CallEngineEvent {
  const CallEngineParticipantLeft(this.identity, this.name);
  final String identity;
  final String name;
}

class CallEngineReconnecting extends CallEngineEvent {
  const CallEngineReconnecting();
}

class CallEngineReconnected extends CallEngineEvent {
  const CallEngineReconnected();
}

class CallEngineDisconnected extends CallEngineEvent {
  const CallEngineDisconnected(this.cause);
  final CallDisconnectCause cause;
}

class CallEngineRecordingChanged extends CallEngineEvent {
  const CallEngineRecordingChanged(this.recording);
  final bool recording;
}

/// A message on `lk.chat` from someone else.
class CallEngineChat extends CallEngineEvent {
  const CallEngineChat({required this.streamId, required this.identity, required this.body});
  final String streamId;
  final String identity;
  final String body;
}

/// Whether audio can play (web autoplay policy).
class CallEngineAudioPlayback extends CallEngineEvent {
  const CallEngineAudioPlayback(this.canPlay);
  final bool canPlay;
}

/// The list of microphones, cameras or speakers changed (or became readable after a permission).
class CallEngineDevicesChanged extends CallEngineEvent {
  const CallEngineDevicesChanged();
}

enum CallMediaSource { microphone, camera }

/// A device that couldn't be published after connecting.
class CallEngineMediaError extends CallEngineEvent {
  const CallEngineMediaError(this.source, this.error);
  final CallMediaSource source;
  final Object error;
}
