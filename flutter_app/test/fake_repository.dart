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
          recentSuccessCount: c['recentCompletions'] as int,
        ),
        steps: [
          for (final (i, title) in steps.indexed)
            ActionStepInfo(
              id: '${c['id']}-step-$i',
              position: i + 1,
              title: Text2(title, enSteps[i]),
              notes: null,
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
        publishedAt: DateTime(2026, 10, 1),
        helpfulCount: e['helpfulCount'] as int,
        experiencedTooCount: 0,
        differentCount: 0,
        myReactions: const [],
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
    return Profile(id: 'dev-test', role: role, preferredLocale: 'zh-Hant');
  }

  @override
  Future<Profile> updateLocale(String locale) => me();

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
    String? topic,
    String? query,
    String? locale,
    int offset = 0,
  }) async => ExperiencePage([
    for (final e in _experiences.values)
      if ((topic == null || e.topicId == topic) &&
          (query == null || query.isEmpty || e.originalVoice.contains(query)))
        e,
  ], null);

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
    return _experiences[id] = ExperienceItem(
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
      helpfulCount: e.helpfulCount + delta,
      experiencedTooCount: e.experiencedTooCount,
      differentCount: e.differentCount,
      myReactions: reactions.toList()..sort(),
    );
  }

  @override
  Future<ExperienceDetail> requestTranslation(String id, String locale) =>
      experience(id);

  MyExperience _mine(
    String id,
    String voice,
    String status,
    SummaryDraftInfo? summary,
  ) => MyExperience(
    id: id,
    status: status,
    topicId: 'culture_communication',
    identityType: 'degree_student',
    originalVoice: voice,
    latestSummary: summary,
    impact: const Impact(0, 0, 0, 0),
  );

  @override
  Future<MyExperience> createDraft({
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
    String? differentFromId,
  }) async {
    _requireLogin();
    final id = 'draft-${_ids++}';
    return mine[id] = _mine(id, voice, 'draft', null);
  }

  @override
  Future<MyExperience> updateDraft(
    String id, {
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
  }) async => mine[id] = _mine(id, voice, 'draft', null);

  @override
  Future<SummaryDraftInfo> summarize(String experienceId) async {
    if (aiDown) throw const ApiException(503, 'ai_unavailable');
    return SummaryDraftInfo(
      id: 'summary-${_ids++}',
      situation: 'AI 整理的情境',
      feelingOrAttempt: '',
      reminder: 'AI 整理的提醒',
      matchesCurrentVoice: true,
      confirmedAt: null,
    );
  }

  Map<String, String?>? lastPublish;

  @override
  Future<MyExperience> publish(
    String experienceId,
    String summaryId, {
    String? situation,
    String? feelingOrAttempt,
    String? reminder,
  }) async {
    lastPublish = {'situation': situation, 'reminder': reminder};
    final draft = mine[experienceId]!;
    return mine[experienceId] = _mine(
      experienceId,
      draft.originalVoice,
      'published',
      null,
    );
  }

  @override
  Future<void> deleteExperience(String id) async => mine.remove(id);

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
