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
  // Firebase when configured (--dart-define=FIREBASE_…); otherwise development logins.
  final AuthService auth = FirebaseConfig.configured
      ? await FirebaseAuthService.initialize()
      : await DevAuthService.restore();
  final api = ApiClient.fromEnvironment(token: auth.idToken);
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
  );
  await vm.start();
  runApp(CultureBridgeApp(viewModel: vm));
}
