import 'package:culture_bridge/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// On a phone the keyboard takes half the screen. Browsers either shrink the page or
/// report the keyboard as a bottom inset; either way the chat must stay big enough to use
/// and the input must stay above the keyboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TestApp> openAssistant(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final app = TestApp(signedIn: true);
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: app.vm, initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    addTearDown(app.vm.dispose);
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pumpAndSettle();
    return app;
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(Key(key)));

  Finder urgentInLog() => find.descendant(
    of: find.byKey(const Key('assistant-log')),
    matching: find.textContaining('1990'),
  );

  testWidgets(
    'A keyboard over the page: the sheet sits above it, chat stays usable',
    (tester) async {
      await openAssistant(tester, const Size(375, 812));
      expect(
        urgentInLog(),
        findsNothing,
      ); // keyboard closed: the line sits by the input

      // The browser keeps the page size and reports the keyboard as an inset.
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pumpAndSettle();
      const keyboardTop = 812 - 330;
      expect(
        rectOf(tester, 'assistant-input').bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        rectOf(tester, 'assistant-sheet-motion').bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      // The sheet takes the whole height left, and the chat most of it.
      expect(rectOf(tester, 'assistant-sheet-motion').top, lessThan(30));
      expect(rectOf(tester, 'assistant-log').height, greaterThan(250));
      // The emergency line moves into the chat (it scrolls), not gone.
      expect(urgentInLog(), findsOneWidget);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(urgentInLog(), findsNothing);
      expect(rectOf(tester, 'assistant-sheet-motion').top, greaterThan(60));
    },
  );

  testWidgets('A page shrunk by the keyboard: the chat still gets most of it', (
    tester,
  ) async {
    await openAssistant(tester, const Size(375, 812));
    // The browser shrinks the page to what the keyboard leaves.
    tester.view.physicalSize = const Size(375, 480);
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'assistant-input').bottom, lessThanOrEqualTo(480));
    expect(rectOf(tester, 'assistant-sheet-motion').top, lessThan(30));
    expect(rectOf(tester, 'assistant-log').height, greaterThan(250));
    expect(urgentInLog(), findsOneWidget);
  });
}
