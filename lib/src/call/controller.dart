import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/exception.dart';
import '../api/models.dart';
import '../ui/strings.dart';
import 'engine.dart';
import 'livekit_engine.dart';
import 'stage.dart';

/// Where the call screen is:
///
///     lobby --join--> joining --connected--> live --disconnected--> ended
///                       |
///                       +--failed--> error            any --leave--> left
enum TeleCallPhase { lobby, joining, live, ended, error, left }

/// Why the local user is no longer in the call.
enum TeleEndReason { left, roomDeleted, duplicateIdentity, removed, joinFailure, disconnected, error }

/// A chat message on the screen. [id] is the text stream id, which is also the saved message's
/// `stream_id`, so live messages and history are deduplicated on it.
class TeleChatEntry {
  const TeleChatEntry({
    required this.id,
    required this.userId,
    required this.name,
    required this.body,
    required this.mine,
    required this.sentAt,
  });
  final String id;
  final String userId;
  final String name;
  final String body;
  final bool mine;
  final DateTime sentAt;
}

/// A one-line banner shown while live.
class TeleNotice {
  const TeleNotice(this.key, [this.vars = const {}]);
  final TeleStringKey key;
  final Map<String, Object> vars;
}

sealed class TeleCallEvent {
  const TeleCallEvent();
}

class TeleCallJoined extends TeleCallEvent {
  const TeleCallJoined(this.join);
  final TeleJoinResponse join;
}

class TeleParticipantJoined extends TeleCallEvent {
  const TeleParticipantJoined({required this.identity, required this.name, required this.count});
  final String identity;
  final String name;

  /// People in the call now, including you.
  final int count;
}

class TeleParticipantLeft extends TeleCallEvent {
  const TeleParticipantLeft({required this.identity, required this.name, required this.count});
  final String identity;
  final String name;
  final int count;
}

/// A new chat message (not history), for unread badges outside the screen.
class TeleChatReceived extends TeleCallEvent {
  const TeleChatReceived(this.message);
  final TeleChatEntry message;
}

/// The user left, or closed the ended or error screen.
class TeleCallLeft extends TeleCallEvent {
  const TeleCallLeft(this.reason);
  final TeleEndReason reason;
}

/// Joining failed. [error] is usually a [TeleException].
class TeleCallFailed extends TeleCallEvent {
  const TeleCallFailed(this.error);
  final Object error;
  String? get code => error is TeleException ? (error as TeleException).code : null;
}

/// Runs one call: lobby, connect, media toggles, stage, chat, recording, reconnects.
///
/// [join] returns a join response, from [TeleClient.joinInvite], [TeleClient.joinCall] or your
/// backend. It is called again for a fresh join when the media SDK gives up reconnecting.
/// [client] is optional: with it the controller loads chat history, saves sent messages, and lets
/// hosts record and end the call.
class TeleCallController extends ChangeNotifier {
  TeleCallController({
    required Future<TeleJoinResponse> Function() join,
    this.client,
    CallEngine? engine,
    TeleLayout layout = TeleLayout.grid,
    this.persistChat = true,
    this.loadChatHistory = true,
    this.maxRejoinAttempts = 2,
    this.rejoinDelay = const Duration(seconds: 1),
    Future<void> Function()? endForAll,
    Future<void> Function(bool on)? setRecording,
    bool microphone = true,
    bool camera = true,
  })  : _joiner = join,
        _engine = engine ?? LiveKitCallEngine(),
        _layout = layout,
        _endForAll = endForAll,
        _setRecording = setRecording,
        _micWanted = microphone,
        _camWanted = camera {
    _sub = _engine.events.listen(_onEngine);
  }

  /// Joins through an invite code.
  factory TeleCallController.invite(TeleClient client, String code, {CallEngine? engine, TeleLayout layout = TeleLayout.grid}) =>
      TeleCallController(join: () => client.joinInvite(code), client: client, engine: engine, layout: layout);

  /// Joins a call the user is a member of.
  factory TeleCallController.call(TeleClient client, String callId, {CallEngine? engine, TeleLayout layout = TeleLayout.grid}) =>
      TeleCallController(join: () => client.joinCall(callId), client: client, engine: engine, layout: layout);

  final TeleClient? client;

  /// Also `POST` each sent message to Tele (deduplicated by stream id). Needs [client].
  final bool persistChat;

  /// Load saved messages after connecting, so latecomers see earlier chat. Needs [client].
  final bool loadChatHistory;

  /// Fresh joins to try when the SDK gives up reconnecting, before showing "You were disconnected".
  final int maxRejoinAttempts;
  final Duration rejoinDelay;

  final Future<TeleJoinResponse> Function() _joiner;
  final CallEngine _engine;
  final Future<void> Function()? _endForAll;
  final Future<void> Function(bool on)? _setRecording;
  late final StreamSubscription<CallEngineEvent> _sub;
  final _events = StreamController<TeleCallEvent>.broadcast();

  TeleCallPhase _phase = TeleCallPhase.lobby;
  TeleJoinResponse? _join;
  Object? _error;
  TeleEndReason? _endReason;
  TeleNotice? _notice;
  bool _sdkReconnecting = false;
  bool _rejoining = false;
  bool _micWanted;
  bool _camWanted;
  bool _recordingBusy = false;
  bool _disposed = false;
  bool _chatOpen = false;
  int _unread = 0;
  String? _pinned;
  TeleLayout _layout;
  final List<TeleChatEntry> _messages = [];
  final Set<String> _seen = {};

  CallEngine get engine => _engine;

  /// Call events: joined, participants, new chat messages, left, failed.
  Stream<TeleCallEvent> get events => _events.stream;

  TeleCallPhase get phase => _phase;
  TeleJoinResponse? get joinResponse => _join;
  TeleCall? get call => _join?.call;
  bool get isHost => _join?.isHost ?? false;

  /// The join error (phase [TeleCallPhase.error]); usually a [TeleException].
  Object? get error => _error;
  String? get errorCode => _error is TeleException ? (_error as TeleException).code : null;
  TeleEndReason? get endReason => _endReason;
  TeleNotice? get notice => _notice;

  /// True while the SDK reconnects or the controller rejoins.
  bool get reconnecting =>
      _sdkReconnecting || _rejoining || _engine.connectionState == TeleConnectionState.reconnecting;

  bool get microphoneEnabled => _phase == TeleCallPhase.live ? _engine.microphoneEnabled : _micWanted;
  bool get cameraEnabled => _phase == TeleCallPhase.live ? _engine.cameraEnabled : _camWanted;
  bool get screenShareEnabled => _engine.screenShareEnabled;
  bool get speakerphoneOn => _engine.speakerphoneOn;
  bool get isRecording => _engine.isRecording;
  bool get recordingBusy => _recordingBusy;
  bool get canRecord => isHost && (_setRecording != null || client != null);
  bool get canEndForAll => isHost && (_endForAll != null || client != null);

  List<CallParticipant> get participants => _engine.participants;
  int get participantCount => _engine.participants.length;

  TeleLayout get layout => _layout;
  set layout(TeleLayout v) {
    if (v == _layout) return;
    _layout = v;
    notifyListeners();
  }

  /// The tile key this viewer pinned. Pins are local and never sent to anyone.
  String? get pinned => _pinned;

  void togglePinned(String key) {
    _pinned = togglePin(_pinned, key);
    notifyListeners();
  }

  /// The active speaker's camera tile key: the loudest remote speaker, else the loudest.
  String? get speakerKey {
    final speakers = _engine.activeSpeakers;
    if (speakers.isEmpty) return null;
    final local = _engine.participants.where((p) => p.isLocal).map((p) => p.identity).firstOrNull;
    return tileKey(speakers.firstWhere((s) => s != local, orElse: () => speakers.first));
  }

  /// What goes large and what goes in the strip.
  TeleStage get stage =>
      arrangeStage(tilesFor(_engine.participants), layout: _layout, pinned: _pinned, speaker: speakerKey);

  List<TeleChatEntry> get messages => List.unmodifiable(_messages);
  int get unreadCount => _unread;
  bool get chatOpen => _chatOpen;
  set chatOpen(bool v) {
    if (v == _chatOpen && (!v || _unread == 0)) return;
    _chatOpen = v;
    if (v) _unread = 0;
    notifyListeners();
  }

  void dismissNotice() => _setNotice(null);

  void _setNotice(TeleNotice? n, {bool ifEmpty = false}) {
    if (ifEmpty && _notice != null) return;
    _notice = n;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _emit(TeleCallEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  // ---- lobby ----

  /// Opens the camera preview if the camera is on. Call once when the lobby shows.
  Future<void> startPreview() async {
    if (_phase != TeleCallPhase.lobby || !_camWanted) return;
    try {
      await _engine.setPreviewCamera(true);
    } catch (_) {
      _camWanted = false;
      _setNotice(const TeleNotice(TeleStringKey.cameraUnavailable));
    }
    _changed();
  }

  // ---- joining ----

  /// Leaves the lobby and connects. Media follows the lobby's microphone and camera toggles.
  Future<void> join() async {
    if (_phase != TeleCallPhase.lobby) return;
    _phase = TeleCallPhase.joining;
    _changed();
    try {
      final j = await _joiner();
      if (_disposed || _phase != TeleCallPhase.joining) return;
      _join = j;
      await _engine.connect(j, microphone: _micWanted, camera: _camWanted);
      if (_disposed || _phase != TeleCallPhase.joining) return;
      _phase = TeleCallPhase.live;
      _changed();
      _emit(TeleCallJoined(j));
      unawaited(_loadHistory());
    } catch (e) {
      if (_disposed || _phase != TeleCallPhase.joining) return;
      await _engine.disconnect().catchError((_) {});
      _error = e;
      _endReason = TeleEndReason.error;
      _phase = TeleCallPhase.error;
      _changed();
      _emit(TeleCallFailed(e));
    }
  }

  /// From the error or ended screen: back to the lobby for another attempt.
  Future<void> retry() async {
    if (_phase != TeleCallPhase.error && _phase != TeleCallPhase.ended) return;
    _phase = TeleCallPhase.lobby;
    _error = null;
    _endReason = null;
    _notice = null;
    _pinned = null;
    _messages.clear();
    _seen.clear();
    _unread = 0;
    _changed();
    await startPreview();
  }

  /// Leaves the call (or closes the ended or error screen) and emits [TeleCallLeft].
  Future<void> leave() async {
    if (_phase == TeleCallPhase.left) return;
    final reason = (_phase == TeleCallPhase.ended || _phase == TeleCallPhase.error)
        ? (_endReason ?? TeleEndReason.left)
        : TeleEndReason.left;
    _phase = TeleCallPhase.left;
    _endReason = reason;
    _rejoining = false;
    _changed();
    await _engine.disconnect().catchError((_) {});
    await _engine.setPreviewCamera(false).catchError((_) {});
    _emit(TeleCallLeft(reason));
  }

  /// Hosts: ends the call for everyone, then leaves.
  Future<void> endForAll() async {
    final id = call?.id;
    if (!canEndForAll || id == null) return;
    await (_endForAll?.call() ?? client!.endCall(id));
    await leave();
  }

  // ---- media ----

  Future<void> setMicrophone(bool on) async {
    _micWanted = on;
    if (_phase != TeleCallPhase.live) return _changed();
    try {
      await _engine.setMicrophone(on);
    } catch (_) {
      _setNotice(const TeleNotice(TeleStringKey.micUnavailable));
    }
    _changed();
  }

  Future<void> setCamera(bool on) async {
    _camWanted = on;
    try {
      if (_phase == TeleCallPhase.live) {
        await _engine.setCamera(on);
      } else if (_phase == TeleCallPhase.lobby) {
        await _engine.setPreviewCamera(on);
      }
    } catch (_) {
      _camWanted = false;
      _setNotice(const TeleNotice(TeleStringKey.cameraUnavailable));
    }
    _changed();
  }

  Future<void> toggleMicrophone() => setMicrophone(!microphoneEnabled);
  Future<void> toggleCamera() => setCamera(!cameraEnabled);

  Future<void> flipCamera() async {
    try {
      await _engine.flipCamera();
    } catch (_) {
      _setNotice(const TeleNotice(TeleStringKey.cameraUnavailable));
    }
    _changed();
  }

  Future<void> setSpeakerphone(bool on) async {
    await _engine.setSpeakerphone(on).catchError((_) {});
    _changed();
  }

  /// Shares this device's screen (web and desktop; see [CallEngine.canShareScreen]).
  Future<void> setScreenShare(bool on) async {
    try {
      await _engine.setScreenShare(on);
    } catch (_) {
      if (on) _setNotice(const TeleNotice(TeleStringKey.screenShareFailed));
    }
    _changed();
  }

  Future<List<TeleMediaDevice>> devices() => _engine.devices();

  Future<void> selectDevice(TeleMediaDevice device, {String? label}) async {
    try {
      await _engine.selectDevice(device);
    } catch (_) {
      _setNotice(TeleNotice(TeleStringKey.switchFailed, {'device': label ?? device.label}));
    }
    _changed();
  }

  // ---- recording ----

  /// Hosts: starts or stops recording. The banner follows what the media server reports.
  Future<void> setRecording(bool on) async {
    final id = call?.id;
    if (!canRecord || id == null || _recordingBusy) return;
    _recordingBusy = true;
    _changed();
    try {
      if (_setRecording != null) {
        await _setRecording(on);
      } else if (on) {
        await client!.startRecording(id);
      } else {
        await client!.stopRecording(id);
      }
    } catch (_) {
      _setNotice(const TeleNotice(TeleStringKey.recordingFailed));
    } finally {
      _recordingBusy = false;
      _changed();
    }
  }

  // ---- chat ----

  String get _localUserId => _engine.participants.where((p) => p.isLocal).map((p) => p.userId).firstOrNull ?? '';

  /// Sends [text] on `lk.chat`, shows it, and (with [persistChat]) saves it to Tele.
  Future<void> sendChat(String text) async {
    final body = text.trim();
    if (body.isEmpty || _phase != TeleCallPhase.live) return;
    final streamId = await _engine.sendChat(body);
    final me = _engine.participants.where((p) => p.isLocal).firstOrNull;
    final sentAt = DateTime.now();
    _addChat(TeleChatEntry(
        id: streamId, userId: me?.userId ?? '', name: me?.name ?? '', body: body, mine: true, sentAt: sentAt));
    final id = call?.id;
    if (persistChat && client != null && id != null) {
      unawaited(client!.postMessage(id, streamId: streamId, body: body, sentAt: sentAt).then<void>((_) {}, onError: (_) {}));
    }
  }

  bool _addChat(TeleChatEntry m, {bool announce = true}) {
    if (!_seen.add(m.id)) return false;
    // Keep the list in time order: history can arrive after live messages.
    final i = _messages.lastIndexWhere((x) => !x.sentAt.isAfter(m.sentAt));
    _messages.insert(i + 1, m);
    if (announce) {
      if (!m.mine && !_chatOpen) _unread++;
      _emit(TeleChatReceived(m));
    }
    _changed();
    return true;
  }

  Future<void> _loadHistory() async {
    final id = call?.id;
    if (!loadChatHistory || client == null || id == null) return;
    try {
      final list = await client!.listAllMessages(id);
      if (_disposed) return;
      final me = _localUserId;
      for (final m in list) {
        _addChat(
          TeleChatEntry(
              id: m.streamId, userId: m.userId, name: m.name.isNotEmpty ? m.name : m.userId, body: m.body,
              mine: m.userId == me, sentAt: m.sentAt),
          announce: false,
        );
      }
    } catch (_) {
      // History is a convenience; the live chat still works.
    }
  }

  // ---- engine events ----

  void _onEngine(CallEngineEvent e) {
    switch (e) {
      case CallEngineChanged():
      case CallEngineRecordingChanged():
        _changed();
      case CallEngineParticipantJoined(:final identity, :final name):
        _changed();
        _emit(TeleParticipantJoined(identity: identity, name: name, count: participantCount));
      case CallEngineParticipantLeft(:final identity, :final name):
        if (_pinned != null && _pinned!.startsWith('$identity:')) _pinned = null;
        _changed();
        _emit(TeleParticipantLeft(identity: identity, name: name, count: participantCount));
      case CallEngineReconnecting():
        _sdkReconnecting = true;
        _changed();
      case CallEngineReconnected():
        _sdkReconnecting = false;
        _changed();
      case CallEngineChat(:final streamId, :final identity, :final body):
        final p = _engine.participants.where((p) => p.identity == identity).firstOrNull;
        _addChat(TeleChatEntry(
            id: streamId, userId: p?.userId ?? identity, name: p?.name ?? identity, body: body, mine: false,
            sentAt: DateTime.now()));
      case CallEngineMediaError(:final source):
        _setNotice(
          TeleNotice(source == CallMediaSource.microphone
              ? TeleStringKey.micUnavailableJoined
              : TeleStringKey.cameraUnavailableJoined),
          ifEmpty: source == CallMediaSource.camera,
        );
      case CallEngineDisconnected(:final cause):
        unawaited(_onDisconnected(cause));
    }
  }

  Future<void> _onDisconnected(CallDisconnectCause cause) async {
    // While joining, the failed connect decides the screen.
    if (_phase != TeleCallPhase.live || _rejoining) return;
    _sdkReconnecting = false;
    switch (cause) {
      case CallDisconnectCause.roomDeleted:
        return _end(TeleEndReason.roomDeleted);
      case CallDisconnectCause.duplicateIdentity:
        return _end(TeleEndReason.duplicateIdentity);
      case CallDisconnectCause.removed:
        return _end(TeleEndReason.removed);
      case CallDisconnectCause.joinFailure:
        return _end(TeleEndReason.joinFailure);
      case CallDisconnectCause.connectionLost:
        return _rejoin();
    }
  }

  /// The SDK gave up: get a fresh token and a fresh join, and reconnect.
  Future<void> _rejoin() async {
    if (maxRejoinAttempts <= 0) return _end(TeleEndReason.disconnected);
    _rejoining = true;
    _changed();
    for (var attempt = 1; attempt <= maxRejoinAttempts; attempt++) {
      if (attempt > 1 || rejoinDelay > Duration.zero) await Future<void>.delayed(rejoinDelay * attempt);
      if (_disposed || _phase != TeleCallPhase.live) return;
      try {
        client?.invalidateToken();
        final j = await _joiner();
        if (_disposed || _phase != TeleCallPhase.live) return;
        _join = j;
        await _engine.connect(j, microphone: _micWanted, camera: _camWanted);
        if (_disposed || _phase != TeleCallPhase.live) return;
        _rejoining = false;
        _changed();
        unawaited(_loadHistory());
        return;
      } on TeleException catch (e) {
        if (e.code == 'call_ended' || e.code == 'call_cancelled' || e.code == 'too_late') {
          _rejoining = false;
          return _end(TeleEndReason.roomDeleted);
        }
      } catch (_) {
        // try again
      }
    }
    _rejoining = false;
    _end(TeleEndReason.disconnected);
  }

  void _end(TeleEndReason reason) {
    if (_phase != TeleCallPhase.live) return;
    _phase = TeleCallPhase.ended;
    _endReason = reason;
    _changed();
    unawaited(_engine.disconnect().catchError((_) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub.cancel());
    unawaited(_engine.dispose().catchError((_) {}));
    unawaited(_events.close());
    super.dispose();
  }
}
