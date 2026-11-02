// JSON shaped exactly like the server's DTOs (server/internal/api/dto.go and friends).

const callJson = {
  'id': 'c1',
  'title': 'Design review',
  'status': 'scheduled',
  'access_policy': 'listed_only',
  'host_user_id': 'u-001',
  'scheduled_start': '2026-10-20T04:00:00Z',
  'scheduled_end': '2026-10-20T04:45:00Z',
  'join_opens_at': '2026-10-20T03:50:00Z',
  'join_closes_at': '2026-10-20T05:15:00Z',
  'join_opens_before_minutes': 10,
  'join_closes_after_minutes': 30,
  'max_participants': 10,
  'max_duration_minutes': 240,
  'record': false,
  'created_at': '2026-10-13T09:00:00.123456Z',
};

const instantCallJson = {
  'id': 'c2',
  'title': 'Quick',
  'status': 'live',
  'access_policy': 'any_client_user',
  'host_user_id': 'u-001',
  'scheduled_start': null,
  'scheduled_end': null,
  'join_opens_at': null,
  'join_closes_at': null,
  'join_opens_before_minutes': 10,
  'join_closes_after_minutes': 30,
  'max_participants': 4,
  'max_duration_minutes': 60,
  'record': true,
  'created_at': '2026-10-13T09:00:00+06:00',
};

const memberJson = {'user_id': 'u-001', 'name': 'Rahim', 'role': 'host', 'added_at': '2026-10-13T09:00:00Z'};

const inviteJson = {
  'id': 'i1',
  'code': 'q3V9x2',
  'url': 'https://app.example/call/q3V9x2',
  'label': 'calendar link',
  'expires_at': '2026-10-20T05:15:00Z',
  'max_uses': 5,
  'use_count': 0,
  'created_at': '2026-10-13T09:00:00Z',
};

const createdCallJson = {
  ...callJson,
  'members': [memberJson],
  'invite': inviteJson,
};

const previewJson = {
  'call': {
    'id': 'c1',
    'title': 'Design review',
    'status': 'scheduled',
    'host': {'user_id': 'u-001', 'name': 'Rahim'},
    'scheduled_start': '2026-10-20T04:00:00Z',
    'scheduled_end': '2026-10-20T04:45:00Z',
    'join_opens_at': '2026-10-20T03:50:00Z',
    'join_closes_at': '2026-10-20T05:15:00Z',
  },
  'invite': {'label': 'calendar link', 'expires_at': null},
  'can_join_now': false,
  'reason': {'code': 'too_early', 'message': 'the call is not open for joining yet', 'opens_at': '2026-10-20T03:50:00Z'},
};

const joinJson = {
  'ws_url': 'wss://lk.example',
  'token': 'media-token',
  'token_expires_at': '2026-10-13T09:10:00Z',
  'ice_servers': [
    {
      'urls': ['stun:stun.cloudflare.com:3478'],
    },
    {
      'urls': ['turn:turn.cloudflare.com:3478?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'],
      'username': 'user',
      'credential': 'pass',
    },
  ],
  'identity': 'u:01a131d1',
  'grant_id': 'g1',
  'role': 'host',
  'call': instantCallJson,
};

const messageJson = {
  'id': 'm1',
  'stream_id': 'TS_x2',
  'user_id': 'bob',
  'name': 'Bob',
  'body': 'হ্যালো 👋',
  'sent_at': '2026-10-13T09:01:12Z',
};

const recordingJson = {
  'id': 'r1',
  'call_id': 'c1',
  'state': 'available',
  'started_at': '2026-10-13T09:00:05Z',
  'ended_at': '2026-10-13T09:00:58Z',
  'duration_seconds': 53,
  'size_bytes': 142576,
};

const sessionJson = {
  'room_sid': 'RM_1',
  'room_name': 'tele-c1',
  'closed_at': null,
  'closed_by': null,
  'id': 's1',
  'status': 'open',
  'started_at': '2026-10-13T09:00:00Z',
  'ended_at': null,
  'duration_seconds': 120,
  'billable_seconds': null,
  'billable_minutes': '2.0000',
  'amount': '0.0000',
  'currency': 'BDT',
  'peak_participants': 2,
  'unique_participants': 2,
  'participants': [
    {
      'id': 'p1',
      'user_internal_id': 'x',
      'participant_sid': 'PA_1',
      'identity': 'u:1',
      'grant_id': 'g1',
      'last_seen_at': '2026-10-13T09:02:00Z',
      'ip_source': 'request',
      'team': null,
      'user_id': 'u-001',
      'name': 'Rahim',
      'joined_at': '2026-10-13T09:00:00Z',
      'left_at': null,
      'duration_seconds': 120,
      'ip': '203.0.113.5',
      'user_agent': 'app',
      'platform': 'android',
    },
  ],
};
