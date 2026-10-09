import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/data/content_repository.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AssetContentRepository repository;
  setUpAll(() async {
    repository = await AssetContentRepository.load();
  });
  Future<BridgeViewModel> mount(
    WidgetTester tester,
    String route,
    Size size,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = BridgeViewModel(
      content: repository,
      preferences: MemoryPreferences(),
    );
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: vm, initialLocation: route),
    );
    await tester.pumpAndSettle();
    addTearDown(vm.dispose);
    return vm;
  }

  for (final width in [320.0, 375.0, 768.0, 1024.0, 1440.0]) {
    for (final route in [
      '/',
      '/explore',
      '/share',
      '/profile',
      '/experiences/first-rental',
      '/actions/arc',
      '/actions/arc/progress',
      '/actions/arc/complete',
    ]) {
      testWidgets('$route renders without overflow at $width', (tester) async {
        await mount(tester, route, Size(width, 900));
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
  testWidgets(
    'Share validates blank input and keeps draft when editing review',
    (tester) async {
      final vm = await mount(tester, '/share', const Size(1024, 1000));
      await tester.ensureVisible(find.byKey(const Key('review-draft')));
      await tester.tap(find.byKey(const Key('review-draft')));
      await tester.pumpAndSettle();
      expect(find.text('請先寫下發生了什麼事，再整理你的經驗。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('share-voice')),
        'My classmates helped me settle in.',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.ensureVisible(find.byKey(const Key('review-draft')));
      await tester.tap(find.byKey(const Key('review-draft')));
      await tester.pumpAndSettle();
      expect(vm.reviewedDraft!.voice, 'My classmates helped me settle in.');
      await tester.ensureVisible(find.byKey(const Key('edit-draft')));
      await tester.tap(find.byKey(const Key('edit-draft')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(
          TextFormField,
          'My classmates helped me settle in.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('Mobile navigation and language toggle work', (tester) async {
    await mount(tester, '/', const Size(375, 812));
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('你的影響'), findsOneWidget);
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();
    expect(find.text('Your impact'), findsOneWidget);
  });
  testWidgets('Step interaction updates progress', (tester) async {
    final vm = await mount(
      tester,
      '/actions/arc/progress',
      const Size(375, 812),
    );
    await tester.ensureVisible(find.byKey(const Key('step-0')));
    await tester.tap(find.byKey(const Key('step-0')));
    await tester.pumpAndSettle();
    expect(vm.completed('arc'), {0});
    expect(find.text('進度: 1 / 5'), findsOneWidget);
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
