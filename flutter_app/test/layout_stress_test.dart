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
    '/faqs',
    '/faqs/nisa-1070',
    '/faqs/nisa-900',
    '/welcome',
    '/profile/settings',
    '/profile?tab=saved',
    '/guide/welcome',
    '/official',
    '/explore?q=居留',
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
          app.vm.toggleSavedFaq('nisa-1070');
          await app.repository.setSaved('first-rental', true);
          app.repository
            ..nickname = 'A rather long nickname, 30 ch'
            ..realName = '王大明 Alexander Christopher Montgomery'
            ..signAs('first-rental', 'A rather long nickname, 30 ch');
          await app.vm.loadProfile();
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
          expect(
            find.byKey(const Key('assistant-post-nisa-1070')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

AssistantReply _longReply() => AssistantReply(
  conversationId: 'c1',
  text:
      'According to the official answer from the National Immigration Agency, '
      'apply within thirty days before your Alien Resident Certificate expires.',
  cards: const [
    AssistantCard(
      type: 'faq',
      id: 'nisa-1070',
      title:
          'How early before my Alien Resident Certificate (ARC) expires can I '
          'apply to extend it as a degree student?',
      excerpt: 'Apply within 30 days before it expires, with your passport.',
      category: 'Visas, residence permits and Alien Resident Certificates',
      agency: 'National Immigration Agency, Ministry of the Interior',
      postedOn: '2026-08-03',
    ),
    AssistantCard(
      type: 'experience',
      id: 'first-rental',
      title: '',
      reminder: 'Read every clause with a friend before signing.',
    ),
  ],
  screenActions: const [ScreenAction('open_faq', 'nisa-1070', null)],
  fallback: false,
);
