// Typed views of Tele API responses. Field names follow the JSON (snake_case becomes camelCase).
// Enums keep the wire value and fall back to `unknown` so a new server value never breaks parsing.

typedef Json = Map<String, dynamic>;

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.parse(v) : null;
DateTime _timeReq(Object? v) => DateTime.parse(v! as String);
String _str(Object? v) => v is String ? v : '';
String? _strOpt(Object? v) => v is String ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOpt(Object? v) => v is num ? v.toInt() : null;
List<Json> _list(Object? v) => v is List ? v.whereType<Json>().toList() : const [];

/// Sends a time the way Tele accepts it (RFC 3339, UTC).
String teleTime(DateTime t) => t.toUtc().toIso8601String();

enum TeleCallStatus {
  scheduled('scheduled'),
  live('live'),
  ended('ended'),
  cancelled('cancelled'),
  unknown('unknown');

  const TeleCallStatus(this.value);
  final String value;
  static TeleCallStatus parse(Object? v) =>
      values.firstWhere((e) => e.value == v, orElse: () => TeleCallStatus.unknown);
}

enum TeleAccessPolicy {
  /// An invite only works for users added as members.
  listedOnly('listed_only'),

  /// Anyone among your users with the code can join.
  anyClientUser('any_client_user'),
  unknown('unknown');

  const TeleAccessPolicy(this.value);
  final String value;
  static TeleAccessPolicy parse(Object? v) =>
      values.firstWhere((e) => e.value == v, orElse: () => TeleAccessPolicy.unknown);
}

enum TeleRole {
  host('host'),
  participant('participant'),
  unknown('unknown');

  const TeleRole(this.value);
  final String value;
  static TeleRole parse(Object? v) => values.firstWhere((e) => e.value == v, orElse: () => TeleRole.unknown);
}

enum TeleRecordingState {
  recording('recording'),
  processing('processing'),
  available('available'),
  failed('failed'),
  archived('archived'),
  restoring('restoring'),
  restored('restored'),
  expired('expired'),
  unknown('unknown');

  const TeleRecordingState(this.value);
  final String value;
  static TeleRecordingState parse(Object? v) =>
      values.firstWhere((e) => e.value == v, orElse: () => TeleRecordingState.unknown);
}

/// One of your users, as sent in request bodies (`host`, `members`).
class TeleUserInput {
  const TeleUserInput(this.userId, {this.name, this.team});
  final String userId;
  final String? name;
  final String? team;

  Json toJson() => {'user_id': userId, 'name': ?name, 'team': ?team};
}

/// A user as Tele returns it (`GET /v1/me`, invite preview host).
class TeleUser {
  const TeleUser({required this.userId, required this.name, this.team});
  final String userId;
  final String name;
  final String? team;

  factory TeleUser.fromJson(Json j) =>
      TeleUser(userId: _str(j['user_id']), name: _str(j['name']), team: _strOpt(j['team']));
}

class TeleMember {
  const TeleMember({required this.userId, required this.name, required this.role, required this.addedAt});
  final String userId;
  final String name;
  final TeleRole role;
  final DateTime addedAt;

  factory TeleMember.fromJson(Json j) => TeleMember(
        userId: _str(j['user_id']),
        name: _str(j['name']),
        role: TeleRole.parse(j['role']),
        addedAt: _timeReq(j['added_at']),
      );
}

/// An invite. [code] and [url] are only present when it was just created; Tele never shows a code again.
class TeleInvite {
  const TeleInvite({
    required this.id,
    required this.label,
    required this.useCount,
    required this.createdAt,
    this.code,
    this.url,
    this.expiresAt,
    this.maxUses,
    this.revokedAt,
  });
  final String id;
  final String? code;
  final String? url;
  final String label;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;
  final DateTime? revokedAt;
  final DateTime createdAt;

  factory TeleInvite.fromJson(Json j) => TeleInvite(
        id: _str(j['id']),
        code: _strOpt(j['code']),
        url: _strOpt(j['url']),
        label: _str(j['label']),
        expiresAt: _time(j['expires_at']),
        maxUses: _intOpt(j['max_uses']),
        useCount: _int(j['use_count']),
        revokedAt: _time(j['revoked_at']),
        createdAt: _timeReq(j['created_at']),
      );
}

class TeleCall {
  const TeleCall({
    required this.id,
    required this.title,
    required this.status,
    required this.accessPolicy,
    required this.hostUserId,
    required this.joinOpensBeforeMinutes,
    required this.joinClosesAfterMinutes,
    required this.maxParticipants,
    required this.maxDurationMinutes,
    required this.record,
    required this.createdAt,
    this.scheduledStart,
    this.scheduledEnd,
    this.joinOpensAt,
    this.joinClosesAt,
    this.cancelledAt,
    this.endedAt,
    this.members = const [],
    this.invite,
  });

  final String id;
  final String title;
  final TeleCallStatus status;
  final TeleAccessPolicy accessPolicy;
  final String hostUserId;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? joinOpensAt;
  final DateTime? joinClosesAt;
  final int joinOpensBeforeMinutes;
  final int joinClosesAfterMinutes;
  final int maxParticipants;
  final int maxDurationMinutes;
  final bool record;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final DateTime? endedAt;

  /// Present on create and get; empty on list, update and join.
  final List<TeleMember> members;

  /// The default invite, only on create (with its one-time code).
  final TeleInvite? invite;

  factory TeleCall.fromJson(Json j) => TeleCall(
        id: _str(j['id']),
        title: _str(j['title']),
        status: TeleCallStatus.parse(j['status']),
        accessPolicy: TeleAccessPolicy.parse(j['access_policy']),
        hostUserId: _str(j['host_user_id']),
        scheduledStart: _time(j['scheduled_start']),
        scheduledEnd: _time(j['scheduled_end']),
        joinOpensAt: _time(j['join_opens_at']),
        joinClosesAt: _time(j['join_closes_at']),
        joinOpensBeforeMinutes: _int(j['join_opens_before_minutes']),
        joinClosesAfterMinutes: _int(j['join_closes_after_minutes']),
        maxParticipants: _int(j['max_participants']),
        maxDurationMinutes: _int(j['max_duration_minutes']),
        record: j['record'] == true,
        createdAt: _timeReq(j['created_at']),
        cancelledAt: _time(j['cancelled_at']),
        endedAt: _time(j['ended_at']),
        members: _list(j['members']).map(TeleMember.fromJson).toList(),
        invite: j['invite'] is Json ? TeleInvite.fromJson(j['invite'] as Json) : null,
      );
}

/// Why a user can't join (invite preview `reason`, or a join error).
class TeleJoinDenial {
  const TeleJoinDenial({required this.code, required this.message, this.opensAt});
  final String code;
  final String message;
  final DateTime? opensAt;

  factory TeleJoinDenial.fromJson(Json j) =>
      TeleJoinDenial(code: _str(j['code']), message: _str(j['message']), opensAt: _time(j['opens_at']));
}

class TeleInvitePreviewCall {
  const TeleInvitePreviewCall({
    required this.id,
    required this.title,
    required this.status,
    required this.host,
    this.scheduledStart,
    this.scheduledEnd,
    this.joinOpensAt,
    this.joinClosesAt,
  });
  final String id;
  final String title;
  final TeleCallStatus status;
  final TeleUser host;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? joinOpensAt;
  final DateTime? joinClosesAt;

  factory TeleInvitePreviewCall.fromJson(Json j) => TeleInvitePreviewCall(
        id: _str(j['id']),
        title: _str(j['title']),
        status: TeleCallStatus.parse(j['status']),
        host: TeleUser.fromJson(j['host'] is Json ? j['host'] as Json : const {}),
        scheduledStart: _time(j['scheduled_start']),
        scheduledEnd: _time(j['scheduled_end']),
        joinOpensAt: _time(j['join_opens_at']),
        joinClosesAt: _time(j['join_closes_at']),
      );
}

/// `GET /v1/invites/{code}`: what to show on a lobby screen, and whether the current user can join now.
class TeleInvitePreview {
  const TeleInvitePreview({
    required this.call,
    required this.inviteLabel,
    required this.canJoinNow,
    this.inviteExpiresAt,
    this.reason,
  });
  final TeleInvitePreviewCall call;
  final String inviteLabel;
  final DateTime? inviteExpiresAt;
  final bool canJoinNow;

  /// Null when [canJoinNow] is true.
  final TeleJoinDenial? reason;

  factory TeleInvitePreview.fromJson(Json j) {
    final inv = j['invite'] is Json ? j['invite'] as Json : const <String, dynamic>{};
    return TeleInvitePreview(
      call: TeleInvitePreviewCall.fromJson(j['call'] as Json),
      inviteLabel: _str(inv['label']),
      inviteExpiresAt: _time(inv['expires_at']),
      canJoinNow: j['can_join_now'] == true,
      reason: j['reason'] is Json ? TeleJoinDenial.fromJson(j['reason'] as Json) : null,
    );
  }
}

class TeleIceServer {
  const TeleIceServer({required this.urls, this.username, this.credential});
  final List<String> urls;
  final String? username;
  final String? credential;

  factory TeleIceServer.fromJson(Json j) => TeleIceServer(
        urls: j['urls'] is List ? (j['urls'] as List).whereType<String>().toList() : const [],
        username: _strOpt(j['username']),
        credential: _strOpt(j['credential']),
      );
}

/// The join response: everything the media SDK needs.
class TeleJoinResponse {
  const TeleJoinResponse({
    required this.wsUrl,
    required this.token,
    required this.identity,
    required this.grantId,
    required this.role,
    required this.call,
    this.tokenExpiresAt,
    this.iceServers,
  });

  final String wsUrl;

  /// The media token: valid for 10 minutes to connect; the SDK refreshes it while connected.
  final String token;
  final DateTime? tokenExpiresAt;

  /// Short-lived TURN credentials that replace the SDK's ICE servers. Null means use the SDK defaults.
  final List<TeleIceServer>? iceServers;
  final String identity;
  final String grantId;
  final TeleRole role;
  final TeleCall call;

  bool get isHost => role == TeleRole.host;

  factory TeleJoinResponse.fromJson(Json j) => TeleJoinResponse(
        wsUrl: _str(j['ws_url']),
        token: _str(j['token']),
        tokenExpiresAt: _time(j['token_expires_at']),
        iceServers: j['ice_servers'] is List ? _list(j['ice_servers']).map(TeleIceServer.fromJson).toList() : null,
        identity: _str(j['identity']),
        grantId: _str(j['grant_id']),
        role: TeleRole.parse(j['role']),
        call: TeleCall.fromJson(j['call'] as Json),
      );
}

/// A saved chat message from `GET /v1/calls/{id}/messages`. [streamId] matches the text stream id.
class TeleChatMessage {
  const TeleChatMessage({
    required this.id,
    required this.streamId,
    required this.userId,
    required this.name,
    required this.body,
    required this.sentAt,
  });
  final String id;
  final String streamId;
  final String userId;
  final String name;
  final String body;
  final DateTime sentAt;

  factory TeleChatMessage.fromJson(Json j) => TeleChatMessage(
        id: _str(j['id']),
        streamId: _str(j['stream_id']),
        userId: _str(j['user_id']),
        name: _str(j['name']),
        body: _str(j['body']),
        sentAt: _timeReq(j['sent_at']),
      );
}

/// The result of `POST /v1/calls/{id}/messages`: [created] is false when it was already recorded.
class TelePostedMessage {
  const TelePostedMessage({required this.streamId, required this.created});
  final String streamId;
  final bool created;

  factory TelePostedMessage.fromJson(Json j) =>
      TelePostedMessage(streamId: _str(j['stream_id']), created: j['created'] == true);
}

class TeleRecording {
  const TeleRecording({
    required this.id,
    required this.callId,
    required this.state,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    this.sizeBytes,
    this.error,
    this.restoredUntil,
  });
  final String id;
  final String callId;
  final TeleRecordingState state;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final int? sizeBytes;
  final String? error;
  final DateTime? restoredUntil;

  factory TeleRecording.fromJson(Json j) => TeleRecording(
        id: _str(j['id']),
        callId: _str(j['call_id']),
        state: TeleRecordingState.parse(j['state']),
        startedAt: _time(j['started_at']),
        endedAt: _time(j['ended_at']),
        durationSeconds: _intOpt(j['duration_seconds']),
        sizeBytes: _intOpt(j['size_bytes']),
        error: _strOpt(j['error']),
        restoredUntil: _time(j['restored_until']),
      );
}

class TeleSessionParticipant {
  const TeleSessionParticipant({
    required this.id,
    required this.userId,
    required this.name,
    required this.identity,
    required this.participantSid,
    required this.joinedAt,
    required this.lastSeenAt,
    required this.durationSeconds,
    required this.platform,
    this.grantId,
    this.leftAt,
    this.team,
    this.ip,
    this.ipSource,
    this.userAgent,
    this.disconnectReason,
  });
  final String id;
  final String userId;
  final String name;
  final String identity;
  final String participantSid;
  final String? grantId;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final DateTime lastSeenAt;
  final int durationSeconds;
  final String platform;
  final String? team;

  /// Null after the 30-day retention window.
  final String? ip;
  final String? ipSource;
  final String? userAgent;
  final String? disconnectReason;

  factory TeleSessionParticipant.fromJson(Json j) => TeleSessionParticipant(
        id: _str(j['id']),
        userId: _str(j['user_id']),
        name: _str(j['name']),
        identity: _str(j['identity']),
        participantSid: _str(j['participant_sid']),
        grantId: _strOpt(j['grant_id']),
        joinedAt: _timeReq(j['joined_at']),
        leftAt: _time(j['left_at']),
        lastSeenAt: _timeReq(j['last_seen_at']),
        durationSeconds: _int(j['duration_seconds']),
        platform: _str(j['platform']),
        team: _strOpt(j['team']),
        ip: _strOpt(j['ip']),
        ipSource: _strOpt(j['ip_source']),
        userAgent: _strOpt(j['user_agent']),
        disconnectReason: _strOpt(j['disconnect_reason']),
      );
}

/// One room session of a call (`GET /v1/calls/{id}/sessions`, host only).
class TeleSession {
  const TeleSession({
    required this.id,
    required this.status,
    required this.roomSid,
    required this.roomName,
    required this.durationSeconds,
    required this.peakParticipants,
    required this.uniqueParticipants,
    required this.participants,
    this.startedAt,
    this.endedAt,
    this.closedAt,
    this.closedBy,
    this.billableSeconds,
    this.billableMinutes,
    this.amount,
    this.currency,
    this.endReason,
  });
  final String id;
  final String status;
  final String roomSid;
  final String roomName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? closedAt;
  final String? closedBy;
  final int durationSeconds;
  final int? billableSeconds;

  /// Decimal strings, as Tele sends them (for example `"1.5000"`).
  final String? billableMinutes;
  final String? amount;
  final String? currency;
  final int peakParticipants;
  final int uniqueParticipants;
  final String? endReason;
  final List<TeleSessionParticipant> participants;

  factory TeleSession.fromJson(Json j) => TeleSession(
        id: _str(j['id']),
        status: _str(j['status']),
        roomSid: _str(j['room_sid']),
        roomName: _str(j['room_name']),
        startedAt: _time(j['started_at']),
        endedAt: _time(j['ended_at']),
        closedAt: _time(j['closed_at']),
        closedBy: _strOpt(j['closed_by']),
        durationSeconds: _int(j['duration_seconds']),
        billableSeconds: _intOpt(j['billable_seconds']),
        billableMinutes: _strOpt(j['billable_minutes']),
        amount: _strOpt(j['amount']),
        currency: _strOpt(j['currency']),
        peakParticipants: _int(j['peak_participants']),
        uniqueParticipants: _int(j['unique_participants']),
        endReason: _strOpt(j['end_reason']),
        participants: _list(j['participants']).map(TeleSessionParticipant.fromJson).toList(),
      );
}

/// `GET /v1/me`: who the token represents.
class TeleMe {
  const TeleMe({required this.client, required this.scope, this.user});
  final String client;

  /// `user` or `service`.
  final String scope;
  final TeleUser? user;

  factory TeleMe.fromJson(Json j) => TeleMe(
        client: _str(j['client']),
        scope: _str(j['scope']),
        user: j['user'] is Json ? TeleUser.fromJson(j['user'] as Json) : null,
      );
}

/// Options for an invite: `POST /v1/calls/{id}/invites`, or the default invite on create.
class TeleInviteOptions {
  const TeleInviteOptions({this.label, this.expiresAt, this.maxUses});
  final String? label;
  final DateTime? expiresAt;
  final int? maxUses;

  Json toJson() => {
        'label': ?label,
        if (expiresAt != null) 'expires_at': teleTime(expiresAt!),
        'max_uses': ?maxUses,
      };
}
