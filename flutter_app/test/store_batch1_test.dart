// Store batch 1: terms and AI notice, legal links, reporting AI answers, blocking
// commenters, suspending authors, clearer error messages and the mobile start-up fixes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/app_loader.dart';
import 'package:culture_bridge/data/admin_repository.dart';
import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/data/auth_service.dart';
import 'package:culture_bridge/data/culture_repository.dart';
import 'package:culture_bridge/data/error_reporter.dart';
import 'package:culture_bridge/domain/api_models.dart';
import 'package:culture_bridge/ui/core/app_shell.dart';
import 'package:culture_bridge/ui/core/loading.dart';
import 'package:culture_bridge/ui/features/me_page.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher/link.dart';

import 'test_helpers.dart';

/// Sign-in that a person cancels: Google's sheet closed without choosing an account.
class _CancellingAuth extends AuthService {
  @override
  bool get signedIn => false;
  @override
  bool get usesDevLogin => false;
  @override
  Future<String?> idToken() async => null;
  @override
  Future<void> signInWithGoogle() async => throw const SignInCancelled();
  @override
  Future<void> signInAsDev(String name, {String? role}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteLogin() async {}
}

/// Staff API answered from memory; records what was sent.
class _AdminServer {
  final List<http.Request> sent = [];
  List<Map<String, Object?>> assistantReports = [
    {
      'id': 'a1',
      'question': '居留證要準備什麼？',
      'answer': '帶護照就好。',
      'reason': 'inaccurate',
      'details': '還要在學證明',
      'created_at': '2026-11-01T00:00:00Z',
      'status': 'open',
      'conversation_id': 'c1',
    },
  ];

  AdminRepository repository() => AdminRepository(
    ApiClient(
      baseUrl: 'https://example.test',
      token: () async => 'token',
      client: MockClient((request) async {
        sent.add(request);
        final body = _respond(request);
        return http.Response(
          body == null ? '' : jsonEncode(body),
          body == null ? 204 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  );

  Object? _respond(http.Request request) {
    final path = request.url.path.replaceFirst('/api', '');
    if (request.method == 'POST') {
      if (path == '/admin/assistant-reports/a1/resolve') {
        assistantReports = [];
      }
      return null;
    }
    return switch (path) {
      '/admin/assistant-reports' => assistantReports,
      '/admin/reports' => [
        {
          'report_id': 'r1',
          'target_id': 'professor-see',
          'target_status': 'published',
          'original_voice': '一篇被檢舉的貼文',
          'reasons': {'harassment': 2},
          'notes': <String>[],
          'report_count': 2,
          'author_ref': 'user-9',
        },
      ],
      _ => throw StateError('unexpected ${request.url}'),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TestApp> mount(
    WidgetTester tester,
    String route, {
    Size size = const Size(1280, 1600),
    bool signedIn = true,
    FutureOr<void> Function(TestApp app)? before,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = TestApp(signedIn: signedIn);
    await before?.call(app);
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: app.vm, initialLocation: route),
    );
    await tester.pumpAndSettle();
    addTearDown(app.vm.dispose);
    return app;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();

  group('Error messages', () {
    test('each server code has its own message', () {
      final vm = TestApp().vm;
      String text(String code, [int status = 400]) =>
          vm.errorText(ApiException(status, code));
      expect(text('content_not_allowed'), contains('不允許'));
      expect(text('account_suspended'), contains('停權'));
      expect(text('auth_unavailable'), contains('登入服務'));
      expect(text('daily_limit_reached', 429), '今天的次數用完了，明天再試');
      expect(text('rate_limited', 429), vm.t('rateLimited'));
      expect(text('already_reported'), '你已經檢舉過了');
      expect(text('too_many_saved'), contains('收藏'));
      expect(text('experience_not_found', 404), '這則內容已經不在了');
      expect(text('comment_not_found', 404), '這則內容已經不在了');
      for (final code in ['internal_error', 'http_502', 'http_503']) {
        expect(text(code, 503), '伺服器忙碌，請稍後再試');
      }
      expect(text('http_504', 504), '伺服器忙碌，請稍後再試');
      expect(text('terms_not_accepted', 403), contains('使用條款'));
      vm.setEnglish(true);
      expect(
        vm.errorText(const ApiException(429, 'daily_limit_reached')),
        contains('tomorrow'),
      );
    });

    test('a failed translation says the translation failed', () async {
      final app = TestApp();
      await Future<void>.delayed(Duration.zero);
      app.repository.translationError = const ApiException(
        503,
        'ai_unavailable',
      );
      final item = (await app.repository.explore()).items.first;
      // Shown in English to this zh reader, so the post has no translation yet.
      final english = ExperienceItem(
        id: item.id,
        topicId: item.topicId,
        identityType: item.identityType,
        sourceLocale: 'en',
        originalVoice: 'hello',
        situation: '',
        feelingOrAttempt: '',
        reminder: '',
        translation: null,
        publishedAt: item.publishedAt,
        helpfulCount: 0,
        experiencedTooCount: 0,
        differentCount: 0,
        myReactions: const [],
      );
      await app.vm.toggleTranslation(english);
      expect(app.vm.notice, '翻譯失敗，請稍後再試');
      expect(app.vm.notice, isNot(contains('草稿')));
    });

    test('a reaction or save that already happened counts as done', () async {
      final app = TestApp();
      await Future<void>.delayed(Duration.zero);
      await app.vm.loadExperience('professor-see');
      final item = app.vm.experience('professor-see').data!.item;
      app.repository.reactError = const ApiException(409, 'conflict');
      await app.vm.toggleReaction(item, 'experienced_too');
      expect(app.vm.notice, isNull);
      expect(
        app.vm.experience('professor-see').data!.item.myReactions,
        contains('experienced_too'),
      );

      app.repository.saveError = const ApiException(409, 'conflict');
      await app.vm.toggleSaved(item);
      expect(app.vm.notice, '已收藏，在「我的 › 收藏」找得到');
      expect(app.vm.experience('professor-see').data!.item.saved, isTrue);
    });

    test(
      'a confirm that could not reach the server can be tried again',
      () async {
        final app = TestApp();
        await Future<void>.delayed(Duration.zero);
        app.repository.confirmErrors.add(
          const ApiException(0, 'network_error'),
        );
        final operation = PendingOperation(
          id: 'op1',
          summary: '開始辦理',
          status: 'pending',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          targetId: 'arc',
          result: null,
        );
        await app.vm.resolveOperation(operation, true);
        expect(app.vm.operationStates['op1'], isNot('network_error'));
        expect(app.vm.operationStates['op1'] ?? 'pending', 'pending');
        expect(app.vm.operationRetryable('op1'), isTrue);
        await app.vm.resolveOperation(operation, true);
        expect(app.vm.operationStates['op1'], 'confirmed');
        expect(app.vm.operationRetryable('op1'), isFalse);
      },
    );

    testWidgets('the confirm card stays usable after a network error', (
      tester,
    ) async {
      final app = await mount(tester, '/actions/arc');
      app.repository.assistantReply = (message) => AssistantReply(
        conversationId: 'c1',
        text: '要幫你開始辦理嗎？',
        cards: const [],
        screenActions: const [],
        pendingOperations: [
          PendingOperation(
            id: 'op1',
            summary: '開始辦理「申請或更新 ARC」',
            status: 'pending',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            targetId: 'arc',
            result: null,
          ),
        ],
        fallback: false,
      );
      app.repository.confirmErrors.add(const ApiException(0, 'network_error'));
      await tap(tester, find.byKey(const Key('assistant-button')));
      await tap(tester, find.text('居留證要準備什麼？'));
      await tap(tester, find.byKey(const Key('confirm-op1')));
      expect(find.text('無法完成'), findsNothing);
      expect(find.byKey(const Key('operation-retry-op1')), findsOneWidget);
      await tap(tester, find.byKey(const Key('confirm-op1')));
      expect(app.repository.confirmed, ['op1']);
      expect(find.text('已開始，打開進度'), findsOneWidget);
    });
  });

  group('Terms of use', () {
    test('accepting stores the version and clears the need', () async {
      final app = TestApp();
      app.repository.acceptedTerms = null;
      // Signing in lands asynchronously; a profile asked for before it is dropped.
      await Future<void>.delayed(Duration.zero);
      await app.vm.loadProfile();
      expect(app.vm.needsTerms, isTrue);
      expect(await app.vm.acceptTerms(), isNull);
      expect(app.repository.termsAccepted, [1]);
      expect(app.vm.needsTerms, isFalse);
    });

    test('a server that says the terms are missing asks again', () async {
      final app = TestApp();
      await Future<void>.delayed(Duration.zero);
      await app.vm.loadProfile();
      expect(app.vm.needsTerms, isFalse);
      // Accepted on an older version: the server refuses the post.
      app.repository.acceptedTerms = 0;
      app.vm.updateDraft(title: '標題', voice: '內文內文', category: 'life');
      final (error, item) = await app.vm.publishDraft();
      expect(item, isNull);
      expect(error, contains('使用條款'));
      expect(app.vm.needsTerms, isTrue);
    });

    test('the config sets the version and the legal pages', () {
      final config = ClientConfig.fromJson({
        'terms_version': 3,
        'legal': {
          'privacy': '/privacy',
          'terms': '/terms',
          'account_deletion': '/account-deletion',
        },
        'support_email': 'help@example.test',
      });
      expect(config.termsVersion, 3);
      expect(config.termsPath, '/terms');
      expect(config.supportEmail, 'help@example.test');
      final fallback = ClientConfig.fromJson(null);
      expect(fallback.termsVersion, 1);
      expect(fallback.privacyPath, '/privacy');
      expect(fallback.supportEmail, isNull);
    });

    testWidgets('the first post asks to accept the terms, then publishes', (
      tester,
    ) async {
      final app = await mount(
        tester,
        '/share',
        before: (app) => app.repository.acceptedTerms = null,
      );
      await tester.enterText(find.byKey(const Key('share-title')), '第一篇');
      await tester.enterText(find.byKey(const Key('share-voice')), '我的經驗分享');
      await tap(tester, find.byKey(const Key('share-cat-life')));
      await tap(tester, find.byKey(const Key('publish')));
      expect(find.byKey(const Key('terms-sheet')), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsWidgets);
      expect(find.textContaining('24 小時'), findsOneWidget);
      expect(find.textContaining('零容忍'), findsOneWidget);
      expect(find.textContaining('停權'), findsWidgets);
      expect(
        tester.widget<Link>(find.byKey(const Key('terms-link-terms'))).uri,
        Uri.parse('https://example.test/terms'),
      );
      expect(
        tester.widget<Link>(find.byKey(const Key('terms-link-privacy'))).uri,
        Uri.parse('https://example.test/privacy'),
      );
      expect(app.repository.lastPublish, isNull);
      await tap(tester, find.text('同意並繼續'));
      expect(app.repository.termsAccepted, [1]);
      expect(app.repository.lastPublish?['title'], '第一篇');
      // Await the debounced draft save.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a comment waits for the terms; declining sends nothing', (
      tester,
    ) async {
      final app = await mount(
        tester,
        '/experiences/professor-see',
        before: (app) => app.repository.acceptedTerms = null,
      );
      await tester.enterText(find.byKey(const Key('comment-box')), '我也是');
      await tap(tester, find.byKey(const Key('send-comment')));
      expect(find.byKey(const Key('terms-sheet')), findsOneWidget);
      await tap(tester, find.byKey(const Key('terms-decline')));
      expect(find.byKey(const Key('terms-sheet')), findsNothing);
      expect(app.repository.postComments['professor-see'], isNull);
    });

    testWidgets('a server refusal opens the terms and sends after accepting', (
      tester,
    ) async {
      final app = await mount(tester, '/experiences/professor-see');
      app.repository.acceptedTerms = 0;
      await tester.enterText(find.byKey(const Key('comment-box')), '我也是');
      await tap(tester, find.byKey(const Key('send-comment')));
      expect(find.byKey(const Key('terms-sheet')), findsOneWidget);
      await tap(tester, find.text('同意並繼續'));
      expect(app.repository.postComments['professor-see']!.single.body, '我也是');
    });
  });

  group('Assistant', () {
    testWidgets('the first question shows the AI notice once', (tester) async {
      final app = await mount(
        tester,
        '/',
        before: (app) => app.preferences.aiNoticeSeen = false,
      );
      await tap(tester, find.byKey(const Key('assistant-button')));
      expect(find.text('AI 回答可能有誤，請以官方公告為準。'), findsOneWidget);
      await tap(tester, find.text('居留證要準備什麼？'));
      expect(find.byKey(const Key('ai-notice')), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsWidgets);
      expect(app.repository.assistantMessages, isEmpty);
      await tap(tester, find.byKey(const Key('ai-notice-ok')));
      expect(app.preferences.aiNoticeSeen, isTrue);
      expect(app.repository.assistantMessages, ['居留證要準備什麼？']);

      await tester.enterText(find.byKey(const Key('assistant-input')), '再問');
      await tap(tester, find.byKey(const Key('assistant-send')));
      expect(find.byKey(const Key('ai-notice')), findsNothing);
      expect(app.repository.assistantMessages.last, '再問');
    });

    testWidgets('an answer can be reported', (tester) async {
      final app = await mount(tester, '/');
      await tap(tester, find.byKey(const Key('assistant-button')));
      await tap(tester, find.text('居留證要準備什麼？'));
      await tap(tester, find.byKey(const Key('report-answer-1')));
      for (final reason in ['不正確', '冒犯', '有害', '其他']) {
        expect(inDialog(reason), findsOneWidget);
      }
      await tap(tester, inDialog('不正確'));
      await tester.enterText(
        find.byKey(const Key('answer-report-details')),
        '少了文件',
      );
      await tap(tester, inDialog('送出'));
      expect(app.repository.assistantReports.single, {
        'conversation_id': 'conv-1',
        'question': '居留證要準備什麼？',
        'answer': '依據「申請工作證」流程卡（已驗證）。',
        'reason': 'inaccurate',
        'details': '少了文件',
      });
    });

    test('the AI notice is remembered on the device', () async {
      final app = TestApp();
      app.preferences.aiNoticeSeen = false;
      expect(app.vm.aiNoticeSeen, isFalse);
      app.vm.acknowledgeAiNotice();
      expect(app.preferences.aiNoticeSeen, isTrue);
      expect(app.vm.aiNoticeSeen, isTrue);
    });
  });

  group('Comments', () {
    testWidgets('block the person who wrote a comment', (tester) async {
      late CommentItem other;
      final app = await mount(
        tester,
        '/experiences/professor-see',
        before: (app) =>
            other = app.repository.addOthersComment('professor-see', '難聽的話'),
      );
      await tap(tester, find.byKey(Key('comment-menu-${other.id}')));
      expect(find.text('移除留言'), findsNothing);
      await tap(tester, find.text('封鎖這位留言者'));
      await tap(tester, inDialog('確認'));
      expect(app.repository.blockedCommenters, [other.id]);
      expect(find.text('難聽的話'), findsNothing);
    });

    testWidgets('the post author can remove a comment', (tester) async {
      late CommentItem other;
      final app = await mount(
        tester,
        '/experiences/professor-see',
        before: (app) => other = app.repository.addOthersComment(
          'professor-see',
          '廣告留言',
          removable: true,
        ),
      );
      await tap(tester, find.byKey(Key('comment-menu-${other.id}')));
      await tap(tester, find.text('移除留言'));
      await tap(tester, inDialog('移除'));
      expect(app.repository.deletedComments, [other.id]);
      expect(find.text('廣告留言'), findsNothing);
    });

    test('comments read whether the reader may remove them', () {
      final comment = CommentItem.fromJson({
        'id': 'c1',
        'body': 'hi',
        'created_at': '2026-11-01T00:00:00Z',
        'removable_by_me': true,
      });
      expect(comment.removableByMe, isTrue);
      expect(
        CommentItem.fromJson({
          'id': 'c2',
          'body': 'hi',
          'created_at': '2026-11-01T00:00:00Z',
        }).removableByMe,
        isFalse,
      );
    });
  });

  group('Legal links', () {
    testWidgets('settings link to the privacy policy, terms and support', (
      tester,
    ) async {
      await mount(
        tester,
        '/profile/settings',
        before: (app) => app.vm.config = ClientConfig.fromJson({
          'support_email': 'help@example.test',
        }),
      );
      Uri uri(String key) => tester.widget<Link>(find.byKey(Key(key))).uri!;
      expect(uri('link-privacy'), Uri.parse('https://example.test/privacy'));
      expect(uri('link-terms'), Uri.parse('https://example.test/terms'));
      expect(uri('link-support'), Uri.parse('mailto:help@example.test'));
      expect(find.text('隱私權政策'), findsOneWidget);
      expect(find.text('使用條款'), findsOneWidget);
    });

    testWidgets('without a support email there is no support link', (
      tester,
    ) async {
      await mount(tester, '/profile/settings');
      expect(find.byKey(const Key('link-privacy')), findsOneWidget);
      expect(find.byKey(const Key('link-support')), findsNothing);
    });

    testWidgets('signing in mentions the terms and links them', (tester) async {
      await mount(tester, '/signin', signedIn: false);
      expect(find.text('登入即表示你同意使用條款與隱私權政策'), findsOneWidget);
      expect(find.byKey(const Key('link-terms')), findsOneWidget);
      expect(find.byKey(const Key('link-privacy')), findsOneWidget);
    });
  });

  group('Staff', () {
    Future<(TestApp, _AdminServer)> mountAdmin(
      WidgetTester tester,
      String route, {
      String role = 'admin',
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = TestApp(signedIn: false);
      base.repository.role = role;
      final server = _AdminServer();
      final vm = BridgeViewModel(
        repository: base.repository,
        auth: base.auth,
        messages: loadMessages(),
        preferences: base.preferences,
        admin: server.repository(),
      );
      addTearDown(vm.dispose);
      addTearDown(base.vm.dispose);
      await base.auth.signInAsDev(role);
      await vm.loadProfile();
      await tester.pumpWidget(
        CultureBridgeApp(viewModel: vm, initialLocation: route),
      );
      await tester.pumpAndSettle();
      return (base, server);
    }

    testWidgets('open assistant reports can be marked handled', (tester) async {
      final (_, server) = await mountAdmin(
        tester,
        '/admin?tab=assistant',
        role: 'reviewer',
      );
      expect(find.text('居留證要準備什麼？', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('帶護照就好。'), findsOneWidget);
      expect(server.sent.first.url.queryParameters['status'], 'open');
      await tap(tester, find.text('已處理'));
      final resolve = server.sent.firstWhere((r) => r.method == 'POST');
      expect(resolve.url.path, '/api/admin/assistant-reports/a1/resolve');
      expect(find.textContaining('帶護照就好。'), findsNothing);
    });

    testWidgets('an admin can suspend the author of reported content', (
      tester,
    ) async {
      final (_, server) = await mountAdmin(tester, '/admin?tab=reports');
      await tap(tester, find.text('停權作者'));
      expect(server.sent.where((r) => r.method == 'POST'), isEmpty);
      await tap(tester, inDialog('停權'));
      expect(
        server.sent.where((r) => r.method == 'POST').single.url.path,
        '/api/admin/reports/r1/suspend-author',
      );
    });

    testWidgets('reviewers do not see the suspend action', (tester) async {
      await mountAdmin(tester, '/admin?tab=reports', role: 'reviewer');
      expect(find.text('隱藏內容'), findsOneWidget);
      expect(find.text('停權作者'), findsNothing);
    });

    test('the staff API sends the agreed requests', () async {
      final server = _AdminServer();
      final repo = server.repository();
      final reports = await repo.assistantReports('open');
      expect(reports.single.reason, 'inaccurate');
      expect(reports.single.conversationId, 'c1');
      await repo.resolveAssistantReport('a1', note: '已更新文件');
      expect(jsonDecode(server.sent.last.body), {'note': '已更新文件'});
      await repo.suspendReportAuthor('r1');
      expect(server.sent.last.url.path, '/api/admin/reports/r1/suspend-author');
      expect((await repo.reports('pending')).single.authorRef, 'user-9');
    });
  });

  group('Culture API', () {
    test('new calls use the agreed paths and bodies', () async {
      final sent = <http.Request>[];
      final repo = ApiCultureRepository(
        ApiClient(
          baseUrl: 'https://example.test',
          token: () async => 't',
          client: MockClient((request) async {
            sent.add(request);
            final body = request.url.path == '/api/me/terms'
                ? jsonEncode({
                    'id': 'u1',
                    'role': 'student',
                    'preferred_locale': 'zh-Hant',
                    'terms_version': 1,
                  })
                : request.url.path == '/api/assistant/reports'
                ? jsonEncode({'id': 'r1'})
                : '';
            return http.Response(
              body,
              body.isEmpty ? 201 : 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      final profile = await repo.acceptTerms(1);
      expect(profile.termsVersion, 1);
      expect(jsonDecode(sent.last.body), {'version': 1});
      await repo.blockCommenter('c9');
      expect(sent.last.url.path, '/api/blocks');
      expect(jsonDecode(sent.last.body), {'comment_id': 'c9'});
      await repo.reportAssistantAnswer(
        conversationId: 'conv',
        question: 'q' * 1200,
        answer: 'a' * 5000,
        reason: 'harmful',
        details: '  ',
      );
      final body = jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect(sent.last.url.path, '/api/assistant/reports');
      expect((body['question'] as String).length, 1000);
      expect((body['answer'] as String).length, 4000);
      expect(body['reason'], 'harmful');
      expect(body['details'], isNull);
      expect(body['conversation_id'], 'conv');
      expect(repo.siteUrl('/terms'), 'https://example.test/terms');
    });
  });

  group('Mobile', () {
    test('apps use the production API unless one is configured', () {
      String noOrigin() => throw UnsupportedError('no page on mobile');
      expect(
        ApiClient.resolveBaseUrl(
          configured: '',
          web: false,
          pageOrigin: noOrigin,
        ),
        ApiClient.productionBaseUrl,
      );
      expect(
        ApiClient.productionBaseUrl,
        'https://culture-bridge-z7gcp33vjq-de.a.run.app',
      );
      expect(
        ApiClient.resolveBaseUrl(
          configured: 'http://10.0.2.2:8000/',
          web: false,
          pageOrigin: noOrigin,
        ),
        'http://10.0.2.2:8000',
      );
      expect(
        ApiClient.resolveBaseUrl(
          configured: '',
          web: true,
          pageOrigin: () => 'https://app.example.test',
        ),
        'https://app.example.test',
      );
    });

    test('phones need their own Firebase app id', () {
      const server = {
        'apiKey': 'key',
        'projectId': 'proj',
        'appId': '1:web-app-id',
        'messagingSenderId': '42',
        'authDomain': 'proj.firebaseapp.com',
      };
      // The web keeps using the server's web settings.
      expect(
        FirebaseConfig.resolve(
          web: true,
          platform: TargetPlatform.android,
          defines: const {},
          server: server,
        )!.options.appId,
        '1:web-app-id',
      );
      expect(
        () => FirebaseConfig.resolve(
          web: false,
          platform: TargetPlatform.android,
          defines: const {},
          server: server,
        ),
        throwsA(
          isA<FirebaseSetupError>().having(
            (e) => e.toString(),
            'message',
            contains('FIREBASE_ANDROID_APP_ID'),
          ),
        ),
      );
      final android = FirebaseConfig.resolve(
        web: false,
        platform: TargetPlatform.android,
        defines: const {'FIREBASE_ANDROID_APP_ID': '1:android'},
        server: server,
      )!;
      expect(android.options.appId, '1:android');
      expect(android.options.apiKey, 'key');
      final ios = FirebaseConfig.resolve(
        web: false,
        platform: TargetPlatform.iOS,
        defines: const {
          'FIREBASE_APP_ID': '1:shared',
          'FIREBASE_API_KEY': 'ios-key',
          'FIREBASE_PROJECT_ID': 'proj',
        },
        server: null,
      )!;
      expect(ios.options.appId, '1:shared');
      expect(ios.options.apiKey, 'ios-key');
      // No Firebase anywhere: development sign-in, as before.
      expect(
        FirebaseConfig.resolve(
          web: false,
          platform: TargetPlatform.android,
          defines: const {},
          server: null,
        ),
        isNull,
      );
    });

    testWidgets('a loading screen shows until the app is ready', (
      tester,
    ) async {
      final ready = Completer<BridgeViewModel>();
      final app = TestApp();
      addTearDown(app.vm.dispose);
      await tester.pumpWidget(AppLoader(start: () => ready.future));
      expect(find.byKey(const Key('launch-screen')), findsOneWidget);
      expect(find.text('Culture Bridge'), findsWidgets);
      ready.complete(app.vm);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-screen')), findsNothing);
      expect(find.byType(CultureBridgeApp), findsOneWidget);
    });

    testWidgets('a failed start shows why and can be retried', (tester) async {
      final app = TestApp();
      addTearDown(app.vm.dispose);
      var tries = 0;
      await tester.pumpWidget(
        AppLoader(
          start: () async {
            if (tries++ == 0) {
              throw const FirebaseSetupError('FIREBASE_IOS_APP_ID');
            }
            return app.vm;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-error')), findsOneWidget);
      expect(find.textContaining('FIREBASE_IOS_APP_ID'), findsOneWidget);
      await tester.tap(find.byKey(const Key('launch-retry')));
      await tester.pumpAndSettle();
      expect(tries, 2);
      expect(find.byType(CultureBridgeApp), findsOneWidget);
    });

    testWidgets('a start that never answers ends in the error screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        AppLoader(
          start: () => Completer<BridgeViewModel>().future,
          timeout: const Duration(seconds: 5),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-error')), findsOneWidget);
    });

    testWidgets('system back off a tab goes Home, not out of the app', (
      tester,
    ) async {
      await mount(tester, '/explore', size: const Size(375, 812));
      Future<void> systemBack() async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(
            const MethodCall('popRoute'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      final closed = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') closed.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await systemBack();
      expect(location(tester), '/');
      expect(closed, isEmpty);
      // On Home, back leaves the app.
      await systemBack();
      expect(closed, hasLength(1));
    });

    testWidgets('system back on a page opened directly goes to its parent', (
      tester,
    ) async {
      await mount(tester, '/profile/settings', size: const Size(375, 812));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(location(tester), '/profile');
    });

    testWidgets('landscape phones keep the sidebar clear of the notch', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(left: 59, right: 59);
      addTearDown(tester.view.resetPadding);
      await mount(tester, '/', size: const Size(932, 430));
      final sidebar = tester.getRect(
        find.byKey(const Key('desktop-navigation')),
      );
      expect(sidebar.left, greaterThanOrEqualTo(59));
      final main = tester.getRect(find.byType(PageFrame).first);
      expect(main.right, lessThanOrEqualTo(932 - 59));
    });

    testWidgets('closing the Google sheet is not an error', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = TestApp(signedIn: false);
      final vm = BridgeViewModel(
        repository: base.repository,
        auth: _CancellingAuth(),
        messages: loadMessages(),
        preferences: base.preferences,
      );
      addTearDown(vm.dispose);
      addTearDown(base.vm.dispose);
      await tester.pumpWidget(
        CultureBridgeApp(viewModel: vm, initialLocation: '/signin'),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('google-sign-in')));
      expect(find.text(vm.t('genericError')), findsNothing);
      expect(find.byType(ErrorPanel), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('google-sign-in')))
            .onPressed,
        isNotNull,
      );
    });

    test('Firebase cancel codes count as cancelled', () {
      for (final code in [
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'web-context-cancelled',
        'canceled',
      ]) {
        expect(FirebaseAuthService.isCancelled(code), isTrue, reason: code);
      }
      expect(
        FirebaseAuthService.isCancelled('network-request-failed'),
        isFalse,
      );
    });

    test('errors report the screen the person was on', () async {
      final sent = <http.Request>[];
      final reporter = ErrorReporter(
        ApiClient(
          baseUrl: 'https://example.test',
          token: () async => null,
          client: MockClient((request) async {
            sent.add(request);
            return http.Response('', 204);
          }),
        ),
        route: () => '/experiences/abc',
      );
      await reporter.report(StateError('boom'), null);
      expect(
        (jsonDecode(sent.single.body) as Map)['route'],
        '/experiences/abc',
      );
    });

    testWidgets('the app tells error reports where it is', (tester) async {
      await mount(tester, '/explore');
      expect(CultureBridgeApp.location, '/explore');
    });

    testWidgets('titles cut after 24 characters keep emoji whole', (
      tester,
    ) async {
      final voice = '${'😀' * 30}後面';
      final app = await mount(
        tester,
        '/profile',
        before: (app) => app.repository.mine['d1'] = MyExperience(
          id: 'd1',
          status: 'draft',
          topicId: 'life_adaptation',
          identityType: 'other',
          originalVoice: voice,
          latestSummary: null,
          impact: const Impact(0, 0, 0, 0),
        ),
      );
      expect(app.vm.mine.data, isNotEmpty);
      expect(find.text('${'😀' * 24}…'), findsOneWidget);
    });

    test('post headings cut by characters too', () {
      final item = ExperienceItem(
        id: 'x',
        topicId: 'life_adaptation',
        identityType: 'other',
        sourceLocale: 'zh-Hant',
        originalVoice: '👍' * 30,
        situation: '',
        feelingOrAttempt: '',
        reminder: '',
        translation: null,
        publishedAt: DateTime(2026),
        helpfulCount: 0,
        experiencedTooCount: 0,
        differentCount: 0,
        myReactions: const [],
      );
      expect(item.heading(false), '${'👍' * 24}…');
    });

    testWidgets('a photo picked before Android restarted the app is used', (
      tester,
    ) async {
      final previous = recoverLostAvatarPhoto;
      addTearDown(() => recoverLostAvatarPhoto = previous);
      recoverLostAvatarPhoto = () async => Uint8List.fromList([1, 2, 3]);
      final app = await mount(tester, '/profile/settings');
      expect(app.repository.uploadedPhotos, [
        base64Encode([1, 2, 3]),
      ]);
    });

    test('iOS settings for the App Store', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      String after(String key) =>
          plist.split('<key>$key</key>')[1].trim().split('\n').first.trim();
      expect(after('ITSAppUsesNonExemptEncryption'), '<false/>');
      expect(after('CFBundleName'), '<string>Culture Bridge</string>');
      expect(plist, contains('<key>CFBundleLocalizations</key>'));
      expect(plist, contains('<string>zh-Hant</string>'));
      expect(plist, contains('<string>en</string>'));
    });
  });

  group('Review fixes', () {
    test('a full saved list says so instead of pretending it saved', () async {
      final app = TestApp();
      await Future<void>.delayed(Duration.zero);
      await app.vm.loadExperience('professor-see');
      final item = app.vm.experience('professor-see').data!.item;
      app.repository.saveError = const ApiException(409, 'too_many_saved');
      await app.vm.toggleSaved(item);
      expect(app.vm.notice, isNotNull);
      expect(app.vm.notice, isNot(contains('已收藏')));
      expect(app.vm.experience('professor-see').data!.item.saved, isFalse);
    });

    test(
      'drafts go to AI tag suggestions only after the terms are accepted',
      () async {
        final app = TestApp();
        await Future<void>.delayed(Duration.zero);
        app.repository.acceptedTerms = null;
        await app.vm.loadProfile();
        app.vm.updateDraft(title: '第一次租屋', voice: '房東要兩個月押金，我先問了學長姐。');
        await app.vm.refreshTagSuggestions();
        expect(app.repository.suggestCalls, 0);
        await app.vm.acceptTerms();
        await app.vm.refreshTagSuggestions();
        expect(app.repository.suggestCalls, 1);
      },
    );

    testWidgets('the loader opens the link the app was started with', (
      tester,
    ) async {
      final app = TestApp();
      addTearDown(app.vm.dispose);
      await tester.pumpWidget(
        AppLoader(
          start: () async => app.vm,
          initialLocation: '/explore?cat=life',
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      expect(router.state.uri.toString(), '/explore?cat=life');
    });
  });
}
