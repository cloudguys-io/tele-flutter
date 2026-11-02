// Opens a Tele call from an invite code.
//
// The app asks YOUR backend for a Tele user token (POST <token URL> returns {"token": "..."}); the
// API secret stays on the backend. Defaults can be baked in at build time:
//
//   flutter run --dart-define=TELE_TOKEN_URL=https://yourapp.example/api/tele/token \
//               --dart-define=TELE_API_URL=https://tele-api.cloudguys.io \
//               --dart-define=TELE_INVITE=q3V9x2...
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tele_flutter/tele_flutter.dart';

const _tokenUrl = String.fromEnvironment('TELE_TOKEN_URL', defaultValue: 'http://localhost:8000/api/tele/token');
const _apiUrl = String.fromEnvironment('TELE_API_URL', defaultValue: 'https://tele-api.cloudguys.io');
const _invite = String.fromEnvironment('TELE_INVITE');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tele example',
        theme: ThemeData(colorSchemeSeed: const Color(0xFFC6432A), extensions: const [TeleCallTheme.light]),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFFC6432A),
          brightness: Brightness.dark,
          extensions: const [TeleCallTheme.dark],
        ),
        home: const StartPage(),
      );
}

/// Fetches a user token from your backend. Add your own session header here.
Future<String> fetchTeleToken(Uri tokenUrl) async {
  final res = await http.post(tokenUrl);
  if (res.statusCode != 200) throw Exception('token endpoint returned ${res.statusCode}');
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return body['token'] as String;
}

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _token = TextEditingController(text: _tokenUrl);
  final _api = TextEditingController(text: _apiUrl);
  final _code = TextEditingController(text: _invite);
  String _language = 'en';
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    _api.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    final tokenUrl = Uri.parse(_token.text.trim());
    final client = TeleClient(baseUrl: Uri.parse(_api.text.trim()), tokenProvider: () => fetchTeleToken(tokenUrl));
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      // Preview first: it says what the call is and whether this user can join now.
      final preview = await client.previewInvite(code);
      final me = await client.me();
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CallPage(client: client, code: code, title: preview.call.title, name: me.user?.name, language: _language),
      ));
    } on TeleException catch (e) {
      setState(() => _status = teleErrorText(TeleStrings.of(_language), e));
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tele example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: _token, decoration: const InputDecoration(labelText: 'Token URL (your backend)')),
            TextField(controller: _api, decoration: const InputDecoration(labelText: 'Tele API URL')),
            TextField(controller: _code, decoration: const InputDecoration(labelText: 'Invite code')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'bn', label: Text('বাংলা'))],
              selected: {_language},
              onSelectionChanged: (v) => setState(() => _language = v.first),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _open, child: const Text('Open call')),
            if (_status != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_status!)),
          ],
        ),
      );
}

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.client, required this.code, required this.title, this.name, required this.language});
  final TeleClient client;
  final String code;
  final String title;
  final String? name;
  final String language;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final TeleCallController _call = TeleCallController.invite(widget.client, widget.code);

  @override
  void dispose() {
    _call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TeleCallScreen(
          controller: _call,
          title: widget.title,
          displayName: widget.name,
          language: widget.language,
          onLeave: (_) => Navigator.of(context).maybePop(),
          onEvent: (e) {
            if (e is TeleParticipantJoined) debugPrint('${e.name} joined (${e.count} in call)');
          },
        ),
      );
}
