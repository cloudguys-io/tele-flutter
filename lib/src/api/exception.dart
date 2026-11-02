/// An error from the Tele API, or from reaching it.
///
/// Tele errors share one shape: `{"error": {"code", "message", "opens_at"?}}`. Branch on [code];
/// [message] is for logs and may change. [opensAt] is only set for `too_early`.
class TeleException implements Exception {
  const TeleException({required this.status, required this.code, required this.message, this.opensAt});

  /// The HTTP status, or 0 when the request never got a response (network error).
  final int status;

  /// The Tele error code, for example `too_early`, `call_full` or `unauthenticated`.
  ///
  /// When the response wasn't a Tele error body, this is `network_error` (no response) or `http_<status>`.
  final String code;

  final String message;

  /// When the join window opens; only present for `too_early`.
  final DateTime? opensAt;

  /// Parses a Tele error body. Falls back to `http_<status>` when the body isn't one.
  factory TeleException.fromResponse(int status, Object? body) {
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map<String, dynamic> && err['code'] is String) {
        final opens = err['opens_at'];
        return TeleException(
          status: status,
          code: err['code'] as String,
          message: err['message'] is String ? err['message'] as String : '',
          opensAt: opens is String ? DateTime.parse(opens) : null,
        );
      }
    }
    return TeleException(status: status, code: 'http_$status', message: 'unexpected response ($status)');
  }

  @override
  String toString() => 'TeleException($status $code: $message)';
}
