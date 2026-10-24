import 'dart:convert';
import 'dart:typed_data';

import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/domain/api_models.dart';
import 'package:culture_bridge/ui/core/design_system.dart';
import 'package:culture_bridge/ui/features/assistant_panel.dart';
import 'package:culture_bridge/ui/features/me_page.dart';
import 'package:culture_bridge/ui/features/post_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  for (final width in [320.0, 375.0, 820.0, 1180.0, 1440.0]) {
    for (final route in [
      '/',
      '/explore',
      '/explore?cat=official',
      '/explore?cat=food',
      '/explore?q=居留',
      '/share',
      '/profile',
      '/profile?tab=saved',
      '/profile/settings',
      '/signin',
      '/guide/welcome',
      '/official',
      '/experiences/first-rental',
      '/actions/arc',
      '/actions/arc/progress',
      '/actions/arc/complete',
      '/assistant',
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

  testWidgets('Sidebar is icon-only on tablet portrait and full on web', (
    tester,
  ) async {
    await mount(tester, '/', const Size(820, 1180));
    expect(
      tester.getSize(find.byKey(const Key('desktop-navigation'))).width,
      76,
    );
    expect(find.byKey(const Key('header-search')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, '/', const Size(1280, 800));
    expect(
      tester.getSize(find.byKey(const Key('desktop-navigation'))).width,
      232,
    );
  });

  testWidgets('Home: the official account pinned, then only student posts', (
    tester,
  ) async {
    await mount(tester, '/', const Size(1280, 2400));
    final pinned = tester.getTopLeft(find.byKey(const Key('guide-welcome')));
    final post = tester.getTopLeft(find.byKey(const Key('post-first-rental')));
    expect(pinned.dy, lessThan(post.dy));
    expect(find.text('初次來台灣？可以來這邊看看'), findsOneWidget);
    // Official guides live on the official account's page, not in the feed.
    expect(find.byKey(const Key('guide-arc')), findsNothing);
    // Official posts are marked only by the name and avatar: no seal, badge or check mark.
    expect(find.byType(OfficialSeal), findsNothing);
    expect(find.text('官方'), findsNothing);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('The pinned card opens the official account and its posts', (
    tester,
  ) async {
    await mount(tester, '/', const Size(375, 812));
    await tap(tester, find.text('初次來台灣？可以來這邊看看'));
    expect(find.byKey(const Key('official-account')), findsOneWidget);
    expect(find.text('官方帳號'), findsWidgets);
    expect(find.byKey(const Key('guide-arc')), findsOneWidget);
    expect(find.byKey(const Key('post-first-rental')), findsNothing);
  });

  testWidgets('A whole card opens its post, not just the title', (
    tester,
  ) async {
    await mount(tester, '/', const Size(1280, 2400));
    final pinned = find.byKey(const Key('guide-welcome'));
    // Tap the empty right side of the card, far from the title.
    await tester.tapAt(tester.getTopRight(pinned) + const Offset(-40, 60));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('official-account')), findsOneWidget);

    await tap(tester, find.byKey(const Key('back')));
    final post = find.byKey(const Key('post-first-rental'));
    await tester.tapAt(tester.getTopRight(post) + const Offset(-200, 70));
    await tester.pumpAndSettle();
    expect(find.text('學生分享'), findsWidgets);
  });

  testWidgets('Opened posts are dimmed and marked read', (tester) async {
    final app = await mount(tester, '/official', const Size(1280, 2400));
    await tap(tester, find.text('申請或更新 ARC').first);
    expect(app.vm.isRead('guide:arc'), isTrue);
    await tap(tester, find.byKey(const Key('back')));
    expect(find.textContaining('已看過'), findsOneWidget);
  });

  testWidgets('Explore: categories, search sections and popular tags', (
    tester,
  ) async {
    await mount(tester, '/explore', const Size(375, 1600));
    for (final label in ['全部', '生活', '美食', '住宿', '交通', '學業', '文化', '文化差異']) {
      expect(find.text(label), findsWidgets);
    }
    // Official posts live on the official account's page, not in a tab here.
    expect(find.byKey(const Key('cat-official')), findsNothing);
    expect(find.byKey(const Key('guide-arc')), findsNothing);
    expect(find.text('學生分享'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('sort-new')), findsOneWidget);
    expect(find.text('#夜市'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('explore-search')), 'ARC');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('官方指南'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('guide-row-arc')), findsOneWidget);
    expect(find.byKey(const Key('ask-assistant')), findsOneWidget);

    await tap(tester, find.byKey(const Key('cat-food')));
    expect(find.textContaining('找不到'), findsOneWidget);
  });

  testWidgets('Explore sorts student posts by newest or popular', (
    tester,
  ) async {
    await mount(tester, '/explore', const Size(1280, 3000));
    List<ExperienceItem> shown() => [
      for (final card in tester.widgetList<StudentPostCard>(
        find.byType(StudentPostCard),
      ))
        card.item,
    ];
    final newest = shown();
    expect(newest.length, greaterThan(1));
    for (var i = 1; i < newest.length; i++) {
      expect(
        newest[i - 1].publishedAt.isBefore(newest[i].publishedAt),
        isFalse,
      );
    }

    await tap(tester, find.byKey(const Key('sort-hot')));
    int heat(ExperienceItem e) => e.experiencedTooCount + 2 * e.commentCount;
    final popular = shown();
    expect(popular.length, newest.length);
    for (var i = 1; i < popular.length; i++) {
      expect(heat(popular[i - 1]), greaterThanOrEqualTo(heat(popular[i])));
    }
    // The order sticks when switching categories.
    await tap(tester, find.byKey(const Key('cat-life')));
    final life = shown();
    for (var i = 1; i < life.length; i++) {
      expect(heat(life[i - 1]), greaterThanOrEqualTo(heat(life[i])));
    }
  });

  for (final (route, name) in [
    ('/explore', '探索'),
    ('/share', '分享'),
    ('/profile', '我的'),
  ]) {
    testWidgets('$route shows its name in the header on phones only', (
      tester,
    ) async {
      await mount(tester, route, const Size(1280, 900));
      expect(find.text(name), findsOneWidget); // the sidebar
      await tester.pumpWidget(const SizedBox());
      await mount(tester, route, const Size(375, 812));
      expect(find.text(name), findsNWidgets(2)); // header and bottom tab
    });
  }

  testWidgets('Selected chips have readable white labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bridgeTheme(),
        home: Scaffold(
          body: Row(
            children: [
              ChoiceChip(
                label: const Text('流程'),
                selected: true,
                onSelected: (_) {},
              ),
              ChoiceChip(
                label: const Text('檢舉'),
                selected: false,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    Color colorOf(String text) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .text
        .style!
        .color!;
    expect(colorOf('流程'), Palette.onMoss);
    expect(colorOf('檢舉'), Palette.ink);
    // The label keeps the app's font and size (the theme style replaces Material's).
    final style = tester
        .renderObject<RenderParagraph>(find.text('檢舉'))
        .text
        .style!;
    expect(style.fontFamily, 'Spectral');
    expect(style.fontSize, 14);
  });

  for (final width in [1100.0, 1920.0]) {
    testWidgets('Stickers never sit behind cards at $width', (tester) async {
      await mount(tester, '/official', Size(width, 1200));
      // The page's two stickers; the empty-state ones live inside cards.
      final stickers = find.byType(Sticker);
      expect(stickers, findsWidgets);
      final cards = find.byType(NoteCard);
      for (final sticker in tester.widgetList<Sticker>(stickers)) {
        final s = tester.getRect(find.byWidget(sticker));
        for (final card in tester.widgetList<NoteCard>(cards)) {
          final c = tester.getRect(find.byWidget(card));
          expect(s.overlaps(c), isFalse, reason: '$s overlaps $c');
        }
      }
    });
  }

  testWidgets('Guide steps show English notes in English', (tester) async {
    final app = await mount(tester, '/actions/arc', const Size(1280, 1600));
    expect(find.text('先線上預約。'), findsOneWidget);
    app.vm.setEnglish(true);
    await tester.pumpAndSettle();
    expect(find.text('Book online first.'), findsOneWidget);
    expect(find.text('先線上預約。'), findsNothing);
    // Sources show English names, without the Chinese reviewer notes.
    expect(find.textContaining('Sources: Example Agency'), findsOneWidget);
  });

  testWidgets('Official posts and the account use the team logo', (
    tester,
  ) async {
    await mount(tester, '/official', const Size(1280, 1600));
    Iterable<String> logos() => tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName)
        .where((name) => name == 'assets/images/logo-mark.png');
    // The account header plus every official post byline.
    expect(logos().length, greaterThan(2));
  });

  testWidgets('New posts appear on Home without a reload', (tester) async {
    final app = await mount(tester, '/', const Size(1280, 2400));
    expect(find.text('剛發的新貼文'), findsNothing);
    // Someone else publishes while this page is open.
    await app.repository.publishPost(
      title: '剛發的新貼文',
      voice: '測試即時更新。',
      category: 'life',
      tags: const [],
      sourceLocale: 'zh-Hant',
    );
    await app.vm.refreshNewPosts();
    await tester.pumpAndSettle();
    expect(find.text('剛發的新貼文'), findsOneWidget);
    // It goes to the top of the feed, under the pinned official card.
    final fresh = tester.getTopLeft(find.text('剛發的新貼文')).dy;
    final older = tester
        .getTopLeft(find.byKey(const Key('post-first-rental')))
        .dy;
    expect(fresh, lessThan(older));
  });

  testWidgets('Tapping a tag searches for it', (tester) async {
    await mount(tester, '/experiences/first-rental', const Size(1280, 1400));
    await tap(tester, find.text('#居留證'));
    expect(find.text('學生分享'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('post-first-rental')), findsOneWidget);
  });

  testWidgets('Guests are sent to sign in, then back', (tester) async {
    final app = await mount(
      tester,
      '/actions/arc',
      const Size(1280, 1600),
      signedIn: false,
    );
    await tap(tester, find.byKey(const Key('start-action')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('dev-name')), 'mei');
    await tap(tester, find.byKey(const Key('dev-sign-in')));
    expect(app.vm.signedIn, isTrue);
    // First sign-in without names: asked once, can skip.
    expect(find.text('歡迎！要怎麼稱呼你？'), findsOneWidget);
    await tap(tester, find.byKey(const Key('names-later')));
    expect(find.byKey(const Key('start-action')), findsOneWidget);
  });

  testWidgets('Share: required fields, AI tags, publish as written', (
    tester,
  ) async {
    final app = await mount(tester, '/share', const Size(1280, 2000));
    await tap(tester, find.byKey(const Key('publish')));
    expect(find.text('先寫一個標題'), findsOneWidget);
    expect(find.text('先寫內文再發布'), findsOneWidget);
    expect(find.text('選一個分類，大家才找得到'), findsOneWidget);
    expect(app.repository.lastPublish, isNull);

    await tester.enterText(find.byKey(const Key('share-title')), '居留證要先預約');
    await tester.enterText(
      find.byKey(const Key('share-voice')),
      '我以為可以直接去服務站，結果要先線上預約。',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('＋ #居留證'), findsOneWidget);
    await tap(tester, find.text('＋ #居留證'));
    expect(find.text('✓ #居留證'), findsOneWidget);
    await tap(tester, find.byKey(const Key('share-cat-life')));
    expect(find.text('發布後會長這樣'.toUpperCase()), findsOneWidget);

    await tap(tester, find.byKey(const Key('publish')));
    expect(app.repository.lastPublish, containsPair('title', '居留證要先預約'));
    expect(
      app.repository.lastPublish,
      containsPair('voice', '我以為可以直接去服務站，結果要先線上預約。'),
    );
    expect(app.repository.lastPublish!['tags'], ['#居留證']);
    // Opens the new post: the author's words, not an AI rewrite.
    expect(find.text('居留證要先預約'), findsOneWidget);
    // Only the author's words: no sentence the app adds under the post.
    expect(find.textContaining('未經 AI 改寫'), findsNothing);
    expect(app.vm.draft.isEmpty, isTrue);
  });

  testWidgets('Names set after sign-in sign a published post', (tester) async {
    final app = await mount(
      tester,
      '/share',
      const Size(1280, 2000),
      signedIn: false,
    );
    // Guests are asked to sign in before they can write anything.
    expect(find.byKey(const Key('share-title')), findsNothing);
    await tap(tester, find.text('登入'));
    await tester.enterText(find.byKey(const Key('dev-name')), 'mei');
    await tap(tester, find.byKey(const Key('dev-sign-in')));
    await tester.enterText(find.byKey(const Key('nickname')), '  小  美 ');
    await tap(tester, find.byKey(const Key('save-names')));
    expect(app.repository.nickname, '小 美');
    // Back on Share, now signed in.
    await tester.enterText(find.byKey(const Key('share-title')), '夜市');
    await tester.enterText(find.byKey(const Key('share-voice')), '第一次去夜市。');
    await tap(tester, find.byKey(const Key('share-cat-food')));
    await tap(tester, find.byKey(const Key('post-as-real_name')));
    expect(find.textContaining('先到「我的 › 設定」填寫'), findsOneWidget);
    await tap(tester, find.byKey(const Key('post-as-nickname')));
    await tap(tester, find.byKey(const Key('publish')));
    expect(app.repository.lastPublish!['author_display'], 'nickname');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Signed posts show the name, others stay anonymous', (
    tester,
  ) async {
    await mount(
      tester,
      '/experiences/professor-see',
      const Size(1280, 1400),
      before: (app) async => app.repository.signAs('professor-see', '小美'),
    );
    expect(find.textContaining('小美 · '), findsOneWidget);
    expect(find.textContaining('匿名 · '), findsNothing);
  });

  testWidgets('Post: me too, comments with replies and likes', (tester) async {
    final app = await mount(
      tester,
      '/experiences/professor-see',
      const Size(1280, 1800),
    );
    await tap(tester, find.byKey(const Key('me-too')));
    expect(find.text('我也遇過 1'), findsOneWidget);

    await tap(tester, find.byKey(const Key('send-comment')));
    expect(find.text('先寫點什麼再送出'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-box')), '我也是這樣');
    await tap(tester, find.byKey(const Key('send-comment')));
    expect(find.text('我也是這樣'), findsOneWidget);
    await tap(tester, find.text('有同感'));
    expect(find.text('有同感 1'), findsOneWidget);
    await tap(tester, find.text('回覆'));
    expect(find.textContaining('回覆 匿名學生'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-box')), '謝謝');
    await tap(tester, find.byKey(const Key('send-comment')));
    final comments = app.repository.postComments['professor-see']!;
    expect(comments.last.replyToId, comments.first.id);
  });

  testWidgets('Official guide: steps, documents checklist, share under it', (
    tester,
  ) async {
    final app = await mount(tester, '/actions/arc', const Size(375, 2400));
    expect(find.text('步驟'.toUpperCase()), findsOneWidget);
    expect(find.text('已備妥 0 / 2'), findsOneWidget);
    await tap(tester, find.byKey(const Key('document-1')));
    expect(find.text('已備妥 1 / 2'), findsOneWidget);
    await tap(tester, find.byKey(const Key('share-under-guide')));
    expect(app.vm.draft.actionId, 'arc');
    expect(find.textContaining('也會出現在官方指南'), findsOneWidget);
    // Let the debounced draft save run before the test ends.
    await tester.pump(const Duration(seconds: 1));
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
      const Size(1280, 1400),
      before: (app) => app.vm.startAction('arc'),
    );
    await tap(tester, find.text('流程和原本不同'));
    await tap(tester, find.text('費用'));
    await tap(tester, find.byKey(const Key('send-outcome')));
    expect(app.repository.feedback.single['category'], 'fee');
    expect(app.repository.executions, isEmpty);
  });

  testWidgets('Mobile tabs, My page and the language setting', (tester) async {
    await mount(tester, '/', const Size(375, 812));
    await tap(tester, find.byKey(const Key('nav-3')));
    expect(find.text('我的分享'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    await tap(tester, find.byKey(const Key('open-settings')));
    await tap(tester, find.byKey(const Key('locale-en')));
    expect(find.text('Settings'), findsOneWidget);
  });

  for (final size in [const Size(375, 812), const Size(1280, 900)]) {
    testWidgets('Header switches language at ${size.width}', (tester) async {
      final app = await mount(tester, '/', size);
      expect(find.byKey(const Key('header-language')), findsOneWidget);
      await tap(tester, find.byKey(const Key('header-language')));
      expect(app.vm.english, isTrue);
      expect(find.text('中文'), findsOneWidget);
      await tap(tester, find.byKey(const Key('header-language')));
      expect(app.vm.english, isFalse);
      expect(find.text('EN'), findsOneWidget);
    });
  }

  testWidgets('An unpublished draft on My page continues in Share', (
    tester,
  ) async {
    final app = await mount(
      tester,
      '/profile',
      const Size(375, 1400),
      before: (app) async =>
          app.repository.mine['old-draft'] = const MyExperience(
            id: 'old-draft',
            status: 'draft',
            topicId: 'life_adaptation',
            identityType: 'other',
            originalVoice: '去郵局開戶要帶居留證。',
            latestSummary: null,
            impact: Impact(0, 0, 0, 0),
            title: '郵局開戶',
            category: 'life',
          ),
    );
    expect(find.textContaining('草稿，點標題繼續編輯'), findsOneWidget);
    await tap(tester, find.text('郵局開戶'));
    expect(find.widgetWithText(TextField, '郵局開戶'), findsOneWidget);
    expect(find.widgetWithText(TextField, '去郵局開戶要帶居留證。'), findsOneWidget);

    await tap(tester, find.byKey(const Key('publish')));
    expect(app.repository.lastPublish, containsPair('title', '郵局開戶'));
    // The unpublished copy is gone once it is published.
    expect(app.repository.mine.containsKey('old-draft'), isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('A draft on My page can be deleted', (tester) async {
    final app = await mount(
      tester,
      '/profile',
      const Size(375, 1400),
      before: (app) async =>
          app.repository.mine['old-draft'] = const MyExperience(
            id: 'old-draft',
            status: 'draft',
            topicId: 'life_adaptation',
            identityType: 'other',
            originalVoice: '文華路的餐廳很好吃。',
            latestSummary: null,
            impact: Impact(0, 0, 0, 0),
            title: '文華路餐廳',
            category: 'food',
          ),
    );
    await tap(tester, find.byKey(const Key('delete-draft-old-draft')));
    expect(find.text('刪除這篇草稿？'), findsOneWidget);
    await tap(tester, find.byKey(const Key('confirm-delete-draft')));
    expect(app.repository.mine.containsKey('old-draft'), isFalse);
    expect(find.text('文華路餐廳'), findsNothing);
  });

  testWidgets('Save a post and find it under My › Saved', (tester) async {
    final app = await mount(
      tester,
      '/experiences/professor-see',
      const Size(1280, 1400),
    );
    await tap(tester, find.byKey(const Key('save-post')));
    expect(app.repository.saved, ['professor-see']);
    expect(find.text('已收藏，在「我的 › 收藏」找得到'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      '/profile?tab=saved',
      const Size(1280, 1600),
      before: (other) => other.repository.setSaved('professor-see', true),
    );
    expect(find.byKey(const Key('post-professor-see')), findsOneWidget);
    await tap(tester, find.byTooltip(RegExp('取消收藏')));
    expect(find.byKey(const Key('post-professor-see')), findsNothing);
    expect(find.text('還沒有收藏'), findsOneWidget);
  });

  testWidgets('Guests are asked to sign in before saving', (tester) async {
    await mount(
      tester,
      '/experiences/professor-see',
      const Size(1280, 1400),
      signedIn: false,
    );
    await tap(tester, find.byKey(const Key('save-post')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
  });

  testWidgets('Report and block from a post', (tester) async {
    final app = await mount(
      tester,
      '/experiences/professor-see',
      const Size(1280, 1400),
    );
    await tap(tester, find.byKey(const Key('moderation-menu')));
    await tap(tester, find.text('檢舉').last);
    await tap(tester, find.text('騷擾或霸凌'));
    await tap(tester, inDialog('送出'));
    expect(app.repository.reports, ['professor-see:harassment']);

    await tap(tester, find.byKey(const Key('moderation-menu')));
    await tap(tester, find.text('封鎖這位作者'));
    await tap(tester, inDialog('確認'));
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

  testWidgets('Assistant: greeting, suggestions, links and confirm cards', (
    tester,
  ) async {
    final app = await mount(tester, '/actions/arc', const Size(1280, 900));
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
    expect(find.textContaining('我是 Culture Bridge 助理'), findsOneWidget);
    expect(find.text('居留證要準備什麼？'), findsOneWidget);
    expect(find.textContaining('1990'), findsOneWidget);
    // Web: a floating window; the bubble stays to close it.
    expect(find.byKey(const Key('assistant-button')), findsOneWidget);

    await tap(tester, find.text('居留證要準備什麼？'));
    expect(app.repository.assistantMessages, ['居留證要準備什麼？']);
    // The guide shows as an official post card, like student posts.
    expect(find.byKey(const Key('assistant-post-arc')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('assistant-post-arc')),
        matching: find.text('申請或更新 ARC'),
      ),
      findsOneWidget,
    );
    expect(find.text('打開辦理進度 →'), findsOneWidget);
    await tap(tester, find.byKey(const Key('confirm-op1')));
    expect(app.repository.confirmed, ['op1']);
    expect(find.text('已開始，打開進度'), findsOneWidget);
  });

  testWidgets('Guests are asked to sign in before using the assistant', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812), signedIn: false);
    await tap(tester, find.byKey(const Key('assistant-button')));
    expect(find.text('請先登入'), findsOneWidget);
    expect(find.text('AI 助理僅提供給已登入的使用者，請先登入後再使用。'), findsOneWidget);
    expect(app.vm.assistantOpen, isFalse);

    await tap(tester, find.text('取消'));
    expect(find.byKey(const Key('sign-in-prompt')), findsNothing);
    expect(app.vm.assistantOpen, isFalse);

    await tap(tester, find.byKey(const Key('assistant-button')));
    await tap(tester, find.byKey(const Key('sign-in-prompt-go')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
    expect(app.repository.assistantMessages, isEmpty);
  });

  testWidgets('Guests are asked to sign in before sharing', (tester) async {
    await mount(tester, '/', const Size(375, 812), signedIn: false);
    await tap(tester, find.byKey(const Key('nav-2')));
    expect(find.text('請先登入'), findsOneWidget);
    expect(find.text('分享經驗需要登入帳號，請先登入後再分享。'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(find.byKey(const Key('share-title')), findsNothing);

    await tap(tester, find.byKey(const Key('nav-2')));
    await tap(tester, find.byKey(const Key('sign-in-prompt-go')));
    expect(find.byKey(const Key('dev-name')), findsOneWidget);
  });

  testWidgets('A guest opening the share page directly sees sign in first', (
    tester,
  ) async {
    await mount(tester, '/share', const Size(375, 812), signedIn: false);
    expect(find.byKey(const Key('share-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('share-title')), findsNothing);
  });

  testWidgets('Change and remove the profile photo in Settings', (
    tester,
  ) async {
    final app = await mount(tester, '/profile/settings', const Size(375, 1200));
    pickAvatarPhoto = () async => Uint8List.fromList([1, 2, 3]);
    addTearDown(() => pickAvatarPhoto = () async => null);
    expect(find.byKey(const Key('remove-avatar')), findsNothing);

    await tap(tester, find.byKey(const Key('change-avatar')));
    expect(app.repository.uploadedPhotos, [
      base64Encode([1, 2, 3]),
    ]);
    expect(app.vm.profile?.avatarUrl, '/api/avatars/photo-1');
    expect(find.text('大頭貼已更新'), findsOneWidget);

    await tap(tester, find.byKey(const Key('remove-avatar')));
    expect(app.vm.profile?.avatarUrl, isNull);
    expect(find.byKey(const Key('remove-avatar')), findsNothing);
  });

  testWidgets('Assistant answers show the closest posts, which open', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812));
    app.repository.assistantReply = (message) => const AssistantReply(
      conversationId: 'c1',
      text: '租屋前先看清楚合約。',
      cards: [
        AssistantCard(
          type: 'experience',
          id: 'first-rental',
          title: '第一次在台中租房子',
          verificationStatus: null,
          lastVerifiedAt: null,
          recentSuccessCount: 0,
          sources: [],
          reminder: '',
          excerpt: '看房時記得問電費怎麼算……',
          category: 'housing',
        ),
      ],
      screenActions: [],
      pendingOperations: [],
      fallback: false,
    );
    await tap(tester, find.byKey(const Key('assistant-button')));
    await tester.enterText(find.byType(TextField).last, '租房子要注意什麼？');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('相關貼文'), findsOneWidget);
    expect(find.text('第一次在台中租房子'), findsOneWidget);

    await tap(tester, find.byKey(const Key('assistant-post-first-rental')));
    expect(app.vm.assistantOpen, isFalse); // phones close the chat
    expect(
      find.byKey(const Key('save-post')),
      findsOneWidget,
    ); // on the post's page
  });

  testWidgets('Assistant on a phone covers the page and hides the bubble', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812));
    await tap(tester, find.byKey(const Key('assistant-button')));
    expect(app.vm.assistantOpen, isTrue);
    expect(find.byKey(const Key('assistant-button')), findsNothing);
    await tap(tester, find.byKey(const Key('assistant-close')));
    expect(find.byKey(const Key('assistant-button')), findsOneWidget);
  });

  testWidgets('The assistant tab opens the chat as a whole page', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(375, 812));
    app.repository.assistantReply = (message) => const AssistantReply(
      conversationId: 'c1',
      text: '租屋前先看清楚合約。',
      cards: [
        AssistantCard(
          type: 'experience',
          id: 'first-rental',
          title: '第一次在台中租房子',
          verificationStatus: null,
          lastVerifiedAt: null,
          recentSuccessCount: 0,
          sources: [],
          reminder: '',
          excerpt: '看房時記得問電費怎麼算……',
          category: 'housing',
        ),
      ],
      screenActions: [],
      pendingOperations: [],
      fallback: false,
    );
    await tap(tester, find.byKey(const Key('nav-4')));
    expect(find.byKey(const Key('assistant-page')), findsOneWidget);
    expect(find.text('居留證要準備什麼？'), findsOneWidget);
    // The page is the chat: no bubble, no close button, nothing over it.
    expect(find.byKey(const Key('assistant-button')), findsNothing);
    expect(find.byKey(const Key('assistant-close')), findsNothing);
    expect(app.vm.assistantOpen, isFalse);

    await tap(tester, find.text('租屋要注意什麼？'));
    expect(app.repository.assistantMessages, ['租屋要注意什麼？']);
    await tap(tester, find.byKey(const Key('assistant-post-first-rental')));
    expect(find.byKey(const Key('save-post')), findsOneWidget);

    // Back on the tab, the conversation is still there.
    await tap(tester, find.byKey(const Key('back')));
    expect(find.byKey(const Key('assistant-page')), findsOneWidget);
    expect(find.text('租屋前先看清楚合約。'), findsOneWidget);
  });

  testWidgets('The bubble chat continues on the assistant page', (
    tester,
  ) async {
    final app = await mount(tester, '/', const Size(1280, 900));
    await tap(tester, find.byKey(const Key('assistant-button')));
    await tap(tester, find.text('怎麼加入健保？'));
    expect(app.repository.assistantMessages, ['怎麼加入健保？']);

    await tap(tester, find.byKey(const Key('nav-4')));
    // The floating window closes; the same conversation fills the page.
    expect(app.vm.assistantOpen, isFalse);
    expect(find.byKey(const Key('assistant-button')), findsNothing);
    expect(find.byKey(const Key('assistant-page')), findsOneWidget);
    expect(find.text('怎麼加入健保？'), findsOneWidget);

    await tap(tester, find.byKey(const Key('nav-0')));
    expect(find.byKey(const Key('assistant-button')), findsOneWidget);
    expect(app.vm.assistantOpen, isFalse);
  });

  testWidgets('Guests are asked to sign in before the assistant tab', (
    tester,
  ) async {
    await mount(tester, '/', const Size(375, 812), signedIn: false);
    await tap(tester, find.byKey(const Key('nav-4')));
    expect(find.text('AI 助理僅提供給已登入的使用者，請先登入後再使用。'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(find.byKey(const Key('assistant-page')), findsNothing);
  });

  testWidgets('A guest opening the assistant page directly sees sign in', (
    tester,
  ) async {
    final app = await mount(
      tester,
      '/assistant',
      const Size(375, 812),
      signedIn: false,
    );
    expect(find.byKey(const Key('assistant-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('assistant-input')), findsNothing);
    expect(app.repository.assistantMessages, isEmpty);
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
      '/explore?cat=life',
    );
    expect(
      screenActionPath(const ScreenAction('open_explore', null, 'food')),
      '/explore?cat=food',
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
    await mount(tester, '/admin', const Size(1280, 900));
    expect(find.text('只有審查者與管理者可以使用。'), findsOneWidget);
  });
}
