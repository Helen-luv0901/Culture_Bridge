import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/assistant_panel.dart';
import '../features/explore_page.dart';
import 'design_system.dart';
import 'layout.dart';

/// The frame around every screen. Phone: header and bottom tabs. Tablet portrait: a 76px
/// icon sidebar. Tablet landscape and web: a 232px sidebar and search in the header.
/// The centre column is at most 880px wide; there is no right rail.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;

  static const tabs = ['/', '/explore', '/share', '/profile'];
  static const icons = ['home', 'explore', 'share', 'me'];
  static const maxContentWidth = 880.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Posts and guides keep the tab they were opened from highlighted.
  int _lastTab = 0;

  int? get _tabOfPath {
    final path = widget.uri.path;
    if (path == '/') return 0;
    if (path.startsWith('/explore')) return 1;
    if (path == '/share') return 2;
    if (path.startsWith('/profile')) return 3;
    return null;
  }

  int get _index => _tabOfPath ?? _lastTab;

  bool get _isTabRoot => AppShell.tabs.contains(widget.uri.path);

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
    if (path == '/') return layout == AppLayout.phone ? 'Culture Bridge' : '';
    if (path.startsWith('/explore')) return vm.pair('探索', 'Explore');
    if (path == '/share') return vm.pair('分享', 'Share');
    if (path == '/profile/settings') return vm.pair('設定', 'Settings');
    if (path.startsWith('/profile')) return vm.pair('我的', 'My');
    if (path.startsWith('/experiences')) {
      return vm.pair('學生分享', 'Student post');
    }
    if (path.startsWith('/actions')) {
      if (path.endsWith('/progress')) return vm.t('myActionProgress');
      if (path.endsWith('/complete')) return vm.t('actionCompletion');
      return vm.pair('官方指南', 'Official guide');
    }
    if (path.startsWith('/guide')) return vm.pair('官方指南', 'Official guide');
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

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    _showNotice(context);
    final layout = AppLayout.of(context);
    final phone = layout == AppLayout.phone;
    // The route navigator; each page brings its own scrolling frame (PageFrame).
    final content = widget.child;
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
                            _Sidebar(
                              compact: layout == AppLayout.tablet,
                              index: _index,
                              onTap: (i) => _goTab(context, i),
                            ),
                            Expanded(child: content),
                          ],
                        ),
                ),
              ],
            ),
          ),
          // Phone: the panel covers the page, so the bubble hides. Elsewhere it toggles.
          if (!(phone && vm.assistantOpen))
            Positioned(
              right: phone ? 16 : 28,
              bottom: phone ? 16 : 28,
              child: const AssistantBubble(),
            ),
        ],
      ),
      bottomNavigationBar: phone
          ? _BottomTabs(index: _index, onTap: (i) => _goTab(context, i))
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
          if (vm.assistantOpen)
            AssistantOverlay(
              uri: widget.uri,
              onNavigate: (path) => context.push(path),
            ),
        ],
      ),
    );
  }
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Culture Bridge',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle(20),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              if (showBack)
                IconButton(
                  key: const Key('back'),
                  tooltip: vm.pair('返回', 'Back'),
                  onPressed: onBack,
                  icon: const AppIcon('back'),
                ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(18),
                  ),
                ),
              ),
              if (!phone)
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: layout == AppLayout.web ? 300 : 240,
                    ),
                    child: SearchField(
                      key: const Key('header-search'),
                      compact: true,
                      initial: onExplore ? uri.queryParameters['q'] ?? '' : '',
                      category: onExplore
                          ? uri.queryParameters['cat'] ?? 'all'
                          : 'all',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One page on notebook paper: it scrolls on its own, centred and at most 880px wide.
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
    return NotebookBackground(
      child: SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppShell.maxContentWidth,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

List<String> _navLabels(BuildContext context) {
  final vm = BridgeScope.of(context);
  return [
    vm.pair('首頁', 'Home'),
    vm.pair('探索', 'Explore'),
    vm.pair('分享', 'Share'),
    vm.pair('我的', 'My'),
  ];
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.index,
    required this.onTap,
  });

  /// Tablet portrait: icons with small labels in a 76px rail.
  final bool compact;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final labels = _navLabels(context);
    return Container(
      key: const Key('desktop-navigation'),
      width: compact ? 76 : 232,
      decoration: const BoxDecoration(
        color: Palette.nav,
        border: Border(right: BorderSide(color: Palette.edge)),
      ),
      padding: EdgeInsets.symmetric(
        vertical: compact ? 20 : 24,
        horizontal: compact ? 10 : 16,
      ),
      child: Column(
        children: [
          for (int i = 0; i < AppShell.tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SidebarItem(
                key: Key('nav-$i'),
                icon: AppShell.icons[i],
                label: labels[i],
                selected: index == i,
                compact: compact,
                onTap: () => onTap(i),
              ),
            ),
        ],
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
    final color = selected ? Palette.moss : Palette.muted;
    final weight = selected ? FontWeight.w700 : FontWeight.w400;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Palette.paleMoss : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
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
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        AppIcon(icon, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              color: selected ? Palette.moss : Palette.ink,
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
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final labels = _navLabels(context);
    return Material(
      key: const Key('mobile-navigation'),
      color: Palette.nav,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Palette.edge)),
          ),
          child: Row(
            children: [
              for (int i = 0; i < AppShell.tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: index == i,
                    button: true,
                    child: InkWell(
                      key: Key('nav-$i'),
                      onTap: () => onTap(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 66),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _RingedIcon(
                                name: AppShell.icons[i],
                                selected: index == i,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                labels[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: index == i
                                      ? Palette.moss
                                      : Palette.muted,
                                  fontWeight: index == i
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The current tab's icon gets a thin brick circle around it, like a pen mark.
class _RingedIcon extends StatelessWidget {
  const _RingedIcon({required this.name, required this.selected});
  final String name;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: selected
        ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Palette.brick, width: 1.5),
          )
        : null,
    child: AppIcon(
      name,
      size: 20,
      color: selected ? Palette.moss : Palette.muted,
    ),
  );
}
