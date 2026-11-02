import 'dart:async';

import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:tele_flutter/tele_flutter.dart';

/// An in-memory [CallEngine]: tests set its state and push events.
class FakeEngine implements CallEngine {
  final _events = StreamController<CallEngineEvent>.broadcast(sync: true);
  final calls = <String>[];
  final sent = <String>[];
  final joins = <TeleJoinResponse>[];

  TeleConnectionState state = TeleConnectionState.disconnected;
  List<CallParticipant> remotes = [];
  List<String> speakers = [];
  bool recording = false;
  bool mic = false;
  bool cam = false;
  bool screen = false;
  bool speaker = true;
  bool previewOn = false;
  Object? connectError;
  Object? previewError;
  Object? micError;
  int _stream = 0;
  String localName = 'Me';
  String localUserId = 'me';

  void emit(CallEngineEvent e) => _events.add(e);

  CallParticipant get local => CallParticipant(
        identity: 'u:me',
        name: localName,
        userId: localUserId,
        isLocal: true,
        microphoneEnabled: mic,
        cameraEnabled: cam,
        hasScreenShare: screen,
      );

  /// Adds a remote participant and announces it.
  void join(String who, {bool screenShare = false, bool speaking = false}) {
    remotes = [...remotes, remote(who, screenShare: screenShare, speaking: speaking)];
    emit(CallEngineParticipantJoined('u:$who', who));
  }

  static CallParticipant remote(String who, {bool screenShare = false, bool speaking = false}) => CallParticipant(
        identity: 'u:$who',
        name: who,
        userId: who,
        isLocal: false,
        isSpeaking: speaking,
        microphoneEnabled: true,
        cameraEnabled: true,
        hasScreenShare: screenShare,
      );

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  TeleConnectionState get connectionState => state;

  @override
  List<CallParticipant> get participants => state == TeleConnectionState.disconnected ? const [] : [local, ...remotes];

  @override
  List<String> get activeSpeakers => speakers;

  @override
  bool get isRecording => recording;

  @override
  bool get microphoneEnabled => mic;

  @override
  bool get cameraEnabled => cam;

  @override
  bool get screenShareEnabled => screen;

  @override
  bool get speakerphoneOn => speaker;

  @override
  bool canSelectAudioOutput = true;

  @override
  bool canFlipCamera = true;

  @override
  bool canShareScreen = true;

  @override
  VideoTrack? get previewTrack => null;

  @override
  Future<void> setPreviewCamera(bool on) async {
    calls.add('preview:$on');
    if (on && previewError != null) throw previewError!;
    previewOn = on;
  }

  List<TeleMediaDevice> deviceList = const [
    TeleMediaDevice(id: 'm1', label: 'Built-in Mic', kind: TeleMediaKind.audioInput, selected: true),
    TeleMediaDevice(id: 'm2', label: 'USB Mic', kind: TeleMediaKind.audioInput),
    TeleMediaDevice(id: 'v1', label: 'FaceTime', kind: TeleMediaKind.videoInput, selected: true),
  ];

  @override
  Future<List<TeleMediaDevice>> devices() async => deviceList;

  @override
  Future<void> selectDevice(TeleMediaDevice device) async => calls.add('select:${device.id}');

  @override
  Future<void> connect(TeleJoinResponse join, {required bool microphone, required bool camera}) async {
    calls.add('connect:mic=$microphone,cam=$camera');
    joins.add(join);
    if (connectError != null) throw connectError!;
    state = TeleConnectionState.connected;
    mic = microphone;
    cam = camera;
    previewOn = false;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    state = TeleConnectionState.disconnected;
  }

  @override
  Future<void> setMicrophone(bool on) async {
    calls.add('mic:$on');
    if (micError != null) throw micError!;
    mic = on;
  }

  @override
  Future<void> setCamera(bool on) async {
    calls.add('cam:$on');
    cam = on;
  }

  @override
  Future<void> setScreenShare(bool on) async {
    calls.add('screen:$on');
    screen = on;
  }

  @override
  Future<void> flipCamera() async => calls.add('flip');

  @override
  Future<void> setSpeakerphone(bool on) async {
    calls.add('speaker:$on');
    speaker = on;
  }

  @override
  Future<String> sendChat(String text) async {
    sent.add(text);
    return 'TS_local_${++_stream}';
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _events.close();
  }
}
