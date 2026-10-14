import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/domain/api_models.dart';
import 'package:culture_bridge/ui/features/assistant_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TestApp> mount(
    WidgetTester tester,
    String route,
    Size size, {
    bool signedIn = true,
    Future<void> Function(TestApp app)? before,
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

  for (final width in [320.0, 375.0, 768.0, 1024.0, 1440.0]) {
    for (final route in [
      '/',
      '/explore',
      '/share',
      '/profile',
      '/signin',
      '/experiences/first-rental',
      '/actions/arc',
      '/actions/arc/progress',
      '/actions/arc/complete',
    ]) {
      testWidgets('$route renders without overflow at $width', (tester) async {
        await mount(
          tester,
          route,
          Size(width, 900),
          before: (app) => app.vm.startAction('arc'),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            Key(width < 768 ? 'mobile-navigation' : 'desktop-navigation'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Home lists procedures from the API and my progress', (
    tester,
  ) async {
    await mount(
      tester,
      '/',
      const Size(1024, 1400),
      before: (app) => app.vm.startAction('arc'),
    );
    expect(find.text('申請工作證'), findsOneWidget);
    expect(find.byKey(const Key('progress-arc')), findsOneWidget);
  });

  testWidgets('Guests are sent to sign in, then back', (tester) async {
    final app = await mount(
      tester,
      '/actions/arc',
      const Size(1024, 1200),
      signedIn: false,
    );
    await tap(tester, find.byKey(const Key('start-action')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('dev-name')), 'mei');
    await tap(tester, find.byKey(const Key('dev-sign-in')));
    expect(app.vm.signedIn, isTrue);
    expect(find.byKey(const Key('start-action')), findsOneWidget);
  });

  testWidgets('Share: blank check, AI summary, edit and publish', (
    tester,
  ) async {
    final app = await mount(tester, '/share', const Size(1024, 1400));
    await tap(tester, find.byKey(const Key('review-draft')));
    expect(find.text('請先寫下發生了什麼事，再整理你的經驗。'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('share-voice')), '同學幫我適應生活。');
    await tester.pump(const Duration(milliseconds: 350));
    await tap(tester, find.byKey(const Key('review-draft')));
    expect(find.widgetWithText(TextField, 'AI 整理的情境'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('summary-reminder')), '我改過的提醒');
    await tap(tester, find.byKey(const Key('publish')));
    expect(app.repository.lastPublish!['reminder'], '我改過的提醒');
    expect(find.text('已發布'), findsOneWidget);
    expect(app.vm.draft.voice, '');
  });

  testWidgets('AI failure keeps the draft and explains', (tester) async {
    final app = await mount(tester, '/share', const Size(1024, 1400));
    app.repository.aiDown = true;
    await tester.enterText(find.byKey(const Key('share-voice')), '原話');
    await tester.pump(const Duration(milliseconds: 350));
    await tap(tester, find.byKey(const Key('review-draft')));
    expect(find.textContaining('AI 整理暫時無法使用'), findsOneWidget);
    expect(app.vm.draft.serverId, isNotNull);
  });

  testWidgets('Mobile navigation and language toggle work', (tester) async {
    await mount(tester, '/', const Size(375, 812));
    await tap(tester, find.byKey(const Key('nav-3')));
    expect(find.text('你的影響'), findsOneWidget);
    await tap(tester, find.byKey(const Key('locale-en')));
    expect(find.text('Your impact'), findsOneWidget);
  });

  testWidgets('Step interaction and stuck report reach the API', (
    tester,
  ) async {
    final app = await mount(
      tester,
      '/actions/arc/progress',
      const Size(375, 1400),
      before: (app) => app.vm.startAction('arc'),
    );
    await tap(tester, find.byKey(const Key('step-0')));
    expect(find.text('進度: 1 / 5'), findsOneWidget);

    await tap(tester, find.byKey(const Key('stuck-1')));
    await tap(tester, find.text('需要的文件不同'));
    await tap(tester, find.text('送出'));
    expect(app.repository.feedback.single['category'], 'documents');
    expect(app.repository.executions.single.steps[1].state, 'stuck');
  });

  testWidgets('Completion sends the outcome', (tester) async {
    final app = await mount(
      tester,
      '/actions/arc/complete',
      const Size(1024, 1400),
      before: (app) => app.vm.startAction('arc'),
    );
    await tap(tester, find.text('流程和原本不同'));
    await tap(tester, find.text('費用'));
    await tap(tester, find.byKey(const Key('send-outcome')));
    expect(app.repository.feedback.single['category'], 'fee');
    expect(app.repository.executions, isEmpty);
  });

  testWidgets('Save an experience and find it under My', (tester) async {
    final app = await mount(
      tester,
      '/experiences/professor-see',
      const Size(1024, 1400),
    );
    await tap(tester, find.byKey(const Key('save-professor-see')));
    expect(app.repository.saved, ['professor-see']);
    expect(find.text('已收藏，可以在「我的」找到。'), findsOneWidget);
    final saved = tester.widget<IconButton>(
      find.byKey(const Key('save-professor-see')),
    );
    expect(saved.isSelected, isTrue);
    expect(saved.tooltip, '取消收藏');

    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      '/profile',
      const Size(1024, 1600),
      before: (other) async {
        await other.repository.setSaved('professor-see', true);
      },
    );
    expect(find.text('收藏的經驗'), findsOneWidget);
    expect(find.byKey(const Key('saved-professor-see')), findsOneWidget);
    await tap(tester, find.text('取消收藏'));
    expect(find.byKey(const Key('saved-professor-see')), findsNothing);
    expect(find.textContaining('還沒有收藏'), findsOneWidget);
  });

  testWidgets('Guests are asked to sign in before saving', (tester) async {
    await mount(
      tester,
      '/experiences/professor-see',
      const Size(1024, 1400),
      signedIn: false,
    );
    await tap(tester, find.byKey(const Key('save-professor-see')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
  });

  testWidgets('Report and block from an experience', (tester) async {
    final app = await mount(
      tester,
      '/experiences/professor-see',
      const Size(1024, 1400),
    );
    await tap(tester, find.byKey(const Key('moderation-menu')));
    await tap(tester, find.text('檢舉'));
    await tap(tester, find.text('騷擾或霸凌'));
    await tap(tester, find.text('送出'));
    expect(app.repository.reports, ['professor-see:harassment']);

    await tap(tester, find.byKey(const Key('moderation-menu')));
    await tap(tester, find.text('封鎖這位作者'));
    await tap(tester, find.text('確認'));
    expect(app.repository.blocked, {'professor-see'});
  });

  testWidgets('Small landscape and 200 percent text remain readable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, '/profile', const Size(812, 375));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Assistant answers with cards and confirm cards', (tester) async {
    final app = await mount(tester, '/actions/arc', const Size(1024, 1200));
    app.repository.assistantReply = (message) => AssistantReply(
      conversationId: 'c1',
      text: '依據「申請或更新 ARC」流程卡。',
      cards: const [
        AssistantCard(
          type: 'action',
          id: 'arc',
          title: '申請或更新 ARC',
          verificationStatus: 'verified',
          lastVerifiedAt: '2026-08-14',
          recentSuccessCount: 12,
          sources: ['內政部移民署'],
          reminder: null,
        ),
      ],
      screenActions: const [ScreenAction('open_progress', 'arc', null)],
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
    await tap(tester, find.byKey(const Key('assistant-button')));
    await tester.enterText(find.byKey(const Key('assistant-input')), '幫我開始辦這個');
    await tap(tester, find.byKey(const Key('assistant-send')));
    expect(app.repository.assistantMessages, ['幫我開始辦這個']);
    expect(find.text('依據: 申請或更新 ARC'), findsOneWidget);
    expect(find.text('打開辦理進度'), findsOneWidget);

    await tap(tester, find.byKey(const Key('confirm-op1')));
    expect(app.repository.confirmed, ['op1']);
    expect(find.text('已開始，打開進度'), findsOneWidget);
  });

  test('Only whitelisted screen actions become routes', () {
    expect(
      screenActionPath(const ScreenAction('open_action', 'arc', null)),
      '/actions/arc',
    );
    expect(
      screenActionPath(
        const ScreenAction('open_explore', null, 'life_adaptation'),
      ),
      '/explore?topic=lifeAdaptation',
    );
    expect(
      screenActionPath(const ScreenAction('open_admin', 'x', null)),
      isNull,
    );
    expect(
      screenActionPath(const ScreenAction('open_action', null, null)),
      isNull,
    );
    expect(
      screenActionPath(const ScreenAction('open_action', '../admin', null)),
      '/actions/..%2Fadmin',
    );
  });

  testWidgets('Admin console is staff-only', (tester) async {
    await mount(tester, '/admin', const Size(1024, 900));
    expect(find.text('只有審查者與管理者可以使用。'), findsOneWidget);
  });
}
