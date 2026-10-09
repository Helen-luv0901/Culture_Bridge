import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;
  static const paths = ['/', '/explore', '/share', '/profile'];
  static const keys = ['home', 'explore', 'share', 'myExperiences'];
  static const icons = ['home', 'compass', 'feather', 'user'];
  int get index {
    if (uri.path.startsWith('/explore') ||
        uri.path.startsWith('/experiences')) {
      return uri.queryParameters['from']?.startsWith('/profile') == true
          ? 3
          : 1;
    }
    if (uri.path == '/share' || uri.path == '/review') return 2;
    if (uri.path == '/profile') return 3;
    return 0;
  }

  String title(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (uri.path.startsWith('/experiences')) return vm.t('similarSituations');
    if (uri.path.startsWith('/actions')) {
      if (uri.path.endsWith('/progress')) return vm.t('myActionProgress');
      if (uri.path.endsWith('/complete')) return vm.t('actionCompletion');
      return vm.action(uri.pathSegments.last)?.text('title', vm.english) ??
          vm.t('officialActionGuide');
    }
    if (uri.path == '/review') return vm.t('reviewBeforePublish');
    return vm.t(keys[index]);
  }

  void back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final from = uri.queryParameters['from'];
    if (from != null && from.startsWith('/') && !from.startsWith('//')) {
      context.go(from);
      return;
    }
    if (uri.path.endsWith('/progress') || uri.path.endsWith('/complete')) {
      context.go('/actions/${uri.pathSegments[1]}');
      return;
    }
    context.go(uri.path == '/review' ? '/share' : '/');
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final mobile = c.maxWidth < 768;
        final wide = c.maxWidth > 1100;
        return Scaffold(
          body: PaperBackground(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Palette.edge)),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: mobile ? 16 : 28,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => context.go('/'),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Culture Bridge',
                                style: displayStyle(mobile ? 19 : 24),
                              ),
                            ),
                          ),
                        ),
                        if (wide)
                          Expanded(
                            child: Text(
                              vm.pair(
                                '一起寫下在台灣的生活',
                                'A shared notebook for life in Taiwan',
                              ),
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                        TextButton(
                          key: const Key('locale-zh'),
                          onPressed: () => vm.setEnglish(false),
                          child: Text(
                            '中',
                            style: TextStyle(
                              decoration: !vm.english
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('locale-en'),
                          onPressed: () => vm.setEnglish(true),
                          child: Text(
                            'EN',
                            style: TextStyle(
                              decoration: vm.english
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1380),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!mobile)
                              Container(
                                key: const Key('desktop-navigation'),
                                width: wide ? 228 : 190,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: Palette.edge),
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 28,
                                    horizontal: 14,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (int i = 0; i < 4; i++)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: TextButton(
                                            key: Key('nav-$i'),
                                            style: TextButton.styleFrom(
                                              backgroundColor: index == i
                                                  ? Palette.paleMoss
                                                  : Colors.transparent,
                                              foregroundColor: Palette.ink,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 16,
                                                  ),
                                            ),
                                            onPressed: () =>
                                                context.go(paths[i]),
                                            child: Row(
                                              children: [
                                                InkIcon(icons[i]),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(vm.t(keys[i])),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 60),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          vm.pair(
                                            '每一段經驗，都讓我們多懂一點。',
                                            'Every experience adds a different perspective.',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontStyle: FontStyle.italic,
                                            color: Palette.muted,
                                          ),
                                        ),
                                      ),
                                      Image.asset(
                                        'assets/images/botanical-0.png',
                                        height: 100,
                                        fit: BoxFit.contain,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Builder(
                                builder: (context) => SingleChildScrollView(
                                  key: ValueKey(uri.toString()),
                                  padding: EdgeInsets.fromLTRB(
                                    mobile
                                        ? 20
                                        : wide
                                        ? 48
                                        : 28,
                                    32,
                                    mobile
                                        ? 20
                                        : wide
                                        ? 48
                                        : 28,
                                    36,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        vm.pair(
                                          '你的台灣生活筆記',
                                          'Your Taiwan notebook',
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'CourierPrime',
                                          fontFamilyFallback: ['NotoSerifTC'],
                                          fontSize: 12,
                                          color: Palette.muted,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 16,
                                        runSpacing: 12,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Semantics(
                                            header: true,
                                            child: Text(
                                              title(context),
                                              style: displayStyle(
                                                mobile ? 30 : 44,
                                              ),
                                            ),
                                          ),
                                          if (!paths.contains(uri.path))
                                            TextButton.icon(
                                              onPressed: () => back(context),
                                              icon: const InkIcon('back'),
                                              label: Text(
                                                vm.pair('返回', 'Back'),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 28),
                                      child,
                                      const SizedBox(height: 40),
                                      const Divider(color: Palette.edge),
                                      Text(
                                        vm.pair(
                                          '不同的經驗，多一種理解。',
                                          'Different experiences. More ways to understand.',
                                        ),
                                        style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                          fontSize: 14,
                                          color: Palette.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: mobile
              ? SafeArea(
                  child: Container(
                    key: const Key('mobile-navigation'),
                    decoration: const BoxDecoration(
                      color: Palette.high,
                      border: Border(top: BorderSide(color: Palette.edge)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        for (int i = 0; i < 4; i++)
                          Expanded(
                            child: TextButton(
                              key: Key('nav-$i'),
                              onPressed: () => context.go(paths[i]),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 2,
                                ),
                                foregroundColor: Palette.ink,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RingIcon(icons[i], selected: index == i),
                                  Text(
                                    vm.t(i == 3 ? 'my' : keys[i]),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
