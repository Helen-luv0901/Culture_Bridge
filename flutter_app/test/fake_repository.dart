import 'dart:convert';
import 'dart:io';

import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/data/auth_service.dart';
import 'package:culture_bridge/data/culture_repository.dart';
import 'package:culture_bridge/domain/api_models.dart';

/// An in-memory backend built from assets/data/content.json, behaving like the real API for the
/// flows the screens use.
class FakeCultureRepository implements CultureRepository {
  FakeCultureRepository(this.auth) {
    final raw =
        jsonDecode(File('assets/data/content.json').readAsStringSync()) as Json;
    for (final card in raw['actionCards'] as List) {
      final c = card as Json;
      final en = (c['translations'] as Json)['en'] as Json;
      final steps = List<String>.from(c['steps'] as List);
      final enSteps = List<String>.from(en['steps'] as List);
      _actions[c['id'] as String] = ActionDetail(
        summary: ActionSummary(
          id: c['id'] as String,
          versionNumber: 1,
          title: Text2(c['title'] as String, en['title'] as String),
          description: Text2(
            c['description'] as String,
            en['description'] as String,
          ),
          applicableTo: Text2(
            c['applicableTo'] as String,
            en['applicableTo'] as String,
          ),
          location: Text2(c['location'] as String, en['location'] as String),
          verificationStatus: switch (c['status']) {
            'Needs Review' => 'needs_review',
            'Community Supported' => 'community_supported',
            _ => 'verified',
          },
          lastVerifiedAt: DateTime.parse(c['verifiedAt'] as String),
          publishedAt: DateTime.parse(c['verifiedAt'] as String),
          recentSuccessCount: c['recentCompletions'] as int,
        ),
        documents: const [
          Text2('護照正本', 'Passport'),
          Text2('在學證明', 'Certificate of enrollment'),
        ],
        steps: [
          for (final (i, title) in steps.indexed)
            ActionStepInfo(
              id: '${c['id']}-step-$i',
              position: i + 1,
              title: Text2(title, enSteps[i]),
              notes: i == 0 ? '先線上預約。' : null,
              notesEn: i == 0 ? 'Book online first.' : null,
              recentStuckCount: 0,
            ),
        ],
        sources: [
          for (final title in c['sources'] as List)
            SourceInfo(
              title: title as String,
              url: 'https://example.gov.tw/${c['id']}',
              publisher: title,
              kind: 'official',
              evidenceNote: 'demo',
            ),
        ],
      );
    }
    for (final item in raw['experiences'] as List) {
      final e = item as Json;
      final en = (e['translations'] as Json)['en'] as Json;
      _experiences[e['id'] as String] = ExperienceItem(
        id: e['id'] as String,
        topicId: e['topicKey'] == 'lifeAdaptation'
            ? 'life_adaptation'
            : 'culture_communication',
        identityType: switch (e['identityTypeKey']) {
          'exchangeStudent' => 'exchange_student',
          'languageStudent' => 'language_student',
          _ => 'degree_student',
        },
        sourceLocale: 'zh-Hant',
        originalVoice: e['originalVoice'] as String,
        situation: e['summary'] as String,
        feelingOrAttempt: '',
        reminder: e['reminder'] as String,
        translation: ExperienceTranslation(
          locale: 'en',
          originalVoice: en['originalVoice'] as String,
          situation: en['summary'] as String,
          feelingOrAttempt: '',
          reminder: en['reminder'] as String,
          method: 'human',
        ),
        publishedAt: DateTime(2026, 10, 1 + _experiences.length),
        helpfulCount: e['helpfulCount'] as int,
        experiencedTooCount: 0,
        differentCount: 0,
        myReactions: const [],
        tags: const ['#居留證'],
      );
    }
  }

  final AuthService auth;
  final Map<String, ActionDetail> _actions = {};
  final Map<String, ExperienceItem> _experiences = {};
  final List<Execution> executions = [];
  final Map<String, MyExperience> mine = {};
  final List<String> reports = [];
  final List<Map<String, Object?>> feedback = [];
  final Set<String> blocked = {};
  bool aiDown = false;
  String role = 'student';
  int _ids = 0;

  void _requireLogin() {
    if (!auth.signedIn) throw const ApiException(401, 'login_required');
  }

  @override
  Future<Profile> me() async {
    _requireLogin();
    return Profile(
      id: 'dev-test',
      role: role,
      preferredLocale: 'zh-Hant',
      nickname: nickname,
      realName: realName,
      avatarUrl: avatarUrl,
    );
  }

  String? avatarUrl;
  final List<String> uploadedPhotos = [];

  @override
  Future<void> uploadAvatar(String base64Image) async {
    _requireLogin();
    uploadedPhotos.add(base64Image);
    avatarUrl = '/api/avatars/photo-${uploadedPhotos.length}';
  }

  @override
  Future<void> deleteAvatar() async {
    _requireLogin();
    avatarUrl = null;
  }

  @override
  String imageUrl(String path) => path;

  @override
  Future<Profile> updateLocale(String locale) => me();

  String? nickname;
  String? realName;

  @override
  Future<Profile> updateNames({String? nickname, String? realName}) {
    _requireLogin();
    this.nickname = nickname;
    this.realName = realName;
    return me();
  }

  @override
  Future<void> deleteAccount() async {
    _requireLogin();
    executions.clear();
    mine.clear();
  }

  @override
  Future<List<ActionSummary>> actions() async => [
    for (final a in _actions.values) a.summary,
  ];

  @override
  Future<ActionDetail> action(String id) async =>
      _actions[id] ?? (throw const ApiException(404, 'action_not_found'));

  Execution _execution(String id, String actionId, Map<String, String> states) {
    final detail = _actions[actionId]!;
    return Execution(
      id: id,
      actionId: actionId,
      versionNumber: 1,
      title: detail.summary.title,
      startedAt: DateTime(2026, 10, 13),
      finishedAt: null,
      outcome: null,
      steps: [
        for (final s in detail.steps)
          ExecutionStepState(
            stepId: s.id,
            position: s.position,
            title: s.title,
            state: states[s.id] ?? 'pending',
          ),
      ],
      newerVersionAvailable: false,
    );
  }

  @override
  Future<Execution> startExecution(String actionId, String identityType) async {
    _requireLogin();
    final existing = executions
        .where((e) => e.actionId == actionId)
        .firstOrNull;
    if (existing != null) return existing;
    final execution = _execution('exec-${_ids++}', actionId, const {});
    executions.add(execution);
    return execution;
  }

  @override
  Future<List<Execution>> myExecutions({bool includeFinished = false}) async {
    _requireLogin();
    return [...executions];
  }

  @override
  Future<Execution> setStep(
    String executionId,
    String stepId,
    String state,
  ) async {
    final index = executions.indexWhere((e) => e.id == executionId);
    final old = executions[index];
    final states = {
      for (final s in old.steps) s.stepId: s.state,
      stepId: state,
    };
    return executions[index] = _execution(old.id, old.actionId, states);
  }

  @override
  Future<Execution> finishExecution(String executionId, String outcome) async {
    final old = executions.firstWhere((e) => e.id == executionId);
    executions.remove(old);
    return Execution(
      id: old.id,
      actionId: old.actionId,
      versionNumber: 1,
      title: old.title,
      startedAt: old.startedAt,
      finishedAt: DateTime(2026, 10, 14),
      outcome: outcome,
      steps: old.steps,
      newerVersionAvailable: false,
    );
  }

  @override
  Future<void> sendFeedback(
    String executionId, {
    required String kind,
    String? stepId,
    String? category,
    String? text,
  }) async {
    feedback.add({
      'kind': kind,
      'step': stepId,
      'category': category,
      'text': text,
    });
    if (kind == 'stuck') await setStep(executionId, stepId!, 'stuck');
  }

  @override
  Future<ExperiencePage> explore({
    String? category,
    String? query,
    String? locale,
    String? actionId,
    String sort = 'new',
    int offset = 0,
  }) async {
    final items = [
      for (final e in _experiences.values)
        if ((category == null || e.categoryKey == category) &&
            (actionId == null || e.actionId == actionId) &&
            (query == null || query.isEmpty || _matches(e, query)))
          e,
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    if (sort == 'hot') {
      int heat(ExperienceItem e) => e.experiencedTooCount + 2 * e.commentCount;
      items.sort((a, b) => heat(b).compareTo(heat(a)));
    }
    return ExperiencePage(items, null);
  }

  bool _matches(ExperienceItem e, String query) =>
      '${e.title} ${e.originalVoice} ${e.tags.join(' ')}'.contains(
        query.trim(),
      );

  @override
  Future<SearchResults> search(String query, {String? locale}) async =>
      SearchResults([
        for (final a in _actions.values)
          if (a.summary.title.zh.contains(query.trim()) ||
              a.summary.title.en.toLowerCase().contains(query.toLowerCase()))
            a.summary,
      ], (await explore(query: query)).items);

  @override
  Future<List<String>> popularTags() async => const ['#居留證', '#夜市'];

  @override
  Future<ExperienceDetail> experience(String id, {String? locale}) async =>
      ExperienceDetail(
        _experiences[id] ??
            (throw const ApiException(404, 'experience_not_found')),
        const [],
        null,
      );

  @override
  Future<ExperienceItem> react(String id, String kind, bool on) async {
    _requireLogin();
    final e = _experiences[id]!;
    final reactions = {...e.myReactions};
    on ? reactions.add(kind) : reactions.remove(kind);
    final delta =
        (reactions.contains('helpful') ? 1 : 0) -
        (e.myReactions.contains('helpful') ? 1 : 0);
    return _experiences[id] = _copy(
      e,
      helpfulCount: e.helpfulCount + delta,
      experiencedTooCount:
          e.experiencedTooCount +
          (reactions.contains('experienced_too') ? 1 : 0) -
          (e.myReactions.contains('experienced_too') ? 1 : 0),
      myReactions: reactions.toList()..sort(),
    );
  }

  ExperienceItem _copy(
    ExperienceItem e, {
    int? helpfulCount,
    int? experiencedTooCount,
    List<String>? myReactions,
    String? authorName,
  }) => ExperienceItem(
    id: e.id,
    topicId: e.topicId,
    identityType: e.identityType,
    sourceLocale: e.sourceLocale,
    originalVoice: e.originalVoice,
    situation: e.situation,
    feelingOrAttempt: e.feelingOrAttempt,
    reminder: e.reminder,
    translation: e.translation,
    publishedAt: e.publishedAt,
    helpfulCount: helpfulCount ?? e.helpfulCount,
    experiencedTooCount: experiencedTooCount ?? e.experiencedTooCount,
    differentCount: e.differentCount,
    myReactions: myReactions ?? e.myReactions,
    saved: e.saved,
    authorName: authorName ?? e.authorName,
    title: e.title,
    category: e.category,
    tags: e.tags,
    commentCount: e.commentCount,
    mine: e.mine,
    actionId: e.actionId,
  );

  /// Make an experience show [name] as its author (what the API does for signed posts).
  void signAs(String id, String name) =>
      _experiences[id] = _copy(_experiences[id]!, authorName: name);

  /// Newest first, like the API.
  final List<String> saved = [];

  @override
  Future<void> setSaved(String id, bool on) async {
    _requireLogin();
    final e = _experiences[id];
    if (on && e == null) throw const ApiException(404, 'experience_not_found');
    saved.remove(id);
    if (on) saved.insert(0, id);
    if (e != null) _experiences[id] = e.withSaved(on);
  }

  @override
  Future<List<ExperienceItem>> savedExperiences({String? locale}) async {
    _requireLogin();
    return [for (final id in saved) ?_experiences[id]];
  }

  @override
  Future<ExperienceDetail> requestTranslation(String id, String locale) =>
      experience(id);

  /// Keyword rules standing in for the AI that suggests tags.
  static const _tagRules = {
    '居留': '#居留證',
    '預約': '#線上預約',
    '夜市': '#夜市',
    '公車': '#公車',
    '租': '#租屋',
  };

  @override
  Future<List<String>> suggestTags({
    required String title,
    required String text,
    String? category,
  }) async {
    _requireLogin();
    if (aiDown) throw const ApiException(503, 'ai_unavailable');
    return [
      for (final rule in _tagRules.entries)
        if ('$title$text'.contains(rule.key)) rule.value,
    ];
  }

  Map<String, Object?>? lastPublish;

  @override
  Future<ExperienceItem> publishPost({
    required String title,
    required String voice,
    required String category,
    required List<String> tags,
    required String sourceLocale,
    String authorDisplay = 'anonymous',
    String? differentFromId,
    String? actionId,
  }) async {
    _requireLogin();
    lastPublish = {
      'title': title,
      'voice': voice,
      'category': category,
      'tags': tags,
      'author_display': authorDisplay,
      'different_from_id': differentFromId,
      'action_id': actionId,
    };
    final id = 'post-${_ids++}';
    final item = ExperienceItem(
      id: id,
      topicId: category == 'culture'
          ? 'culture_communication'
          : 'life_adaptation',
      identityType: 'other',
      sourceLocale: sourceLocale,
      originalVoice: voice,
      situation: '',
      feelingOrAttempt: '',
      reminder: '',
      translation: null,
      publishedAt: DateTime.now(),
      helpfulCount: 0,
      experiencedTooCount: 0,
      differentCount: 0,
      myReactions: const [],
      authorName: switch (authorDisplay) {
        'nickname' => nickname,
        'real_name' => realName,
        _ => null,
      },
      title: title,
      category: category,
      tags: tags,
      mine: true,
      actionId: actionId,
    );
    _experiences[id] = item;
    mine[id] = MyExperience(
      id: id,
      status: 'published',
      topicId: item.topicId,
      identityType: 'other',
      originalVoice: voice,
      latestSummary: null,
      impact: const Impact(0, 0, 0, 0),
      title: title,
      category: category,
      tags: tags,
      publishedAt: item.publishedAt,
    );
    return item;
  }

  final Map<String, List<CommentItem>> postComments = {};

  @override
  Future<List<CommentItem>> comments(String experienceId) async => [
    ...?postComments[experienceId],
  ];

  @override
  Future<CommentItem> addComment(
    String experienceId, {
    required String body,
    String? replyToId,
    String authorDisplay = 'anonymous',
  }) async {
    _requireLogin();
    final comment = CommentItem(
      id: 'c-${_ids++}',
      body: body,
      createdAt: DateTime.now(),
      likeCount: 0,
      replyToId: replyToId,
      authorName: authorDisplay == 'nickname' ? nickname : null,
      mine: true,
    );
    postComments.putIfAbsent(experienceId, () => []).add(comment);
    return comment;
  }

  @override
  Future<CommentItem> likeComment(String commentId, bool on) async {
    _requireLogin();
    for (final list in postComments.values) {
      final i = list.indexWhere((c) => c.id == commentId);
      if (i < 0) continue;
      final c = list[i];
      return list[i] = CommentItem(
        id: c.id,
        body: c.body,
        createdAt: c.createdAt,
        likeCount: c.likeCount + (on ? 1 : -1),
        replyToId: c.replyToId,
        authorName: c.authorName,
        liked: on,
        byPostAuthor: c.byPostAuthor,
        mine: c.mine,
      );
    }
    throw const ApiException(404, 'comment_not_found');
  }

  @override
  Future<void> deleteComment(String commentId) async {
    for (final list in postComments.values) {
      list.removeWhere((c) => c.id == commentId || c.replyToId == commentId);
    }
  }

  @override
  Future<void> reportComment(
    String commentId,
    String reason,
    String? note,
  ) async => reports.add('comment:$commentId:$reason');

  @override
  Future<void> deleteExperience(String id) async {
    mine.remove(id);
    _experiences.remove(id);
  }

  @override
  Future<List<MyExperience>> myExperiences() async {
    _requireLogin();
    return mine.values.toList();
  }

  @override
  Future<void> report(String experienceId, String reason, String? note) async =>
      reports.add('$experienceId:$reason');

  @override
  Future<void> blockAuthor(String experienceId) async {
    blocked.add(experienceId);
    _experiences.remove(experienceId);
  }

  @override
  Future<List<BlockInfo>> blocks() async => [
    for (final id in blocked) BlockInfo(id, DateTime(2026, 10, 13)),
  ];

  @override
  Future<void> unblock(String blockId) async => blocked.remove(blockId);

  final List<String> assistantMessages = [];
  AssistantReply Function(String message)? assistantReply;

  @override
  Future<AssistantReply> askAssistant({
    required String message,
    required String locale,
    String? conversationId,
    Map<String, String>? screen,
  }) async {
    assistantMessages.add(message);
    return assistantReply?.call(message) ??
        AssistantReply(
          conversationId: conversationId ?? 'conv-1',
          text: '依據「申請工作證」流程卡（已驗證）。',
          cards: const [],
          screenActions: const [],
          pendingOperations: const [],
          fallback: false,
        );
  }

  @override
  Future<void> clearConversation(String conversationId) async {}

  final List<String> confirmed = [];

  @override
  Future<PendingOperation> confirmOperation(String id) async {
    confirmed.add(id);
    return PendingOperation(
      id: id,
      summary: '',
      status: 'confirmed',
      expiresAt: DateTime(2030),
      targetId: 'arc',
      result: const {'execution_id': 'exec-x'},
    );
  }

  @override
  Future<PendingOperation> cancelOperation(String id) async => PendingOperation(
    id: id,
    summary: '',
    status: 'cancelled',
    expiresAt: DateTime(2030),
    targetId: 'arc',
    result: null,
  );
}
