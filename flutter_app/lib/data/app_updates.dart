import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's package on Google Play.
const playPackage = 'com.culturebridge.culture_bridge';

/// Whether Google Play has a newer version of this app than the one running.
///
/// Only an Android app installed from Play can tell (testers included); anywhere else, or
/// when Play can't be asked, the answer is no.
Future<bool> playHasUpdate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final info = await InAppUpdate.checkForUpdate();
    return info.updateAvailability == UpdateAvailability.updateAvailable;
  } on Object {
    return false;
  }
}

/// Opens the app's page in the Play Store app, or on the Play website without it.
Future<void> openPlayPage() async {
  final store = Uri.parse('market://details?id=$playPackage');
  final web = Uri.parse(
    'https://play.google.com/store/apps/details?id=$playPackage',
  );
  try {
    if (await launchUrl(store, mode: LaunchMode.externalApplication)) return;
  } on Object {
    // No Play Store app: the website below.
  }
  await launchUrl(web, mode: LaunchMode.externalApplication);
}
