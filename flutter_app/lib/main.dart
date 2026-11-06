import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_loader.dart';
import 'data/admin_repository.dart';
import 'data/api_client.dart';
import 'data/auth_service.dart';
import 'data/culture_repository.dart';
import 'data/error_reporter.dart';
import 'data/messages.dart';
import 'data/preferences_repository.dart';
import 'domain/api_models.dart';
import 'ui/view_models/bridge_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Screen readers on the web get the page from the start, not only after an "Enable
  // accessibility" button that Flutter otherwise puts first. The apps use the platform's.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  // Posts and guides opened with push get their own address, so they can be shared.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // The token getter is wired up once we know which sign-in to use.
  AuthService? auth;
  final api = ApiClient.fromEnvironment(token: () async => auth?.idToken());
  ErrorReporter(api, route: () => CultureBridgeApp.location ?? '').install();

  /// Everything the first screen needs. The loading screen shows meanwhile; a failure
  /// shows an error screen with a retry, which runs this again.
  Future<BridgeViewModel> start() async {
    // Asked for at the same time rather than one after another. The server's answer
    // waits at most 2 x 8 s (a cold start answers in a few seconds).
    final configLoad = api.clientConfig(
      wait: const Duration(seconds: 8),
      attempts: 2,
    );
    final messagesLoad = MessageCatalog.load();
    final preferencesLoad = SharedPreferences.getInstance();
    final server = await configLoad;
    // Throws FirebaseSetupError when an app was built without its Firebase app id.
    final firebase = FirebaseConfig.resolve(
      web: kIsWeb,
      platform: defaultTargetPlatform,
      defines: FirebaseConfig.defines,
      server: server?['firebase'] as Map<String, dynamic>?,
    );
    if (firebase == null && server == null && !kIsWeb && !kDebugMode) {
      // A released app that can't reach the server can't do anything yet: say so.
      throw const StartupError(
        '暫時連不上伺服器，請檢查網路後重試。',
        "Can't reach the server right now. Check your connection and try again.",
      );
    }
    if (firebase != null) {
      try {
        auth = await FirebaseAuthService.initialize(firebase)
            .timeout(const Duration(seconds: 20));
      } on Object catch (error) {
        throw StartupError(
          '登入服務啟動失敗，請檢查網路後重試。',
          'Sign-in could not start. Check your connection and try again.',
          error,
        );
      }
    } else {
      // No Firebase: development logins, which only a development server accepts.
      auth = await DevAuthService.restore(
        // Without the server's answer, only a debug build assumes a development server.
        enabled: server == null
            ? kDebugMode
            : server['environment'] == 'development',
      );
    }
    final vm = BridgeViewModel(
      repository: ApiCultureRepository(api),
      admin: AdminRepository(api),
      auth: auth!,
      messages: await messagesLoad,
      preferences: LocalPreferencesRepository(await preferencesLoad),
      systemEnglish: !WidgetsBinding
          .instance
          .platformDispatcher
          .locale
          .languageCode
          .startsWith('zh'),
      livePostsEvery: const Duration(seconds: 20),
      config: ClientConfig.fromJson(server),
    );
    // The profile first: the settings form fills its fields from it once.
    await vm.start();
    return vm;
  }

  // The address the page was opened with (a shared post on the web). Read it now: the
  // loading screen's own navigator resets it to "/" before the app's router starts.
  final opened = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  runApp(
    AppLoader(
      start: start,
      initialLocation: opened == '/' ? null : opened,
      onReady: (vm) {
        // New posts show up on their own while the app is open; no checks in the
        // background.
        vm.startLivePosts();
        // The listener registers itself with Flutter and lives as long as the app.
        AppLifecycleListener(
          onShow: () => vm.setAppVisible(true),
          onHide: () => vm.setAppVisible(false),
        );
      },
    ),
  );
}
