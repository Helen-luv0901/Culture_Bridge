import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'domain/keys.dart';
import 'ui/core/app_shell.dart';
import 'ui/core/design_system.dart';
import 'ui/features/account_pages.dart';
import 'ui/features/action_pages.dart';
import 'ui/features/admin_pages.dart';
import 'ui/features/browse_pages.dart';
import 'ui/features/experience_page.dart';
import 'ui/features/explore_page.dart';
import 'ui/features/home_page.dart';
import 'ui/features/me_page.dart';
import 'ui/features/share_page.dart';
import 'ui/view_models/bridge_view_model.dart';

class CultureBridgeApp extends StatefulWidget {
  const CultureBridgeApp({
    super.key,
    required this.viewModel,
    this.initialLocation,
  });
  final BridgeViewModel viewModel;
  final String? initialLocation;
  @override
  State<CultureBridgeApp> createState() => _CultureBridgeAppState();
}

class _CultureBridgeAppState extends State<CultureBridgeApp> {
  late final GoRouter router = GoRouter(
    initialLocation: widget.initialLocation,
    // The old "review the AI summary" step is gone: posts publish as written.
    redirect: (context, state) => state.uri.path == '/review' ? '/share' : null,
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
            );
          }),
          _page('/share', (state) => const SharePage()),
          _page(
            '/profile',
            (state) => ProfilePage(
              tab: state.uri.queryParameters['tab'] == 'saved'
                  ? 'saved'
                  : 'posts',
            ),
            routes: [_page('settings', (state) => const SettingsPage())],
          ),
          _page('/official', (state) => const OfficialAccountPage()),
          // Older links and saved bookmarks to the welcome guide.
          _page('/guide/welcome', (state) => const OfficialAccountPage()),
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
              _page(
                'progress',
                (state) => ActionProgressPage(id: state.pathParameters['id']!),
              ),
              _page(
                'complete',
                (state) =>
                    ActionCompletionPage(id: state.pathParameters['id']!),
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
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BridgeScope(
    viewModel: widget.viewModel,
    child: ListenableBuilder(
      listenable: widget.viewModel,
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
