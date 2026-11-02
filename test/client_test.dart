import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tele_flutter/tele_flutter.dart';

import 'fixtures.dart';

/// A fake Tele API: answers `METHOD /path` from [routes] and records every request.
class FakeApi {
  FakeApi(this.routes);
  final Map<String, (int, Object?)> routes;
  final requests = <http.Request>[];
  int tokenCalls = 0;
  String token = 'tok-1';

  late final client = TeleClient(
    baseUrl: Uri.parse('https://tele.test'),
    platform: 'android',
    httpClient: MockClient((req) async {
      requests.add(req);
      final key = '${req.method} ${req.url.path}';
      final route = routes[key];
      if (route == null) return http.Response('{"error":{"code":"not_found","message":"no route $key"}}', 404);
      final (status, body) = route;
      return http.Response.bytes(
        body == null ? const [] : utf8.encode(body is String ? body : jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
    tokenProvider: () async {
      tokenCalls++;
      return token;
    },
  );

  http.Request get last => requests.last;
  Map<String, dynamic> get lastBody => jsonDecode(last.body) as Map<String, dynamic>;
}

void main() {
  group('calls', () {
    test('createCall sends only the fields given and parses members and the invite', () async {
      final api = FakeApi({'POST /v1/calls': (201, createdCallJson)});
      final call = await api.client.createCall(
        title: 'Design review',
        accessPolicy: TeleAccessPolicy.listedOnly,
        scheduledStart: DateTime.utc(2026, 10, 20, 4),
        scheduledEnd: DateTime.parse('2026-10-20T10:45:00+06:00'),
        maxParticipants: 3,
        record: true,
        members: [const TeleUserInput('u-102', name: 'Karim')],
        invite: TeleInviteOptions(label: 'calendar link', expiresAt: DateTime.utc(2026, 10, 20, 5, 15), maxUses: 5),
      );
      expect(api.last.method, 'POST');
      expect(api.last.url.toString(), 'https://tele.test/v1/calls');
      expect(api.last.headers['Authorization'], 'Bearer tok-1');
      expect(api.last.headers['Content-Type'], startsWith('application/json'));
      expect(api.lastBody, {
        'title': 'Design review',
        'access_policy': 'listed_only',
        'scheduled_start': '2026-10-20T04:00:00.000Z',
        'scheduled_end': '2026-10-20T04:45:00.000Z',
        'max_participants': 3,
        'record': true,
        'members': [
          {'user_id': 'u-102', 'name': 'Karim'},
        ],
        'invite': {'label': 'calendar link', 'expires_at': '2026-10-20T05:15:00.000Z', 'max_uses': 5},
      });
      expect(call.id, 'c1');
      expect(call.status, TeleCallStatus.scheduled);
      expect(call.accessPolicy, TeleAccessPolicy.listedOnly);
      expect(call.scheduledStart, DateTime.utc(2026, 10, 20, 4));
      expect(call.createdAt.isUtc, isTrue);
      expect(call.cancelledAt, isNull);
      expect(call.members.single.role, TeleRole.host);
      expect(call.members.single.addedAt, DateTime.utc(2026, 10, 13, 9));
      expect(call.invite!.code, 'q3V9x2');
      expect(call.invite!.url, 'https://app.example/call/q3V9x2');
      expect(call.invite!.maxUses, 5);
    });

    test('createCall with only a title sends only the title', () async {
      final api = FakeApi({'POST /v1/calls': (201, createdCallJson)});
      await api.client.createCall(title: 'Quick');
      expect(api.lastBody, {'title': 'Quick'});
    });

    test('listCalls passes filters as query parameters and parses nullable times', () async {
      final api = FakeApi({
        'GET /v1/calls': (200, {
          'calls': [callJson, instantCallJson],
        }),
      });
      final calls = await api.client.listCalls(
        statuses: [TeleCallStatus.scheduled, TeleCallStatus.live],
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 1),
        limit: 20,
      );
      expect(api.last.url.queryParameters, {
        'status': 'scheduled,live',
        'from': '2026-10-01T00:00:00.000Z',
        'to': '2026-11-01T00:00:00.000Z',
        'limit': '20',
      });
      expect(calls, hasLength(2));
      expect(calls[1].scheduledStart, isNull);
      expect(calls[1].joinOpensAt, isNull);
      expect(calls[1].record, isTrue);
      expect(calls[1].accessPolicy, TeleAccessPolicy.anyClientUser);
      expect(calls[1].createdAt, DateTime.utc(2026, 10, 13, 3));
      expect(calls[1].members, isEmpty);
    });

    test('listCalls without filters sends no query', () async {
      final api = FakeApi({
        'GET /v1/calls': (200, {'calls': <Object>[]}),
      });
      expect(await api.client.listCalls(), isEmpty);
      expect(api.last.url.query, isEmpty);
    });

    test('getCall, cancelCall and endCall', () async {
      final api = FakeApi({
        'GET /v1/calls/c1': (200, {
          ...callJson,
          'members': [memberJson],
        }),
        'DELETE /v1/calls/c1': (200, {...callJson, 'status': 'cancelled', 'cancelled_at': '2026-10-13T10:00:00Z'}),
        'POST /v1/calls/c1/end': (200, {...callJson, 'status': 'ended', 'ended_at': '2026-10-13T10:00:00Z'}),
      });
      expect((await api.client.getCall('c1')).members.single.name, 'Rahim');
      final cancelled = await api.client.cancelCall('c1');
      expect(cancelled.status, TeleCallStatus.cancelled);
      expect(cancelled.cancelledAt, DateTime.utc(2026, 10, 13, 10));
      final ended = await api.client.endCall('c1');
      expect(api.last.method, 'POST');
      expect(ended.status, TeleCallStatus.ended);
      expect(ended.endedAt, isNotNull);
    });

    test('updateCall sends only changed fields', () async {
      final api = FakeApi({'PATCH /v1/calls/c1': (200, callJson)});
      await api.client.updateCall('c1', title: 'New', accessPolicy: TeleAccessPolicy.anyClientUser, record: false);
      expect(api.last.method, 'PATCH');
      expect(api.lastBody, {'title': 'New', 'access_policy': 'any_client_user', 'record': false});
      await api.client.updateCall('c1', scheduledStart: DateTime.utc(2026, 1, 1), scheduledEnd: DateTime.utc(2026, 1, 2), maxParticipants: 4);
      expect(api.lastBody, {
        'scheduled_start': '2026-01-01T00:00:00.000Z',
        'scheduled_end': '2026-01-02T00:00:00.000Z',
        'max_participants': 4,
      });
    });

    test('putMember and removeMember', () async {
      final api = FakeApi({
        'PUT /v1/calls/c1/members/u%202': (200, {
          'members': [memberJson, {...memberJson, 'user_id': 'u 2', 'role': 'participant'}],
        }),
        'DELETE /v1/calls/c1/members/u%202': (204, null),
      });
      final members = await api.client.putMember('c1', 'u 2', name: 'Nadia', team: 'sales');
      expect(api.last.url.toString(), 'https://tele.test/v1/calls/c1/members/u%202');
      expect(api.lastBody, {'name': 'Nadia', 'team': 'sales'});
      expect(members[1].role, TeleRole.participant);
      await api.client.removeMember('c1', 'u 2');
      expect(api.last.method, 'DELETE');
      expect(api.last.body, isEmpty);
    });

    test('listSessions parses sessions and participants', () async {
      final api = FakeApi({
        'GET /v1/calls/c1/sessions': (200, {
          'sessions': [sessionJson],
        }),
      });
      final s = (await api.client.listSessions('c1')).single;
      expect(s.status, 'open');
      expect(s.endedAt, isNull);
      expect(s.billableSeconds, isNull);
      expect(s.billableMinutes, '2.0000');
      expect(s.currency, 'BDT');
      expect(s.peakParticipants, 2);
      final p = s.participants.single;
      expect(p.platform, 'android');
      expect(p.leftAt, isNull);
      expect(p.team, isNull);
      expect(p.ip, '203.0.113.5');
      expect(p.grantId, 'g1');
    });
  });

  group('invites', () {
    test('createInvite, listInvites, revokeInvite', () async {
      final api = FakeApi({
        'POST /v1/calls/c1/invites': (201, inviteJson),
        'GET /v1/calls/c1/invites': (200, {
          'invites': [
            {...inviteJson, 'code': null, 'url': null, 'max_uses': null, 'expires_at': null, 'revoked_at': '2026-10-14T00:00:00Z'},
          ],
        }),
        'DELETE /v1/invites/i1': (204, null),
      });
      final inv = await api.client.createInvite('c1', options: TeleInviteOptions(label: 'auditor', maxUses: 1, expiresAt: DateTime.utc(2026, 10, 21)));
      expect(api.lastBody, {'label': 'auditor', 'expires_at': '2026-10-21T00:00:00.000Z', 'max_uses': 1});
      expect(inv.code, 'q3V9x2');
      await api.client.createInvite('c1');
      expect(api.lastBody, isEmpty);
      final list = await api.client.listInvites('c1');
      expect(list.single.code, isNull);
      expect(list.single.maxUses, isNull);
      expect(list.single.revokedAt, DateTime.utc(2026, 10, 14));
      await api.client.revokeInvite('i1');
      expect(api.last.method, 'DELETE');
    });

    test('previewInvite parses the reason', () async {
      final api = FakeApi({'GET /v1/invites/q3V9x2': (200, previewJson)});
      final p = await api.client.previewInvite('q3V9x2');
      expect(p.canJoinNow, isFalse);
      expect(p.call.host.name, 'Rahim');
      expect(p.call.status, TeleCallStatus.scheduled);
      expect(p.inviteLabel, 'calendar link');
      expect(p.inviteExpiresAt, isNull);
      expect(p.reason!.code, 'too_early');
      expect(p.reason!.opensAt, DateTime.utc(2026, 10, 20, 3, 50));
    });
  });

  group('joining', () {
    test('joinInvite sends X-Client-Platform and parses ICE servers', () async {
      final api = FakeApi({'POST /v1/invites/a%2Fb/join': (200, joinJson)});
      final j = await api.client.joinInvite('a/b');
      expect(api.last.url.toString(), 'https://tele.test/v1/invites/a%2Fb/join');
      expect(api.last.headers['X-Client-Platform'], 'android');
      expect(api.last.headers['Authorization'], 'Bearer tok-1');
      expect(j.wsUrl, 'wss://lk.example');
      expect(j.isHost, isTrue);
      expect(j.iceServers, hasLength(2));
      expect(j.iceServers![0].username, isNull);
      expect(j.iceServers![1].urls, hasLength(2));
      expect(j.iceServers![1].credential, 'pass');
      expect(j.call.status, TeleCallStatus.live);
      expect(j.tokenExpiresAt, DateTime.utc(2026, 10, 13, 9, 10));
    });

    test('joinCall parses null ice_servers as null', () async {
      final api = FakeApi({
        'POST /v1/calls/c2/join': (200, {...joinJson, 'ice_servers': null, 'role': 'participant'}),
      });
      final j = await api.client.joinCall('c2');
      expect(j.iceServers, isNull);
      expect(j.role, TeleRole.participant);
      expect(api.last.headers['X-Client-Platform'], 'android');
    });

    test('a join proxy is called instead of Tele, with your headers and no Tele token', () async {
      final requests = <http.Request>[];
      var tokenCalls = 0;
      final client = TeleClient(
        baseUrl: Uri.parse('https://tele.test'),
        platform: 'ios',
        tokenProvider: () async {
          tokenCalls++;
          return 'tok';
        },
        joinProxy: TeleJoinProxy(
          url: (t) => Uri.parse(t.inviteCode != null
              ? 'https://backend.test/tele/join?code=${t.inviteCode}'
              : 'https://backend.test/calls/${t.callId}/join'),
          headers: () => {'Authorization': 'Session abc'},
        ),
        httpClient: MockClient((req) async {
          requests.add(req);
          if (req.url.path.startsWith('/calls/')) {
            return http.Response('{"error":{"code":"too_early","message":"not yet","opens_at":"2026-10-20T03:50:00Z"}}', 409);
          }
          return http.Response(jsonEncode(joinJson), 200);
        }),
      );
      final j = await client.joinInvite('code1');
      expect(j.grantId, 'g1');
      expect(requests.single.url.toString(), 'https://backend.test/tele/join?code=code1');
      expect(requests.single.method, 'POST');
      expect(requests.single.headers['Authorization'], 'Session abc');
      expect(requests.single.headers['X-Client-Platform'], 'ios');
      expect(tokenCalls, 0);
      await expectLater(
        client.joinCall('c9'),
        throwsA(isA<TeleException>().having((e) => e.code, 'code', 'too_early').having((e) => e.opensAt, 'opensAt', DateTime.utc(2026, 10, 20, 3, 50))),
      );
    });
  });

  group('backend route convention', () {
    test('TeleJoinProxy.backend joins and reads history under /api/tele', () async {
      final seen = <String>[];
      final client = TeleClient(
        baseUrl: Uri.parse('https://tele.test'),
        platform: 'flutter-web',
        tokenProvider: () async => fail('no Tele token when everything goes through the backend'),
        joinProxy: TeleJoinProxy.backend(Uri.parse('https://app.test/api/tele/'), headers: () => {'Cookie': 's=1'}),
        httpClient: MockClient((req) async {
          seen.add('${req.method} ${req.url} ${req.headers['Cookie']} ${req.headers['X-Client-Platform']}');
          if (req.url.path.endsWith('/messages')) {
            return http.Response.bytes(utf8.encode(jsonEncode({'messages': [messageJson]})), 200);
          }
          return http.Response(jsonEncode(joinJson), 200);
        }),
      );
      await client.joinInvite('a/b');
      await client.joinCall('c 1');
      final msgs = await client.listMessages('c 1', after: 'm0', limit: 5);
      expect(msgs.single.streamId, 'TS_x2');
      expect(seen, [
        'POST https://app.test/api/tele/invites/a%2Fb/join s=1 flutter-web',
        'POST https://app.test/api/tele/calls/c%201/join s=1 flutter-web',
        'GET https://app.test/api/tele/calls/c%201/messages?after=m0&limit=5 s=1 null',
      ]);
    });

    test('history stays on Tele when the proxy has no messages route', () async {
      final seen = <String>[];
      final client = TeleClient(
        baseUrl: Uri.parse('https://tele.test'),
        tokenProvider: () async => 't',
        joinProxy: TeleJoinProxy.backend(Uri.parse('https://app.test/api/tele'), messages: false),
        httpClient: MockClient((req) async {
          seen.add(req.url.toString());
          return http.Response('{"messages":[]}', 200);
        }),
      );
      await client.listMessages('c1');
      expect(seen, ['https://tele.test/v1/calls/c1/messages']);
    });
  });

  group('chat', () {
    test('listMessages pages with after and limit', () async {
      final api = FakeApi({
        'GET /v1/calls/c1/messages': (200, {
          'messages': [messageJson],
        }),
      });
      final list = await api.client.listMessages('c1', after: 'm0', limit: 50);
      expect(api.last.url.queryParameters, {'after': 'm0', 'limit': '50'});
      expect(list.single.body, 'হ্যালো 👋');
      expect(list.single.streamId, 'TS_x2');
      expect(list.single.sentAt, DateTime.utc(2026, 10, 13, 9, 1, 12));
    });

    test('listAllMessages follows after until a short page', () async {
      var page = 0;
      final client = TeleClient(
        baseUrl: Uri.parse('https://tele.test'),
        tokenProvider: () async => 't',
        httpClient: MockClient((req) async {
          page++;
          final after = req.url.queryParameters['after'];
          expect(req.url.queryParameters['limit'], '2');
          final msgs = switch (after) {
            null => [{...messageJson, 'id': 'a'}, {...messageJson, 'id': 'b'}],
            'b' => [{...messageJson, 'id': 'c'}],
            _ => throw StateError('unexpected after=$after'),
          };
          return http.Response.bytes(utf8.encode(jsonEncode({'messages': msgs})), 200);
        }),
      );
      final all = await client.listAllMessages('c1', pageSize: 2);
      expect(all.map((m) => m.id), ['a', 'b', 'c']);
      expect(page, 2);
    });

    test('postMessage sends stream_id, body and sent_at', () async {
      final api = FakeApi({
        'POST /v1/calls/c1/messages': (201, {'stream_id': 'TS_1', 'created': true}),
      });
      final r = await api.client.postMessage('c1', streamId: 'TS_1', body: 'হ্যালো', sentAt: DateTime.utc(2026, 10, 13, 9, 1, 12));
      expect(api.lastBody, {'stream_id': 'TS_1', 'body': 'হ্যালো', 'sent_at': '2026-10-13T09:01:12.000Z'});
      expect(r.created, isTrue);
      expect(r.streamId, 'TS_1');
    });
  });

  group('recordings', () {
    test('start, stop, list, get, restore', () async {
      final api = FakeApi({
        'POST /v1/calls/c1/recording/start': (202, {...recordingJson, 'state': 'recording', 'ended_at': null, 'duration_seconds': null, 'size_bytes': null}),
        'POST /v1/calls/c1/recording/stop': (202, {...recordingJson, 'state': 'processing'}),
        'GET /v1/calls/c1/recordings': (200, {
          'recordings': [recordingJson],
        }),
        'GET /v1/recordings/r1': (200, {...recordingJson, 'state': 'failed', 'error': 'no tracks'}),
        'POST /v1/recordings/r1/restore': (202, {...recordingJson, 'state': 'restoring', 'restored_until': '2026-11-01T00:00:00Z'}),
      });
      final started = await api.client.startRecording('c1');
      expect(started.state, TeleRecordingState.recording);
      expect(started.durationSeconds, isNull);
      expect((await api.client.stopRecording('c1')).state, TeleRecordingState.processing);
      final list = await api.client.listRecordings('c1');
      expect(list.single.sizeBytes, 142576);
      expect(list.single.endedAt, DateTime.utc(2026, 10, 13, 9, 0, 58));
      final failed = await api.client.getRecording('r1');
      expect(failed.state, TeleRecordingState.failed);
      expect(failed.error, 'no tracks');
      final restoring = await api.client.restoreRecording('r1');
      expect(restoring.state, TeleRecordingState.restoring);
      expect(restoring.restoredUntil, DateTime.utc(2026, 11, 1));
    });

    test('unknown states parse as unknown', () {
      expect(TeleRecordingState.parse('frozen'), TeleRecordingState.unknown);
      expect(TeleCallStatus.parse(null), TeleCallStatus.unknown);
    });
  });

  group('other', () {
    test('me', () async {
      final api = FakeApi({
        'GET /v1/me': (200, {
          'client': 'Demo',
          'scope': 'user',
          'user': {'user_id': 'u-1', 'name': 'Rahim', 'team': 'sales'},
        }),
      });
      final me = await api.client.me();
      expect(me.scope, 'user');
      expect(me.user!.team, 'sales');
    });

    test('reportDiagnostic posts the body', () async {
      final api = FakeApi({'POST /v1/calls/c1/diagnostics': (204, null)});
      await api.client.reportDiagnostic('c1', grantId: 'g1', participantSid: 'PA_1', kind: 'connected', payload: {'state': 'connected', 'tracks': <Object>[]});
      expect(api.lastBody, {
        'grant_id': 'g1',
        'participant_sid': 'PA_1',
        'kind': 'connected',
        'payload': {'state': 'connected', 'tracks': <Object>[]},
      });
    });
  });

  group('errors and tokens', () {
    test('Tele errors become TeleException with status, code and message', () async {
      final api = FakeApi({
        'POST /v1/invites/x/join': (409, {
          'error': {'code': 'call_full', 'message': 'max_participants reached'},
        }),
        'GET /v1/calls/c1': (403, {
          'error': {'code': 'forbidden', 'message': 'only the host can do this'},
        }),
        'GET /v1/me': (502, '<html>bad gateway</html>'),
      });
      await expectLater(
        api.client.joinInvite('x'),
        throwsA(isA<TeleException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.code, 'code', 'call_full')
            .having((e) => e.message, 'message', 'max_participants reached')
            .having((e) => e.opensAt, 'opensAt', isNull)),
      );
      await expectLater(api.client.getCall('c1'), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'forbidden')));
      await expectLater(api.client.me(), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'http_502')));
    });

    test('a network failure becomes network_error', () async {
      final client = TeleClient(
        tokenProvider: () async => 't',
        httpClient: MockClient((_) async => throw http.ClientException('connection refused')),
      );
      await expectLater(client.me(), throwsA(isA<TeleException>().having((e) => e.status, 'status', 0).having((e) => e.code, 'code', 'network_error')));
    });

    test('the token is cached between requests', () async {
      final api = FakeApi({
        'GET /v1/me': (200, {'client': 'c', 'scope': 'user'}),
      });
      await api.client.me();
      await api.client.me();
      expect(api.tokenCalls, 1);
    });

    test('a 401 fetches a fresh token and retries once', () async {
      var calls = 0;
      final seen = <String?>[];
      var tokens = 0;
      final client = TeleClient(
        tokenProvider: () async => 'tok-${++tokens}',
        httpClient: MockClient((req) async {
          calls++;
          seen.add(req.headers['Authorization']);
          if (req.headers['Authorization'] == 'Bearer tok-1') {
            return http.Response('{"error":{"code":"unauthenticated","message":"token expired"}}', 401);
          }
          return http.Response('{"client":"c","scope":"user"}', 200);
        }),
      );
      await client.me();
      expect(calls, 2);
      expect(seen, ['Bearer tok-1', 'Bearer tok-2']);
    });

    test('a second 401 is thrown, not retried again', () async {
      var calls = 0;
      final client = TeleClient(
        tokenProvider: () async => 'tok',
        httpClient: MockClient((req) async {
          calls++;
          return http.Response('{"error":{"code":"unauthenticated","message":"bad signature"}}', 401);
        }),
      );
      await expectLater(client.me(), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'unauthenticated')));
      expect(calls, 2);
    });

    test('a token about to expire is replaced before use', () async {
      String jwt(DateTime exp) {
        String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
        return '${b64({'alg': 'HS256'})}.${b64({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
      }

      final issued = [jwt(DateTime.now().add(const Duration(seconds: 10))), jwt(DateTime.now().add(const Duration(hours: 1)))];
      var n = 0;
      final used = <String?>[];
      final client = TeleClient(
        tokenProvider: () async => issued[n++],
        httpClient: MockClient((req) async {
          used.add(req.headers['Authorization']);
          return http.Response('{"client":"c","scope":"user"}', 200);
        }),
      );
      await client.me(); // first token is already near expiry, but it's all we have
      await client.me(); // so the next request asks again
      await client.me();
      expect(n, 2);
      expect(used, ['Bearer ${issued[0]}', 'Bearer ${issued[1]}', 'Bearer ${issued[1]}']);
    });

    test('invalidateToken forces a new token', () async {
      final api = FakeApi({
        'GET /v1/me': (200, {'client': 'c', 'scope': 'user'}),
      });
      await api.client.me();
      api.client.invalidateToken();
      await api.client.me();
      expect(api.tokenCalls, 2);
    });

    test('the default base URL and platform', () {
      final c = TeleClient(tokenProvider: () async => 't');
      expect(c.baseUrl.toString(), 'https://tele-api.cloudguys.io');
      expect(c.platform, startsWith('flutter-'));
      expect(c.platform.length, lessThanOrEqualTo(32));
      expect(c.timeout, const Duration(seconds: 20));
      c.close();
    });

    test('a slow response becomes a timeout TeleException', () async {
      final client = TeleClient(
        tokenProvider: () async => 't',
        timeout: const Duration(milliseconds: 50),
        httpClient: MockClient((_) => Future.delayed(const Duration(seconds: 2), () => http.Response('{}', 200))),
      );
      await expectLater(client.me(), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'timeout').having((e) => e.status, 'status', 0)));
    });

    test('a failing token provider becomes a token_provider TeleException', () async {
      var calls = 0;
      final client = TeleClient(
        tokenProvider: () async {
          calls++;
          throw StateError('signed out');
        },
        httpClient: MockClient((_) async => fail('no request without a token')),
      );
      await expectLater(client.me(), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'token_provider')));
      await expectLater(client.joinInvite('x'), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'token_provider')));
      expect(calls, 2, reason: 'a failure is not cached');
    });

    test('a base URL with a path prefix keeps it', () async {
      final seen = <Uri>[];
      final client = TeleClient(
        baseUrl: Uri.parse('https://gw.test/tele/'),
        tokenProvider: () async => 't',
        httpClient: MockClient((req) async {
          seen.add(req.url);
          return http.Response('{"client":"c","scope":"user"}', 200);
        }),
      );
      await client.me();
      expect(seen.single.toString(), 'https://gw.test/tele/v1/me');
    });
  });
}
