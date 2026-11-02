import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../api/models.dart';
import 'engine.dart';

/// The chat topic every Tele client uses, so web, Flutter and mobile apps can talk to each other.
const teleChatTopic = 'lk.chat';

/// Maps the join response's `ice_servers` into the SDK's RTC configuration.
///
/// Tele's TURN servers replace the SDK defaults and are passed as is (they already include STUN).
/// When `ice_servers` is null, no servers are passed and the SDK uses its defaults.
RTCConfiguration rtcConfigurationFor(TeleJoinResponse join) {
  final ice = join.iceServers
      ?.map((s) => RTCIceServer(urls: s.urls, username: s.username, credential: s.credential))
      .toList();
  return ice == null ? const RTCConfiguration() : RTCConfiguration(iceServers: ice);
}

/// Maps the SDK's disconnect reason onto what the call screen shows. Returns null for a disconnect
/// this client asked for.
CallDisconnectCause? disconnectCauseOf(DisconnectReason? reason) => switch (reason) {
      DisconnectReason.clientInitiated => null,
      DisconnectReason.roomDeleted => CallDisconnectCause.roomDeleted,
      DisconnectReason.duplicateIdentity => CallDisconnectCause.duplicateIdentity,
      DisconnectReason.participantRemoved => CallDisconnectCause.removed,
      DisconnectReason.joinFailure => CallDisconnectCause.joinFailure,
      _ => CallDisconnectCause.connectionLost,
    };

bool get _isMobile =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

/// [CallEngine] on `livekit_client`. Each [connect] builds a new [Room], so a rejoin starts clean.
class LiveKitCallEngine implements CallEngine {
  LiveKitCallEngine({this.roomOptions = const RoomOptions(adaptiveStream: true, dynacast: true)});

  /// The base room options. Selected devices are layered on top.
  final RoomOptions roomOptions;

  final _events = StreamController<CallEngineEvent>.broadcast();
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LocalVideoTrack? _preview;
  String? _audioInputId;
  String? _videoInputId;
  CameraPosition _position = CameraPosition.front;
  bool _speakerphone = true;
  bool _leaving = false;
  bool _previewWanted = false;

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  TeleConnectionState get connectionState => switch (_room?.connectionState) {
        ConnectionState.connected => TeleConnectionState.connected,
        ConnectionState.connecting => TeleConnectionState.connecting,
        ConnectionState.reconnecting => TeleConnectionState.reconnecting,
        _ => TeleConnectionState.disconnected,
      };

  @override
  List<CallParticipant> get participants {
    final room = _room;
    final lp = room?.localParticipant;
    if (room == null || lp == null) return const [];
    return [_snapshot(lp, true), for (final p in room.remoteParticipants.values) _snapshot(p, false)];
  }

  CallParticipant _snapshot(Participant p, bool local) {
    VideoTrack? video(TrackSource s) {
      final pub = p.getTrackPublicationBySource(s);
      final t = pub?.track;
      return pub != null && !pub.muted && t is VideoTrack ? t : null;
    }

    return CallParticipant(
      identity: p.identity,
      name: p.name.isNotEmpty ? p.name : (p.attributes['user_id'] ?? p.identity),
      userId: p.attributes['user_id'] ?? p.identity,
      isLocal: local,
      isSpeaking: p.isSpeaking,
      microphoneEnabled: p.isMicrophoneEnabled(),
      cameraEnabled: p.isCameraEnabled(),
      cameraTrack: video(TrackSource.camera),
      screenShareTrack: video(TrackSource.screenShareVideo),
      hasScreenShare: p.isScreenShareEnabled(),
    );
  }

  @override
  List<String> get activeSpeakers => [for (final p in _room?.activeSpeakers ?? const <Participant>[]) p.identity];

  @override
  bool get isRecording => _room?.isRecording ?? false;

  @override
  bool get microphoneEnabled => _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  @override
  bool get cameraEnabled => _room?.localParticipant?.isCameraEnabled() ?? false;

  @override
  bool get screenShareEnabled => _room?.localParticipant?.isScreenShareEnabled() ?? false;

  @override
  bool get speakerphoneOn => _speakerphone;

  @override
  bool get canSelectAudioOutput => !_isMobile;

  @override
  bool get canFlipCamera => _isMobile;

  // Mobile screen sharing needs a broadcast extension (iOS) or a foreground service (Android) in the app.
  @override
  bool get canShareScreen => !_isMobile;

  @override
  VideoTrack? get previewTrack => _preview;

  CameraCaptureOptions get _cameraOptions => CameraCaptureOptions(deviceId: _videoInputId, cameraPosition: _position);

  @override
  Future<void> setPreviewCamera(bool on) async {
    _previewWanted = on;
    if (!on) {
      final t = _preview;
      _preview = null;
      await t?.stop();
      return;
    }
    if (_preview != null) return;
    final track = await LocalVideoTrack.createCameraTrack(_cameraOptions);
    // The camera may have been turned off, or the call joined, while the permission prompt was open.
    if (!_previewWanted || _preview != null || _room != null) {
      await track.stop();
      return;
    }
    _preview = track;
    _emit(const CallEngineChanged());
  }

  @override
  Future<List<TeleMediaDevice>> devices() async {
    final all = await Hardware.instance.enumerateDevices();
    final hw = Hardware.instance;
    TeleMediaKind? kind(String k) => switch (k) {
          'audioinput' => TeleMediaKind.audioInput,
          'videoinput' => TeleMediaKind.videoInput,
          'audiooutput' => TeleMediaKind.audioOutput,
          _ => null,
        };
    String? selected(TeleMediaKind k) => switch (k) {
          TeleMediaKind.audioInput => _audioInputId ?? hw.selectedAudioInput?.deviceId,
          TeleMediaKind.videoInput => _videoInputId ?? hw.selectedVideoInput?.deviceId,
          TeleMediaKind.audioOutput => hw.selectedAudioOutput?.deviceId,
        };
    return [
      for (final d in all)
        if (kind(d.kind) case final k?)
          TeleMediaDevice(id: d.deviceId, label: d.label, kind: k, selected: d.deviceId == selected(k)),
    ];
  }

  @override
  Future<void> selectDevice(TeleMediaDevice device) async {
    final md = MediaDevice(device.id, device.label, switch (device.kind) {
      TeleMediaKind.audioInput => 'audioinput',
      TeleMediaKind.videoInput => 'videoinput',
      TeleMediaKind.audioOutput => 'audiooutput',
    }, null);
    final room = _room;
    switch (device.kind) {
      case TeleMediaKind.audioInput:
        _audioInputId = device.id;
        await (room != null ? room.setAudioInputDevice(md) : Hardware.instance.selectAudioInput(md));
      case TeleMediaKind.videoInput:
        _videoInputId = device.id;
        if (room != null) {
          await room.setVideoInputDevice(md);
        } else if (_preview != null) {
          await _preview!.switchCamera(device.id);
        }
      case TeleMediaKind.audioOutput:
        await (room != null ? room.setAudioOutputDevice(md) : Hardware.instance.selectAudioOutput(md));
    }
    _emit(const CallEngineChanged());
  }

  @override
  Future<void> connect(TeleJoinResponse join, {required bool microphone, required bool camera}) async {
    await _closeRoom();
    _leaving = false;
    final room = Room(
      roomOptions: roomOptions.copyWith(
        defaultCameraCaptureOptions: _cameraOptions,
        defaultAudioCaptureOptions: AudioCaptureOptions(deviceId: _audioInputId),
      ),
    );
    _room = room;
    _listen(room);
    try {
      await room.connect(join.wsUrl, join.token, connectOptions: ConnectOptions(rtcConfiguration: rtcConfigurationFor(join)));
    } catch (_) {
      await _closeRoom();
      rethrow;
    }
    if (_isMobile) await AudioManager.instance.setSpeakerOutputPreferred(_speakerphone).catchError((_) {});

    final lp = room.localParticipant!;
    if (microphone) {
      await lp.setMicrophoneEnabled(true).then<void>((_) {}, onError: (Object e) {
        _emit(CallEngineMediaError(CallMediaSource.microphone, e));
      });
    }
    final preview = _preview;
    _preview = null;
    if (camera) {
      // Publish the lobby's preview track so the camera isn't opened twice.
      final publish = preview != null ? lp.publishVideoTrack(preview) : lp.setCameraEnabled(true);
      await publish.then<void>((_) {}, onError: (Object e) {
        _emit(CallEngineMediaError(CallMediaSource.camera, e));
      });
    } else {
      await preview?.stop();
    }
    _emit(const CallEngineChanged());
  }

  void _listen(Room room) {
    void changed(Object _) => _emit(const CallEngineChanged());
    final l = room.createListener()
      ..on<ParticipantConnectedEvent>((e) => _emit(CallEngineParticipantJoined(e.participant.identity, _name(e.participant))))
      ..on<ParticipantDisconnectedEvent>((e) => _emit(CallEngineParticipantLeft(e.participant.identity, _name(e.participant))))
      ..on<TrackSubscribedEvent>(changed)
      ..on<TrackUnsubscribedEvent>(changed)
      ..on<TrackPublishedEvent>(changed)
      ..on<TrackUnpublishedEvent>(changed)
      ..on<TrackMutedEvent>(changed)
      ..on<TrackUnmutedEvent>(changed)
      ..on<LocalTrackPublishedEvent>(changed)
      ..on<LocalTrackUnpublishedEvent>(changed)
      ..on<ActiveSpeakersChangedEvent>(changed)
      ..on<ParticipantNameUpdatedEvent>(changed)
      ..on<ParticipantAttributesChanged>(changed)
      ..on<RoomRecordingStatusChanged>((e) => _emit(CallEngineRecordingChanged(e.activeRecording)))
      ..on<RoomReconnectingEvent>((_) => _emit(const CallEngineReconnecting()))
      ..on<RoomReconnectedEvent>((_) => _emit(const CallEngineReconnected()))
      ..on<RoomDisconnectedEvent>((e) {
        if (_leaving || room != _room) return;
        final cause = disconnectCauseOf(e.reason);
        if (cause != null) _emit(CallEngineDisconnected(cause));
      });
    _listener = l;
    room.registerTextStreamHandler(teleChatTopic, (TextStreamReader reader, String identity) async {
      final body = await reader.readAll();
      final id = reader.info?.id;
      if (id == null || room != _room) return;
      _emit(CallEngineChat(streamId: id, identity: identity, body: body));
    });
  }

  static String _name(Participant p) => p.name.isNotEmpty ? p.name : (p.attributes['user_id'] ?? p.identity);

  void _emit(CallEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _closeRoom() async {
    final room = _room;
    if (room == null) return;
    _leaving = true;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    room.unregisterTextStreamHandler(teleChatTopic);
    await room.disconnect().catchError((_) {});
    await room.dispose();
  }

  @override
  Future<void> disconnect() => _closeRoom();

  LocalParticipant get _lp {
    final lp = _room?.localParticipant;
    if (lp == null) throw StateError('not connected');
    return lp;
  }

  @override
  Future<void> setMicrophone(bool on) async {
    await _lp.setMicrophoneEnabled(on);
    _emit(const CallEngineChanged());
  }

  @override
  Future<void> setCamera(bool on) async {
    await _lp.setCameraEnabled(on, cameraCaptureOptions: _cameraOptions);
    _emit(const CallEngineChanged());
  }

  @override
  Future<void> setScreenShare(bool on) async {
    await _lp.setScreenShareEnabled(on);
    _emit(const CallEngineChanged());
  }

  @override
  Future<void> flipCamera() async {
    _position = _position.switched();
    final track = _room?.localParticipant?.getTrackPublicationBySource(TrackSource.camera)?.track ?? _preview;
    if (track is LocalVideoTrack) await track.setCameraPosition(_position);
    _emit(const CallEngineChanged());
  }

  @override
  Future<void> setSpeakerphone(bool on) async {
    _speakerphone = on;
    if (_isMobile) await AudioManager.instance.setSpeakerOutputPreferred(on);
    _emit(const CallEngineChanged());
  }

  @override
  Future<String> sendChat(String text) async {
    final info = await _lp.sendText(text, options: SendTextOptions(topic: teleChatTopic));
    return info.id;
  }

  @override
  Future<void> dispose() async {
    await _closeRoom();
    await setPreviewCamera(false);
    await _events.close();
  }
}
