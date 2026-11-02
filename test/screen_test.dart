import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tele_flutter/tele_flutter.dart';

import 'controller_test.dart' show joinAs;
import 'fake_engine.dart';

void main() {
  late FakeEngine engine;
  setUp(() => engine = FakeEngine());

  Future<TeleCallController> pump(
    WidgetTester tester, {
    Future<TeleJoinResponse> Function()? join,
    String? language,
    Map<TeleStringKey, String>? strings,
    Size size = const Size(1280, 900),
    void Function(TeleEndReason)? onLeave,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = TeleCallController(join: join ?? () async => joinAs(), engine: engine, rejoinDelay: Duration.zero);
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: TeleCallScreen(
          controller: c,
          language: language,
          strings: strings,
          title: 'Design review',
          displayName: 'Rahim Uddin',
          onLeave: onLeave,
        ),
      ),
    ));
    await tester.pump();
    return c;
  }

  testWidgets('lobby toggles, then Join goes live', (tester) async {
    final c = await pump(tester);
    expect(find.text('Design review'), findsOneWidget);
    expect(find.text('Joining as Rahim Uddin'), findsOneWidget);
    expect(engine.previewOn, isTrue);
    // Device pickers show for kinds with more than one device.
    expect(find.text('Microphone'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mic on'));
    await tester.pump();
    expect(find.bySemanticsLabel('Mic off'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Camera on'));
    await tester.pump();
    expect(find.text('Camera is off'), findsOneWidget);
    expect(engine.previewOn, isFalse);

    await tester.tap(find.text('Join call'));
    await tester.pump();
    expect(c.phase, TeleCallPhase.live);
    expect(engine.calls, contains('connect:mic=false,cam=false'));
    expect(find.text('Quick'), findsOneWidget); // the call title from the join response
    expect(find.text('1 in call'), findsOneWidget);
    expect(find.bySemanticsLabel('Unmute'), findsOneWidget);
    expect(find.bySemanticsLabel('Leave'), findsOneWidget);
    expect(find.bySemanticsLabel('End for all'), findsNothing, reason: 'no client and no endForAll callback');
  });

  testWidgets('pin button and double tap pin a tile to the stage', (tester) async {
    final c = await pump(tester);
    await c.join();
    engine.join('Ann');
    engine.join('Bob');
    await tester.pump();
    expect(c.stage.focus, isNull);

    // The tile also listens for double taps, so a single tap resolves after the double-tap timeout.
    await tester.tap(find.bySemanticsLabel('Pin Bob'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.pinned, 'u:Bob:camera');
    expect(find.bySemanticsLabel('Unpin Bob'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Unpin Bob'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.pinned, isNull);

    final annTile = find.bySemanticsLabel('Ann');
    expect(annTile, findsOneWidget);
    await tester.tap(annTile);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(annTile);
    await tester.pumpAndSettle();
    expect(c.pinned, 'u:Ann:camera');
  });

  testWidgets('every control is at least 44px', (tester) async {
    final c = await pump(tester, size: const Size(400, 800));
    await c.join();
    engine.join('Ann');
    await tester.pump();
    for (final label in ['Mute', 'Turn camera off', 'Chat', 'Leave', 'Pin Ann', 'Share screen', 'Devices']) {
      final size = tester.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
  });

  testWidgets('chat: unread badge, open, send', (tester) async {
    final c = await pump(tester);
    await c.join();
    engine.join('Bob');
    engine.emit(const CallEngineChat(streamId: 'TS_1', identity: 'u:Bob', body: 'হ্যালো 👋'));
    await tester.pump();
    expect(find.bySemanticsLabel('Chat, 1 unread'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Chat, 1 unread'));
    await tester.pump();
    expect(c.unreadCount, 0);
    expect(find.text('হ্যালো 👋'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hello Bob');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(engine.sent, ['Hello Bob']);
    expect(find.text('Hello Bob'), findsOneWidget);
    expect(find.bySemanticsLabel('You: Hello Bob'), findsOneWidget);

    await tester.tap(find.byTooltip('Close chat'));
    await tester.pump();
    expect(c.chatOpen, isFalse);
  });

  testWidgets('recording banner and reconnecting notice', (tester) async {
    final c = await pump(tester);
    await c.join();
    engine.recording = true;
    engine.emit(const CallEngineRecordingChanged(true));
    await tester.pump();
    expect(find.text('This call is being recorded'), findsOneWidget);
    engine.emit(const CallEngineReconnecting());
    await tester.pump();
    expect(find.text('Reconnecting...'), findsOneWidget);
    engine.emit(const CallEngineReconnected());
    await tester.pump();
    expect(find.text('Reconnecting...'), findsNothing);
  });

  testWidgets("too_early shows \"This call isn't open yet\" with the opening time", (tester) async {
    final c = await pump(tester,
        join: () async => throw TeleException(status: 409, code: 'too_early', message: 'x', opensAt: DateTime(2026, 10, 20, 9, 50)));
    await tester.tap(find.text('Join call'));
    await tester.pump();
    expect(c.phase, TeleCallPhase.error);
    expect(find.text("This call isn't open yet. Opens at 09:50"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(c.phase, TeleCallPhase.lobby);
  });

  testWidgets('other join errors get friendly text; Close leaves with the reason', (tester) async {
    final left = <TeleEndReason>[];
    await pump(tester,
        join: () async => throw const TeleException(status: 410, code: 'invite_revoked', message: 'x'), onLeave: left.add);
    await tester.tap(find.text('Join call'));
    await tester.pump();
    expect(find.text('This link is no longer valid.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump();
    expect(left, [TeleEndReason.error]);
  });

  testWidgets('the ended screen explains why', (tester) async {
    final c = await pump(tester);
    await c.join();
    engine.emit(const CallEngineDisconnected(CallDisconnectCause.duplicateIdentity));
    await tester.pump();
    await tester.pump();
    expect(find.text('You joined this call from another device, so this one was disconnected.'), findsOneWidget);
    expect(find.text('Rejoin'), findsOneWidget);
  });

  testWidgets('Bangla strings, with an override', (tester) async {
    final c = await pump(tester, language: 'bn-BD', strings: {TeleStringKey.joinCall: 'ঢুকুন'});
    expect(find.text('ঢুকুন'), findsOneWidget);
    expect(find.text('রাহিম'), findsNothing);
    expect(find.text('Rahim Uddin হিসেবে যোগ দিচ্ছেন'), findsOneWidget);
    expect(find.bySemanticsLabel('মাইক চালু'), findsOneWidget);
    await tester.tap(find.text('ঢুকুন'));
    await tester.pump();
    expect(c.phase, TeleCallPhase.live);
    expect(find.text('কলে 1 জন'), findsOneWidget);
    expect(find.bySemanticsLabel('বের হন'), findsOneWidget);
  });

  testWidgets('hosts with an endForAll callback get a confirmed End for all', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var ended = 0;
    final c = TeleCallController(join: () async => joinAs(), engine: engine, endForAll: () async => ended++);
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TeleCallScreen(controller: c, lobby: false))));
    await tester.pump();
    expect(c.phase, TeleCallPhase.live, reason: 'without a lobby the screen joins at once');
    await tester.tap(find.bySemanticsLabel('End for all'));
    await tester.pumpAndSettle();
    expect(find.text('End the call for everyone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'End for all'));
    await tester.pumpAndSettle();
    expect(ended, 1);
    expect(c.phase, TeleCallPhase.left);
  });

  testWidgets('dark theme and a ThemeExtension override', (tester) async {
    final custom = TeleCallTheme.dark.copyWith(accent: const Color(0xFF0A7CFF), radius: 8);
    await pump(tester, theme: ThemeData(brightness: Brightness.dark, extensions: [custom]));
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join call'));
    expect(button.style!.backgroundColor!.resolve({}), const Color(0xFF0A7CFF));
    expect(TeleCallTheme.light.lerp(TeleCallTheme.dark, 1).background, TeleCallTheme.dark.background);
  });

  test('strings fall back to English and format placeholders', () {
    final s = TeleStrings.of('fr');
    expect(s.languageCode, 'en');
    expect(s.format(TeleStringKey.pin, {'name': 'Ann'}), 'Pin Ann');
    expect(TeleStrings.of('bn')[TeleStringKey.tooEarly], 'এই কলটি এখনো খোলেনি।');
    for (final key in TeleStringKey.values) {
      expect(TeleStrings.dictionaries['bn']![key], isNotNull, reason: '$key missing in bn');
      expect(TeleStrings.dictionaries['en']![key], isNotNull, reason: '$key missing in en');
    }
  });
}
