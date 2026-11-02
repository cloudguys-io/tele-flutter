import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show DisconnectReason;
import 'package:tele_flutter/tele_flutter.dart';

import 'fixtures.dart';

TeleTile cam(String who, {bool local = false}) =>
    TeleTile(CallParticipant(identity: who, name: who, userId: who, isLocal: local));
TeleTile screen(String who, {bool local = false}) =>
    TeleTile(CallParticipant(identity: who, name: who, userId: who, isLocal: local, hasScreenShare: true), screen: true);

List<String> keys(TeleStage s) => [for (final t in s.rest) t.key];

void main() {
  group('arrangeStage (same rules as the web call UI)', () {
    test('an even grid when nobody shares or pins', () {
      final s = arrangeStage([cam('me', local: true), cam('ann'), cam('bob')], layout: TeleLayout.grid);
      expect(s.focus, isNull);
      expect(keys(s), ['me:camera', 'ann:camera', 'bob:camera']);
    });

    test("someone else's screen share takes the stage, even in grid layout", () {
      final s = arrangeStage([cam('me', local: true), cam('ann'), screen('ann'), cam('bob')], layout: TeleLayout.grid);
      expect(s.focus!.key, 'ann:screen_share');
      expect(keys(s), ['me:camera', 'ann:camera', 'bob:camera']);
    });

    test('your own screen share stays in the grid unless you pin it', () {
      final tiles = [cam('me', local: true), screen('me', local: true), cam('ann')];
      expect(arrangeStage(tiles, layout: TeleLayout.grid).focus, isNull);
      expect(arrangeStage(tiles, layout: TeleLayout.grid, pinned: 'me:screen_share').focus!.key, 'me:screen_share');
    });

    test('a pin beats a screen share and the active speaker', () {
      final tiles = [cam('me', local: true), cam('ann'), screen('ann'), cam('bob')];
      expect(arrangeStage(tiles, layout: TeleLayout.speaker, pinned: 'bob:camera', speaker: 'ann:camera').focus!.key, 'bob:camera');
      expect(arrangeStage(tiles, layout: TeleLayout.grid, pinned: 'me:camera').focus!.key, 'me:camera');
    });

    test('a pin on someone who left falls back to the normal rules', () {
      final s = arrangeStage([cam('me', local: true), cam('ann')], layout: TeleLayout.grid, pinned: 'gone:camera');
      expect(s.focus, isNull);
      expect(keys(s), ['me:camera', 'ann:camera']);
    });

    test('speaker layout follows the speaker, else the first remote tile', () {
      final tiles = [cam('me', local: true), cam('ann'), cam('bob')];
      expect(arrangeStage(tiles, layout: TeleLayout.speaker, speaker: 'bob:camera').focus!.key, 'bob:camera');
      expect(arrangeStage(tiles, layout: TeleLayout.speaker).focus!.key, 'ann:camera');
    });

    test('alone in the call there is nothing to focus', () {
      final s = arrangeStage([cam('me', local: true)], layout: TeleLayout.grid, pinned: 'me:camera');
      expect(s.focus, isNull);
      expect(keys(s), ['me:camera']);
    });

    test('pinning the pinned tile unpins it', () {
      expect(togglePin(null, 'a'), 'a');
      expect(togglePin('a', 'b'), 'b');
      expect(togglePin('a', 'a'), isNull);
    });

    test('tilesFor adds a tile per screen share', () {
      final p = [
        const CallParticipant(identity: 'me', name: 'me', userId: 'me', isLocal: true),
        const CallParticipant(identity: 'ann', name: 'ann', userId: 'ann', isLocal: false, hasScreenShare: true),
      ];
      expect(tilesFor(p).map((t) => t.key), ['me:camera', 'ann:camera', 'ann:screen_share']);
    });
  });

  group('LiveKit mapping', () {
    test('ice_servers map into the RTC configuration as is', () {
      final cfg = rtcConfigurationFor(TeleJoinResponse.fromJson(joinJson));
      expect(cfg.iceServers, hasLength(2));
      expect(cfg.iceServers![0].urls, ['stun:stun.cloudflare.com:3478']);
      expect(cfg.iceServers![0].username, isNull);
      expect(cfg.iceServers![1].urls, ['turn:turn.cloudflare.com:3478?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp']);
      expect(cfg.iceServers![1].username, 'user');
      expect(cfg.iceServers![1].credential, 'pass');
    });

    test('null ice_servers leave the SDK defaults', () {
      final cfg = rtcConfigurationFor(TeleJoinResponse.fromJson({...joinJson, 'ice_servers': null}));
      expect(cfg.iceServers, isNull);
      expect(cfg.toMap()['iceServers'], isNull, reason: 'no servers passed, so the SDK keeps its defaults');
    });

    test('disconnect reasons', () {
      expect(disconnectCauseOf(DisconnectReason.clientInitiated), isNull);
      expect(disconnectCauseOf(DisconnectReason.roomDeleted), CallDisconnectCause.roomDeleted);
      expect(disconnectCauseOf(DisconnectReason.duplicateIdentity), CallDisconnectCause.duplicateIdentity);
      expect(disconnectCauseOf(DisconnectReason.participantRemoved), CallDisconnectCause.removed);
      expect(disconnectCauseOf(DisconnectReason.joinFailure), CallDisconnectCause.joinFailure);
      expect(disconnectCauseOf(DisconnectReason.reconnectAttemptsExceeded), CallDisconnectCause.connectionLost);
      expect(disconnectCauseOf(DisconnectReason.signalingConnectionFailure), CallDisconnectCause.connectionLost);
      expect(disconnectCauseOf(null), CallDisconnectCause.connectionLost);
    });

    test('the chat topic is lk.chat', () => expect(teleChatTopic, 'lk.chat'));
  });
}
