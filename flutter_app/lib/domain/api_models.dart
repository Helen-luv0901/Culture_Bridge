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
    this.nickname,
    this.realName,
    this.avatarUrl,
  });
  factory Profile.fromJson(Json json) => Profile(
    id: json['id'] as String,
    role: json['role'] as String,
    preferredLocale: json['preferred_locale'] as String,
    nickname: json['nickname'] as String?,
    realName: json['real_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
  );
  final String id;
  final String role;
  final String preferredLocale;

  /// Optional; shown only on experiences the person chose to sign with them.
  final String? nickname;
  final String? realName;

  /// Server path of the profile photo, if any.
  final String? avatarUrl;
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
    this.slug = '',
    this.publishedAt,
  });
  factory ActionSummary.fromJson(Json json) => ActionSummary(
    id: json['id'] as String,
    slug: json['slug'] as String? ?? '',
    versionNumber: json['version_number'] as int,
    title: Text2.fromJson(json['title'] as Json),
    description: Text2.fromJson(json['description'] as Json),
    applicableTo: Text2.fromJson(json['applicable_to'] as Json),
    location: json['location'] == null
        ? null
        : Text2.fromJson(json['location'] as Json),
    verificationStatus: json['verification_status'] as String,
    lastVerifiedAt: _date(json['last_verified_at']),
    publishedAt: _date(json['published_at']),
    recentSuccessCount: json['recent_success_count'] as int,
  );
  final String id;
  final String slug;
  final int versionNumber;
  final Text2 title;
  final Text2 description;
  final Text2 applicableTo;
  final Text2? location;
  final String verificationStatus;
  final DateTime? lastVerifiedAt;

  /// When this version went public; the feed sorts official guides by it.
  final DateTime? publishedAt;
  final int recentSuccessCount;
}

class ActionStepInfo {
  const ActionStepInfo({
    required this.id,
    required this.position,
    required this.title,
    required this.notes,
    required this.recentStuckCount,
    this.notesEn,
  });
  factory ActionStepInfo.fromJson(Json json) => ActionStepInfo(
    id: json['id'] as String,
    position: json['position'] as int,
    title: Text2.fromJson(json['title'] as Json),
    notes: json['notes'] as String?,
    notesEn: json['notes_en'] as String?,
    recentStuckCount: json['recent_stuck_count'] as int,
  );
  final String id;
  final int position;
  final Text2 title;
  final String? notes;
  final String? notesEn;
  final int recentStuckCount;

  /// The notes in the reader's language; English falls back to Chinese.
  String? notesFor(bool english) =>
      english && (notesEn ?? '').trim().isNotEmpty ? notesEn : notes;
}

class SourceInfo {
  const SourceInfo({
    required this.title,
    required this.url,
    required this.publisher,
    required this.kind,
    required this.evidenceNote,
    this.publisherEn = '',
  });
  factory SourceInfo.fromJson(Json json) => SourceInfo(
    title: json['title'] as String,
    url: json['url'] as String,
    publisher: json['publisher'] as String,
    kind: json['kind'] as String,
    evidenceNote: json['evidence_note'] as String,
    publisherEn: json['publisher_en'] as String? ?? '',
  );
  final String title;
  final String url;
  final String publisher;
  final String publisherEn;
  final String kind;
  final String evidenceNote;

  /// The publisher's name in the reader's language.
  String publisherFor(bool english) =>
      english && publisherEn.isNotEmpty ? publisherEn : publisher;
}

class ActionDetail {
  const ActionDetail({
    required this.summary,
    required this.steps,
    required this.sources,
    this.documents = const [],
  });
  factory ActionDetail.fromJson(Json json) => ActionDetail(
    summary: ActionSummary.fromJson(json),
    steps: _list(json['steps'], ActionStepInfo.fromJson),
    sources: _list(json['sources'], SourceInfo.fromJson),
    documents: _list(json['documents'], Text2.fromJson),
  );
  final ActionSummary summary;
  final List<ActionStepInfo> steps;
  final List<SourceInfo> sources;

  /// What to bring, shown as a checklist the student ticks before going.
  final List<Text2> documents;
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

/// The seven categories students post into. Explore adds "all" and "official" in front.
const postCategories = [
  'life',
  'food',
  'housing',
  'transit',
  'study',
  'culture',
  'difference',
];

/// Older posts only have one of the two original topics.
String categoryFor(String? category, String topicId) =>
    category ?? (topicId == 'culture_communication' ? 'culture' : 'life');

class ExperienceTranslation {
  const ExperienceTranslation({
    required this.locale,
    required this.originalVoice,
    required this.situation,
    required this.feelingOrAttempt,
    required this.reminder,
    required this.method,
    this.title,
  });
  factory ExperienceTranslation.fromJson(Json json) => ExperienceTranslation(
    locale: json['locale'] as String,
    title: json['title'] as String?,
    originalVoice: json['original_voice'] as String,
    situation: json['situation'] as String,
    feelingOrAttempt: json['feeling_or_attempt'] as String,
    reminder: json['reminder'] as String,
    method: json['method'] as String,
  );
  final String locale;
  final String? title;
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
    this.saved = false,
    this.authorName,
    this.authorAvatarUrl,
    this.title = '',
    this.category,
    this.tags = const [],
    this.commentCount = 0,
    this.mine = false,
    this.actionId,
  });
  factory ExperienceItem.fromJson(Json json) => ExperienceItem(
    id: json['id'] as String,
    topicId: json['topic_id'] as String,
    identityType: json['identity_type'] as String,
    sourceLocale: json['source_locale'] as String,
    originalVoice: json['original_voice'] as String,
    situation: json['situation'] as String? ?? '',
    feelingOrAttempt: json['feeling_or_attempt'] as String? ?? '',
    reminder: json['reminder'] as String? ?? '',
    translation: json['translation'] == null
        ? null
        : ExperienceTranslation.fromJson(json['translation'] as Json),
    publishedAt: _date(json['published_at'])!,
    helpfulCount: json['helpful_count'] as int,
    experiencedTooCount: json['experienced_too_count'] as int,
    differentCount: json['different_count'] as int,
    myReactions: List<String>.from(json['my_reactions'] as List),
    saved: json['saved'] as bool? ?? false,
    authorName: json['author_name'] as String?,
    authorAvatarUrl: json['author_avatar_url'] as String?,
    title: json['title'] as String? ?? '',
    category: json['category'] as String?,
    tags: List<String>.from(json['tags'] as List? ?? const []),
    commentCount: json['comment_count'] as int? ?? 0,
    mine: json['mine'] as bool? ?? false,
    actionId: json['action_id'] as String?,
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

  /// In the reader's private "read later" list.
  final bool saved;

  /// The nickname or real name the author chose to sign with; null means anonymous.
  final String? authorName;

  /// The author's photo; only on signed posts.
  final String? authorAvatarUrl;

  /// Written by the author; older posts have none and show the start of the text instead.
  final String title;
  final String? category;
  final List<String> tags;
  final int commentCount;

  /// Written by the signed-in reader (they can delete it).
  final bool mine;

  /// The official guide this post was shared under, if any.
  final String? actionId;

  String get categoryKey => categoryFor(category, topicId);

  ExperienceItem withSaved(bool value) => copyWith(saved: value);

  ExperienceItem copyWith({bool? saved, int? commentCount}) => ExperienceItem(
    id: id,
    topicId: topicId,
    identityType: identityType,
    sourceLocale: sourceLocale,
    originalVoice: originalVoice,
    situation: situation,
    feelingOrAttempt: feelingOrAttempt,
    reminder: reminder,
    translation: translation,
    publishedAt: publishedAt,
    helpfulCount: helpfulCount,
    experiencedTooCount: experiencedTooCount,
    differentCount: differentCount,
    myReactions: myReactions,
    saved: saved ?? this.saved,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    title: title,
    category: category,
    tags: tags,
    commentCount: commentCount ?? this.commentCount,
    mine: mine,
    actionId: actionId,
  );

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

  /// The title, or for older posts without one the start of the text.
  String heading(bool translated) {
    final own = (translated ? translation?.title : null) ?? title;
    if (own.trim().isNotEmpty) return own.trim();
    final text = voice(translated).trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 24 ? '${text.substring(0, 24)}…' : text;
  }
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

/// Keyword search over official guides and student posts.
class SearchResults {
  const SearchResults(this.actions, this.experiences);
  factory SearchResults.fromJson(Json json) => SearchResults(
    _list(json['actions'], ActionSummary.fromJson),
    _list(json['experiences'], ExperienceItem.fromJson),
  );
  final List<ActionSummary> actions;
  final List<ExperienceItem> experiences;
}

/// A comment under a student post; [replyToId] points at the comment it answers.
class CommentItem {
  const CommentItem({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.likeCount,
    this.replyToId,
    this.authorName,
    this.authorAvatarUrl,
    this.liked = false,
    this.byPostAuthor = false,
    this.mine = false,
  });
  factory CommentItem.fromJson(Json json) => CommentItem(
    id: json['id'] as String,
    body: json['body'] as String,
    createdAt: _date(json['created_at'])!,
    likeCount: json['like_count'] as int? ?? 0,
    replyToId: json['reply_to_id'] as String?,
    authorName: json['author_name'] as String?,
    authorAvatarUrl: json['author_avatar_url'] as String?,
    liked: json['liked'] as bool? ?? false,
    byPostAuthor: json['by_post_author'] as bool? ?? false,
    mine: json['mine'] as bool? ?? false,
  );
  final String id;
  final String body;
  final DateTime createdAt;
  final int likeCount;
  final String? replyToId;

  /// The commenter's nickname when they chose to sign; null means anonymous.
  final String? authorName;

  /// Their photo; only on signed comments.
  final String? authorAvatarUrl;
  final bool liked;
  final bool byPostAuthor;
  final bool mine;
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
    this.title = '',
    this.category,
    this.tags = const [],
    this.publishedAt,
    this.commentCount = 0,
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
    title: json['title'] as String? ?? '',
    category: json['category'] as String?,
    tags: List<String>.from(json['tags'] as List? ?? const []),
    publishedAt: _date(json['published_at']),
    commentCount: json['comment_count'] as int? ?? 0,
  );
  final String id;
  final String status;
  final String topicId;
  final String identityType;
  final String originalVoice;
  final SummaryDraftInfo? latestSummary;
  final Impact impact;
  final String title;
  final String? category;
  final List<String> tags;
  final DateTime? publishedAt;
  final int commentCount;
  String get categoryKey => categoryFor(category, topicId);
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
    this.excerpt = '',
    this.category,
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
          title: (json['title'] as String?) ?? '',
          verificationStatus: null,
          lastVerifiedAt: null,
          recentSuccessCount: 0,
          sources: const [],
          reminder: json['reminder'] as String,
          excerpt: (json['excerpt'] as String?) ?? '',
          category: json['category'] as String?,
        );
  final String type;
  final String id;
  final String? title;
  final String? verificationStatus;
  final String? lastVerifiedAt;
  final int recentSuccessCount;
  final List<String> sources;
  final String? reminder;

  /// For student posts: the opening words and category, shown on the post card.
  final String excerpt;
  final String? category;
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
