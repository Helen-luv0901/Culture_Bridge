part of 'bridge_view_model.dart';

mixin _BridgeAccount
    on _BridgeCore, _BridgeLibrary, _BridgeComments, _BridgeSharing {
  // ---------- sign-in ----------

  Profile? profile;
  bool get isStaff => profile?.isStaff ?? false;
  bool get isAdmin => profile?.isAdmin ?? false;

  Future<void> start() async {
    if (signedIn) await loadProfile();
  }

  /// How long to wait before asking for the profile again after a failure (a cold or
  /// busy server); the wait grows with each try.
  Duration profileRetryAfter = const Duration(seconds: 3);
  static const _profileMaxTries = 4;
  int _profileTries = 0;
  Timer? _profileRetry;

  /// Bumped on every sign-in change: a profile asked for before it belongs to someone else.
  int _profileGeneration = 0;

  Future<void> loadProfile() async {
    _profileRetry?.cancel();
    final generation = _profileGeneration;
    try {
      final loaded = await repository.me();
      if (generation != _profileGeneration) return;
      profile = loaded;
      _profileTries = 0;
    } on ApiException catch (e) {
      if (generation != _profileGeneration) return;
      if (e.needsLogin) {
        await auth.signOut();
      } else if (signedIn && ++_profileTries < _profileMaxTries) {
        // Without a profile there is no name to post with and no review entry for staff.
        _profileRetry = Timer(
          profileRetryAfter * _profileTries,
          () => unawaited(loadProfile()),
        );
      }
    }
    notifyListeners();
  }

  /// A server image path (a profile photo) as a URL the app can load.
  String? imageUrl(String? path) =>
      path == null ? null : repository.imageUrl(path);

  bool updatingAvatar = false;

  /// Replace the profile photo, or remove it with null. Returns an error message, or null.
  Future<String?> setAvatar(List<int>? bytes) async {
    updatingAvatar = true;
    notifyListeners();
    try {
      if (bytes == null) {
        await repository.deleteAvatar();
      } else {
        await repository.uploadAvatar(base64Encode(bytes));
      }
      profile = await repository.me();
    } on ApiException catch (e) {
      return errorText(e);
    } finally {
      updatingAvatar = false;
      notifyListeners();
    }
    // Signed posts and comments show the photo, so cached lists may be stale.
    _dropLists();
    _comments.clear();
    saved = const Resource();
    notifyListeners();
    return null;
  }

  /// Save the optional names; blank clears one. Returns an error message, or null.
  Future<String?> saveNames(String nickname, String realName) async {
    String? clean(String value) {
      final v = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      return v.isEmpty ? null : v;
    }

    try {
      profile = await repository.updateNames(
        nickname: clean(nickname),
        realName: clean(realName),
      );
    } on ApiException catch (e) {
      return errorText(e);
    }
    // Signed posts and comments show the name, so cached lists may be stale.
    _dropLists();
    _comments.clear();
    saved = const Resource();
    notifyListeners();
    return null;
  }

  /// The person signs out: on a shared computer the next one must not find their
  /// unpublished post. (Being signed out by the app, e.g. an expired login, keeps it.)
  Future<void> signOut() async {
    _forgetDraft();
    await auth.signOut();
  }

  Future<bool> deleteAccount() async {
    try {
      await repository.deleteAccount();
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
    await auth.deleteLogin();
    _draft = const ShareDraft();
    unawaited(preferences.saveDraft(_draft));
    showNotice(pair('帳號與資料已刪除。', 'Your account and data were deleted.'));
    return true;
  }
}
