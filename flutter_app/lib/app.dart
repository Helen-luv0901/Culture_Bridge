import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'domain/keys.dart';
import 'ui/core/app_shell.dart';
import 'ui/core/design_system.dart';
import 'ui/features/account_pages.dart';
import 'ui/features/action_pages.dart';
import 'ui/features/admin_pages.dart';
import 'ui/features/assistant_page.dart';
import 'ui/features/browse_pages.dart';
import 'ui/features/experience_page.dart';
import 'ui/features/explore_page.dart';
import 'ui/features/faq_pages.dart';
import 'ui/features/home_page.dart';
import 'ui/features/me_page.dart';
import 'ui/features/share_page.dart';
import 'ui/view_models/bridge_view_model.dart';

class CultureBridgeApp extends StatefulWidget {
  const CultureBridgeApp({
    super.key,
    required this.viewModel,
    this.initialLocation,
    this.updateCheck,
    this.openStore,
  });
  final BridgeViewModel viewModel;
  final String? initialLocation;

  /// Whether the store has a newer version (asked once, after the app opens); null: never.
  final Future<bool> Function()? updateCheck;

  /// Opens the app's store page, from the update notice.
  final Future<void> Function()? openStore;

  static _CultureBridgeAppState? _shown;

  /// The path of the screen on show (for error reports; an app has no page address).
  static String? get location {
    final router = _shown?.router;
    if (router == null) return null;
    final matches = router.routerDelegate.currentConfiguration;
    return matches.isEmpty ? null : matches.uri.path;
  }

  @override
  State<CultureBridgeApp> createState() => _CultureBridgeAppState();
}

class _CultureBridgeAppState extends State<CultureBridgeApp> {
  @override
  void initState() {
    super.initState();
    CultureBridgeApp._shown = this;
    final check = widget.updateCheck;
    if (check != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerUpdate(check));
    }
  }

  /// A newer version is out: say so, with a button to the store page.
  Future<void> _offerUpdate(Future<bool> Function() check) async {
    if (!await check() || !mounted) return;
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final vm = widget.viewModel;
    final update = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('update-notice'),
        title: Text(
          vm.pair('有新版本', 'A new version is out'),
          style: displayStyle(18),
        ),
        content: Text(
          vm.pair(
            'Culture Bridge 有新版本了，請到 Play 商店更新，才能使用最新的功能和修正。',
            'Culture Bridge has a new version. Update it on Google Play to get the latest '
                'features and fixes.',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(vm.pair('稍後', 'Later')),
          ),
          FilledButton(
            key: const Key('update-now'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(vm.pair('前往更新', 'Update')),
          ),
        ],
      ),
    );
    if (update == true) await widget.openStore?.call();
  }

  late final GoRouter router = GoRouter(
    initialLocation: widget.initialLocation,
    // The old "review the AI summary" step is gone: posts publish as written.
    redirect: (context, state) => switch (state.uri.path) {
      '/review' => '/share',
      // The official account and the guides list became the 問答 tab (procedures, then
      // the official Q&A); one procedure still has its own page under /actions/:id.
      '/official' || '/guide/welcome' || '/guides' || '/actions' => '/faqs',
      '/explore' when state.uri.queryParameters['cat'] == 'official' => '/faqs',
      _ => null,
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(uri: state.uri, child: child),
        routes: [
          _page('/', (state) => const HomePage()),
          _page('/explore', (state) {
            final cat = state.uri.queryParameters['cat'];
            return ExplorePage(
              category: categoryLabels.containsKey(cat) ? cat! : 'all',
              query: state.uri.queryParameters['q'] ?? '',
              sort: state.uri.queryParameters['sort'] == 'hot' ? 'hot' : 'new',
            );
          }),
          _page('/share', (state) => const SharePage()),
          // The chat fills the page and scrolls inside itself, so no PageFrame.
          GoRoute(
            path: '/assistant',
            builder: (context, state) => const AssistantPage(),
          ),
          _page(
            '/profile',
            (state) => ProfilePage(
              tab: state.uri.queryParameters['tab'] == 'saved'
                  ? 'saved'
                  : 'posts',
            ),
            routes: [_page('settings', (state) => const SettingsPage())],
          ),
          _page(
            '/faqs',
            (state) => FaqsPage(
              category: state.uri.queryParameters['cat'],
              procedures: state.uri.queryParameters['view'] == 'procedures',
            ),
            routes: [
              _page(
                ':id',
                (state) => FaqDetailPage(id: state.pathParameters['id']!),
              ),
            ],
          ),
          _page(
            '/admin',
            (state) =>
                AdminPage(tab: state.uri.queryParameters['tab'] ?? 'actions'),
            routes: [
              _page(
                'actions/:id',
                (state) => AdminActionPage(id: state.pathParameters['id']!),
              ),
            ],
          ),
          _page(
            '/welcome',
            (state) => WelcomePage(next: state.uri.queryParameters['next']),
          ),
          _page(
            '/signin',
            (state) => SignInPage(next: state.uri.queryParameters['next']),
          ),
          _page(
            '/experiences/:id',
            (state) => ExperienceDetailPage(id: state.pathParameters['id']!),
          ),
          _page(
            '/actions/:id',
            (state) => ActionDetailPage(id: state.pathParameters['id']!),
            routes: [
              // Old links to the removed progress pages open the procedure itself.
              for (final gone in ['progress', 'complete'])
                GoRoute(
                  path: gone,
                  redirect: (_, state) =>
                      '/actions/${state.pathParameters['id']}',
                ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        const Scaffold(body: Center(child: MissingContent())),
    refreshListenable: widget.viewModel.auth,
  );

  // The app root only depends on the language; pages listen to the view model themselves.
  late final _LanguageChanges language = _LanguageChanges(widget.viewModel);

  @override
  void dispose() {
    if (CultureBridgeApp._shown == this) CultureBridgeApp._shown = null;
    router.dispose();
    language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BridgeScope(
    viewModel: widget.viewModel,
    child: ListenableBuilder(
      listenable: language,
      builder: (context, _) => MaterialApp.router(
        title: 'Culture Bridge',
        debugShowCheckedModeBanner: false,
        theme: bridgeTheme(),
        locale: widget.viewModel.english
            ? const Locale('en')
            : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        supportedLocales: const [
          Locale('en'),
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
}

/// Notifies only when the app language changes, so typing a post or a list refreshing doesn't
/// rebuild the whole MaterialApp.
class _LanguageChanges extends ChangeNotifier {
  _LanguageChanges(this.viewModel) : _english = viewModel.english {
    viewModel.addListener(_check);
  }

  final BridgeViewModel viewModel;
  bool _english;

  void _check() {
    if (viewModel.english == _english) return;
    _english = viewModel.english;
    notifyListeners();
  }

  @override
  void dispose() {
    viewModel.removeListener(_check);
    super.dispose();
  }
}

/// A screen inside the shell: each page scrolls on its own sheet of notebook paper, so pages
/// stacked underneath keep their own layout.
GoRoute _page(
  String path,
  Widget Function(GoRouterState state) build, {
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  builder: (context, state) => PageFrame(child: build(state)),
  routes: routes,
);
