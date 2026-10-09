import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/content_repository.dart';
import 'data/preferences_repository.dart';
import 'ui/view_models/bridge_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final content = await AssetContentRepository.load();
  final preferences = LocalPreferencesRepository(
    await SharedPreferences.getInstance(),
  );
  final vm = BridgeViewModel(
    content: content,
    preferences: preferences,
    systemEnglish: !WidgetsBinding
        .instance
        .platformDispatcher
        .locale
        .languageCode
        .startsWith('zh'),
  );
  runApp(CultureBridgeApp(viewModel: vm));
}
