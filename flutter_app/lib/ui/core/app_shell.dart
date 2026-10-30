import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/assistant_panel.dart';
import '../features/explore_page.dart';
import '../../domain/keys.dart';
import '../features/post_cards.dart' show categoryName, startSharing;
import 'design_system.dart';
import 'layout.dart';

/// The frame around every screen. Phone: header and bottom tabs. Tablet portrait: a 76px
/// icon sidebar. Tablet landscape and web: a 232px sidebar and search in the header.
/// The centre column is at most 880px wide; there is no right rail. Four destinations;
/// the assistant is the chat bubble and writing a post is a button, not tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;

  static const tabs = ['/', '/guides', '/explore', '/profile'];
  static const icons = ['home', 'guide', 'boards', 'me'];
  // A feed reads best around 760px; the side menu holds the rest.
  static const maxContentWidth = 760.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Posts and guides keep the tab they were opened from highlighted.
  int _lastTab = 0;

  int? get _tabOfPath {
    final path = widget.uri.path;
    if (path == '/') return 0;
    if (path == '/guides') return 1;
    if (path.startsWith('/explore')) return 2;
    if (path.startsWith('/profile')) return 3;
    return null;
  }

  int get _index => _tabOfPath ?? _lastTab;

  bool get _onShare => widget.uri.path == '/share';

  bool get _isTabRoot =>
      AppShell.tabs.contains(widget.uri.path) || widget.uri.path == '/share';

  @override
  void initState() {
    super.initState();
    _lastTab = _tabOfPath ?? 0;
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    _lastTab = _tabOfPath ?? _lastTab;
  }

  String _title(BuildContext context, AppLayout layout) {
    final vm = BridgeScope.of(context);
    final path = widget.uri.path;
    final phone = layout == AppLayout.phone;
    if (path == '/') return phone ? 'Culture Bridge' : '';
    // On wider screens the brand and sidebar are already there, so the tabs
    // need no page name beside the brand; phones keep it.
    if (path == '/guides') return phone ? vm.pair('官方指南', 'Guides') : '';
    if (path == '/explore') return phone ? vm.pair('看板', 'Boards') : '';
    if (path == '/share') return phone ? vm.pair('分享', 'Share') : '';
    if (path == '/profile') return phone ? vm.pair('我的', 'Me') : '';
    if (path == '/assistant') return phone ? vm.pair('助理', 'Assistant') : '';
    if (path == '/profile/settings') return vm.pair('設定', 'Settings');
    if (path.startsWith('/experiences')) {
      return vm.pair('學生分享', 'Student post');
    }
    if (path.startsWith('/actions')) {
      if (path.endsWith('/progress')) return vm.t('myActionProgress');
      if (path.endsWith('/complete')) return vm.t('actionCompletion');
      return vm.pair('官方指南', 'Official guide');
    }
    if (path == '/signin') return vm.t('signIn');
    if (path == '/welcome') return vm.t('profileNames');
    if (path.startsWith('/admin')) return vm.pair('審查與管理', 'Review & admin');
    return '';
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final path = widget.uri.path;
    if (path.endsWith('/progress') || path.endsWith('/complete')) {
      context.go('/actions/${widget.uri.pathSegments[1]}');
      return;
    }
    if (path.startsWith('/profile/')) {
      context.go('/profile');
      return;
    }
    context.go(AppShell.tabs[_index]);
  }

  void _goTab(BuildContext context, int i) => context.go(AppShell.tabs[i]);

  void _showNotice(BuildContext context) {
    final vm = BridgeScope.of(context);
    final notice = vm.notice;
    if (notice == null) return;
    // Show one-off messages (published, saved, errors) once, then clear them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (vm.notice != notice) return;
      vm.notice = null;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  /// Home, the guides list and a guide's page all show what is in progress.
  void _loadExecutions(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.signedIn || !vm.executions.needsLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (vm.signedIn && vm.executions.needsLoad) vm.loadExecutions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    _showNotice(context);
    _loadExecutions(context);
    final layout = AppLayout.of(context);
    final phone = layout == AppLayout.phone;
    // The assistant tab is the chat itself: no bubble or window over it, and a
    // window left open closes (its conversation carries on in the page).
    final onAssistantPage = widget.uri.path == '/assistant';
    if (onAssistantPage && vm.assistantOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vm.assistantOpen) vm.closeAssistant();
      });
    }
    // The route navigator; each page brings its own scrolling frame (PageFrame).
    final content = Semantics(
      role: SemanticsRole.main,
      container: true,
      child: widget.child,
    );
    final navLabel = vm.pair('主選單', 'Main menu');
    final header = _Header(
      layout: layout,
      title: _title(context, layout),
      showBack: !_isTabRoot,
      onBack: () => _back(context),
      uri: widget.uri,
    );
    final scaffold = Scaffold(
      backgroundColor: Palette.paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                header,
                Expanded(
                  child: phone
                      ? content
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              role: SemanticsRole.navigation,
                              container: true,
                              label: navLabel,
                              child: _Sidebar(
                                compact: layout == AppLayout.tablet,
                                index: _index,
                                onTap: (i) => _goTab(context, i),
                                uri: widget.uri,
                              ),
                            ),
                            Expanded(child: content),
                          ],
                        ),
                ),
              ],
            ),
          ),
          // Phone: the panel covers the page, so the bubble hides. Elsewhere it toggles.
          // Phones also leave it off posts, guides and the share form, where it sat
          // over Send and the guide's steps; the tabs still have it.
          if (!onAssistantPage &&
              !(phone && (vm.assistantOpen || !_isTabRoot || _onShare)))
            Positioned(
              right: phone ? 16 : 28,
              bottom: phone ? 16 : 28,
              child: const AssistantBubble(),
            ),
        ],
      ),
      bottomNavigationBar: phone
          ? Semantics(
              role: SemanticsRole.navigation,
              container: true,
              label: navLabel,
              child: _BottomTabs(
                index: _index,
                onTap: (i) => _goTab(context, i),
              ),
            )
          : null,
    );
    // The assistant sits above everything, the phone's tab bar included; back closes it.
    return PopScope(
      canPop: !vm.assistantOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && vm.assistantOpen) vm.closeAssistant();
      },
      child: Stack(
        children: [
          Positioned.fill(child: scaffold),
          if (vm.assistantOpen && !onAssistantPage)
            AssistantOverlay(
              uri: widget.uri,
              onNavigate: (path) => context.push(path),
            ),
        ],
      ),
    );
  }
}

/// Tabs whose page starts with its own PageTitle.
const _ownTitle = {'/guides', '/share'};

/// The tab's name, for the h1 when the header shows none.
String _pageName(BuildContext context, Uri uri) {
  final vm = BridgeScope.of(context);
  return switch (uri.path) {
    '/explore' => vm.pair('看板', 'Boards'),
    '/profile' => vm.pair('我的', 'Me'),
    _ => vm.pair('Culture Bridge 首頁', 'Culture Bridge home'),
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.layout,
    required this.title,
    required this.showBack,
    required this.onBack,
    required this.uri,
  });
  final AppLayout layout;
  final String title;
  final bool showBack;
  final VoidCallback onBack;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final phone = layout == AppLayout.phone;
    final onExplore = uri.path == '/explore';
    // The page's name is its h1, unless the page has its own title (PageTitle) or is
    // a post or guide (those titles are the h1).
    final nameIsH1 = !showBack && !_ownTitle.contains(uri.path);
    return Material(
      color: Palette.header,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: phone ? 56 : 64,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Palette.edge)),
          ),
          padding: EdgeInsets.only(
            left: phone ? (showBack ? 4 : 16) : 24,
            right: phone ? 16 : 32,
          ),
          child: Row(
            children: [
              if (!phone) ...[
                // The brand lines up with the 232px sidebar on web.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: layout == AppLayout.web ? 184 : 0,
                    maxWidth: layout == AppLayout.web ? 184 : 200,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: InkWell(
                      key: const Key('brand'),
                      onTap: () => context.go('/'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _BrandMark(),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Culture Bridge',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: displayStyle(19),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              if (phone && uri.path == '/') ...[
                const _BrandMark(),
                const SizedBox(width: 10),
              ],
              if (showBack)
                IconButton(
                  key: const Key('back'),
                  tooltip: vm.pair('返回', 'Back'),
                  onPressed: onBack,
                  icon: const AppIcon('back'),
                ),
              // Wide screens show no page name; screen readers still get one h1.
              if (!phone && title.isEmpty && nameIsH1)
                Semantics(
                  header: true,
                  headingLevel: 1,
                  label: _pageName(context, uri),
                  child: const SizedBox(width: 1, height: 1),
                ),
              if (phone || title.isNotEmpty)
                Expanded(
                  child: Semantics(
                    header: nameIsH1,
                    headingLevel: nameIsH1 ? 1 : null,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(18),
                    ),
                  ),
                ),
              if (!phone)
                Expanded(
                  flex: title.isEmpty ? 1 : 0,
                  child: Align(
                    // Centred like a forum's search bar when the page has no title.
                    alignment: title.isEmpty
                        ? Alignment.center
                        : AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: title.isEmpty ? 520 : 300,
                      ),
                      child: SearchField(
                        key: const Key('header-search'),
                        compact: true,
                        initial: onExplore
                            ? uri.queryParameters['q'] ?? ''
                            : '',
                        category: onExplore
                            ? uri.queryParameters['cat'] ?? 'all'
                            : 'all',
                      ),
                    ),
                  ),
                ),
              if (!phone) ...[
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  key: const Key('nav-share'),
                  onPressed: () => startSharing(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const AppIcon('add', size: 18, strokeWidth: 2.2),
                  label: Text(vm.pair('發文', 'Write a post')),
                ),
              ],
              if (phone && !onExplore)
                IconButton(
                  key: const Key('header-search-button'),
                  tooltip: vm.pair('搜尋', 'Search'),
                  onPressed: () => context.go('/explore'),
                  icon: const AppIcon('search', size: 21),
                ),
              SizedBox(width: phone ? 0 : 12),
              const _LanguageToggle(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's mark: the bridge in a moss circle.
class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Palette.moss,
      shape: BoxShape.circle,
    ),
    child: const AppIcon(
      'bridge',
      size: 19,
      color: Palette.onMoss,
      strokeWidth: 2,
    ),
  );
}

/// Switches between Chinese and English from any page; it shows the other language.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return TextButton(
      key: const Key('header-language'),
      onPressed: () => vm.setEnglish(!vm.english),
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: Palette.ink,
      ),
      child: Text(
        vm.english ? '中文' : 'EN',
        semanticsLabel: vm.english ? '切換成中文' : 'Switch to English',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One page on the gray ground: it scrolls on its own, centred and at most 880px wide.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final padding = switch (AppLayout.of(context)) {
      // Room at the bottom so the chat bubble never covers the last item.
      AppLayout.phone => const EdgeInsets.fromLTRB(16, 14, 16, 88),
      AppLayout.tablet => const EdgeInsets.fromLTRB(28, 24, 28, 96),
      AppLayout.web => const EdgeInsets.fromLTRB(32, 28, 32, 96),
    };
    Widget page(Widget content) => SingleChildScrollView(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppShell.maxContentWidth),
          child: content,
        ),
      ),
    );
    return NotebookBackground(child: page(child));
  }
}

List<String> _navLabels(BuildContext context) {
  final vm = BridgeScope.of(context);
  return [
    vm.pair('首頁', 'Home'),
    vm.pair('指南', 'Guides'),
    vm.pair('看板', 'Boards'),
    vm.pair('我的', 'Me'),
  ];
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.index,
    required this.onTap,
    required this.uri,
  });

  /// Tablet portrait: icons with small labels in a 76px rail.
  final bool compact;
  final int index;
  final ValueChanged<int> onTap;
  final Uri uri;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final labels = _navLabels(context);
    final board = uri.path == '/explore' ? uri.queryParameters['cat'] : null;
    return Container(
      key: const Key('desktop-navigation'),
      width: compact ? 76 : 232,
      decoration: const BoxDecoration(
        color: Palette.header,
        border: Border(right: BorderSide(color: Palette.edge)),
      ),
      // Short landscape screens with large text scroll the menu instead of clipping it.
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 16 : 20,
          horizontal: compact ? 10 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < AppShell.tabs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _SidebarItem(
                  key: Key('nav-$i'),
                  icon: AppShell.icons[i],
                  label: labels[i],
                  selected: index == i && board == null,
                  compact: compact,
                  onTap: () => onTap(i),
                ),
              ),
            if (!compact) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Semantics(
                  header: true,
                  child: Text(vm.pair('所有看板', 'All boards'), style: labelStyle),
                ),
              ),
              for (final key in categoryLabels.keys)
                if (key != 'all' && key != 'official')
                  _BoardItem(
                    key: Key('side-board-$key'),
                    label: categoryName(vm, key),
                    selected: board == key,
                    onTap: () => context.go('/explore?cat=$key'),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final String icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.ink : Palette.muted;
    final weight = selected ? FontWeight.w700 : FontWeight.w400;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? Palette.chip : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: FocusInk(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          ringRadius: const BorderRadius.all(Radius.circular(10)),
          onTap: onTap,
          child: ExcludeSemantics(
            child: compact
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      maxWidth: 56,
                      minHeight: 56,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(icon, color: color),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: color,
                            fontWeight: weight,
                          ),
                        ),
                      ],
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            icon,
                            size: 20,
                            color: color,
                            strokeWidth: selected ? 2.2 : 1.7,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 15,
                                color: Palette.ink,
                                fontWeight: weight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A board in the side menu; it opens Explore on that board.
class _BoardItem extends StatelessWidget {
  const _BoardItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: label,
    child: Material(
      color: selected ? Palette.chip : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: FocusInk(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        ringRadius: const BorderRadius.all(Radius.circular(10)),
        onTap: onTap,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected ? Palette.moss : Palette.edge,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: Palette.ink,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.index, required this.onTap});

  /// Low like other phone apps' tab bars; each tab is still well over 44px to tap.
  static const height = 56.0;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final labels = _navLabels(context);
    Widget tab(int i) {
      final on = index == i;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: labels[i],
          child: InkWell(
            key: Key('nav-$i'),
            onTap: () => onTap(i),
            child: ExcludeSemantics(
              // Grows with large text instead of clipping the label.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: height),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The current tab's icon sits on a pill, not only darker.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: on ? Palette.paleMoss : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: AppIcon(
                        AppShell.icons[i],
                        size: 22,
                        color: on ? Palette.moss : Palette.muted,
                        strokeWidth: on ? 2.3 : 1.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: on ? Palette.ink : Palette.muted,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      key: const Key('mobile-navigation'),
      color: Palette.nav,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Palette.edge)),
          ),
          child: Row(
            children: [
              tab(0),
              tab(1),
              // Writing a post sits in the middle, like a forum app's ＋.
              Expanded(
                child: SizedBox(
                  height: height,
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: vm.pair('發文', 'Write a post'),
                      child: Material(
                        color: Palette.moss,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: InkWell(
                          key: const Key('nav-share'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => startSharing(context),
                          child: const ExcludeSemantics(
                            child: SizedBox(
                              width: 52,
                              height: 44,
                              child: Center(
                                child: AppIcon(
                                  'add',
                                  size: 22,
                                  color: Palette.onMoss,
                                  strokeWidth: 2.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );
  }
}
