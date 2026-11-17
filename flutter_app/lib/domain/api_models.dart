// Immutable mirrors of the backend's JSON (backend/app/services/*.py). Field names follow the API.

import 'package:flutter/widgets.dart' show StringCharacters;

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

List<T> _list<T>(Object? value, T Function(Json) parse) => [
  for (final item in (value as List? ?? const [])) parse(item as Json),
];

/// A text in both app languages.
class Text2 {
  const Text2(this.zh, this.en);
  factory Text2.fromJson(Json? json) =>
      Text2(json?['zh'] as String? ?? '', json?['en'] as String? ?? '');
  final String zh;
  final String en;
  String of(bool english) => (english && en.isNotEmpty) || zh.isEmpty ? en : zh;
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.preferredLocale,
    this.nickname,
    this.realName,
    this.avatarUrl,
    this.termsVersion,
  });
  factory Profile.fromJson(Json json) => Profile(
    id: json['id'] as String,
    role: json['role'] as String,
    preferredLocale: json['preferred_locale'] as String,
    nickname: json['nickname'] as String?,
    realName: json['real_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    termsVersion: json['terms_version'] as int?,
  );
  final String id;
  final String role;
  final String preferredLocale;

  /// Optional; shown only on experiences the person chose to sign with them.
  final String? nickname;
  final String? realName;

  /// Server path of the profile photo, if any.
  final String? avatarUrl;

  /// The terms of use version this account accepted; null if never.
  final int? termsVersion;
  bool get isStaff => role == 'reviewer' || role == 'admin';
  bool get isAdmin => role == 'admin';
}

/// The terms version this app was written for, used when the server's config is missing.
const currentTermsVersion = 1;

/// Public settings from `GET /api/config` the screens use: which terms version to accept,
/// where the legal pages are, and how to reach support.
class ClientConfig {
  const ClientConfig({
    this.termsVersion = currentTermsVersion,
    this.privacyPath = '/privacy',
    this.termsPath = '/terms',
    this.accountDeletionPath = '/account-deletion',
    this.supportEmail,
  });

  /// Defaults stand in for anything missing (the server could not be reached).
  factory ClientConfig.fromJson(Json? json) {
    final legal = json?['legal'] as Json? ?? const {};
    final email = (json?['support_email'] as String? ?? '').trim();
    return ClientConfig(
      termsVersion: json?['terms_version'] as int? ?? currentTermsVersion,
      privacyPath: legal['privacy'] as String? ?? '/privacy',
      termsPath: legal['terms'] as String? ?? '/terms',
      accountDeletionPath:
          legal['account_deletion'] as String? ?? '/account-deletion',
      supportEmail: email.isEmpty ? null : email,
    );
  }

  final int termsVersion;
  final String privacyPath;
  final String termsPath;
  final String accountDeletionPath;
  final String? supportEmail;
}

/// The first [count] characters of [text] (whole emoji), with … when it was longer.
String clipText(String text, int count) {
  final chars = text.characters;
  return chars.length > count ? '${chars.take(count)}…' : text;
}

// ---------- official Q&A ----------

/// One of the official site's question categories, with how many questions it holds.
class FaqCategory {
  const FaqCategory(this.id, this.name, this.count);
  factory FaqCategory.fromJson(Json json) => FaqCategory(
    json['id'] as String,
    Text2.fromJson(json['name'] as Json),
    json['count'] as int? ?? 0,
  );
  final String id;
  final Text2 name;
  final int count;
}

/// Who a question applies to (foreign, overseas Chinese, Hong Kong & Macao, mainland students).
class FaqIdentity {
  const FaqIdentity(this.id, this.name);
  factory FaqIdentity.fromJson(Json json) =>
      FaqIdentity(json['id'] as String, Text2.fromJson(json['name'] as Json));
  final String id;
  final Text2 name;
}

/// A note that an official answer may no longer hold.
class FaqReview {
  const FaqReview({required this.kind, required this.note, this.supersededBy});
  factory FaqReview.fromJson(Json json) => FaqReview(
    kind: json['kind'] as String? ?? '',
    note: Text2.fromJson(json['note'] as Json?),
    supersededBy: json['superseded_by'] as String?,
  );

  /// 'superseded', 'conflict' or 'time_limited'.
  final String kind;

  /// One sentence for students.
  final Text2 note;

  /// The newer question that replaces this one, if any.
  final String? supersededBy;
}

/// An official question answered by a government agency (MOE NISA), as listed.
class FaqSummary {
  const FaqSummary({
    required this.id,
    required this.categoryId,
    required this.question,
    required this.excerpt,
    this.identities = const [],
    this.postedOn,
    this.hasEnglish = true,
    this.audience = 'student',
    this.review,
  });
  factory FaqSummary.fromJson(Json json) => FaqSummary(
    id: json['id'] as String,
    categoryId: json['category_id'] as String,
    identities: List<String>.from(json['identities'] as List? ?? const []),
    question: Text2.fromJson(json['question'] as Json),
    excerpt: Text2.fromJson(json['excerpt'] as Json),
    postedOn: json['posted_on'] as String?,
    hasEnglish: json['has_english'] as bool? ?? true,
    audience: json['audience'] as String? ?? 'student',
    review: json['review'] == null
        ? null
        : FaqReview.fromJson(json['review'] as Json),
  );
  final String id;
  final String categoryId;
  final List<String> identities;
  final Text2 question;
  final Text2 excerpt;

  /// The day the site posted it (YYYY-MM-DD), if known.
  final String? postedOn;

  /// False when the official site has no English version (English shows the Chinese).
  final bool hasEnglish;

  /// 'student', or 'school' for a school-administration question asked by staff.
  final String audience;
  bool get forSchool => audience == 'school';

  /// Set when the answer may be outdated, ended or contradicted.
  final FaqReview? review;

  /// Whether every word of [query] appears in the question or excerpt, in either language.
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return true;
    final text = '${question.zh} ${question.en} ${excerpt.zh} ${excerpt.en}'
        .toLowerCase();
    return words.every(text.contains);
  }
}

/// A whole official answer, with who answered it and where it comes from.
class FaqDetail {
  const FaqDetail({
    required this.summary,
    required this.category,
    required this.answer,
    required this.source,
    required this.agency,
    required this.publisher,
    required this.url,
  });
  factory FaqDetail.fromJson(Json json) => FaqDetail(
    summary: FaqSummary.fromJson(json),
    category: Text2.fromJson(json['category'] as Json),
    answer: Text2.fromJson(json['answer'] as Json),
    source: Text2.fromJson(json['source'] as Json),
    agency: Text2.fromJson(json['agency'] as Json),
    publisher: Text2.fromJson(json['publisher'] as Json),
    url: json['url'] as String? ?? '',
  );
  final FaqSummary summary;
  final Text2 category;

  /// Plain text over several lines; the line breaks matter.
  final Text2 answer;

  /// Where the question was asked (such as a training course); may be empty.
  final Text2 source;

  /// The government agency that answered.
  final Text2 agency;
  final Text2 publisher;

  /// The question on the official site.
  final String url;
}

/// Every official question with its categories and identities (`GET /faqs`), newest first.
class FaqCatalog {
  const FaqCatalog(this.categories, this.identities, this.items);
  factory FaqCatalog.fromJson(Json json) => FaqCatalog(
    _list(json['categories'], FaqCategory.fromJson),
    _list(json['identities'], FaqIdentity.fromJson),
    _list(json['items'], FaqSummary.fromJson),
  );
  final List<FaqCategory> categories;
  final List<FaqIdentity> identities;
  final List<FaqSummary> items;

  FaqCategory? category(String id) =>
      categories.where((c) => c.id == id).firstOrNull;
  FaqIdentity? identity(String id) =>
      identities.where((i) => i.id == id).firstOrNull;
  FaqSummary? item(String id) => items.where((i) => i.id == id).firstOrNull;
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
    return clipText(text, 24);
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

/// Keyword search over the official Q&A and student posts.
class SearchResults {
  const SearchResults(this.faqs, this.experiences);
  factory SearchResults.fromJson(Json json) => SearchResults(
    _list(json['faqs'], FaqSummary.fromJson),
    _list(json['experiences'], ExperienceItem.fromJson),
  );
  final List<FaqSummary> faqs;
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
    this.removableByMe = false,
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
    removableByMe: json['removable_by_me'] as bool? ?? false,
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

  /// The reader may remove it: they wrote it, wrote the post, or are staff.
  final bool removableByMe;
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
  const BlockInfo(this.id, this.createdAt, {this.persona});
  factory BlockInfo.fromJson(Json json) => BlockInfo(
    json['id'] as String,
    _date(json['created_at'])!,
    persona: json['persona'] as String?,
  );
  final String id;
  final DateTime createdAt;

  /// 'anonymous' or 'named': a block hides only the identity it was made from, so it never
  /// shows which anonymous posts belong to a named author. Null on older blocks (both).
  final String? persona;
}

// ---------- assistant ----------

/// An official question or a student post the assistant's answer relies on.
class AssistantCard {
  const AssistantCard({
    required this.type,
    required this.id,
    required this.title,
    this.reminder,
    this.excerpt = '',
    this.category,
    this.agency = '',
    this.postedOn,
    this.url = '',
  });

  /// Null for kinds this app doesn't show (older procedure cards, anything new).
  static AssistantCard? fromJson(Json json) => switch (json['type']) {
    'faq' => AssistantCard(
      type: 'faq',
      id: json['faq_id'] as String,
      title: json['question'] as String? ?? '',
      excerpt: json['excerpt'] as String? ?? '',
      category: json['category'] as String?,
      agency: json['answering_agency'] as String? ?? '',
      postedOn: json['posted_on'] as String?,
      url: json['url'] as String? ?? '',
    ),
    'experience' => AssistantCard(
      type: 'experience',
      id: json['experience_id'] as String,
      title: json['title'] as String? ?? '',
      reminder: json['reminder'] as String?,
      excerpt: json['excerpt'] as String? ?? '',
      category: json['category'] as String?,
    ),
    _ => null,
  };

  /// 'faq' or 'experience'.
  final String type;
  final String id;

  /// The question, or the post's title.
  final String title;
  final String? reminder;

  /// The opening words of the answer or post.
  final String excerpt;

  /// A question's category name, or a post's category key.
  final String? category;

  /// For questions: the agency that answered, when it was posted and the official page.
  final String agency;
  final String? postedOn;
  final String url;
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

class AssistantReply {
  const AssistantReply({
    required this.conversationId,
    required this.text,
    required this.cards,
    required this.screenActions,
    required this.fallback,
  });
  factory AssistantReply.fromJson(Json json) => AssistantReply(
    conversationId: json['conversation_id'] as String,
    text: json['text'] as String,
    cards: [
      for (final card in json['cards'] as List? ?? const [])
        ?AssistantCard.fromJson(card as Json),
    ],
    screenActions: _list(json['screen_actions'], ScreenAction.fromJson),
    fallback: json['fallback'] as bool,
  );
  final String conversationId;
  final String text;
  final List<AssistantCard> cards;
  final List<ScreenAction> screenActions;
  final bool fallback;
}
