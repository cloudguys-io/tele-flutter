import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tele_flutter/tele_flutter.dart';

import 'fake_engine.dart';
import 'fixtures.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

TeleJoinResponse joinAs({String role = 'host', String callId = 'c2'}) => TeleJoinResponse.fromJson({
      ...joinJson,
      'role': role,
      'call': {...instantCallJson, 'id': callId},
    });

/// A Tele API stand-in for the controller's client: history, message saves, recording, end.
class Backend {
  Backend({this.history = const []});
  final List<Map<String, Object?>> history;
  String? joinError;
  int endStatus = 200;
  final requests = <http.Request>[];
  int tokens = 0;

  late final client = TeleClient(
    baseUrl: Uri.parse('https://tele.test'),
    tokenProvider: () async => 'tok-${++tokens}',
    httpClient: MockClient((req) async {
      requests.add(req);
      final key = '${req.method} ${req.url.path}';
      final (int status, Object body) = switch (key) {
        'GET /v1/calls/c2/messages' => (200, {'messages': history}),
        'POST /v1/calls/c2/messages' => (201, {'stream_id': (jsonDecode(req.body) as Map)['stream_id'], 'created': true}),
        'POST /v1/calls/c2/recording/start' => (202, {...recordingJson, 'state': 'recording'}),
        'POST /v1/calls/c2/recording/stop' => (409, {'error': {'code': 'not_recording', 'message': 'no'}}),
        'POST /v1/calls/c2/end' => endStatus == 200 ? (200, {...instantCallJson, 'status': 'ended'}) : (endStatus, {'error': {'code': 'forbidden', 'message': 'no'}}),
        'POST /v1/calls/c2/join' => joinError != null
            ? (409, {'error': {'code': joinError, 'message': 'no'}})
            : (200, {...joinJson, 'call': {...instantCallJson, 'id': 'c2'}}),
        'POST /v1/invites/inv1/join' => (200, {...joinJson, 'call': {...instantCallJson, 'id': 'c2'}}),
        _ => (404, {'error': {'code': 'not_found', 'message': key}}),
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
    }),
  );

  List<String> get paths => [for (final r in requests) '${r.method} ${r.url.path}'];
}

void main() {
  late FakeEngine engine;
  setUp(() => engine = FakeEngine());

  TeleCallController make({Future<TeleJoinResponse> Function()? join, TeleClient? client, TeleLayout layout = TeleLayout.grid, int rejoins = 2}) =>
      TeleCallController(
        join: join ?? () async => joinAs(),
        client: client,
        engine: engine,
        layout: layout,
        maxRejoinAttempts: rejoins,
        rejoinDelay: Duration.zero,
      );

  group('joining', () {
    test('lobby toggles carry into the connect, and joined is emitted', () async {
      final c = make();
      final events = <TeleCallEvent>[];
      c.events.listen(events.add);
      await c.startPreview();
      expect(engine.previewOn, isTrue);
      await c.setMicrophone(false);
      expect(c.microphoneEnabled, isFalse);
      await c.join();
      expect(c.phase, TeleCallPhase.live);
      expect(engine.calls, contains('connect:mic=false,cam=true'));
      expect(c.isHost, isTrue);
      expect(c.call!.id, 'c2');
      await settle();
      expect(events.whereType<TeleCallJoined>(), hasLength(1));
    });

    test('a camera that cannot open in the lobby turns the camera off with a notice', () async {
      engine.previewError = Exception('denied');
      final c = make();
      await c.startPreview();
      expect(c.cameraEnabled, isFalse);
      expect(c.notice!.key, TeleStringKey.cameraUnavailable);
      await c.join();
      expect(engine.calls, contains('connect:mic=true,cam=false'));
    });

    test('a join error goes to the error phase with the Tele code', () async {
      final c = make(join: () async => throw const TeleException(status: 409, code: 'too_early', message: 'not yet'));
      final events = <TeleCallEvent>[];
      c.events.listen(events.add);
      await c.join();
      expect(c.phase, TeleCallPhase.error);
      expect(c.errorCode, 'too_early');
      await settle();
      expect((events.single as TeleCallFailed).code, 'too_early');
    });

    test('a failed media connect is an error too, and retry returns to the lobby', () async {
      engine.connectError = Exception('ws closed');
      final c = make();
      await c.join();
      expect(c.phase, TeleCallPhase.error);
      expect(c.errorCode, isNull);
      engine.connectError = null;
      await c.retry();
      expect(c.phase, TeleCallPhase.lobby);
      await c.join();
      expect(c.phase, TeleCallPhase.live);
    });

    test('leave disconnects and emits left; closing the ended screen reports why it ended', () async {
      final c = make();
      final left = <TeleEndReason>[];
      c.events.listen((e) {
        if (e is TeleCallLeft) left.add(e.reason);
      });
      await c.join();
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.duplicateIdentity));
      await settle();
      expect(c.phase, TeleCallPhase.ended);
      expect(c.endReason, TeleEndReason.duplicateIdentity);
      await c.leave();
      expect(c.phase, TeleCallPhase.left);
      await settle();
      expect(left, [TeleEndReason.duplicateIdentity]);
    });
  });

  group('end reasons', () {
    for (final (cause, reason) in [
      (CallDisconnectCause.roomDeleted, TeleEndReason.roomDeleted),
      (CallDisconnectCause.removed, TeleEndReason.removed),
      (CallDisconnectCause.joinFailure, TeleEndReason.joinFailure),
      (CallDisconnectCause.duplicateIdentity, TeleEndReason.duplicateIdentity),
    ]) {
      test('$cause ends the call as $reason', () async {
        final c = make();
        await c.join();
        engine.emit(CallEngineDisconnected(cause));
        await settle();
        expect(c.phase, TeleCallPhase.ended);
        expect(c.endReason, reason);
      });
    }

    test('a disconnect while joining is decided by the connect result', () async {
      final c = make();
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.roomDeleted));
      await settle();
      expect(c.phase, TeleCallPhase.lobby);
    });
  });

  group('reconnect and rejoin', () {
    test('SDK reconnecting shows the notice until reconnected', () async {
      final c = make();
      await c.join();
      engine.emit(const CallEngineReconnecting());
      expect(c.reconnecting, isTrue);
      engine.emit(const CallEngineReconnected());
      expect(c.reconnecting, isFalse);
      expect(c.phase, TeleCallPhase.live);
    });

    test('when the SDK gives up, the controller joins again with a fresh token', () async {
      final backend = Backend();
      var joins = 0;
      final c = make(client: backend.client, join: () async {
        joins++;
        return joinAs();
      });
      await c.join();
      await settle();
      final tokensBefore = backend.tokens;
      await c.setCamera(false);
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await settle();
      expect(joins, 1, reason: 'the rejoin goes through client.joinCall');
      expect(backend.paths, contains('POST /v1/calls/c2/join'));
      expect(engine.calls, contains('disconnect'), reason: 'the dead room is dropped first');
      expect(c.phase, TeleCallPhase.live);
      expect(c.reconnecting, isFalse);
      expect(engine.calls.where((x) => x.startsWith('connect')).last, 'connect:mic=true,cam=false');
      // The rejoin reloaded history, which needed a new token after invalidateToken().
      expect(backend.tokens, greaterThan(tokensBefore));
    });

    test('rejoin gives up after the attempts and shows disconnected', () async {
      var joins = 0;
      final c = make(join: () async {
        joins++;
        if (joins > 1) throw const TeleException(status: 0, code: 'network_error', message: 'offline');
        return joinAs();
      });
      await c.join();
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await settle();
      expect(joins, 3);
      expect(c.phase, TeleCallPhase.ended);
      expect(c.endReason, TeleEndReason.disconnected);
    });

    test('rejoin stops when the call has ended meanwhile', () async {
      var joins = 0;
      final c = make(join: () async {
        if (++joins > 1) throw const TeleException(status: 409, code: 'call_ended', message: 'ended');
        return joinAs();
      });
      await c.join();
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await settle();
      expect(joins, 2);
      expect(c.endReason, TeleEndReason.roomDeleted);
    });

    test('with no rejoin attempts, a lost connection ends the call', () async {
      final c = make(rejoins: 0);
      await c.join();
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await settle();
      expect(c.endReason, TeleEndReason.disconnected);
    });
  });

  group('stage', () {
    test('pinned tile beats a screen share, which beats the active speaker', () async {
      final c = make(layout: TeleLayout.speaker);
      await c.join();
      engine.join('ann', screenShare: true);
      engine.join('bob');
      engine.speakers = ['u:bob'];
      expect(c.stage.focus!.key, 'u:ann:screen_share');
      c.togglePinned('u:bob:camera');
      expect(c.stage.focus!.key, 'u:bob:camera');
      expect(c.stage.rest.map((t) => t.key), ['u:me:camera', 'u:ann:camera', 'u:ann:screen_share']);
      c.togglePinned('u:bob:camera');
      expect(c.pinned, isNull);
      expect(c.stage.focus!.key, 'u:ann:screen_share');
    });

    test('speaker layout follows the loudest remote speaker; grid stays even', () async {
      final c = make(layout: TeleLayout.speaker);
      await c.join();
      engine.join('ann');
      engine.join('bob');
      engine.speakers = ['u:me', 'u:bob'];
      expect(c.speakerKey, 'u:bob:camera');
      expect(c.stage.focus!.key, 'u:bob:camera');
      engine.speakers = [];
      expect(c.stage.focus!.key, 'u:ann:camera');
      c.layout = TeleLayout.grid;
      expect(c.stage.focus, isNull);
      expect(c.stage.rest, hasLength(3));
    });

    test('your own screen share stays small', () async {
      final c = make();
      await c.join();
      engine.join('ann');
      await c.setScreenShare(true);
      expect(c.stage.focus, isNull);
      expect(c.stage.rest.map((t) => t.key), contains('u:me:screen_share'));
    });

    test('a pin on someone who left is dropped', () async {
      final c = make();
      await c.join();
      engine.join('ann');
      engine.join('bob');
      c.togglePinned('u:ann:camera');
      engine.remotes = [FakeEngine.remote('bob')];
      engine.emit(const CallEngineParticipantLeft('u:ann', 'ann'));
      expect(c.pinned, isNull);
      expect(c.stage.focus, isNull);
    });

    test('participant events carry the count', () async {
      final c = make();
      final events = <TeleCallEvent>[];
      c.events.listen(events.add);
      await c.join();
      engine.join('ann');
      engine.remotes = [];
      engine.emit(const CallEngineParticipantLeft('u:ann', 'ann'));
      await settle();
      final joined = events.whereType<TeleParticipantJoined>().single;
      expect((joined.name, joined.count), ('ann', 2));
      expect(events.whereType<TeleParticipantLeft>().single.count, 1);
    });
  });

  group('chat', () {
    test('history and live messages are deduplicated by stream id and kept in time order', () async {
      final backend = Backend(history: [
        {...messageJson, 'id': 'm1', 'stream_id': 'TS_a', 'sent_at': '2020-01-01T00:00:00Z'},
        {...messageJson, 'id': 'm2', 'stream_id': 'TS_live', 'sent_at': '2020-01-01T00:00:01Z'},
        {...messageJson, 'id': 'm3', 'stream_id': 'TS_mine', 'user_id': 'me', 'name': 'Me', 'sent_at': '2020-01-01T00:00:02Z'},
      ]);
      final c = make(client: backend.client);
      final received = <TeleChatEntry>[];
      c.events.listen((e) {
        if (e is TeleChatReceived) received.add(e.message);
      });
      await c.join();
      engine.join('bob');
      // A live message arrives before history loads; history contains it too.
      engine.emit(const CallEngineChat(streamId: 'TS_live', identity: 'u:bob', body: 'হ্যালো 👋'));
      await settle();
      expect(c.messages.map((m) => m.id), ['TS_a', 'TS_mine', 'TS_live']);
      expect(c.messages[1].mine, isTrue);
      expect(c.messages.last.name, 'bob');
      // Only the live message is announced and counted as unread.
      expect(received.map((m) => m.id), ['TS_live']);
      expect(c.unreadCount, 1);
      engine.emit(const CallEngineChat(streamId: 'TS_live', identity: 'u:bob', body: 'again'));
      expect(c.messages, hasLength(3));
      c.chatOpen = true;
      expect(c.unreadCount, 0);
      engine.emit(const CallEngineChat(streamId: 'TS_b', identity: 'u:bob', body: 'seen'));
      expect(c.unreadCount, 0);
    });

    test('sending posts on lk.chat, shows it as mine and saves it to Tele', () async {
      final backend = Backend();
      final c = make(client: backend.client);
      await c.join();
      await c.sendChat('  হ্যালো  ');
      await c.sendChat('   ');
      await settle();
      expect(engine.sent, ['হ্যালো']);
      expect(c.messages.single.mine, isTrue);
      expect(c.messages.single.id, 'TS_local_1');
      final post = backend.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/messages')).single;
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['stream_id'], 'TS_local_1');
      expect(body['body'], 'হ্যালো');
      expect(body['sent_at'], isA<String>());
      expect(c.unreadCount, 0);
    });

    test('without a client, chat still works locally', () async {
      final c = make();
      await c.join();
      await c.sendChat('hi');
      expect(c.messages.single.body, 'hi');
    });
  });

  group('recording and host controls', () {
    test('hosts start recording through the client; the banner follows the media server', () async {
      final backend = Backend();
      final c = make(client: backend.client);
      await c.join();
      expect(c.canRecord, isTrue);
      await c.setRecording(true);
      expect(backend.paths, contains('POST /v1/calls/c2/recording/start'));
      expect(c.isRecording, isFalse);
      engine.recording = true;
      engine.emit(const CallEngineRecordingChanged(true));
      expect(c.isRecording, isTrue);
      await c.setRecording(false);
      expect(c.notice!.key, TeleStringKey.recordingFailed);
      expect(c.recordingBusy, isFalse);
    });

    test('participants cannot record or end for all', () async {
      final c = make(client: Backend().client, join: () async => joinAs(role: 'participant'));
      await c.join();
      expect(c.canRecord, isFalse);
      expect(c.canEndForAll, isFalse);
    });

    test('end for all ends the call through the client, then leaves', () async {
      final backend = Backend();
      final c = make(client: backend.client);
      await c.join();
      await c.endForAll();
      expect(backend.paths, contains('POST /v1/calls/c2/end'));
      expect(c.phase, TeleCallPhase.left);
    });

    test('custom end and recording callbacks replace the client', () async {
      final log = <String>[];
      final c = TeleCallController(
        join: () async => joinAs(),
        engine: engine,
        endForAll: () async => log.add('end'),
        setRecording: (on) async => log.add('rec:$on'),
      );
      await c.join();
      expect(c.canRecord && c.canEndForAll, isTrue);
      await c.setRecording(true);
      await c.endForAll();
      expect(log, ['rec:true', 'end']);
    });
  });

  group('media', () {
    test('toggles go to the engine while live; failures show a notice', () async {
      final c = make();
      await c.join();
      await c.toggleMicrophone();
      await c.toggleCamera();
      await c.flipCamera();
      await c.setSpeakerphone(false);
      expect(engine.calls, containsAllInOrder(['mic:false', 'cam:false', 'flip', 'speaker:false']));
      expect(c.microphoneEnabled, isFalse);
      expect(c.speakerphoneOn, isFalse);
      engine.micError = Exception('busy');
      await c.setMicrophone(true);
      expect(c.notice!.key, TeleStringKey.micUnavailable);
      c.dismissNotice();
      expect(c.notice, isNull);
    });

    test('media errors after connecting show the joined-muted notices', () async {
      final c = make();
      await c.join();
      engine.emit(CallEngineMediaError(CallMediaSource.microphone, Exception('x')));
      expect(c.notice!.key, TeleStringKey.micUnavailableJoined);
      engine.emit(CallEngineMediaError(CallMediaSource.camera, Exception('x')));
      expect(c.notice!.key, TeleStringKey.micUnavailableJoined, reason: 'the camera notice only fills an empty banner');
    });

    test('device selection goes to the engine', () async {
      final c = make();
      final list = await c.devices();
      await c.selectDevice(list[1]);
      expect(engine.calls, contains('select:m2'));
    });
  });

  test('a caller-supplied engine is disconnected, not disposed, unless ownsEngine', () async {
    final c = make();
    c.dispose();
    await settle();
    expect(engine.calls, isNot(contains('dispose')));
    expect(engine.calls, contains('disconnect'));
    final other = FakeEngine();
    TeleCallController(join: () async => joinAs(), engine: other, ownsEngine: true).dispose();
    await settle();
    expect(other.calls, contains('dispose'));
  });

  test('chat history can come from the backend route (Flutter web)', () async {
    final urls = <String>[];
    final client = TeleClient(
      baseUrl: Uri.parse('https://tele.test'),
      tokenProvider: () async => 't',
      joinProxy: TeleJoinProxy.backend(Uri.parse('https://app.test/api/tele')),
      httpClient: MockClient((req) async {
        urls.add('${req.method} ${req.url.replace(query: '')}');
        return http.Response.bytes(utf8.encode(jsonEncode({'messages': [messageJson]})), 200);
      }),
    );
    final c = make(client: client);
    await c.join();
    await settle();
    expect(c.messages.single.id, 'TS_x2');
    expect(urls, ['GET https://app.test/api/tele/calls/c2/messages?']);
  });

  group('review fixes', () {
    test('an invite call rejoins by call id, so the invite is not used again', () async {
      final backend = Backend();
      final c = TeleCallController.invite(backend.client, 'inv1', engine: engine, microphone: false, persistChat: false);
      await c.join();
      expect(engine.calls.first, 'connect:mic=false,cam=true');
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await settle();
      expect(backend.paths.where((p) => p.endsWith('/join')), ['POST /v1/invites/inv1/join', 'POST /v1/calls/c2/join']);
      expect(c.phase, TeleCallPhase.live);
      c.dispose();
    });

    for (final code in ['invite_revoked', 'not_invited']) {
      test('$code during a rejoin is final', () async {
        final backend = Backend()..joinError = code;
        final c = make(client: backend.client);
        await c.join();
        engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
        await settle();
        expect(backend.paths.where((p) => p == 'POST /v1/calls/c2/join'), hasLength(1));
        expect(c.endReason, TeleEndReason.disconnected);
      });
    }

    test('while rejoining, the old room participants are gone from the stage', () async {
      final c = TeleCallController(
        join: () async => joinAs(),
        rejoin: (_) => Completer<TeleJoinResponse>().future,
        engine: engine,
        rejoinDelay: Duration.zero,
      );
      await c.join();
      engine.join('ann');
      expect(c.participantCount, 2);
      engine.emit(const CallEngineDisconnected(CallDisconnectCause.connectionLost));
      await settle();
      expect(c.reconnecting, isTrue);
      expect(c.participants, isEmpty);
      expect(c.stage.rest, isEmpty);
    });

    test('a failed join closes the lobby preview', () async {
      final c = make(join: () async => throw const TeleException(status: 409, code: 'call_full', message: 'full'));
      await c.startPreview();
      expect(engine.previewOn, isTrue);
      await c.join();
      expect(engine.previewOn, isFalse);
    });

    test('a failed chat send keeps nothing, returns false and shows a notice', () async {
      final c = make();
      await c.join();
      engine.chatError = Exception('not connected');
      expect(await c.sendChat('hello'), isFalse);
      expect(c.messages, isEmpty);
      expect(c.notice!.key, TeleStringKey.chatFailed);
    });

    test('messages over 2000 code points are not sent', () async {
      final c = make();
      await c.join();
      expect(await c.sendChat('হ' * 2001), isFalse);
      expect(await c.sendChat('😀' * 2000), isTrue, reason: 'emoji count as one code point each');
      expect(engine.sent, hasLength(1));
    });

    test('a failed end for all shows a notice and stays in the call', () async {
      final backend = Backend()..endStatus = 403;
      final c = make(client: backend.client);
      await c.join();
      await c.endForAll();
      expect(c.phase, TeleCallPhase.live);
      expect(c.notice!.key, TeleStringKey.endForAllFailed);
    });

    test('blocked autoplay asks for a tap, and startAudio clears it', () async {
      engine.audioOk = false;
      final c = make();
      await c.join();
      expect(c.needsAudioStart, isTrue);
      await c.startAudio();
      expect(engine.calls, contains('startAudio'));
      expect(c.needsAudioStart, isFalse);
      engine.emit(const CallEngineAudioPlayback(false));
      expect(c.needsAudioStart, isTrue);
    });

    test('media changes notify the media listenable only', () async {
      final c = make();
      await c.join();
      var main = 0, media = 0;
      c.addListener(() => main++);
      c.media.addListener(() => media++);
      engine.emit(const CallEngineChanged());
      c.togglePinned('u:me:camera');
      expect((main, media), (0, 2));
      await c.setMicrophone(false);
      expect(main, greaterThan(0));
    });
  });
}
