// Immutable mirrors of the backend's JSON (backend/app/services/*.py). Field names follow the API.

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

List<T> _list<T>(Object? value, T Function(Json) parse) => [
  for (final item in (value as List? ?? const [])) parse(item as Json),
];

/// A text in both app languages.
class Text2 {
  const Text2(this.zh, this.en);
  factory Text2.fromJson(Json json) =>
      Text2(json['zh'] as String, json['en'] as String);
  final String zh;
  final String en;
  String of(bool english) => english && en.isNotEmpty ? en : zh;
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.preferredLocale,
  });
  factory Profile.fromJson(Json json) => Profile(
    id: json['id'] as String,
    role: json['role'] as String,
    preferredLocale: json['preferred_locale'] as String,
  );
  final String id;
  final String role;
  final String preferredLocale;
  bool get isStaff => role == 'reviewer' || role == 'admin';
  bool get isAdmin => role == 'admin';
}

// ---------- procedures ----------

class ActionSummary {
  const ActionSummary({
    required this.id,
    required this.versionNumber,
    required this.title,
    required this.description,
    required this.applicableTo,
    required this.location,
    required this.verificationStatus,
    required this.lastVerifiedAt,
    required this.recentSuccessCount,
  });
  factory ActionSummary.fromJson(Json json) => ActionSummary(
    id: json['id'] as String,
    versionNumber: json['version_number'] as int,
    title: Text2.fromJson(json['title'] as Json),
    description: Text2.fromJson(json['description'] as Json),
    applicableTo: Text2.fromJson(json['applicable_to'] as Json),
    location: json['location'] == null
        ? null
        : Text2.fromJson(json['location'] as Json),
    verificationStatus: json['verification_status'] as String,
    lastVerifiedAt: _date(json['last_verified_at']),
    recentSuccessCount: json['recent_success_count'] as int,
  );
  final String id;
  final int versionNumber;
  final Text2 title;
  final Text2 description;
  final Text2 applicableTo;
  final Text2? location;
  final String verificationStatus;
  final DateTime? lastVerifiedAt;
  final int recentSuccessCount;
}

class ActionStepInfo {
  const ActionStepInfo({
    required this.id,
    required this.position,
    required this.title,
    required this.notes,
    required this.recentStuckCount,
  });
  factory ActionStepInfo.fromJson(Json json) => ActionStepInfo(
    id: json['id'] as String,
    position: json['position'] as int,
    title: Text2.fromJson(json['title'] as Json),
    notes: json['notes'] as String?,
    recentStuckCount: json['recent_stuck_count'] as int,
  );
  final String id;
  final int position;
  final Text2 title;
  final String? notes;
  final int recentStuckCount;
}

class SourceInfo {
  const SourceInfo({
    required this.title,
    required this.url,
    required this.publisher,
    required this.kind,
    required this.evidenceNote,
  });
  factory SourceInfo.fromJson(Json json) => SourceInfo(
    title: json['title'] as String,
    url: json['url'] as String,
    publisher: json['publisher'] as String,
    kind: json['kind'] as String,
    evidenceNote: json['evidence_note'] as String,
  );
  final String title;
  final String url;
  final String publisher;
  final String kind;
  final String evidenceNote;
}

class ActionDetail {
  const ActionDetail({
    required this.summary,
    required this.steps,
    required this.sources,
  });
  factory ActionDetail.fromJson(Json json) => ActionDetail(
    summary: ActionSummary.fromJson(json),
    steps: _list(json['steps'], ActionStepInfo.fromJson),
    sources: _list(json['sources'], SourceInfo.fromJson),
  );
  final ActionSummary summary;
  final List<ActionStepInfo> steps;
  final List<SourceInfo> sources;
}

class ExecutionStepState {
  const ExecutionStepState({
    required this.stepId,
    required this.position,
    required this.title,
    required this.state,
  });
  factory ExecutionStepState.fromJson(Json json) => ExecutionStepState(
    stepId: json['step_id'] as String,
    position: json['position'] as int,
    title: Text2.fromJson(json['title'] as Json),
    state: json['state'] as String,
  );
  final String stepId;
  final int position;
  final Text2 title;
  final String state;
}

class Execution {
  const Execution({
    required this.id,
    required this.actionId,
    required this.versionNumber,
    required this.title,
    required this.startedAt,
    required this.finishedAt,
    required this.outcome,
    required this.steps,
    required this.newerVersionAvailable,
  });
  factory Execution.fromJson(Json json) => Execution(
    id: json['id'] as String,
    actionId: json['action_id'] as String,
    versionNumber: json['version_number'] as int,
    title: Text2.fromJson(json['title'] as Json),
    startedAt: _date(json['started_at'])!,
    finishedAt: _date(json['finished_at']),
    outcome: json['outcome'] as String?,
    steps: _list(json['steps'], ExecutionStepState.fromJson),
    newerVersionAvailable: json['newer_version_available'] as bool,
  );
  final String id;
  final String actionId;
  final int versionNumber;
  final Text2 title;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? outcome;
  final List<ExecutionStepState> steps;
  final bool newerVersionAvailable;
  int get doneCount => steps.where((s) => s.state == 'done').length;
  bool get finished => finishedAt != null;
}

// ---------- experiences ----------

class ExperienceTranslation {
  const ExperienceTranslation({
    required this.locale,
    required this.originalVoice,
    required this.situation,
    required this.feelingOrAttempt,
    required this.reminder,
    required this.method,
  });
  factory ExperienceTranslation.fromJson(Json json) => ExperienceTranslation(
    locale: json['locale'] as String,
    originalVoice: json['original_voice'] as String,
    situation: json['situation'] as String,
    feelingOrAttempt: json['feeling_or_attempt'] as String,
    reminder: json['reminder'] as String,
    method: json['method'] as String,
  );
  final String locale;
  final String originalVoice;
  final String situation;
  final String feelingOrAttempt;
  final String reminder;
  final String method;
}

class ExperienceItem {
  const ExperienceItem({
    required this.id,
    required this.topicId,
    required this.identityType,
    required this.sourceLocale,
    required this.originalVoice,
    required this.situation,
    required this.feelingOrAttempt,
    required this.reminder,
    required this.translation,
    required this.publishedAt,
    required this.helpfulCount,
    required this.experiencedTooCount,
    required this.differentCount,
    required this.myReactions,
  });
  factory ExperienceItem.fromJson(Json json) => ExperienceItem(
    id: json['id'] as String,
    topicId: json['topic_id'] as String,
    identityType: json['identity_type'] as String,
    sourceLocale: json['source_locale'] as String,
    originalVoice: json['original_voice'] as String,
    situation: json['situation'] as String,
    feelingOrAttempt: json['feeling_or_attempt'] as String,
    reminder: json['reminder'] as String,
    translation: json['translation'] == null
        ? null
        : ExperienceTranslation.fromJson(json['translation'] as Json),
    publishedAt: _date(json['published_at'])!,
    helpfulCount: json['helpful_count'] as int,
    experiencedTooCount: json['experienced_too_count'] as int,
    differentCount: json['different_count'] as int,
    myReactions: List<String>.from(json['my_reactions'] as List),
  );
  final String id;
  final String topicId;
  final String identityType;
  final String sourceLocale;
  final String originalVoice;
  final String situation;
  final String feelingOrAttempt;
  final String reminder;
  final ExperienceTranslation? translation;
  final DateTime publishedAt;
  final int helpfulCount;
  final int experiencedTooCount;
  final int differentCount;
  final List<String> myReactions;

  /// Summary text (situation plus feeling), in the translation when [translated].
  String summaryText(bool translated) {
    final t = translated ? translation : null;
    return [
      t?.situation ?? situation,
      t?.feelingOrAttempt ?? feelingOrAttempt,
    ].where((p) => p.isNotEmpty).join(' ');
  }

  String voice(bool translated) =>
      (translated ? translation?.originalVoice : null) ?? originalVoice;
  String reminderText(bool translated) =>
      (translated ? translation?.reminder : null) ?? reminder;
}

class ExperiencePage {
  const ExperiencePage(this.items, this.nextOffset);
  factory ExperiencePage.fromJson(Json json) => ExperiencePage(
    _list(json['items'], ExperienceItem.fromJson),
    json['next_offset'] as int?,
  );
  final List<ExperienceItem> items;
  final int? nextOffset;
}

class ExperienceDetail {
  const ExperienceDetail(this.item, this.different, this.respondsToId);
  factory ExperienceDetail.fromJson(Json json) => ExperienceDetail(
    ExperienceItem.fromJson(json),
    _list(json['different_experiences'], ExperienceItem.fromJson),
    json['responds_to_id'] as String?,
  );
  final ExperienceItem item;
  final List<ExperienceItem> different;
  final String? respondsToId;
}

class SummaryDraftInfo {
  const SummaryDraftInfo({
    required this.id,
    required this.situation,
    required this.feelingOrAttempt,
    required this.reminder,
    required this.matchesCurrentVoice,
    required this.confirmedAt,
  });
  factory SummaryDraftInfo.fromJson(Json json) => SummaryDraftInfo(
    id: json['id'] as String,
    situation: json['situation'] as String,
    feelingOrAttempt: json['feeling_or_attempt'] as String,
    reminder: json['reminder'] as String,
    matchesCurrentVoice: json['matches_current_voice'] as bool,
    confirmedAt: _date(json['confirmed_at']),
  );
  final String id;
  final String situation;
  final String feelingOrAttempt;
  final String reminder;
  final bool matchesCurrentVoice;
  final DateTime? confirmedAt;
}

class Impact {
  const Impact(
    this.helpful,
    this.experiencedToo,
    this.different,
    this.peopleReached,
  );
  factory Impact.fromJson(Json json) => Impact(
    json['helpful_count'] as int,
    json['experienced_too_count'] as int,
    json['different_count'] as int,
    json['people_reached'] as int,
  );
  final int helpful;
  final int experiencedToo;
  final int different;
  final int peopleReached;
}

class MyExperience {
  const MyExperience({
    required this.id,
    required this.status,
    required this.topicId,
    required this.identityType,
    required this.originalVoice,
    required this.latestSummary,
    required this.impact,
  });
  factory MyExperience.fromJson(Json json) => MyExperience(
    id: json['id'] as String,
    status: json['status'] as String,
    topicId: json['topic_id'] as String,
    identityType: json['identity_type'] as String,
    originalVoice: json['original_voice'] as String,
    latestSummary: json['latest_summary'] == null
        ? null
        : SummaryDraftInfo.fromJson(json['latest_summary'] as Json),
    impact: Impact.fromJson(json['impact'] as Json),
  );
  final String id;
  final String status;
  final String topicId;
  final String identityType;
  final String originalVoice;
  final SummaryDraftInfo? latestSummary;
  final Impact impact;
}

class BlockInfo {
  const BlockInfo(this.id, this.createdAt);
  factory BlockInfo.fromJson(Json json) =>
      BlockInfo(json['id'] as String, _date(json['created_at'])!);
  final String id;
  final DateTime createdAt;
}

// ---------- assistant ----------

class AssistantCard {
  const AssistantCard({
    required this.type,
    required this.id,
    required this.title,
    required this.verificationStatus,
    required this.lastVerifiedAt,
    required this.recentSuccessCount,
    required this.sources,
    required this.reminder,
  });
  factory AssistantCard.fromJson(Json json) => json['type'] == 'action'
      ? AssistantCard(
          type: 'action',
          id: json['action_id'] as String,
          title: json['title'] as String,
          verificationStatus: json['verification_status'] as String,
          lastVerifiedAt: json['last_verified_at'] as String?,
          recentSuccessCount: json['recent_success_count'] as int,
          sources: List<String>.from(json['sources'] as List),
          reminder: null,
        )
      : AssistantCard(
          type: 'experience',
          id: json['experience_id'] as String,
          title: null,
          verificationStatus: null,
          lastVerifiedAt: null,
          recentSuccessCount: 0,
          sources: const [],
          reminder: json['reminder'] as String,
        );
  final String type;
  final String id;
  final String? title;
  final String? verificationStatus;
  final String? lastVerifiedAt;
  final int recentSuccessCount;
  final List<String> sources;
  final String? reminder;
}

class ScreenAction {
  const ScreenAction(this.type, this.targetId, this.topic);
  factory ScreenAction.fromJson(Json json) => ScreenAction(
    json['type'] as String,
    json['target_id'] as String?,
    json['topic'] as String?,
  );
  final String type;
  final String? targetId;
  final String? topic;
}

class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.summary,
    required this.status,
    required this.expiresAt,
    required this.targetId,
    required this.result,
  });
  factory PendingOperation.fromJson(Json json) => PendingOperation(
    id: json['id'] as String,
    summary: json['summary'] as String,
    status: json['status'] as String,
    expiresAt: _date(json['expires_at'])!,
    targetId: json['target_id'] as String,
    result: json['result'] as Json?,
  );
  final String id;
  final String summary;
  final String status;
  final DateTime expiresAt;
  final String targetId;
  final Json? result;
}

class AssistantReply {
  const AssistantReply({
    required this.conversationId,
    required this.text,
    required this.cards,
    required this.screenActions,
    required this.pendingOperations,
    required this.fallback,
  });
  factory AssistantReply.fromJson(Json json) => AssistantReply(
    conversationId: json['conversation_id'] as String,
    text: json['text'] as String,
    cards: _list(json['cards'], AssistantCard.fromJson),
    screenActions: _list(json['screen_actions'], ScreenAction.fromJson),
    pendingOperations: _list(
      json['pending_operations'],
      PendingOperation.fromJson,
    ),
    fallback: json['fallback'] as bool,
  );
  final String conversationId;
  final String text;
  final List<AssistantCard> cards;
  final List<ScreenAction> screenActions;
  final List<PendingOperation> pendingOperations;
  final bool fallback;
}
