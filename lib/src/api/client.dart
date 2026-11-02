import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'exception.dart';
import 'models.dart';

/// Returns a Tele user token for the signed-in user. Your backend signs it; the API secret never
/// reaches the app.
typedef TeleTokenProvider = Future<String> Function();

/// Which join a [TeleJoinProxy] is asked for: exactly one of [inviteCode] and [callId] is set.
class TeleJoinTarget {
  const TeleJoinTarget.invite(String this.inviteCode) : callId = null;
  const TeleJoinTarget.call(String this.callId) : inviteCode = null;
  final String? inviteCode;
  final String? callId;
}

/// Routes joins through your backend instead of calling Tele directly.
///
/// The client POSTs to [url] with `X-Client-Platform` and [headers] (your own auth, not a Tele token).
/// Your backend calls Tele's join endpoint and returns the join response as is, or the Tele error body.
class TeleJoinProxy {
  const TeleJoinProxy({required this.url, this.headers});
  final Uri Function(TeleJoinTarget target) url;
  final FutureOr<Map<String, String>> Function()? headers;
}

/// The `X-Client-Platform` value for this device: `web`, `ios`, `android`, `macos`, `windows`,
/// `linux` or `fuchsia`.
String defaultTelePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

/// The Tele REST API, acting as the signed-in user (user token).
///
/// Tokens come from [tokenProvider]. The client keeps the last token, fetches a new one shortly
/// before it expires, and on a `401` fetches a fresh one and retries the request once.
class TeleClient {
  TeleClient({
    required TeleTokenProvider tokenProvider,
    Uri? baseUrl,
    http.Client? httpClient,
    String? platform,
    this.joinProxy,
  })  : _tokenProvider = tokenProvider,
        baseUrl = baseUrl ?? defaultBaseUrl,
        platform = platform ?? defaultTelePlatform(),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  static final Uri defaultBaseUrl = Uri.parse('https://tele-api.cloudguys.io');

  final Uri baseUrl;

  /// Sent as `X-Client-Platform` on joins (≤32 characters).
  final String platform;

  /// When set, [joinInvite] and [joinCall] go through your backend.
  final TeleJoinProxy? joinProxy;

  final TeleTokenProvider _tokenProvider;
  final http.Client _http;
  final bool _ownsHttp;
  String? _token;
  Future<String>? _pending;

  /// Forgets the cached token so the next request asks the token provider again.
  void invalidateToken() => _token = null;

  /// Closes the HTTP client if this client created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  // ---- calls ----

  /// `POST /v1/calls`. The token's user is the host. Leave out [scheduledStart] for an instant call.
  /// The returned call includes `members` and the default `invite` with its one-time code.
  Future<TeleCall> createCall({
    required String title,
    TeleAccessPolicy? accessPolicy,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    int? joinOpensBeforeMinutes,
    int? joinClosesAfterMinutes,
    int? maxParticipants,
    int? maxDurationMinutes,
    bool? record,
    List<TeleUserInput>? members,
    TeleInviteOptions? invite,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (accessPolicy != null) 'access_policy': accessPolicy.value,
      if (scheduledStart != null) 'scheduled_start': teleTime(scheduledStart),
      if (scheduledEnd != null) 'scheduled_end': teleTime(scheduledEnd),
      'join_opens_before_minutes': ?joinOpensBeforeMinutes,
      'join_closes_after_minutes': ?joinClosesAfterMinutes,
      'max_participants': ?maxParticipants,
      'max_duration_minutes': ?maxDurationMinutes,
      'record': ?record,
      if (members != null) 'members': [for (final m in members) m.toJson()],
      if (invite != null) 'invite': invite.toJson(),
    };
    return TeleCall.fromJson(await _json('POST', '/v1/calls', body: body));
  }

  /// `GET /v1/calls`: calls you're a member of, newest first.
  Future<List<TeleCall>> listCalls({List<TeleCallStatus>? statuses, DateTime? from, DateTime? to, int? limit}) async {
    final j = await _json('GET', '/v1/calls', query: {
      if (statuses != null && statuses.isNotEmpty) 'status': statuses.map((s) => s.value).join(','),
      if (from != null) 'from': teleTime(from),
      if (to != null) 'to': teleTime(to),
      if (limit != null) 'limit': '$limit',
    });
    return _items(j, 'calls', TeleCall.fromJson);
  }

  /// `GET /v1/calls/{id}` with its members.
  Future<TeleCall> getCall(String callId) async => TeleCall.fromJson(await _json('GET', '/v1/calls/${_seg(callId)}'));

  /// `PATCH /v1/calls/{id}` (host). Only the fields you pass change.
  Future<TeleCall> updateCall(
    String callId, {
    String? title,
    TeleAccessPolicy? accessPolicy,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    int? maxParticipants,
    bool? record,
  }) async {
    final body = <String, dynamic>{
      'title': ?title,
      if (accessPolicy != null) 'access_policy': accessPolicy.value,
      if (scheduledStart != null) 'scheduled_start': teleTime(scheduledStart),
      if (scheduledEnd != null) 'scheduled_end': teleTime(scheduledEnd),
      'max_participants': ?maxParticipants,
      'record': ?record,
    };
    return TeleCall.fromJson(await _json('PATCH', '/v1/calls/${_seg(callId)}', body: body));
  }

  /// `DELETE /v1/calls/{id}` (host): cancels the call and disconnects anyone in it.
  Future<TeleCall> cancelCall(String callId) async =>
      TeleCall.fromJson(await _json('DELETE', '/v1/calls/${_seg(callId)}'));

  /// `POST /v1/calls/{id}/end` (host): ends the call now for everyone.
  Future<TeleCall> endCall(String callId) async =>
      TeleCall.fromJson(await _json('POST', '/v1/calls/${_seg(callId)}/end'));

  /// `PUT /v1/calls/{id}/members/{user_id}` (host). Returns the call's members.
  Future<List<TeleMember>> putMember(String callId, String userId, {String? name, String? team}) async {
    final j = await _json('PUT', '/v1/calls/${_seg(callId)}/members/${_seg(userId)}',
        body: {'name': ?name, 'team': ?team});
    return _items(j, 'members', TeleMember.fromJson);
  }

  /// `DELETE /v1/calls/{id}/members/{user_id}` (host). The host can't be removed.
  Future<void> removeMember(String callId, String userId) =>
      _send('DELETE', '/v1/calls/${_seg(callId)}/members/${_seg(userId)}');

  /// `GET /v1/calls/{id}/sessions` (host): sessions, participants, IPs, durations, charges.
  Future<List<TeleSession>> listSessions(String callId) async =>
      _items(await _json('GET', '/v1/calls/${_seg(callId)}/sessions'), 'sessions', TeleSession.fromJson);

  // ---- invites ----

  /// `POST /v1/calls/{id}/invites` (host). The result carries the one-time `code`.
  Future<TeleInvite> createInvite(String callId, {TeleInviteOptions options = const TeleInviteOptions()}) async =>
      TeleInvite.fromJson(await _json('POST', '/v1/calls/${_seg(callId)}/invites', body: options.toJson()));

  /// `GET /v1/calls/{id}/invites` (host), without codes.
  Future<List<TeleInvite>> listInvites(String callId) async =>
      _items(await _json('GET', '/v1/calls/${_seg(callId)}/invites'), 'invites', TeleInvite.fromJson);

  /// `DELETE /v1/invites/{invite_id}` (host).
  Future<void> revokeInvite(String inviteId) => _send('DELETE', '/v1/invites/${_seg(inviteId)}');

  /// `GET /v1/invites/{code}`: call summary and whether the current user can join now.
  Future<TeleInvitePreview> previewInvite(String code) async =>
      TeleInvitePreview.fromJson(await _json('GET', '/v1/invites/${_seg(code)}'));

  // ---- joining ----

  /// `POST /v1/invites/{code}/join` (or through [joinProxy]).
  Future<TeleJoinResponse> joinInvite(String code) =>
      _join(TeleJoinTarget.invite(code), '/v1/invites/${_seg(code)}/join');

  /// `POST /v1/calls/{id}/join` for a member (or through [joinProxy]).
  Future<TeleJoinResponse> joinCall(String callId) =>
      _join(TeleJoinTarget.call(callId), '/v1/calls/${_seg(callId)}/join');

  Future<TeleJoinResponse> _join(TeleJoinTarget target, String path) async {
    final headers = {'X-Client-Platform': platform};
    final proxy = joinProxy;
    if (proxy == null) {
      return TeleJoinResponse.fromJson(await _json('POST', path, headers: headers));
    }
    final extra = await proxy.headers?.call() ?? const <String, String>{};
    final req = http.Request('POST', proxy.url(target))..headers.addAll({...extra, ...headers});
    return TeleJoinResponse.fromJson(_decode(await _roundTrip(req)));
  }

  // ---- chat ----

  /// `GET /v1/calls/{id}/messages`: one page, ordered by `sent_at`. Pass the last message's id as
  /// [after] for the next page. [limit] defaults to 200 on the server (maximum 500).
  Future<List<TeleChatMessage>> listMessages(String callId, {String? after, int? limit}) async {
    final j = await _json('GET', '/v1/calls/${_seg(callId)}/messages',
        query: {'after': ?after, if (limit != null) 'limit': '$limit'});
    return _items(j, 'messages', TeleChatMessage.fromJson);
  }

  /// Every saved message, following `after` until a page comes back short.
  Future<List<TeleChatMessage>> listAllMessages(String callId, {int pageSize = 500}) async {
    final all = <TeleChatMessage>[];
    String? after;
    while (true) {
      final page = await listMessages(callId, after: after, limit: pageSize);
      all.addAll(page);
      if (page.length < pageSize) return all;
      after = page.last.id;
    }
  }

  /// `POST /v1/calls/{id}/messages`: saves a message sent over `lk.chat` (deduplicated by [streamId]).
  Future<TelePostedMessage> postMessage(String callId, {required String streamId, required String body, DateTime? sentAt}) async {
    final j = await _json('POST', '/v1/calls/${_seg(callId)}/messages', body: {
      'stream_id': streamId,
      'body': body,
      if (sentAt != null) 'sent_at': teleTime(sentAt),
    });
    return TelePostedMessage.fromJson(j);
  }

  // ---- recordings ----

  /// `POST /v1/calls/{id}/recording/start` (host; the call must be live).
  Future<TeleRecording> startRecording(String callId) async =>
      TeleRecording.fromJson(await _json('POST', '/v1/calls/${_seg(callId)}/recording/start'));

  /// `POST /v1/calls/{id}/recording/stop` (host).
  Future<TeleRecording> stopRecording(String callId) async =>
      TeleRecording.fromJson(await _json('POST', '/v1/calls/${_seg(callId)}/recording/stop'));

  /// `GET /v1/calls/{id}/recordings` (host).
  Future<List<TeleRecording>> listRecordings(String callId) async =>
      _items(await _json('GET', '/v1/calls/${_seg(callId)}/recordings'), 'recordings', TeleRecording.fromJson);

  /// `GET /v1/recordings/{id}` (host).
  Future<TeleRecording> getRecording(String recordingId) async =>
      TeleRecording.fromJson(await _json('GET', '/v1/recordings/${_seg(recordingId)}'));

  /// `POST /v1/recordings/{id}/restore` (host): thaws an archived recording.
  Future<TeleRecording> restoreRecording(String recordingId) async =>
      TeleRecording.fromJson(await _json('POST', '/v1/recordings/${_seg(recordingId)}/restore'));

  // ---- other ----

  /// `GET /v1/me`: who the token represents.
  Future<TeleMe> me() async => TeleMe.fromJson(await _json('GET', '/v1/me'));

  /// `POST /v1/calls/{id}/diagnostics`: client media telemetry bound to a join grant.
  /// Tele answers `409 session_pending` until it has seen the participant join; retry shortly.
  Future<void> reportDiagnostic(
    String callId, {
    required String grantId,
    required String participantSid,
    required String kind,
    required Map<String, dynamic> payload,
  }) =>
      _send('POST', '/v1/calls/${_seg(callId)}/diagnostics',
          body: {'grant_id': grantId, 'participant_sid': participantSid, 'kind': kind, 'payload': payload});

  // ---- transport ----

  static String _seg(String s) => Uri.encodeComponent(s);

  static List<T> _items<T>(Json j, String key, T Function(Json) parse) =>
      (j[key] is List ? (j[key] as List).whereType<Json>() : const <Json>[]).map(parse).toList();

  Future<Json> _json(String method, String path,
      {Object? body, Map<String, String>? query, Map<String, String>? headers}) async {
    return _decode(await _authed(method, path, body: body, query: query, headers: headers));
  }

  Future<void> _send(String method, String path, {Object? body}) async {
    await _authed(method, path, body: body);
  }

  Future<http.Response> _authed(String method, String path,
      {Object? body, Map<String, String>? query, Map<String, String>? headers}) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    http.Request build(String token) {
      final r = http.Request(method, uri)
        ..headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'application/json', ...?headers});
      if (body != null) {
        r.headers['Content-Type'] = 'application/json';
        r.body = jsonEncode(body);
      }
      return r;
    }

    var res = await _roundTrip(build(await _currentToken()));
    if (res.statusCode == 401) {
      _token = null;
      res = await _roundTrip(build(await _currentToken()));
    }
    _check(res);
    return res;
  }

  Future<http.Response> _roundTrip(http.Request req) async {
    try {
      return await http.Response.fromStream(await _http.send(req));
    } on http.ClientException catch (e) {
      throw TeleException(status: 0, code: 'network_error', message: e.message);
    }
  }

  static void _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      body = null;
    }
    throw TeleException.fromResponse(res.statusCode, body);
  }

  static Json _decode(http.Response res) {
    _check(res);
    if (res.bodyBytes.isEmpty) return {};
    final v = jsonDecode(utf8.decode(res.bodyBytes));
    if (v is Json) return v;
    throw TeleException(status: res.statusCode, code: 'invalid_response', message: 'expected a JSON object');
  }

  Future<String> _currentToken() {
    final t = _token;
    if (t != null && !_nearExpiry(t)) return Future.value(t);
    // Concurrent requests share one provider call.
    return _pending ??= _tokenProvider().then((v) {
      _token = v;
      return v;
    }).whenComplete(() => _pending = null);
  }

  /// True when the JWT's `exp` is within 30 seconds. Tokens that can't be read are used as is.
  static bool _nearExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Json ? payload['exp'] : null;
      if (exp is! num) return false;
      return DateTime.now().add(const Duration(seconds: 30)).isAfter(DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000));
    } on FormatException {
      return false;
    }
  }
}
