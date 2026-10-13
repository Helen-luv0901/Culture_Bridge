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
class ApiClient {
  ApiClient({required this.baseUrl, required this.token, http.Client? client})
    : _http = client ?? http.Client();

  /// `--dart-define=API_BASE_URL=https://…` overrides the default (the page's own origin).
  factory ApiClient.fromEnvironment({required TokenProvider token}) {
    const configured = String.fromEnvironment('API_BASE_URL');
    final base = configured.isNotEmpty ? configured : Uri.base.origin;
    return ApiClient(baseUrl: base, token: token);
  }

  final String baseUrl;
  final TokenProvider token;
  final http.Client _http;

  /// Public startup settings (`GET /api/config`); null when the server can't be reached.
  Future<Map<String, dynamic>?> clientConfig() async {
    try {
      return await get('/config') as Map<String, dynamic>;
    } on ApiException {
      return null;
    }
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, [Object? body]) =>
      _send('PUT', path, body: body ?? const {});
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri);
    final bearer = await token();
    if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (_) {
      throw const ApiException(0, 'network_error');
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
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
