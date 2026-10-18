import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/admin_repository.dart';
import '../../data/api_client.dart';
import '../../data/auth_service.dart';
import '../../data/culture_repository.dart';
import '../../data/messages.dart';
import '../../data/preferences_repository.dart';
import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../../domain/models.dart';

/// Data loaded from the API: the last value, whether a load is running, and the last error.
@immutable
class Resource<T> {
  const Resource({this.data, this.error, this.loading = false});
  final T? data;
  final ApiException? error;
  final bool loading;
  bool get needsLoad => data == null && !loading && error == null;
}

/// App state for every screen: language, sign-in, cached API data and the share flow.
class BridgeViewModel extends ChangeNotifier {
  BridgeViewModel({
    required this.repository,
    required this.auth,
    required this.messages,
    required this.preferences,
    this.admin,
    bool systemEnglish = false,
    this.livePostsEvery,
  }) {
    _english = preferences.english ?? systemEnglish;
    _draft = preferences.draft;
    _read = preferences.readIds;
    _savedGuides = preferences.savedGuides;
    _wasSignedIn = auth.signedIn;
    auth.addListener(_onAuthChanged);
  }

  final CultureRepository repository;
  final AuthService auth;
  final MessageCatalog messages;
  final PreferencesRepository preferences;

  /// Reviewer/admin API; the screens only show it to staff, and the server checks roles.
  final AdminRepository? admin;

  /// How often to look for newly published posts while the app is open; null turns it off.
  final Duration? livePostsEvery;
  Timer? _liveTimer;

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

  // ---------- sign-in ----------

  Profile? profile;
  late bool _wasSignedIn;
  bool get signedIn => auth.signedIn;
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

  void _onAuthChanged() {
    if (auth.signedIn == _wasSignedIn) return;
    _wasSignedIn = auth.signedIn;
    _clearPersonalData();
    if (auth.signedIn) unawaited(loadProfile());
    notifyListeners();
  }

  void _clearPersonalData() {
    profile = null;
    chat.clear();
    conversationId = null;
    executions = const Resource();
    mine = const Resource();
    blocks = const Resource();
    saved = const Resource();
    // Lists and details carry "my reactions" and block filtering.
    _dropLists();
    _comments.clear();
    tagSuggestions = const [];
    _suggestedFor = '';
    _suggestRequest++;
    suggestingTags = false;
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

  // ---------- loading helpers ----------

  Future<void> _load<T>(
    Resource<T> Function() current,
    void Function(Resource<T>) store,
    Future<T> Function() fetch,
  ) async {
    store(Resource(data: current().data, loading: true));
    notifyListeners();
    try {
      store(Resource(data: await fetch()));
    } on ApiException catch (e) {
      store(Resource(data: current().data, error: e));
    }
    notifyListeners();
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException {
      // Best effort (e.g. syncing the language preference).
    }
  }

  // ---------- procedures ----------

  Resource<List<ActionSummary>> actions = const Resource();
  Future<void> loadActions() =>
      _load(() => actions, (r) => actions = r, repository.actions);

  final Map<String, Resource<ActionDetail>> _actions = {};
  Resource<ActionDetail> action(String id) => _actions[id] ?? const Resource();
  Future<void> loadAction(String id) => _load(
    () => action(id),
    (r) => _actions[id] = r,
    () => repository.action(id),
  );

  Resource<List<Execution>> executions = const Resource();
  Future<void> loadExecutions() async {
    if (!signedIn) return;
    await _load(
      () => executions,
      (r) => executions = r,
      repository.myExecutions,
    );
  }

  Execution? openExecution(String actionId) => executions.data
      ?.where((e) => e.actionId == actionId && !e.finished)
      .firstOrNull;

  void _replaceExecution(Execution updated) {
    final list = [...?executions.data]..removeWhere((e) => e.id == updated.id);
    if (!updated.finished) list.insert(0, updated);
    executions = Resource(data: list);
    notifyListeners();
  }

  /// Starts (or resumes) the procedure. Null with a notice when it failed.
  Future<Execution?> startAction(String actionId) async {
    try {
      final execution = await repository.startExecution(actionId, 'other');
      _replaceExecution(execution);
      return execution;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return null;
    }
  }

  Future<void> setStepDone(
    Execution execution,
    String stepId,
    bool done,
  ) async {
    try {
      _replaceExecution(
        await repository.setStep(
          execution.id,
          stepId,
          done ? 'done' : 'pending',
        ),
      );
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  static const stuckCategories = {
    'dontUnderstandStep': 'process',
    'documentsDifferent': 'documents',
    'websiteDoesNotWork': 'website',
  };

  Future<bool> reportStuck(
    Execution execution,
    String stepId,
    String reasonKey,
    String? text,
  ) async {
    try {
      await repository.sendFeedback(
        execution.id,
        kind: 'stuck',
        stepId: stepId,
        category: stuckCategories[reasonKey],
        text: text,
      );
      _replaceExecution(
        (await repository.myExecutions()).firstWhere(
          (e) => e.id == execution.id,
        ),
      );
      showNotice(t('feedbackSubmitted'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    } on StateError {
      return true;
    }
  }

  /// Records the outcome; "different" also sends one report per changed category.
  Future<bool> finishAction(
    Execution execution,
    String outcome, {
    Set<String> differences = const {},
    String? text,
  }) async {
    try {
      final categories = differences.isEmpty
          ? <String?>[null]
          : differences.toList();
      if (outcome == 'different') {
        for (final category in categories) {
          await repository.sendFeedback(
            execution.id,
            kind: 'different',
            category: category,
            text: category == categories.first ? text : null,
          );
        }
      }
      _replaceExecution(
        await repository.finishExecution(execution.id, outcome),
      );
      _actions.remove(execution.actionId); // completion counts changed
      actions = const Resource();
      showNotice(t('feedbackThanks'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }

  // ---------- posts: feed, categories, search ----------

  /// Lists of student posts, keyed by what was asked for (see [_listKey]).
  final Map<String, Resource<ExperiencePage>> _explore = {};
  static String _listKey(String? category, String sort, String? actionId) =>
      '${category ?? 'all'}|$sort|${actionId ?? ''}';

  /// Newest student posts in [category] (null: every category).
  /// Student posts, newest first (`'new'`) or most discussed first (`'hot'`:
  /// "me too" taps plus comments).
  Resource<ExperiencePage> posts([String? category, String sort = 'new']) =>
      _explore[_listKey(category, sort, null)] ?? const Resource();
  Future<void> loadPosts([
    String? category,
    bool more = false,
    String sort = 'new',
  ]) => _loadList(category, sort, null, more);

  /// Student posts shared under an official guide.
  Resource<ExperiencePage> postsForAction(String actionId) =>
      _explore[_listKey(null, 'new', actionId)] ?? const Resource();
  Future<void> loadPostsForAction(String actionId) =>
      _loadList(null, 'new', actionId, false);

  /// Starts looking for new posts every [livePostsEvery] while the app is in view.
  void startLivePosts() {
    final every = livePostsEvery;
    if (every == null) return;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(every, (_) => unawaited(refreshNewPosts()));
  }

  /// The app went to the background (no checks) or came back (check now, then keep going).
  void setAppVisible(bool visible) {
    if (!visible) {
      _liveTimer?.cancel();
      _liveTimer = null;
      return;
    }
    unawaited(refreshNewPosts());
    startLivePosts();
  }

  bool _refreshing = false;

  /// Puts posts published since a newest-first list was loaded at its top, without a reload.
  Future<void> refreshNewPosts() async {
    if (_refreshing) return;
    _refreshing = true;
    var changed = false;
    try {
      final keys = [
        for (final entry in _explore.entries)
          if (entry.key.split('|')[1] == 'new' && entry.value.data != null)
            entry.key,
      ];
      for (final key in keys) {
        final [category, _, actionId] = key.split('|');
        final ExperiencePage page;
        try {
          page = await repository.explore(
            category: category == 'all' ? null : category,
            actionId: actionId.isEmpty ? null : actionId,
            locale: locale,
          );
        } on ApiException {
          continue; // offline or busy: try again next time
        }
        final current = _explore[key]?.data;
        if (current == null) continue;
        final known = {for (final e in current.items) e.id};
        final fresh = [
          for (final e in page.items)
            if (!known.contains(e.id)) e,
        ];
        if (fresh.isEmpty) continue;
        _explore[key] = Resource(
          data: ExperiencePage([
            ...fresh,
            ...current.items,
          ], current.nextOffset),
        );
        changed = true;
      }
    } finally {
      _refreshing = false;
    }
    if (changed) notifyListeners();
  }

  Future<void> _loadList(
    String? category,
    String sort,
    String? actionId,
    bool more,
  ) {
    final key = _listKey(category, sort, actionId);
    final current = _explore[key]?.data;
    return _load(
      () => _explore[key] ?? const Resource<ExperiencePage>(),
      (r) => _explore[key] = r,
      () async {
        final page = await repository.explore(
          category: category,
          actionId: actionId,
          sort: sort,
          locale: locale,
          offset: more ? current?.nextOffset ?? 0 : 0,
        );
        return more && current != null
            ? ExperiencePage([...current.items, ...page.items], page.nextOffset)
            : page;
      },
    );
  }

  final Map<String, Resource<SearchResults>> _searches = {};
  Resource<SearchResults> search(String query) =>
      _searches[query.trim()] ?? const Resource();
  Future<void> loadSearch(String query) {
    final q = query.trim();
    return _load(
      () => search(q),
      (r) => _searches[q] = r,
      () => repository.search(q, locale: locale),
    );
  }

  Resource<List<String>> popularTags = const Resource();
  Future<void> loadPopularTags() =>
      _load(() => popularTags, (r) => popularTags = r, repository.popularTags);

  final Map<String, Resource<ExperienceDetail>> _experiences = {};
  Resource<ExperienceDetail> experience(String id) =>
      _experiences[id] ?? const Resource();
  Future<void> loadExperience(String id) => _load(
    () => experience(id),
    (r) => _experiences[id] = r,
    () => repository.experience(id),
  );

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

  bool reacted(ExperienceItem item, String kind) =>
      item.myReactions.contains(kind);

  Future<void> toggleReaction(ExperienceItem item, String kind) async {
    try {
      _updateItem(await repository.react(item.id, kind, !reacted(item, kind)));
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  // ---------- read and bookmarked ----------

  late final Set<String> _read;

  /// Opened before; lists show it dimmed with an "already read" note.
  bool isRead(String id) => _read.contains(id);
  void markRead(String id) {
    if (!_read.add(id)) return;
    unawaited(preferences.saveReadIds(_read));
    // Lists rebuild when the reader comes back, so no notify is needed here.
  }

  late final Set<String> _savedGuides;
  bool guideSaved(String actionId) => _savedGuides.contains(actionId);
  List<String> get savedGuideIds => _savedGuides.toList().reversed.toList();
  void toggleSavedGuide(String actionId) {
    final on = _savedGuides.add(actionId);
    if (!on) _savedGuides.remove(actionId);
    unawaited(preferences.saveSavedGuides(_savedGuides));
    showNotice(
      on
          ? pair('已收藏，在「我的 › 收藏」找得到', 'Saved. Find it under My › Saved.')
          : pair('已取消收藏', 'Removed from saved'),
    );
  }

  /// Ticked items of a guide's "what to bring" list (kept while the app is open).
  final Map<String, Set<int>> _documents = {};
  bool documentReady(String actionId, int index) =>
      _documents[actionId]?.contains(index) ?? false;
  int documentsReady(String actionId) => _documents[actionId]?.length ?? 0;
  void toggleDocument(String actionId, int index) {
    final ready = _documents.putIfAbsent(actionId, () => {});
    if (!ready.remove(index)) ready.add(index);
    notifyListeners();
  }

  // ---------- saved for later ----------

  Resource<List<ExperienceItem>> saved = const Resource();
  Future<void> loadSaved() async {
    if (!signedIn) return;
    await _load(
      () => saved,
      (r) => saved = r,
      () => repository.savedExperiences(locale: locale),
    );
  }

  Future<void> toggleSaved(ExperienceItem item) async {
    final on = !item.saved;
    try {
      await repository.setSaved(item.id, on);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return;
    }
    final list = saved.data;
    saved = on || list == null
        ? const Resource() // reloads, newest first, next time the list is shown
        : Resource(
            data: [
              for (final e in list)
                if (e.id != item.id) e,
            ],
          );
    showNotice(
      on
          ? pair('已收藏，在「我的 › 收藏」找得到', 'Saved. Find it under My › Saved.')
          : pair('已取消收藏', 'Removed from saved'),
    );
    _updateItem(item.withSaved(on));
  }

  final Set<String> _flipped = {};

  /// Whether the card shows the translation: by default when the reader's language differs
  /// from the author's, and the reader can flip it.
  bool translated(ExperienceItem item) {
    final otherLanguage = (item.sourceLocale == 'en') != _english;
    return otherLanguage != _flipped.contains(item.id) &&
        item.translation != null;
  }

  bool canTranslate(ExperienceItem item) =>
      item.translation != null || (item.sourceLocale == 'en') != _english;

  Future<void> toggleTranslation(ExperienceItem item) async {
    if (item.translation == null) {
      try {
        final target = item.sourceLocale == 'en' ? 'zh-Hant' : 'en';
        final detail = await repository.requestTranslation(item.id, target);
        _experiences[item.id] = Resource(data: detail);
        _updateItem(detail.item);
        _flipped.remove(item.id);
      } on ApiException catch (e) {
        showNotice(errorText(e));
      }
      return;
    }
    _flipped.contains(item.id)
        ? _flipped.remove(item.id)
        : _flipped.add(item.id);
    notifyListeners();
  }

  // ---------- comments ----------

  final Map<String, Resource<List<CommentItem>>> _comments = {};
  Resource<List<CommentItem>> comments(String experienceId) =>
      _comments[experienceId] ?? const Resource();
  Future<void> loadComments(String experienceId) => _load(
    () => comments(experienceId),
    (r) => _comments[experienceId] = r,
    () => repository.comments(experienceId),
  );

  /// Null when sent; otherwise the message to show under the box.
  Future<String?> addComment(
    String experienceId,
    String body, {
    String? replyToId,
    bool signed = false,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return pair('先寫點什麼再送出', 'Write something first');
    try {
      final comment = await repository.addComment(
        experienceId,
        body: text,
        replyToId: replyToId,
        authorDisplay: signed ? 'nickname' : 'anonymous',
      );
      _comments[experienceId] = Resource(
        data: [...?_comments[experienceId]?.data, comment],
      );
      _bumpCommentCount(experienceId, 1);
      showNotice(pair('已留言', 'Comment posted'));
      return null;
    } on ApiException catch (e) {
      return errorText(e);
    }
  }

  void _bumpCommentCount(String experienceId, int by) {
    final item = _experiences[experienceId]?.data?.item;
    if (item != null) {
      _updateItem(item.copyWith(commentCount: item.commentCount + by));
    }
  }

  Future<void> toggleCommentLike(String experienceId, CommentItem c) async {
    try {
      final updated = await repository.likeComment(c.id, !c.liked);
      _comments[experienceId] = Resource(
        data: [
          for (final e in _comments[experienceId]?.data ?? <CommentItem>[])
            e.id == c.id ? updated : e,
        ],
      );
      notifyListeners();
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  Future<void> deleteComment(String experienceId, CommentItem c) async {
    try {
      await repository.deleteComment(c.id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return;
    }
    // Replies to a deleted comment go with it on the server too.
    final before = _comments[experienceId]?.data ?? <CommentItem>[];
    final kept = [
      for (final e in before)
        if (e.id != c.id && e.replyToId != c.id) e,
    ];
    _comments[experienceId] = Resource(data: kept);
    _bumpCommentCount(experienceId, kept.length - before.length);
    showNotice(pair('已刪除留言', 'Comment deleted'));
  }

  Future<bool> reportComment(
    String commentId,
    String reason,
    String? note,
  ) async {
    try {
      await repository.reportComment(commentId, reason, note);
      showNotice(t('reportSent'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }

  // ---------- reports and blocks ----------

  Future<bool> report(String experienceId, String reason, String? note) async {
    try {
      await repository.report(experienceId, reason, note);
      showNotice(t('reportSent'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }

  Future<bool> blockAuthor(String experienceId) async {
    try {
      await repository.blockAuthor(experienceId);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
    _dropLists();
    _comments.clear();
    blocks = const Resource();
    saved = const Resource();
    showNotice(t('blocked'));
    return true;
  }

  Resource<List<BlockInfo>> blocks = const Resource();
  Future<void> loadBlocks() =>
      _load(() => blocks, (r) => blocks = r, repository.blocks);
  Future<void> unblock(String id) async {
    try {
      await repository.unblock(id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
    _dropLists();
    _comments.clear();
    await loadBlocks();
  }

  // ---------- my posts ----------

  Resource<List<MyExperience>> mine = const Resource();
  Future<void> loadMine() async {
    if (!signedIn) return;
    await _load(() => mine, (r) => mine = r, repository.myExperiences);
  }

  Future<bool> deleteExperience(String id) async {
    try {
      await repository.deleteExperience(id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
    _dropLists();
    _comments.remove(id);
    saved = const Resource();
    await loadMine();
    showNotice(pair('已刪除這篇分享', 'Post deleted'));
    return true;
  }

  // ---------- sharing ----------

  late ShareDraft _draft;
  ShareDraft get draft => _draft;
  Timer? _saveTimer;

  void _storeDraft(ShareDraft value) {
    _draft = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(preferences.saveDraft(_draft)),
    );
    notifyListeners();
  }

  void updateDraft({
    String? title,
    String? voice,
    String? category,
    String? authorDisplay,
  }) {
    _storeDraft(
      _draft.copyWith(
        title: title,
        voice: voice,
        category: category,
        authorDisplay: authorDisplay,
      ),
    );
    if (title != null || voice != null) _scheduleTagSuggestions();
  }

  void toggleChosenTag(String tag) {
    final chosen = [..._draft.chosenTags];
    if (!chosen.remove(tag)) {
      if (draftTags.length >= maxTags) {
        showNotice(pair('最多 8 個標籤', 'At most 8 tags'));
        return;
      }
      chosen.add(tag);
    }
    _storeDraft(_draft.copyWith(chosenTags: chosen));
  }

  static const maxTagLength = 12;
  static const maxTags = 8;

  /// Adds a tag the student typed; null when added, else why not.
  String? addCustomTag(String raw) {
    final word = raw
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (word.isEmpty) return pair('先輸入標籤文字', 'Type a tag first');
    if (word.length > maxTagLength) {
      return pair('標籤最多 12 個字', 'Tags are at most 12 characters');
    }
    final tag = '#$word';
    if (draftTags.length >= maxTags && !draftTags.contains(tag)) {
      return pair('最多 8 個標籤', 'At most 8 tags');
    }
    if (!_draft.customTags.contains(tag)) {
      _storeDraft(_draft.copyWith(customTags: [..._draft.customTags, tag]));
    }
    return null;
  }

  void removeCustomTag(String tag) => _storeDraft(
    _draft.copyWith(
      customTags: [
        for (final t in _draft.customTags)
          if (t != tag) t,
      ],
    ),
  );

  /// Tags that go out with the post: ticked suggestions first, then the student's own.
  List<String> get draftTags => [
    for (final t in _draft.chosenTags)
      if (!_draft.customTags.contains(t)) t,
    ..._draft.customTags,
  ].take(maxTags).toList();

  ShareDraft _relinked({String? differentFromId, String? actionId}) =>
      ShareDraft(
        title: _draft.title,
        voice: _draft.voice,
        category: _draft.category,
        chosenTags: _draft.chosenTags,
        customTags: _draft.customTags,
        authorDisplay: _draft.authorDisplay,
        differentFromId: differentFromId,
        actionId: actionId,
      );

  /// Start a post that answers [experienceId] ("my experience was different").
  void startDifferentExperience(String experienceId, {String? category}) {
    final next = _relinked(differentFromId: experienceId);
    _storeDraft(
      next.category == null && category != null
          ? next.copyWith(category: category)
          : next,
    );
  }

  /// Start a post that also shows under the official guide [actionId].
  void startPostForAction(String actionId) =>
      _storeDraft(_relinked(actionId: actionId));

  void unlinkDraft({bool post = false, bool guide = false}) =>
      _storeDraft(_draft.unlinked(post: post, guide: guide));

  // AI tag suggestions follow the text, a moment after typing stops.
  List<String> tagSuggestions = const [];
  bool suggestingTags = false;
  Timer? _suggestTimer;
  String _suggestedFor = '';

  /// Bumped for every request (and on publish or sign-out) so a late answer is ignored.
  int _suggestRequest = 0;
  static const _minSuggestLength = 8;

  void _scheduleTagSuggestions() {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(refreshTagSuggestions()),
    );
  }

  Future<void> refreshTagSuggestions() async {
    final title = _draft.title.trim();
    final text = _draft.voice.trim();
    final key = '$title\n$text';
    if (key == _suggestedFor || !signedIn) return;
    if ((title + text).length < _minSuggestLength) {
      _suggestedFor = key;
      tagSuggestions = const [];
      notifyListeners();
      return;
    }
    final request = ++_suggestRequest;
    suggestingTags = true;
    notifyListeners();
    try {
      final tags = await repository.suggestTags(
        title: title,
        text: text,
        category: _draft.category,
      );
      if (request != _suggestRequest) return;
      tagSuggestions = tags;
      _suggestedFor = key;
    } on ApiException {
      // Suggestions are optional; the student can still add tags by hand.
    } finally {
      if (request == _suggestRequest) {
        suggestingTags = false;
        notifyListeners();
      }
    }
  }

  bool publishing = false;

  /// Continue an unpublished post (saved on the server) in Share.
  void continueDraft(MyExperience item) {
    _draft = ShareDraft(
      title: item.title,
      voice: item.originalVoice,
      category: item.category ?? categoryFor(null, item.topicId),
      customTags: item.tags,
      authorDisplay: _draft.authorDisplay,
      resumesId: item.id,
    );
    unawaited(preferences.saveDraft(_draft));
    tagSuggestions = const [];
    _suggestedFor = '';
    _suggestRequest++;
    suggestingTags = false;
    notifyListeners();
    _scheduleTagSuggestions();
  }

  /// Publishes the draft exactly as written. Returns an error message, or the new post.
  Future<(String?, ExperienceItem?)> publishDraft() async {
    final title = _draft.title.trim();
    final voice = _draft.voice.trim();
    final category = _draft.category;
    if (title.isEmpty || voice.isEmpty || category == null) {
      return (pair('標題、內文和分類都要填', 'Add a title, text and category'), null);
    }
    publishing = true;
    notifyListeners();
    try {
      final item = await repository.publishPost(
        title: title,
        voice: voice,
        category: category,
        tags: draftTags,
        sourceLocale: RegExp(r'[㐀-鿿]').hasMatch(title + voice)
            ? 'zh-Hant'
            : 'en',
        authorDisplay: _draft.authorDisplay,
        differentFromId: _draft.differentFromId,
        actionId: _draft.actionId,
      );
      final replaced = _draft.resumesId;
      if (replaced != null) {
        try {
          // The unpublished copy it continued is no longer needed.
          await repository.deleteExperience(replaced);
        } on ApiException {
          // Already gone, or offline: the new post is published either way.
        }
      }
      _draft = ShareDraft(authorDisplay: _draft.authorDisplay);
      unawaited(preferences.saveDraft(_draft));
      tagSuggestions = const [];
      _suggestedFor = '';
      _suggestRequest++;
      suggestingTags = false;
      _dropLists();
      popularTags = const Resource();
      mine = const Resource();
      final label = categoryLabels[category];
      showNotice(
        item.actionId != null
            ? pair('已發布，也貼在官方指南底下', 'Published, also under the guide')
            : pair(
                '已發布，首頁和「${label?.$1}」看得到',
                'Published. It shows on Home and in ${label?.$2}.',
              ),
      );
      return (null, item);
    } on ApiException catch (e) {
      return (errorText(e), null);
    } finally {
      publishing = false;
      notifyListeners();
    }
  }

  // ---------- assistant ----------

  String? conversationId;
  final List<ChatEntry> chat = [];
  bool asking = false;

  /// The chat window over the page; the round bubble opens and closes it.
  bool assistantOpen = false;
  void openAssistant({String? question}) {
    assistantOpen = true;
    notifyListeners();
    if (question != null && question.trim().isNotEmpty) {
      unawaited(ask(question));
    }
  }

  void closeAssistant() {
    assistantOpen = false;
    notifyListeners();
  }

  /// Send a message with what the user is looking at, so "this procedure" can be resolved.
  Future<void> ask(String text, {Map<String, String>? screen}) async {
    final message = text.trim();
    if (message.isEmpty || asking) return;
    chat.add(ChatEntry.user(message));
    asking = true;
    notifyListeners();
    try {
      final reply = await repository.askAssistant(
        message: message,
        locale: locale,
        conversationId: conversationId,
        screen: screen,
      );
      conversationId = reply.conversationId;
      chat.add(ChatEntry.assistant(reply));
    } on ApiException catch (e) {
      chat.add(
        ChatEntry.error(e.needsLogin ? t('signInNeeded') : errorText(e)),
      );
    } finally {
      asking = false;
      notifyListeners();
    }
  }

  Future<void> clearChat() async {
    final id = conversationId;
    chat.clear();
    conversationId = null;
    notifyListeners();
    if (id != null) await _quietly(() => repository.clearConversation(id));
  }

  /// Confirm or cancel a write the assistant prepared (A-17); the user always decides.
  Future<void> resolveOperation(
    PendingOperation operation,
    bool confirm,
  ) async {
    try {
      final result = confirm
          ? await repository.confirmOperation(operation.id)
          : await repository.cancelOperation(operation.id);
      operationStates[operation.id] = result.status;
      if (result.status == 'confirmed') {
        await loadExecutions();
        showNotice(pair('已開始辦理。', 'Started.'));
      }
    } on ApiException catch (e) {
      operationStates[operation.id] = e.code.replaceFirst('operation_', '');
      showNotice(errorText(e));
    }
    notifyListeners();
  }

  /// Latest known status of each pending operation shown in the chat.
  final Map<String, String> operationStates = {};

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    _saveTimer?.cancel();
    _suggestTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }
}

/// One line in the assistant panel.
class ChatEntry {
  ChatEntry.user(this.text) : fromUser = true, reply = null, failed = false;
  ChatEntry.assistant(AssistantReply this.reply)
    : text = reply.text,
      fromUser = false,
      failed = false;
  ChatEntry.error(this.text) : fromUser = false, reply = null, failed = true;
  final String text;
  final bool fromUser;
  final AssistantReply? reply;
  final bool failed;
}
