import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'ui/core/design_system.dart';
import 'ui/core/app_shell.dart';
import 'ui/view_models/bridge_view_model.dart';
import 'ui/features/browse_pages.dart';
import 'ui/features/share_pages.dart';
import 'ui/features/action_pages.dart';

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
    redirect: (context, state) {
      if (state.uri.path == '/review' &&
          widget.viewModel.reviewedDraft == null) {
        return '/share';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(uri: state.uri, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/explore',
            builder: (context, state) {
              final topic = state.uri.queryParameters['topic'];
              return ExplorePage(
                topic:
                    ['lifeAdaptation', 'cultureCommunication'].contains(topic)
                    ? topic!
                    : 'all',
              );
            },
          ),
          GoRoute(
            path: '/share',
            builder: (context, state) => const SharePage(),
          ),
          GoRoute(
            path: '/review',
            builder: (context, state) => const ReviewPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/experiences/:id',
            builder: (context, state) =>
                ExperienceDetailPage(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/actions/:id',
            builder: (context, state) =>
                ActionDetailPage(id: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'progress',
                builder: (context, state) =>
                    ActionProgressPage(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'complete',
                builder: (context, state) =>
                    ActionCompletionPage(id: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        const Scaffold(body: Center(child: MissingContent())),
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
