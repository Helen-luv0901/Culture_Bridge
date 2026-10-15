import 'dart:convert';

import 'package:culture_bridge/data/admin_repository.dart';
import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/domain/admin_models.dart';
import 'package:culture_bridge/ui/core/design_system.dart';
import 'package:culture_bridge/ui/features/admin_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_helpers.dart';

AdminVersion _draft() => AdminVersion.fromJson({
  'id': 'v1',
  'action_id': 'arc-extension',
  'version_number': 1,
  'title_zh': '居留證延期',
  'title_en': 'Extend your ARC',
  'description_zh': '到期前三個月內申請。',
  'description_en': 'Apply within 3 months before expiry.',
  'applicable_to': '外國學生',
  'applicable_to_en': 'Foreign students',
  'location': '線上',
  'location_en': 'Online',
  'documents': [
    {'zh': '護照正本', 'en': 'Passport'},
    {'zh': '在學證明', 'en': ''},
  ],
  'verification_status': 'unverified',
  'published_at': null,
  'created_at': '2026-10-14T00:00:00Z',
  'steps': [
    {
      'id': 's1',
      'position': 1,
      'title_zh': '準備在學證明',
      'title_en': 'Get an enrollment certificate',
      'notes': '一個月內開立（內政部移民署）',
    },
  ],
  'sources': <Object>[],
  'verifications': <Object>[],
});

Future<List<http.Request>> _pump(
  WidgetTester tester, {
  required bool english,
}) async {
  final sent = <http.Request>[];
  final app = TestApp(signedIn: false);
  if (english) app.vm.setEnglish(true);
  final admin = AdminRepository(
    ApiClient(
      baseUrl: 'https://example.test',
      token: () async => 'token',
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode({..._draftJson(request)}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  );
  await tester.binding.setSurfaceSize(const Size(1024, 2400));
  await tester.pumpWidget(
    BridgeScope(
      viewModel: app.vm,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VersionEditor(admin: admin, version: _draft()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sent;
}

Map<String, Object?> _draftJson(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  return {
    'id': 'v1',
    'action_id': 'arc-extension',
    'version_number': 1,
    ...body,
    'verification_status': 'unverified',
    'published_at': null,
    'created_at': '2026-10-14T00:00:00Z',
    'steps': [
      for (final (i, s) in (body['steps'] as List).indexed)
        {...s as Map<String, dynamic>, 'id': 's$i', 'position': i + 1},
    ],
    'sources': <Object>[],
    'verifications': <Object>[],
  };
}

void main() {
  testWidgets('editor shows the interface language and keeps step notes', (
    tester,
  ) async {
    final sent = await _pump(tester, english: false);
    expect(find.text('居留證延期'), findsOneWidget);
    expect(find.text('Extend your ARC'), findsNothing);
    expect(find.text('一個月內開立（內政部移民署）'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Extend your ARC'), findsOneWidget);
    expect(find.text('居留證延期'), findsNothing);
    expect(find.text('Get an enrollment certificate'), findsOneWidget);

    await tester.enterText(find.text('Extend your ARC'), 'Extending your ARC');
    await tester.tap(find.text('儲存草稿'));
    await tester.pumpAndSettle();

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['title_en'], 'Extending your ARC');
    expect(body['title_zh'], '居留證延期'); // the hidden language is kept
    final step = (body['steps'] as List).single as Map<String, dynamic>;
    expect(step['notes'], '一個月內開立（內政部移民署）');
    expect(step['title_en'], 'Get an enrollment certificate');
    // The documents list keeps both languages, one item per line.
    expect(body['documents'], [
      {'zh': '護照正本', 'en': 'Passport'},
      {'zh': '在學證明', 'en': ''},
    ]);
  });

  testWidgets('English interface starts on English content', (tester) async {
    await _pump(tester, english: true);
    expect(find.text('Extend your ARC'), findsOneWidget);
    expect(find.text('居留證延期'), findsNothing);
  });
}
