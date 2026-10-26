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

  Future<void> loadProfile() async {
    try {
      profile = await repository.me();
    } on ApiException catch (e) {
      if (e.needsLogin) await auth.signOut();
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

  Future<void> signOut() => auth.signOut();

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
