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

/// Firebase options come from --dart-define so no project settings live in the repo:
/// FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN,
/// FIREBASE_MESSAGING_SENDER_ID. They identify the project; they are not secrets.
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static bool get configured => apiKey.isNotEmpty && projectId.isNotEmpty;
  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    authDomain: authDomain,
    messagingSenderId: senderId,
  );
}

class FirebaseAuthService extends AuthService {
  FirebaseAuthService._(this._auth) {
    _auth.idTokenChanges().listen((_) => notifyListeners());
  }

  static Future<FirebaseAuthService> initialize() async {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    return FirebaseAuthService._(fb.FirebaseAuth.instance);
  }

  final fb.FirebaseAuth _auth;

  @override
  bool get signedIn => _auth.currentUser != null;
  @override
  bool get usesDevLogin => false;
  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<void> signInWithGoogle() async {
    final provider = fb.GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      await _auth.signInWithProvider(provider);
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
    try {
      await _auth.currentUser?.delete();
    } on fb.FirebaseAuthException {
      // "requires-recent-login": our data is already gone; signing out is enough.
    }
    await _auth.signOut();
  }
}

/// Used when Firebase is not configured (local development against APP_ENV=development):
/// sends `dev:<name>[:<role>]` tokens the backend accepts only in development.
class DevAuthService extends AuthService {
  DevAuthService(this._preferences);
  final SharedPreferences? _preferences;
  String? _token;

  static Future<DevAuthService> restore() async {
    final preferences = await SharedPreferences.getInstance();
    return DevAuthService(preferences)
      .._token = preferences.getString('dev-token');
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
