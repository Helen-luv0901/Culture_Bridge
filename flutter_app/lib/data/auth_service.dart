import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is signed in. The backend identifies people by the token this produces; it never sees
/// passwords or emails.
abstract class AuthService extends ChangeNotifier {
  bool get signedIn;

  /// Shown on the sign-in page: Google sign-in, or a name field for development logins.
  bool get usesDevLogin;
  Future<String?> idToken();
  Future<void> signInWithGoogle();
  Future<void> signInAsDev(String name, {String? role});
  Future<void> signOut();

  /// Remove the login itself after the backend deleted the account (B-17).
  Future<void> deleteLogin();
}

/// The person closed the Google sign-in sheet without choosing an account: not an error.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// The app was built without the Firebase settings this platform needs.
class FirebaseSetupError implements Exception {
  const FirebaseSetupError(this.missing);

  /// The --dart-define that is missing, e.g. FIREBASE_ANDROID_APP_ID.
  final String missing;
  @override
  String toString() =>
      'Firebase is not set up for this platform: build with --dart-define=$missing=…';
}

/// Firebase settings. On the web they come from --dart-define (FIREBASE_API_KEY,
/// FIREBASE_APP_ID, FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN, FIREBASE_MESSAGING_SENDER_ID)
/// or the server's /api/config. The Android and iOS apps need their own app id
/// (FIREBASE_ANDROID_APP_ID / FIREBASE_IOS_APP_ID, or FIREBASE_APP_ID): the server's is the
/// web app's. They identify the project; they are not secrets.
class FirebaseConfig {
  const FirebaseConfig(this.options);
  final FirebaseOptions options;

  /// The --dart-define values this build was made with ('' when not given).
  static const defines = {
    'FIREBASE_API_KEY': String.fromEnvironment('FIREBASE_API_KEY'),
    'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
    'FIREBASE_APP_ID': String.fromEnvironment('FIREBASE_APP_ID'),
    'FIREBASE_ANDROID_APP_ID': String.fromEnvironment(
      'FIREBASE_ANDROID_APP_ID',
    ),
    'FIREBASE_IOS_APP_ID': String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    'FIREBASE_IOS_BUNDLE_ID': String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    'FIREBASE_AUTH_DOMAIN': String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    ),
  };

  /// The settings for this platform, or null when Firebase isn't set up at all (development
  /// logins). Throws [FirebaseSetupError] when an app lacks its own Firebase app id.
  static FirebaseConfig? resolve({
    required bool web,
    required TargetPlatform platform,
    required Map<String, String> defines,
    Map<String, dynamic>? server,
  }) {
    String define(String key) => (defines[key] ?? '').trim();
    String fromServer(String key) => (server?[key] as String? ?? '').trim();
    if (web) {
      final apiKey = define('FIREBASE_API_KEY');
      final projectId = define('FIREBASE_PROJECT_ID');
      if (apiKey.isNotEmpty && projectId.isNotEmpty) {
        return FirebaseConfig(
          FirebaseOptions(
            apiKey: apiKey,
            appId: define('FIREBASE_APP_ID'),
            projectId: projectId,
            authDomain: define('FIREBASE_AUTH_DOMAIN'),
            messagingSenderId: define('FIREBASE_MESSAGING_SENDER_ID'),
          ),
        );
      }
      return fromJson(server);
    }
    String either(String key, String serverKey) {
      final own = define(key);
      return own.isNotEmpty ? own : fromServer(serverKey);
    }

    final apiKey = either('FIREBASE_API_KEY', 'apiKey');
    final projectId = either('FIREBASE_PROJECT_ID', 'projectId');
    if (apiKey.isEmpty || projectId.isEmpty) return null;
    final platformKey = switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'FIREBASE_IOS_APP_ID',
      _ => 'FIREBASE_ANDROID_APP_ID',
    };
    final appId = define(platformKey).isNotEmpty
        ? define(platformKey)
        : define('FIREBASE_APP_ID');
    if (appId.isEmpty) throw FirebaseSetupError(platformKey);
    final authDomain = either('FIREBASE_AUTH_DOMAIN', 'authDomain');
    final bundleId = define('FIREBASE_IOS_BUNDLE_ID');
    return FirebaseConfig(
      FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: either(
          'FIREBASE_MESSAGING_SENDER_ID',
          'messagingSenderId',
        ),
        authDomain: authDomain.isEmpty ? null : authDomain,
        iosBundleId: bundleId.isEmpty ? null : bundleId,
      ),
    );
  }

  static FirebaseConfig? fromJson(Map<String, dynamic>? json) {
    final apiKey = json?['apiKey'] as String? ?? '';
    final projectId = json?['projectId'] as String? ?? '';
    if (apiKey.isEmpty || projectId.isEmpty) return null;
    return FirebaseConfig(
      FirebaseOptions(
        apiKey: apiKey,
        appId: json!['appId'] as String? ?? '',
        projectId: projectId,
        authDomain: json['authDomain'] as String?,
        messagingSenderId: json['messagingSenderId'] as String? ?? '',
      ),
    );
  }
}

class FirebaseAuthService extends AuthService {
  FirebaseAuthService._(this._auth) {
    _auth.idTokenChanges().listen((_) => notifyListeners());
  }

  static Future<FirebaseAuthService> initialize(FirebaseConfig config) async {
    // A retry after a failed start may find it already set up.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: config.options);
    }
    return FirebaseAuthService._(fb.FirebaseAuth.instance);
  }

  final fb.FirebaseAuth _auth;

  @override
  bool get signedIn => _auth.currentUser != null;
  @override
  bool get usesDevLogin => false;
  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  /// Firebase error codes for a sign-in the person cancelled (closed the popup or sheet).
  static bool isCancelled(String code) =>
      code == 'popup-closed-by-user' || code.contains('cancel');

  @override
  Future<void> signInWithGoogle() async {
    final provider = fb.GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      if (kIsWeb) {
        await _auth.signInWithPopup(provider);
      } else {
        await _auth.signInWithProvider(provider);
      }
    } on fb.FirebaseAuthException catch (e) {
      if (isCancelled(e.code)) throw const SignInCancelled();
      rethrow;
    }
  }

  @override
  Future<void> signInAsDev(String name, {String? role}) =>
      throw UnsupportedError(
        'Development login is off when Firebase is set up',
      );

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteLogin() async {
    final user = _auth.currentUser;
    try {
      await user?.delete();
    } on fb.FirebaseAuthException catch (e) {
      // Firebase only deletes a login that signed in recently; confirm with Google once more
      // so the Google email and name it keeps are removed too. Our own data is already gone.
      if (e.code == 'requires-recent-login' && user != null) {
        try {
          final provider = fb.GoogleAuthProvider();
          if (kIsWeb) {
            await user.reauthenticateWithPopup(provider);
          } else {
            await user.reauthenticateWithProvider(provider);
          }
          await user.delete();
        } on fb.FirebaseAuthException {
          // Cancelled or failed: signing out still ends the session.
        }
      }
    }
    await _auth.signOut();
  }
}

/// Used when Firebase is not configured (local development against APP_ENV=development):
/// sends `dev:<name>[:<role>]` tokens the backend accepts only in development.
/// With [enabled] false (a production server without Firebase) nobody can sign in.
class DevAuthService extends AuthService {
  DevAuthService(this._preferences, {this.enabled = true});
  final SharedPreferences? _preferences;
  final bool enabled;
  String? _token;

  static Future<DevAuthService> restore({bool enabled = true}) async {
    final preferences = await SharedPreferences.getInstance();
    final service = DevAuthService(preferences, enabled: enabled);
    if (enabled) service._token = preferences.getString('dev-token');
    return service;
  }

  @override
  bool get signedIn => _token != null;
  @override
  bool get usesDevLogin => true;
  @override
  Future<String?> idToken() async => _token;

  @override
  Future<void> signInWithGoogle() =>
      throw UnsupportedError('Firebase is not configured');

  @override
  Future<void> signInAsDev(String name, {String? role}) async {
    if (!enabled) throw UnsupportedError('Sign-in is not configured');
    final clean = name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '',
    );
    if (clean.isEmpty) return;
    _token = role == null ? 'dev:$clean' : 'dev:$clean:$role';
    await _preferences?.setString('dev-token', _token!);
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _token = null;
    await _preferences?.remove('dev-token');
    notifyListeners();
  }

  @override
  Future<void> deleteLogin() => signOut();
}
