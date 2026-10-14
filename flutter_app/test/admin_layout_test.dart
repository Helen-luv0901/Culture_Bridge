// C-17: the reviewer/admin screens follow the same rule as the rest of the app — phone widths
// with 200% text, in both languages, must lay out without overflow.
import 'dart:convert';

import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/data/admin_repository.dart';
import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/ui/core/loading.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_helpers.dart';

const _longZh = '居留證（ARC）延期申請：在學證明、護照、照片與規費的準備與注意事項';
const _longEn =
    'Extending your Alien Resident Certificate (ARC): enrollment certificate, '
    'passport, photo and fee requirements';

Map<String, String> _title() => {'zh': _longZh, 'en': _longEn};

Map<String, Object?> _version(int number, {required bool draft}) => {
  'id': 'v$number',
  'action_id': 'arc-extension',
  'version_number': number,
  'title_zh': _longZh,
  'title_en': _longEn,
  'description_zh': '到期前三個月內線上申請，逾期會被罰款。',
  'description_en': 'Apply online within three months before it expires.',
  'applicable_to': '持居留證的外國學生',
  'applicable_to_en': 'Foreign students holding an ARC',
  'location': '內政部移民署線上申辦系統',
  'location_en': 'National Immigration Agency online application system',
  'verification_status': draft ? 'unverified' : 'verified',
  'published_at': draft ? null : '2026-09-01T00:00:00Z',
  'created_at': '2026-08-01T00:00:00Z',
  'steps': [
    for (var i = 1; i <= 3; i++)
      {
        'id': 's$i',
        'position': i,
        'title_zh': '第 $i 步：準備在學證明與護照影本並上傳',
        'title_en':
            'Step $i: prepare your enrollment certificate and passport copy',
        'notes': '一個月內開立（內政部移民署、逢甲大學國際處）',
      },
  ],
  'sources': [
    {
      'id': 'src1',
      'title': '外國人居留證延期 Extension of Alien Resident Certificate',
      'url': 'https://www.immigration.gov.tw/5382/5385/7445/7451/7463/very-long-path',
      'publisher': '內政部移民署 National Immigration Agency',
      'kind': 'government',
      'evidence_note': '步驟 1～3 與應備文件',
    },
  ],
  'verifications': [
    {
      'decision': 'confirmed',
      'note': '已對照官方網站 2026-09-01 版本',
      'checked_at': '2026-09-01T00:00:00Z',
    },
  ],
};

Object? _respond(http.Request request) {
  final path = request.url.path.replaceFirst('/api', '');
  return switch (path) {
    '/admin/actions' => [
      for (final (i, draft) in [true, false].indexed)
        {
          'id': i == 0 ? 'arc-extension' : 'nhi',
          'title': _title(),
          'archived_at': null,
          'latest_version_number': draft ? 2 : 1,
          'latest_published_version_number': 1,
          'has_draft': draft,
          'verification_status': draft ? 'needs_review' : 'verified',
        },
    ],
    '/admin/actions/arc-extension/versions' => [
      _version(2, draft: true),
      _version(1, draft: false),
    ],
    '/admin/actions/nhi/versions' => [_version(1, draft: false)],
    '/admin/sources' => [(_version(1, draft: false)['sources'] as List).first],
    '/admin/feedback' => [
      {
        'id': 'f1',
        'action_id': 'arc-extension',
        'action_title': _title(),
        'version_number': 1,
        'step_title': _title(),
        'kind': 'different',
        'category': 'documents',
        'original_voice': '移民署櫃台說還要附上租屋契約影本，網站上沒有寫。' * 3,
        'created_at': '2026-10-01T00:00:00Z',
      },
    ],
    '/admin/reports' => [
      {
        'report_id': 'r1',
        'target_id': 'experience-with-a-very-long-identifier-0001',
        'target_status': 'published',
        'original_voice':
            'A long shared experience that someone reported. ' * 4,
        'reasons': {'misinformation': 2, 'personal_info': 1},
        'notes': ['這裡寫了別人的電話號碼'],
        'report_count': 3,
      },
    ],
    '/admin/kb/documents' => [
      {
        'id': 'd1',
        'title': '外國學生健康檢查及居留證辦理須知 Health check and ARC guide',
        'publisher': '逢甲大學國際處 FCU Office of International Affairs',
        'active': true,
        'chunk_count': 12,
      },
    ],
    '/admin/stats' => {
      'active_users': 120,
      'experience_readers': 80,
      'reader_rate': 0.67,
      'sharing_authors': 14,
      'share_rate': 0.12,
      'published_after_summary': 12,
      'drafts_with_ai_summary': 15,
      'summary_confirm_rate': 0.8,
      'confirmed_with_author_edits': 4,
      'different_responses': 3,
      'returned_within_7_days': 40,
      'return_cohort': 90,
      'return_rate': null,
      'executions_started': 30,
      'outcomes': {'success': 12, 'abandoned': 2},
      'top_stuck_steps': [
        {'action_title': _title(), 'step_title': _title(), 'count': 5},
      ],
    },
    '/admin/users' => [
      {'id': 'firebase-uid-with-a-long-identifier-1234567890', 'role': 'admin'},
      {'id': 'reviewer-2', 'role': 'reviewer'},
    ],
    _ => throw StateError('unexpected request ${request.url}'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const routes = [
    '/admin?tab=actions',
    '/admin?tab=feedback',
    '/admin?tab=reports',
    '/admin?tab=documents',
    '/admin?tab=stats',
    '/admin?tab=accounts',
    '/admin/actions/arc-extension',
    '/admin/actions/nhi',
    '/admin/actions/new',
  ];

  for (final english in [false, true]) {
    for (final width in [320.0, 375.0]) {
      for (final route in routes) {
        final name = '$route at $width, 200% text${english ? ', English' : ''}';
        testWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final base = TestApp(signedIn: false);
          base.repository.role = 'admin';
          final vm = BridgeViewModel(
            repository: base.repository,
            auth: base.auth,
            messages: loadMessages(),
            preferences: base.preferences,
            admin: AdminRepository(
              ApiClient(
                baseUrl: 'https://example.test',
                token: () async => 'token',
                client: MockClient(
                  (request) async => http.Response(
                    jsonEncode(_respond(request)),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  ),
                ),
              ),
            ),
          );
          addTearDown(vm.dispose);
          addTearDown(base.vm.dispose);
          if (english) vm.setEnglish(true);
          base.auth.signInAsDev('admin');
          await vm.loadProfile();
          expect(vm.isAdmin, isTrue);

          await tester.pumpWidget(
            CultureBridgeApp(viewModel: vm, initialLocation: route),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          expect(find.byType(ErrorPanel), findsNothing);
          expect(find.byType(LoadingNote), findsNothing);
        });
      }
    }
  }
}
