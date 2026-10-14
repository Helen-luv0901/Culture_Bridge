// D-15 manual checklist, automated where possible: every main screen at phone widths with
// 200% text and in English must lay out without overflow.
import 'package:culture_bridge/app.dart';
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
          await tester.pumpWidget(
            CultureBridgeApp(viewModel: app.vm, initialLocation: route),
          );
          await tester.pumpAndSettle();
          addTearDown(app.vm.dispose);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
