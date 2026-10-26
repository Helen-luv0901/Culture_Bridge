import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error body from the backend: {"detail": {"code": "...", "message": "..."}}.
class ApiException implements Exception {
  const ApiException(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;
  bool get needsLogin => status == 401;
  @override
  String toString() => 'ApiException($status, $code)';
}

typedef TokenProvider = Future<String?> Function();

/// JSON over HTTP to /api. On the web the API is served from the same origin as the app.
///
/// Every failure reaches callers as an [ApiException]: no answer within [timeout] or no
/// connection is `network_error`, and a body that isn't JSON (a proxy or cold-start error
/// page) is `http_<status>`, or `bad_response` on a success status.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _http = client ?? http.Client();

  /// `--dart-define=API_BASE_URL=https://…` overrides the default (the page's own origin).
  factory ApiClient.fromEnvironment({required TokenProvider token}) {
    const configured = String.fromEnvironment('API_BASE_URL');
    final base = configured.isNotEmpty ? configured : Uri.base.origin;
    return ApiClient(baseUrl: base, token: token);
  }

  final String baseUrl;
  final TokenProvider token;
  final Duration timeout;
  final http.Client _http;

  /// Public startup settings (`GET /api/config`); null when the server can't be reached.
  /// The app waits for this before its first frame. Sign-in needs it, so it tries a few
  /// times (a cold start can take a while or drop the first request) before going on without.
  Future<Map<String, dynamic>?> clientConfig({
    Duration wait = const Duration(seconds: 10),
    int attempts = 3,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _send('GET', '/config', timeout: wait)
            as Map<String, dynamic>;
      } on ApiException {
        continue;
      }
    }
    return null;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  /// [timeout] overrides the default for calls that wait on the AI.
  Future<dynamic> post(String path, [Object? body, Duration? timeout]) =>
      _send('POST', path, body: body ?? const {}, timeout: timeout);
  Future<dynamic> put(String path, [Object? body, Duration? timeout]) =>
      _send('PUT', path, body: body ?? const {}, timeout: timeout);
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final wait = timeout ?? this.timeout;
    final http.Response response;
    try {
      // Refreshing an expired sign-in token needs the network too.
      final bearer = await token().timeout(wait);
      if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(wait);
    } on Exception {
      // No connection, no answer in time (TimeoutException), or no fresh token.
      throw const ApiException(0, 'network_error');
    }
    final Object? decoded;
    try {
      final text = utf8.decode(response.bodyBytes);
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      final status = response.statusCode;
      throw ApiException(
        status,
        status >= 400 ? 'http_$status' : 'bad_response',
      );
    }
    if (response.statusCode >= 400) {
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is Map && detail['code'] is String) {
        throw ApiException(
          response.statusCode,
          detail['code'] as String,
          detail['message'] as String?,
        );
      }
      throw ApiException(response.statusCode, 'http_${response.statusCode}');
    }
    return decoded;
  }
}
