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

/// Firebase web settings: from --dart-define (FIREBASE_API_KEY, FIREBASE_APP_ID,
/// FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN, FIREBASE_MESSAGING_SENDER_ID) or, on the web,
/// from the server's /api/config. They identify the project; they are not secrets.
class FirebaseConfig {
  const FirebaseConfig(this.options);
  final FirebaseOptions options;

  static FirebaseConfig? fromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if (apiKey.isEmpty || projectId.isEmpty) return null;
    return const FirebaseConfig(
      FirebaseOptions(
        apiKey: apiKey,
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        projectId: projectId,
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        messagingSenderId: String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        ),
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
    await Firebase.initializeApp(options: config.options);
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
