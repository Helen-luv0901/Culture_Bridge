import 'dart:async';

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
  }) {
    _english = preferences.english ?? systemEnglish;
    _draft = preferences.draft;
    _wasSignedIn = auth.signedIn;
    auth.addListener(_onAuthChanged);
  }

  final CultureRepository repository;
  final AuthService auth;
  final MessageCatalog messages;
  final PreferencesRepository preferences;

  /// Reviewer/admin API; the screens only show it to staff, and the server checks roles.
  final AdminRepository? admin;

  // ---------- language ----------

  late bool _english;
  bool get english => _english;
  String get locale => _english ? 'en' : 'zh-Hant';
  String t(String key) => messages.get(key, _english);
  String pair(String zh, String en) => _english ? en : zh;

  void setEnglish(bool value) {
    _english = value;
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
      'rate_limited' || 'daily_limit_reached' => t('rateLimited'),
      'already_reported' => t('alreadyReported'),
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
    // Signed experiences show the name, so cached lists may be stale.
    _explore.clear();
    _experiences.clear();
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
    _explore.clear();
    _experiences.clear();
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

  // ---------- experiences ----------

  final Map<String, Resource<ExperiencePage>> _explore = {};
  String _exploreKey(String topic, String query) => '$topic|$query';
  Resource<ExperiencePage> explore(String topic, [String query = '']) =>
      _explore[_exploreKey(topic, query)] ?? const Resource();

  Future<void> loadExplore(
    String topic, {
    String query = '',
    bool more = false,
  }) {
    final key = _exploreKey(topic, query);
    final current = explore(topic, query).data;
    return _load(
      () => explore(topic, query),
      (r) => _explore[key] = r,
      () async {
        final page = await repository.explore(
          topic: topic == 'all' ? null : apiTopic(topic),
          query: query,
          offset: more ? current?.nextOffset ?? 0 : 0,
        );
        return more && current != null
            ? ExperiencePage([...current.items, ...page.items], page.nextOffset)
            : page;
      },
    );
  }

  final Map<String, Resource<ExperienceDetail>> _experiences = {};
  Resource<ExperienceDetail> experience(String id) =>
      _experiences[id] ?? const Resource();
  Future<void> loadExperience(String id) => _load(
    () => experience(id),
    (r) => _experiences[id] = r,
    () => repository.experience(id),
  );

  /// Replace one experience everywhere it is cached (after a reaction).
  void _updateItem(ExperienceItem item) {
    for (final entry in _explore.entries.toList()) {
      final page = entry.value.data;
      if (page == null) continue;
      _explore[entry.key] = Resource(
        data: ExperiencePage([
          for (final e in page.items) e.id == item.id ? item : e,
        ], page.nextOffset),
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
    if (on) showNotice(t('savedNotice'));
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
    _explore.clear();
    _experiences.clear();
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
    _explore.clear();
    _experiences.clear();
    await loadBlocks();
  }

  // ---------- my experiences ----------

  Resource<List<MyExperience>> mine = const Resource();
  Future<void> loadMine() async {
    if (!signedIn) return;
    await _load(() => mine, (r) => mine = r, repository.myExperiences);
  }

  Future<void> deleteExperience(String id) async {
    try {
      await repository.deleteExperience(id);
      _experiences.remove(id);
      _explore.clear();
      await loadMine();
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  // ---------- sharing ----------

  late ShareDraft _draft;
  ShareDraft get draft => _draft;
  SummaryDraftInfo? _summary;

  /// The AI summary waiting for the author's confirmation (B-10).
  SummaryDraftInfo? get reviewSummary => _summary;
  Timer? _saveTimer;

  void updateDraft({String? voice, String? topic, String? identity}) {
    _draft = _draft.copyWith(
      voice: voice ?? _draft.voice,
      topic: topic ?? _draft.topic,
      identity: identity ?? _draft.identity,
    );
    _summary = null;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(preferences.saveDraft(_draft)),
    );
    notifyListeners();
  }

  void startDifferentExperience(String experienceId) {
    _draft = ShareDraft(
      topic: _draft.topic,
      identity: _draft.identity,
      differentFromId: experienceId,
    );
    _summary = null;
    unawaited(preferences.saveDraft(_draft));
    notifyListeners();
  }

  bool organizing = false;

  /// Save the draft on the server and ask the AI to organize it. Null on success, else a
  /// message to show.
  Future<String?> prepareReview() async {
    final voice = _draft.voice.trim();
    if (voice.isEmpty) return '';
    organizing = true;
    notifyListeners();
    try {
      final source = RegExp(r'[㐀-鿿]').hasMatch(voice) ? 'zh-Hant' : 'en';
      final topic = apiTopic(_draft.topic);
      final identity = apiIdentity(_draft.identity);
      String id;
      try {
        id = _draft.serverId == null
            ? (await repository.createDraft(
                topic: topic,
                identityType: identity,
                voice: voice,
                sourceLocale: source,
                differentFromId: _draft.differentFromId,
              )).id
            : (await repository.updateDraft(
                _draft.serverId!,
                topic: topic,
                identityType: identity,
                voice: voice,
                sourceLocale: source,
              )).id;
      } on ApiException catch (e) {
        // The saved server draft is gone (published elsewhere or deleted): start a new one.
        if (_draft.serverId == null || (e.status != 404 && e.status != 409)) {
          rethrow;
        }
        id = (await repository.createDraft(
          topic: topic,
          identityType: identity,
          voice: voice,
          sourceLocale: source,
          differentFromId: _draft.differentFromId,
        )).id;
      }
      _draft = _draft.copyWith(serverId: id);
      unawaited(preferences.saveDraft(_draft));
      _summary = await repository.summarize(id);
      return null;
    } on ApiException catch (e) {
      return errorText(e);
    } finally {
      organizing = false;
      notifyListeners();
    }
  }

  /// Confirm (with optional edits) and publish anonymously.
  Future<String?> publish({
    String? situation,
    String? feelingOrAttempt,
    String? reminder,
    String authorDisplay = 'anonymous',
  }) async {
    final summary = _summary;
    final id = _draft.serverId;
    if (summary == null || id == null) return t('summaryOutdated');
    try {
      await repository.publish(
        id,
        summary.id,
        situation: situation,
        feelingOrAttempt: feelingOrAttempt,
        reminder: reminder,
        authorDisplay: authorDisplay,
      );
    } on ApiException catch (e) {
      return errorText(e);
    }
    _draft = ShareDraft(topic: _draft.topic, identity: _draft.identity);
    _summary = null;
    unawaited(preferences.saveDraft(_draft));
    _explore.clear();
    mine = const Resource();
    showNotice(t('publishedNotice'));
    return null;
  }

  // ---------- assistant ----------

  String? conversationId;
  final List<ChatEntry> chat = [];
  bool asking = false;

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
