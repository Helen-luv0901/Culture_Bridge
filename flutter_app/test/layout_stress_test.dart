// D-15 manual checklist, automated where possible: every main screen at phone widths with
// 200% text and in English must lay out without overflow.
import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/domain/api_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const routes = [
    '/',
    '/explore',
    '/share',
    '/profile',
    '/signin',
    '/experiences/first-rental',
    '/actions/arc',
    '/actions/arc/progress',
    '/actions/arc/complete',
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
          final app = TestApp();
          if (english) app.vm.setEnglish(true);
          await app.vm.startAction('arc');
          await app.repository.setSaved('first-rental', true);
          await tester.pumpWidget(
            CultureBridgeApp(viewModel: app.vm, initialLocation: route),
          );
          await tester.pumpAndSettle();
          addTearDown(app.vm.dispose);
          expect(tester.takeException(), isNull);
        });
      }
      testWidgets(
        'assistant panel at $width, 200% text${english ? ', English' : ''}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final app = TestApp();
          if (english) app.vm.setEnglish(true);
          app.repository.assistantReply = (_) => _longReply();
          await tester.pumpWidget(
            CultureBridgeApp(viewModel: app.vm, initialLocation: '/'),
          );
          await tester.pumpAndSettle();
          addTearDown(app.vm.dispose);
          await tester.tap(find.byKey(const Key('assistant-button')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('assistant-input')),
            'How do I extend my ARC?',
          );
          await tester.tap(find.byKey(const Key('assistant-send')));
          await tester.pumpAndSettle();
          expect(app.repository.assistantMessages, hasLength(1));
          expect(find.byKey(const Key('confirm-op1')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

AssistantReply _longReply() => AssistantReply(
  conversationId: 'c1',
  text:
      'According to the procedure card "Extending your Alien Resident '
      'Certificate", apply online within three months before it expires.',
  cards: const [
    AssistantCard(
      type: 'action',
      id: 'arc',
      title: 'Extending your Alien Resident Certificate (ARC) as a student',
      verificationStatus: 'community_supported',
      lastVerifiedAt: '2026-08-14',
      recentSuccessCount: 12,
      sources: ['National Immigration Agency, Ministry of the Interior'],
      reminder: 'Bring your enrollment certificate issued within one month.',
    ),
    AssistantCard(
      type: 'experience',
      id: 'first-rental',
      title: null,
      verificationStatus: null,
      lastVerifiedAt: null,
      recentSuccessCount: 0,
      sources: [],
      reminder: 'Read every clause with a friend before signing.',
    ),
  ],
  screenActions: const [ScreenAction('open_progress', 'arc', null)],
  pendingOperations: [
    PendingOperation(
      id: 'op1',
      summary: 'Start "Extending your Alien Resident Certificate (ARC)"',
      status: 'pending',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      targetId: 'arc',
      result: null,
    ),
  ],
  fallback: false,
);
