import 'dart:convert';

import 'package:culture_bridge/data/admin_repository.dart';
import 'package:culture_bridge/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AdminRepository _repo(
  List<http.Request> sent,
  Object? Function(http.Request) reply,
) => AdminRepository(
  ApiClient(
    baseUrl: 'https://example.test',
    token: () async => 'token',
    client: MockClient((request) async {
      sent.add(request);
      final body = reply(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        body == null ? 204 : 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  ),
);

void main() {
  test(
    'feedback summary sends the locale and reads counts and themes',
    () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => {
          'action_id': 'bank',
          'feedback_count': 3,
          'counts': [
            {
              'step_id': 's1',
              'step_title': {'zh': '預約', 'en': 'Book'},
              'kind': 'stuck',
              'count': 3,
            },
          ],
          'overview': '學生回報網站進不去。',
          'themes': [
            {
              'title': '網站',
              'detail': '無法登入',
              'feedback_ids': ['a', 'b'],
            },
          ],
          'suggested_checks': ['確認網址'],
          'model_name': 'gemini-test',
        },
      );
      final summary = await repo.summarizeFeedback('bank', english: false);
      expect(sent.single.url.path, '/api/admin/actions/bank/feedback-summary');
      expect(jsonDecode(sent.single.body), {'locale': 'zh-Hant'});
      expect(summary.feedbackCount, 3);
      expect(summary.counts.single.step!.zh, '預約');
      expect(summary.themes.single.reports, 2);
      expect(summary.checks, ['確認網址']);
    },
  );

  test('empty feedback summary has no AI text', () async {
    final repo = _repo(
      [],
      (_) => {
        'action_id': 'bank',
        'feedback_count': 0,
        'counts': <Object>[],
        'overview': null,
        'themes': <Object>[],
        'suggested_checks': <Object>[],
        'model_name': null,
      },
    );
    final summary = await repo.summarizeFeedback('bank', english: true);
    expect(summary.overview, isNull);
    expect(summary.themes, isEmpty);
  });

  test('staff list and role change', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (request) => request.method == 'GET'
          ? [
              {
                'id': 'firebase-1',
                'role': 'admin',
                'created_at': '2026-10-13T00:00:00Z',
              },
            ]
          : null,
    );
    final staff = await repo.staff();
    expect(staff.single.role, 'admin');
    await repo.setRole('firebase:abc', 'reviewer');
    expect(sent.last.method, 'PUT');
    expect(sent.last.url.path, '/api/admin/users/firebase%3Aabc/role');
    expect(jsonDecode(sent.last.body), {'role': 'reviewer'});
  });

  test('usage stats keep missing rates as null', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (_) => {
        'active_users': 4,
        'reader_rate': 0.25,
        'return_rate': null,
        'outcomes': {'success': 2},
        'top_stuck_steps': [
          {
            'action_title': {'zh': '開戶', 'en': 'Bank'},
            'step_title': null,
            'count': 3,
          },
        ],
      },
    );
    final stats = await repo.stats(30);
    expect(sent.single.url.queryParameters, {'days': '30'});
    expect(stats.count('active_users'), 4);
    expect(stats.rate('reader_rate'), 0.25);
    expect(stats.rate('return_rate'), isNull);
    expect(stats.outcomes, {'success': 2});
    expect(stats.stuckSteps.single.step, isNull);
  });
}
