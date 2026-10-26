// Flutter's accessibility guidelines on every main screen, on a phone and on a desktop: tap
// targets at least 44 px (iOS, and WCAG 2.5.5 AAA; the design system's size, docs/product/
// design.md), every tappable thing has a label a screen reader can say, and text has enough
// contrast (WCAG AA). Android's own scanner asks for 48 dp; the 44 px controls are a design
// choice, not checked here.
import 'package:culture_bridge/app.dart';
import 'package:flutter/rendering.dart';
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
    '/profile/settings',
    '/official',
    '/assistant',
  ];
  const screens = {'phone': Size(375, 812), 'desktop': Size(1280, 900)};

  for (final MapEntry(key: screen, value: size) in screens.entries) {
    for (final route in routes) {
      testWidgets('$route on a $screen meets the accessibility guidelines', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = TestApp();
        addTearDown(app.vm.dispose);
        await app.vm.startAction('arc');
        await app.vm.loadProfile();
        await tester.pumpWidget(
          CultureBridgeApp(viewModel: app.vm, initialLocation: route),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(const _TapTargets()));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  }
}

/// 44 x 44 like iOSTapTargetGuideline, except for read-only text: selectable post text reports
/// long-press (to select words), but it isn't something you aim at.
class _TapTargets extends MinimumTapTargetGuideline {
  const _TapTargets()
    : super(
        size: const Size(44, 44),
        link: 'https://developer.apple.com/design/human-interface-guidelines/accessibility',
      );

  @override
  bool shouldSkipNode(SemanticsNode node) {
    final data = node.getSemanticsData();
    final readOnlyText =
        data.flagsCollection.isTextField && data.flagsCollection.isReadOnly;
    return readOnlyText || super.shouldSkipNode(node);
  }
}
