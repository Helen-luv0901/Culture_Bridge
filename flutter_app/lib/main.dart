import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/admin_repository.dart';
import 'data/api_client.dart';
import 'data/auth_service.dart';
import 'data/culture_repository.dart';
import 'data/messages.dart';
import 'data/preferences_repository.dart';
import 'ui/view_models/bridge_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // The token getter is wired up once we know which sign-in to use.
  AuthService? auth;
  final api = ApiClient.fromEnvironment(token: () async => auth?.idToken());
  final server = await api.clientConfig();
  final firebase =
      FirebaseConfig.fromEnvironment() ??
      FirebaseConfig.fromJson(server?['firebase'] as Map<String, dynamic>?);
  auth = firebase != null
      ? await FirebaseAuthService.initialize(firebase)
      // No Firebase: development logins, which only a development server accepts.
      : await DevAuthService.restore(
          enabled: (server?['environment'] ?? 'development') == 'development',
        );
  final vm = BridgeViewModel(
    repository: ApiCultureRepository(api),
    admin: AdminRepository(api),
    auth: auth,
    messages: await MessageCatalog.load(),
    preferences: LocalPreferencesRepository(
      await SharedPreferences.getInstance(),
    ),
    systemEnglish: !WidgetsBinding
        .instance
        .platformDispatcher
        .locale
        .languageCode
        .startsWith('zh'),
    livePostsEvery: const Duration(seconds: 20),
  );
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
