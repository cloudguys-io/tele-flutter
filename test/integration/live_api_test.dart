// Runs against a live Tele API. Skipped unless TELE_API_URL, TELE_API_KEY and TELE_API_SECRET are set:
//
//   set -a; . ./tele-test.env; set +a; flutter test test/integration
//
// These are plain test() calls, not testWidgets(): the widget test binding replaces HttpClient with
// one that answers 400, so network tests must not initialise it.
import 'dart:io';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tele_flutter/tele_flutter.dart';

final _env = Platform.environment;
final _url = _env['TELE_API_URL'];
final _key = _env['TELE_API_KEY'];
final _secret = _env['TELE_API_SECRET'];
final _skip = (_url == null || _key == null || _secret == null) ? 'TELE_API_URL, TELE_API_KEY and TELE_API_SECRET are not set' : null;

/// Signs a user token the way a consumer backend does (HS256 with the API secret). Test-only: apps
/// never hold the secret.
String userToken(String userId, String name, {Duration ttl = const Duration(minutes: 15)}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'iss': _key,
    'sub': userId,
    'iat': now,
    'nbf': now,
    'exp': now + ttl.inSeconds,
    'name': name,
    'tele': {'scope': 'user'},
  }).sign(SecretKey(_secret!), noIssueAt: true);
}

void main() {
  final suffix = Random().nextInt(1 << 32).toRadixString(36);
  final hostId = 'tele-flutter-host-$suffix';
  final guestId = 'tele-flutter-guest-$suffix';

  TeleClient clientFor(String id, String name, {String platform = 'flutter', bool expiredFirst = false}) {
    var calls = 0;
    return TeleClient(
      baseUrl: Uri.parse(_url!),
      platform: platform,
      tokenProvider: () async {
        calls++;
        // The first token is signed with the wrong secret, to exercise the 401 refresh.
        if (expiredFirst && calls == 1) {
          return JWT({'iss': _key, 'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600, 'tele': {'scope': 'user'}})
              .sign(SecretKey('wrong-secret'));
        }
        return userToken(id, name);
      },
    );
  }

  test('create call, invite, preview, join, chat, end', () async {
    final host = clientFor(hostId, 'Flutter Host', platform: 'ios', expiredFirst: true);
    final guest = clientFor(guestId, 'Flutter Guest', platform: 'android');
    addTearDown(host.close);
    addTearDown(guest.close);

    final me = await host.me();
    expect(me.scope, 'user');
    expect(me.user!.userId, hostId);

    final call = await host.createCall(
      title: 'tele-flutter integration $suffix',
      members: [TeleUserInput(guestId, name: 'Flutter Guest')],
      maxParticipants: 3,
    );
    expect(call.status, isNot(TeleCallStatus.unknown));
    expect(call.hostUserId, hostId);
    expect(call.members.map((m) => m.userId), containsAll([hostId, guestId]));
    expect(call.invite!.code, isNotEmpty);
    expect(call.scheduledStart, isNull);

    final listed = await host.listCalls(limit: 50);
    expect(listed.map((c) => c.id), contains(call.id));

    final updated = await host.updateCall(call.id, title: 'tele-flutter integration $suffix (edited)');
    expect(updated.title, endsWith('(edited)'));

    final members = await host.putMember(call.id, 'tele-flutter-extra-$suffix', name: 'Extra');
    expect(members.map((m) => m.userId), contains('tele-flutter-extra-$suffix'));
    await host.removeMember(call.id, 'tele-flutter-extra-$suffix');
    expect((await host.getCall(call.id)).members.map((m) => m.userId), isNot(contains('tele-flutter-extra-$suffix')));

    final invite = await host.createInvite(call.id, options: TeleInviteOptions(label: 'flutter', maxUses: 5, expiresAt: DateTime.now().add(const Duration(hours: 1))));
    expect(invite.code, isNotEmpty);
    expect(invite.maxUses, 5);
    final invites = await host.listInvites(call.id);
    expect(invites.map((i) => i.id), containsAll([call.invite!.id, invite.id]));
    expect(invites.every((i) => i.code == null), isTrue, reason: 'codes are never shown again');

    final preview = await guest.previewInvite(invite.code!);
    expect(preview.call.id, call.id);
    expect(preview.call.host.userId, hostId);
    expect(preview.canJoinNow, isTrue);
    expect(preview.reason, isNull);

    final join = await guest.joinInvite(invite.code!);
    expect(join.wsUrl, startsWith('ws'));
    expect(join.token, isNotEmpty);
    expect(join.role, TeleRole.participant);
    expect(join.call.id, call.id);
    expect(join.grantId, isNotEmpty);
    expect(rtcConfigurationFor(join).iceServers?.length, join.iceServers?.length);

    final hostJoin = await host.joinCall(call.id);
    expect(hostJoin.isHost, isTrue);

    final posted = await guest.postMessage(call.id, streamId: 'TS_flutter_$suffix', body: 'হ্যালো 👋 from Flutter', sentAt: DateTime.now());
    expect(posted.created, isTrue);
    final again = await guest.postMessage(call.id, streamId: 'TS_flutter_$suffix', body: 'হ্যালো 👋 from Flutter');
    expect(again.created, isFalse, reason: 'deduplicated by stream_id');

    final messages = await host.listAllMessages(call.id);
    final mine = messages.where((m) => m.streamId == 'TS_flutter_$suffix').single;
    expect(mine.body, 'হ্যালো 👋 from Flutter');
    expect(mine.userId, guestId);
    expect(mine.name, 'Flutter Guest');

    final sessions = await host.listSessions(call.id);
    expect(sessions, isA<List<TeleSession>>());
    expect(await host.listRecordings(call.id), isEmpty);
    // Nobody is connected to the media server, so the call isn't live and recording can't start.
    await expectLater(
      host.startRecording(call.id),
      throwsA(isA<TeleException>().having((e) => e.code, 'code', anyOf('call_not_live', 'recording_disabled'))),
    );

    // Only the host can end the call.
    await expectLater(guest.endCall(call.id), throwsA(isA<TeleException>().having((e) => e.status, 'status', anyOf(403, 404))));

    await host.revokeInvite(invite.id);
    final revoked = await guest.previewInvite(invite.code!);
    expect(revoked.canJoinNow, isFalse);
    expect(revoked.reason!.code, 'invite_revoked');

    final ended = await host.endCall(call.id);
    expect(ended.status, TeleCallStatus.ended);
    expect(ended.endedAt, isNotNull);

    await expectLater(
      guest.joinCall(call.id),
      throwsA(isA<TeleException>().having((e) => e.code, 'code', 'call_ended').having((e) => e.status, 'status', 409)),
    );
    await expectLater(host.updateCall(call.id, title: 'x'), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'call_closed')));
  }, skip: _skip);

  test('a scheduled call reports too_early, and cancelling it works', () async {
    final host = clientFor(hostId, 'Flutter Host');
    addTearDown(host.close);
    final start = DateTime.now().add(const Duration(days: 2));
    final call = await host.createCall(title: 'tele-flutter scheduled $suffix', scheduledStart: start, scheduledEnd: start.add(const Duration(minutes: 30)));
    expect(call.status, TeleCallStatus.scheduled);
    expect(call.scheduledStart!.difference(start).inSeconds.abs(), lessThan(1));
    expect(call.joinOpensAt, isNotNull);

    final preview = await host.previewInvite(call.invite!.code!);
    expect(preview.reason!.code, 'too_early');
    expect(preview.reason!.opensAt, isNotNull);

    await expectLater(
      host.joinInvite(call.invite!.code!),
      throwsA(isA<TeleException>().having((e) => e.code, 'code', 'too_early').having((e) => e.opensAt, 'opensAt', isNotNull)),
    );

    final cancelled = await host.cancelCall(call.id);
    expect(cancelled.status, TeleCallStatus.cancelled);
    expect(cancelled.cancelledAt, isNotNull);
  }, skip: _skip);

  test('unknown invite codes and bad tokens map to Tele errors', () async {
    final host = clientFor(hostId, 'Flutter Host');
    addTearDown(host.close);
    await expectLater(host.previewInvite('no-such-code-$suffix'), throwsA(isA<TeleException>().having((e) => e.code, 'code', 'invite_not_found')));

    final bad = TeleClient(baseUrl: Uri.parse(_url!), tokenProvider: () async => 'not-a-jwt');
    addTearDown(bad.close);
    await expectLater(bad.me(), throwsA(isA<TeleException>().having((e) => e.status, 'status', 401).having((e) => e.code, 'code', 'unauthenticated')));
  }, skip: _skip);
}
