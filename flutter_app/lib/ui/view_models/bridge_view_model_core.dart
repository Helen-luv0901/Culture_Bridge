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
    this.config = const ClientConfig(),
  });

  final CultureRepository repository;
  final AuthService auth;
  final MessageCatalog messages;
  final PreferencesRepository preferences;

  /// Reviewer/admin API; the screens only show it to staff, and the server checks roles.
  final AdminRepository? admin;

  /// How often to look for newly published posts while the app is open; null turns it off.
  final Duration? livePostsEvery;

  /// The server's public settings (terms version, legal pages, support email).
  ClientConfig config;

  /// A page on the server (privacy policy, terms) as a link that works in the apps too.
  Uri siteUri(String path) => Uri.parse(repository.siteUrl(path));

  /// The server refused a post or comment because the current terms aren't accepted.
  bool _termsRefused = false;

  void _noteTerms(ApiException e) {
    if (e.code == 'terms_not_accepted') _termsRefused = true;
  }

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
      'auth_unavailable' => pair(
        '登入服務暫時無法使用，請稍後再試',
        'Sign-in is unavailable right now. Please try again later',
      ),
      'ai_unavailable' => t('aiUnavailable'),
      'ai_daily_limit_reached' => t('aiDailyLimit'),
      'anonymous_post_author' => pair(
        '這篇是匿名發的，作者留言也只能匿名',
        'This post is anonymous, so its author comments anonymously too',
      ),
      'terms_not_accepted' => pair(
        '發文或留言前，請先同意使用條款',
        'Please accept the terms of use before posting or commenting',
      ),
      'content_not_allowed' => pair(
        '內容有不允許的字詞，請修改後再送出',
        "This contains words that aren't allowed. Please edit it and try again",
      ),
      'cannot_suspend_staff' => pair(
        '不能停權工作人員的帳號',
        "Staff accounts can't be suspended",
      ),
      'terms_version_outdated' => pair(
        '條款剛更新了，請重新開啟 App 後再同意一次',
        'The terms were just updated. Reopen the app and accept them again',
      ),
      'account_suspended' => pair(
        '你的帳號已被停權，暫時不能發文或互動',
        'Your account is suspended, so you cannot post or interact for now',
      ),
      'daily_limit_reached' => pair(
        '今天的次數用完了，明天再試',
        "You've reached today's limit. Try again tomorrow",
      ),
      'rate_limited' => t('rateLimited'),
      'already_reported' => t('alreadyReported'),
      'too_many_saved' => pair(
        '收藏太多了，先移除一些再收藏',
        'You have saved too many. Remove some first',
      ),
      'experience_not_found' ||
      'comment_not_found' => pair('這則內容已經不在了', 'This is no longer here'),
      'internal_error' ||
      'http_500' ||
      'http_502' ||
      'http_503' ||
      'http_504' => pair(
        '伺服器忙碌，請稍後再試',
        'The server is busy. Please try again later',
      ),
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

  /// Whether this account still has to accept the current terms (see the account mixin).
  bool get needsTerms;

  // ---------- loading helpers ----------

  int _nextLoadId = 1;

  Future<void> _load<T>(
    Resource<T> Function() current,
    void Function(Resource<T>) store,
    Future<T> Function() fetch,
  ) async {
    final id = _nextLoadId++;
    final pending = Resource<T>(
      data: current().data,
      loading: true,
      loadId: id,
    );
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
    // request must not put old data back. Data edited meanwhile keeps the load's id.
    final now = current();
    if (!now.loading || now.loadId != id) return;
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
      _explore[entry.key] = entry.value.withData(
        ExperiencePage([for (final e in page.items) swap(e)], page.nextOffset),
      );
    }
    for (final entry in _searches.entries.toList()) {
      final found = entry.value.data;
      if (found == null) continue;
      _searches[entry.key] = entry.value.withData(
        SearchResults(found.actions, [
          for (final e in found.experiences) swap(e),
        ]),
      );
    }
    final detail = _experiences[item.id]?.data;
    if (detail != null) {
      _experiences[item.id] = _experiences[item.id]!.withData(
        ExperienceDetail(item, detail.different, detail.respondsToId),
      );
    }
    notifyListeners();
  }
}

String _listKey(String? category, String sort, String? actionId) =>
    '${category ?? 'all'}|$sort|${actionId ?? ''}';
