import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/ui/core/design_system.dart';
import 'package:culture_bridge/ui/features/post_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// What the 2026-10-30 usability and accessibility check of the preview found.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TestApp> mount(WidgetTester tester, String route, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = TestApp();
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: app.vm, initialLocation: route),
    );
    await tester.pumpAndSettle();
    addTearDown(app.vm.dispose);
    return app;
  }

  List<SemanticsData> semanticsNodes(WidgetTester tester) {
    final nodes = <SemanticsData>[];
    void visit(SemanticsNode node) {
      nodes.add(node.getSemanticsData());
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    return nodes;
  }

  for (final route in [
    '/',
    '/guides',
    '/explore',
    '/experiences/first-rental',
    '/actions/arc',
  ]) {
    testWidgets('All text on $route uses the bundled font', (tester) async {
      await mount(tester, route, const Size(375, 900));
      // Button text without the family falls back to Roboto, which has no Chinese:
      // the preview showed boxes until a fallback font downloaded.
      final families = {
        for (final p in tester.allRenderObjects.whereType<RenderParagraph>())
          p.text.style?.fontFamily,
      }..removeWhere((f) => f != null && f.startsWith('MaterialIcons'));
      expect(families, {'NotoSansTC'});
    });
  }

  testWidgets('A post body reaches screen readers as text', (tester) async {
    await mount(tester, '/experiences/first-rental', const Size(375, 900));
    // SelectableText is read as an empty, disabled text box on the web.
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('The pinned card is one button with a plain name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester, '/', const Size(375, 900));
    expect(
      find.bySemanticsLabel(RegExp(r'^來台第一個月要辦的事，已看 \d+ / \d+$')),
      findsOneWidget,
    );
    expect(
      semanticsNodes(tester).where((n) => n.role == SemanticsRole.progressBar),
      isEmpty,
    );
    handle.dispose();
  });

  for (final (route, size) in [
    ('/', const Size(375, 900)),
    ('/', const Size(1280, 900)),
    ('/guides', const Size(1280, 900)),
    ('/guides', const Size(375, 900)),
    ('/share', const Size(375, 900)),
    ('/explore', const Size(375, 900)),
    ('/experiences/first-rental', const Size(375, 900)),
    ('/experiences/first-rental', const Size(1280, 900)),
  ]) {
    testWidgets('$route at ${size.width} has one h1, one main and one nav', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await mount(tester, route, size);
      final nodes = semanticsNodes(tester);
      expect(nodes.where((n) => n.headingLevel == 1), hasLength(1));
      expect(nodes.where((n) => n.role == SemanticsRole.main), hasLength(1));
      expect(
        nodes.where((n) => n.role == SemanticsRole.navigation),
        hasLength(1),
      );
      handle.dispose();
    });
  }

  testWidgets('Esc closes the assistant wherever the focus is', (tester) async {
    final app = await mount(tester, '/', const Size(1280, 900));
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pumpAndSettle();
    expect(app.vm.assistantOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(app.vm.assistantOpen, isFalse);
  });

  testWidgets('Votes and card titles are single nodes with plain names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester, '/', const Size(375, 900));
    final vote = tester.getSemantics(
      find.byKey(const Key('vote-first-rental')),
    );
    expect(vote.label, startsWith('我也遇過 '));
    expect(vote.childrenCount, 0);
    final title = tester.getSemantics(
      find.byKey(const Key('post-title-first-rental')),
    );
    // The byline, title and excerpt, with no buttons inside it.
    expect(title.label, contains('·'));
    expect(title.childrenCount, 0);
    handle.dispose();
  });

  testWidgets('Esc over a dialog closes the dialog, not the assistant', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(1280, 900));
    await tester.tap(find.byKey(const Key('assistant-button')));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.byType(Scaffold).first),
      builder: (_) => const AlertDialog(content: Text('對話框')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('對話框'), findsNothing);
    expect(app.vm.assistantOpen, isTrue);
  });

  testWidgets('On phones the bubble stays off posts, where it covered Send', (
    tester,
  ) async {
    await mount(tester, '/experiences/first-rental', const Size(375, 900));
    expect(find.byKey(const Key('assistant-button')), findsNothing);
  });

  test('Buttons get a ring only while focused', () {
    final theme = bridgeTheme();
    final rest = {
      'filled': theme.filledButtonTheme.style!.side,
      'icon': theme.iconButtonTheme.style!.side,
      'text': theme.textButtonTheme.style!.side,
    };
    for (final MapEntry(:key, :value) in rest.entries) {
      // styleFrom(side:) once froze the ring into a 1px black border on every button.
      expect(value!.resolve({}), isNull, reason: key);
      expect(value.resolve({WidgetState.focused})!.width, 2, reason: key);
    }
    final outlined = theme.outlinedButtonTheme.style!.side!;
    expect(outlined.resolve({})!.color, Palette.control);
    expect(outlined.resolve({WidgetState.focused})!.color, Palette.moss);
  });

  test('English comment counts are singular for one', () {
    expect(commentsInEnglish(1), '1 comment');
    expect(commentsInEnglish(0), '0 comments');
    expect(commentsInEnglish(3), '3 comments');
  });
}
