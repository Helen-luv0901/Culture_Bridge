import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/admin_repository.dart';
import 'data/api_client.dart';
import 'data/auth_service.dart';
import 'data/culture_repository.dart';
import 'data/error_reporter.dart';
import 'data/messages.dart';
import 'data/preferences_repository.dart';
import 'ui/view_models/bridge_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Screen readers get the page from the start, not only after an "Enable accessibility"
  // button that Flutter otherwise puts first.
  SemanticsBinding.instance.ensureSemantics();
  // Posts and guides opened with push get their own address, so they can be shared.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // The token getter is wired up once we know which sign-in to use.
  AuthService? auth;
  final api = ApiClient.fromEnvironment(token: () async => auth?.idToken());
  ErrorReporter(api).install();
  // What the first screen needs, asked for at the same time rather than one after another.
  // The server's answer waits at most 2 x 8 s (a cold start answers in a few seconds).
  final configLoad = api.clientConfig(
    wait: const Duration(seconds: 8),
    attempts: 2,
  );
  final messagesLoad = MessageCatalog.load();
  final preferencesLoad = SharedPreferences.getInstance();
  final server = await configLoad;
  final firebase =
      FirebaseConfig.fromEnvironment() ??
      FirebaseConfig.fromJson(server?['firebase'] as Map<String, dynamic>?);
  auth = firebase != null
      ? await FirebaseAuthService.initialize(firebase)
      // No Firebase: development logins, which only a development server accepts.
      : await DevAuthService.restore(
          // Without the server's answer, only a debug build assumes a development server.
          enabled: server == null
              ? kDebugMode
              : server['environment'] == 'development',
        );
  final vm = BridgeViewModel(
    repository: ApiCultureRepository(api),
    admin: AdminRepository(api),
    auth: auth,
    messages: await messagesLoad,
    preferences: LocalPreferencesRepository(await preferencesLoad),
    systemEnglish: !WidgetsBinding
        .instance
        .platformDispatcher
        .locale
        .languageCode
        .startsWith('zh'),
    livePostsEvery: const Duration(seconds: 20),
  );
  // The profile first: the settings form fills its fields from it once.
  await vm.start();
  // New posts show up on their own while the app is open; no checks in the background.
  vm.startLivePosts();
  // The listener registers itself with Flutter and lives as long as the app.
  AppLifecycleListener(
    onShow: () => vm.setAppVisible(true),
    onHide: () => vm.setAppVisible(false),
  );
  runApp(CultureBridgeApp(viewModel: vm));
}
