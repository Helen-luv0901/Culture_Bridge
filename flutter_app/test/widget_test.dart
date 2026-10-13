import 'package:culture_bridge/app.dart';
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
}
