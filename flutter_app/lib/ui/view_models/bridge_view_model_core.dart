part of 'bridge_view_model.dart';

/// What every feature mixin shares: the services, language, messages, loading helpers
/// and the post caches several features update.
abstract class _BridgeCore extends ChangeNotifier {
  _BridgeCore({
    required this.repository,
    required this.auth,
    required this.messages,
    required this.preferences,
    this.admin,
    this.livePostsEvery,
  });

  final CultureRepository repository;
  final AuthService auth;
  final MessageCatalog messages;
  final PreferencesRepository preferences;

  /// Reviewer/admin API; the screens only show it to staff, and the server checks roles.
  final AdminRepository? admin;

  /// How often to look for newly published posts while the app is open; null turns it off.
  final Duration? livePostsEvery;

  // ---------- language ----------

  late bool _english;
  bool get english => _english;
  String get locale => _english ? 'en' : 'zh-Hant';
  String t(String key) => messages.get(key, _english);
  String pair(String zh, String en) => _english ? en : zh;

  void setEnglish(bool value) {
    _english = value;
    // Lists carry the translation for the reader's language; load them again.
    _dropLists();
    unawaited(preferences.saveLanguage(value));
    if (signedIn) unawaited(_quietly(() => repository.updateLocale(locale)));
    notifyListeners();
  }

  /// Message for an API failure, in the current language.
  String errorText(Object? error) {
    final code = error is ApiException ? error.code : null;
    return switch (code) {
      'network_error' => t('networkError'),
      'login_required' || 'invalid_token' => t('signInNeeded'),
      'ai_unavailable' => t('aiUnavailable'),
      'ai_daily_limit_reached' => t('aiDailyLimit'),
      'anonymous_post_author' => pair(
        '這篇是匿名發的，作者留言也只能匿名',
        'This post is anonymous, so its author comments anonymously too',
      ),
      'rate_limited' || 'daily_limit_reached' => t('rateLimited'),
      'already_reported' => t('alreadyReported'),
      'avatar_invalid' => pair(
        '這個檔案不是照片，請選 JPG、PNG 或 WebP',
        "That file isn't a photo. Choose a JPG, PNG or WebP",
      ),
      'avatar_too_large' => pair(
        '照片太大了，請選小一點的',
        'That photo is too large. Choose a smaller one',
      ),
      'avatar_daily_limit' => pair(
        '今天換太多次了，明天再試',
        "You've changed it many times today. Try again tomorrow",
      ),
      'summary_outdated' => t('summaryOutdated'),
      _ => t('genericError'),
    };
  }

  /// One-line message shown once on the next screen (e.g. after publishing).
  String? notice;
  void showNotice(String? text) {
    notice = text;
    notifyListeners();
  }

  bool get signedIn => auth.signedIn;

  // ---------- loading helpers ----------

  Future<void> _load<T>(
    Resource<T> Function() current,
    void Function(Resource<T>) store,
    Future<T> Function() fetch,
  ) async {
    final pending = Resource<T>(data: current().data, loading: true);
    store(pending);
    notifyListeners();
    Resource<T> result;
    try {
      result = Resource(data: await fetch());
    } on ApiException catch (e) {
      result = Resource(data: current().data, error: e);
    } on Object catch (error, stack) {
      // A response the app couldn't read: show the retry message instead of loading forever,
      // and report it, since it means the app and the server disagree.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'api'),
      );
      result = Resource(
        data: current().data,
        error: const ApiException(0, 'bad_response'),
      );
    }
    // Dropped meanwhile (sign-out, language switch, a newer load): an answer to the old
    // request must not put old data back.
    if (!identical(current(), pending)) return;
    store(result);
    notifyListeners();
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException {
      // Best effort (e.g. syncing the language preference).
    }
  }

  // ---------- post caches ----------

  /// Lists of student posts, keyed by what was asked for (see [_listKey]).
  final Map<String, Resource<ExperiencePage>> _explore = {};
  final Map<String, Resource<SearchResults>> _searches = {};
  final Map<String, Resource<ExperienceDetail>> _experiences = {};

  /// Drops every cached list (after publishing, deleting, blocking or renaming).
  void _dropLists() {
    _explore.clear();
    _searches.clear();
    _experiences.clear();
  }

  /// Replace one post everywhere it is cached (after a reaction or save).
  void _updateItem(ExperienceItem item) {
    ExperienceItem swap(ExperienceItem e) => e.id == item.id ? item : e;
    for (final entry in _explore.entries.toList()) {
      final page = entry.value.data;
      if (page == null) continue;
      _explore[entry.key] = Resource(
        data: ExperiencePage([
          for (final e in page.items) swap(e),
        ], page.nextOffset),
      );
    }
    for (final entry in _searches.entries.toList()) {
      final found = entry.value.data;
      if (found == null) continue;
      _searches[entry.key] = Resource(
        data: SearchResults(found.actions, [
          for (final e in found.experiences) swap(e),
        ]),
      );
    }
    final detail = _experiences[item.id]?.data;
    if (detail != null) {
      _experiences[item.id] = Resource(
        data: ExperienceDetail(item, detail.different, detail.respondsToId),
      );
    }
    notifyListeners();
  }
}

String _listKey(String? category, String sort, String? actionId) =>
    '${category ?? 'all'}|$sort|${actionId ?? ''}';
