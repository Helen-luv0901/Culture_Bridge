import 'dart:convert';

import 'package:culture_bridge/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientFor(
  MockClientHandler handler, {
  Duration timeout = const Duration(seconds: 1),
}) => ApiClient(
  baseUrl: 'https://cb.test',
  token: () async => null,
  client: MockClient(handler),
  timeout: timeout,
);

Matcher apiError(int status, String code) => isA<ApiException>()
    .having((e) => e.status, 'status', status)
    .having((e) => e.code, 'code', code);

void main() {
  test('An HTML error page from a proxy is an ApiException, not a crash', () {
    final api = clientFor(
      (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
    );
    expect(api.get('/actions'), throwsA(apiError(502, 'http_502')));
  });

  test('A success status with a body that is not JSON is bad_response', () {
    final api = clientFor((_) async => http.Response('<!doctype html>', 200));
    expect(api.get('/actions'), throwsA(apiError(200, 'bad_response')));
  });

  test('The backend error envelope keeps its code and message', () {
    final api = clientFor(
      (_) async => http.Response(
        jsonEncode({
          'detail': {'code': 'daily_limit_reached', 'message': 'later'},
        }),
        429,
      ),
    );
    expect(
      api.post('/blocks', {'experience_id': 'x'}),
      throwsA(apiError(429, 'daily_limit_reached')),
    );
  });

  test('A request with no answer gives up as network_error', () {
    final api = clientFor(
      (_) => Future.delayed(
        const Duration(seconds: 5),
        () => http.Response('{}', 200),
      ),
      timeout: const Duration(milliseconds: 50),
    );
    expect(api.get('/actions'), throwsA(apiError(0, 'network_error')));
  });

  test('A per-call timeout overrides the default for AI calls', () async {
    final api = clientFor(
      (_) => Future.delayed(
        const Duration(milliseconds: 100),
        () => http.Response('{"ok": true}', 200),
      ),
      timeout: const Duration(milliseconds: 10),
    );
    expect(
      await api.post('/assistant/message', {}, const Duration(seconds: 2)),
      {'ok': true},
    );
  });

  test(
    'Startup config is tried three times, then the app goes on without it',
    () async {
      var calls = 0;
      final api = clientFor((_) async {
        calls++;
        return http.Response('Service Unavailable', 503);
      });
      expect(await api.clientConfig(), isNull);
      expect(calls, 3);
    },
  );

  test('A sign-in token that cannot be refreshed is a network_error', () {
    final api = ApiClient(
      baseUrl: 'https://cb.test',
      token: () async => throw Exception('offline'),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(api.get('/me'), throwsA(apiError(0, 'network_error')));
  });

  test('Startup config recovers when the second try answers', () async {
    var calls = 0;
    final api = clientFor(
      (_) async => ++calls == 1
          ? http.Response('cold start', 503)
          : http.Response('{"environment": "production"}', 200),
    );
    expect(await api.clientConfig(), {'environment': 'production'});
  });
}
