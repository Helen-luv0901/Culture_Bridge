import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/ui/core/app_shell.dart' show AppIconSlot;
import 'package:culture_bridge/ui/core/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Motion that makes the app feel like it listens (apple-design / emil-design-eng skills):
/// press feedback, the assistant sliding in and out, and less motion when the device asks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TestApp> mount(
    WidgetTester tester,
    String route,
    Size size, {
    bool reduceMotion = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    final app = TestApp(signedIn: true);
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: app.vm, initialLocation: route),
    );
    await tester.pumpAndSettle();
    addTearDown(app.vm.dispose);
    return app;
  }

  double pressScaleOf(WidgetTester tester, Finder press) => tester
      .widget<AnimatedScale>(
        find.descendant(of: press, matching: find.byType(AnimatedScale)),
      )
      .scale;

  testWidgets('Taps leave no Android ripple', (tester) async {
    await mount(tester, '/explore', const Size(375, 812));
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.splashFactory, NoSplash.splashFactory);
  });

  testWidgets('A pressed card shrinks a little and springs back on release', (
    tester,
  ) async {
    await mount(tester, '/explore', const Size(375, 812));
    final card = find.ancestor(
      of: find.byKey(const Key('board-card-life')),
      matching: find.byType(PressScale),
    );
    final press = card.evaluate().isEmpty
        ? find.descendant(
            of: find.byKey(const Key('board-card-life')),
            matching: find.byType(PressScale),
          )
        : card;
    expect(pressScaleOf(tester, press.first), 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('board-card-life'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(pressScaleOf(tester, press.first), Motion.pressScale);
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 200));
    expect(pressScaleOf(tester, press.first), 1);
  });

  testWidgets('With reduced motion a pressed card keeps its size', (
    tester,
  ) async {
    await mount(tester, '/explore', const Size(375, 812), reduceMotion: true);
    final press = find.descendant(
      of: find.byKey(const Key('board-card-life')),
      matching: find.byType(PressScale),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('board-card-life'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(pressScaleOf(tester, press.first), 1);
    await gesture.cancel();
  });

  testWidgets(
    'On a phone the assistant slides up, and slides away before it goes',
    (tester) async {
      final app = await mount(tester, '/', const Size(375, 812));
      await tester.tap(find.byKey(const Key('assistant-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      SlideTransition sheet() => tester.widget<SlideTransition>(
        find.byKey(const Key('assistant-sheet-motion')),
      );
      expect(sheet().position.value.dy, greaterThan(0)); // still on its way up
      await tester.pumpAndSettle();
      expect(sheet().position.value.dy, 0);

      await tester.tap(find.byKey(const Key('assistant-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(app.vm.assistantOpen, isFalse);
      // Still on screen, sliding down, rather than vanishing.
      expect(find.byKey(const Key('assistant-sheet-motion')), findsOneWidget);
      expect(sheet().position.value.dy, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-sheet-motion')), findsNothing);
    },
  );

  testWidgets('Dragging the assistant down far enough closes it', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812));
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('assistant-grabber')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();
    expect(app.vm.assistantOpen, isFalse);
    expect(find.byKey(const Key('assistant-sheet-motion')), findsNothing);
  });

  testWidgets('A short, slow drag lets the assistant spring back open', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812));
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byKey(const Key('assistant-grabber')),
      const Offset(0, 60),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(app.vm.assistantOpen, isTrue);
    expect(
      tester
          .widget<SlideTransition>(
            find.byKey(const Key('assistant-sheet-motion')),
          )
          .position
          .value
          .dy,
      0,
    );
  });

  testWidgets('With reduced motion the assistant appears and goes at once', (
    tester,
  ) async {
    final app = await mount(
      tester,
      '/',
      const Size(375, 812),
      reduceMotion: true,
    );
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pump();
    expect(
      tester
          .widget<SlideTransition>(
            find.byKey(const Key('assistant-sheet-motion')),
          )
          .position
          .value
          .dy,
      0,
    );
    app.vm.closeAssistant();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('assistant-sheet-motion')), findsNothing);
  });

  testWidgets(
    'On wide screens the assistant window grows from the bubble corner',
    (tester) async {
      await mount(tester, '/', const Size(1280, 900));
      await tester.tap(find.byKey(const Key('assistant-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final grow = tester.widget<ScaleTransition>(
        find.byKey(const Key('assistant-window-motion')),
      );
      expect(grow.alignment, Alignment.bottomRight);
      expect(grow.scale.value, lessThan(1));
      expect(grow.scale.value, greaterThan(0.5)); // never from nothing
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScaleTransition>(
              find.byKey(const Key('assistant-window-motion')),
            )
            .scale
            .value,
        1,
      );
    },
  );

  testWidgets(
    'Thinking dots read as one label and stay still with reduced motion',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ThinkingDots(label: '想一下…')),
        ),
      );
      expect(find.bySemanticsLabel('想一下…'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('Turning a toggle on pops its icon; turning it off does not', (
    tester,
  ) async {
    Widget build(bool on) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PopOnToggle(
            on: on,
            burst: true,
            child: const Icon(Icons.star),
          ),
        ),
      ),
    );
    double scale() => tester
        .widget<ScaleTransition>(find.byKey(const Key('pop-scale')))
        .scale
        .value;
    await tester.pumpWidget(build(false));
    expect(scale(), 1);
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scale(), isNot(1)); // pressed in first
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      find.byKey(const Key('pop-burst')),
      findsOneWidget,
    ); // then lines fly out
    await tester.pumpAndSettle();
    expect(scale(), 1);
    expect(find.byKey(const Key('pop-burst')), findsNothing);

    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scale(), 1);
  });

  Rect highlight(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('nav-indicator')));
  double iconCenter(WidgetTester tester, int i) => tester
      .getCenter(
        find.descendant(
          of: find.byKey(Key('nav-$i')),
          matching: find.byType(AppIconSlot),
        ),
      )
      .dx;
  Future<void> switchTab(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(Key('nav-$i')));
    await tester.pump(); // the route changes
    await tester.pump(); // the new tab is measured
  }

  testWidgets('On the same side of 發文 the highlight slides straight over', (
    tester,
  ) async {
    await mount(tester, '/', const Size(375, 812));
    expect(
      highlight(tester).center.dx,
      moreOrLessEquals(iconCenter(tester, 0), epsilon: 1),
    );
    await switchTab(tester, 1);
    await tester.pump(const Duration(milliseconds: 90));
    final midway = highlight(tester).center.dx;
    expect(midway, greaterThan(iconCenter(tester, 0) + 5)); // on its way
    expect(midway, lessThan(iconCenter(tester, 1) - 5)); // not there yet
    await tester.pumpAndSettle();
    expect(
      highlight(tester).center.dx,
      moreOrLessEquals(iconCenter(tester, 1), epsilon: 1),
    );
  });

  testWidgets(
    'Across 發文 the highlight leaves one edge and comes in the other',
    (tester) async {
      await mount(tester, '/', const Size(375, 812));
      // Left tabs to right tabs: out to the left, in from the right.
      await switchTab(tester, 3);
      await tester.pump(const Duration(milliseconds: 80));
      expect(highlight(tester).center.dx, lessThan(iconCenter(tester, 0) - 5));
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        highlight(tester).center.dx,
        greaterThan(iconCenter(tester, 3) + 5),
      );
      await tester.pumpAndSettle();
      expect(
        highlight(tester).center.dx,
        moreOrLessEquals(iconCenter(tester, 3), epsilon: 1),
      );

      // Right to left: out to the right, in from the left.
      await switchTab(tester, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        highlight(tester).center.dx,
        greaterThan(iconCenter(tester, 3) + 5),
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(highlight(tester).center.dx, lessThan(iconCenter(tester, 0) - 5));
      await tester.pumpAndSettle();
      expect(
        highlight(tester).center.dx,
        moreOrLessEquals(iconCenter(tester, 0), epsilon: 1),
      );
    },
  );

  testWidgets('With reduced motion the tab highlight jumps', (tester) async {
    await mount(tester, '/', const Size(375, 812), reduceMotion: true);
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final target = tester
        .getCenter(
          find.descendant(
            of: find.byKey(const Key('nav-3')),
            matching: find.byType(AppIconSlot),
          ),
        )
        .dx;
    expect(
      tester.getRect(find.byKey(const Key('nav-indicator'))).center.dx,
      moreOrLessEquals(target, epsilon: 1),
    );
  });
}
