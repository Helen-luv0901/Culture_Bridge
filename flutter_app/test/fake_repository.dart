import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/data/auth_service.dart';
import 'package:culture_bridge/data/culture_repository.dart';
import 'package:culture_bridge/domain/api_models.dart';

/// An in-memory backend: student posts from assets/data/content.json and a few official
/// questions, behaving like the real API for the flows the screens use.
class FakeCultureRepository implements CultureRepository {
  FakeCultureRepository(this.auth) {
    final raw =
        jsonDecode(File('assets/data/content.json').readAsStringSync()) as Json;
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
  final Map<String, ExperienceItem> _experiences = {};
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
      termsVersion: acceptedTerms,
    );
  }

  /// The terms version this account accepted (null: never) and the one the server wants.
  int? acceptedTerms = 1;
  int serverTermsVersion = 1;
  final List<int> termsAccepted = [];

  void _requireTerms() {
    if (acceptedTerms != serverTermsVersion) {
      throw const ApiException(403, 'terms_not_accepted');
    }
  }

  @override
  Future<Profile> acceptTerms(int version) async {
    _requireLogin();
    if (version != serverTermsVersion) {
      throw const ApiException(422, 'terms_version_outdated');
    }
    termsAccepted.add(version);
    acceptedTerms = version;
    return me();
  }

  @override
  String siteUrl(String path) => 'https://example.test$path';

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
    mine.clear();
  }

  /// Official questions, newest first (like the API).
  static final faqItems = [for (final d in faqDetails.values) d.summary];

  static const _categories = [
    FaqCategory('visa-arc', Text2('簽證與居留', 'Visas & residence'), 1),
    FaqCategory('work', Text2('工作', 'Work'), 1),
    FaqCategory('insurance', Text2('健保', 'Health insurance'), 1),
  ];

  static const _identities = [
    FaqIdentity('foreign', Text2('外國學生', 'International students')),
    FaqIdentity('overseas-chinese', Text2('僑生', 'Overseas Chinese students')),
    FaqIdentity('hong-kong-macao', Text2('港澳生', 'Hong Kong & Macao students')),
    FaqIdentity('mainland', Text2('陸生', 'Mainland Chinese students')),
  ];

  static const _publisher = Text2(
    '教育部 NISA 計畫辦公室',
    'Ministry of Education NISA Office',
  );

  static const faqDetails = {
    'nisa-1070': FaqDetail(
      summary: FaqSummary(
        id: 'nisa-1070',
        categoryId: 'visa-arc',
        identities: ['foreign'],
        question: Text2('居留證到期前多久可以申請延期？', 'How early can I renew my ARC?'),
        excerpt: Text2(
          '居留期限屆滿前 30 日內申請。',
          'Apply within 30 days before it expires.',
        ),
        postedOn: '2026-08-03',
      ),
      category: Text2('簽證與居留', 'Visas & residence'),
      answer: Text2(
        '居留期限屆滿前 30 日內，向移民署申請延期。\n請攜帶護照、居留證及在學證明。',
        'Apply to the immigration agency within 30 days before it expires.\nBring your passport, ARC and enrollment certificate.',
      ),
      source: Text2('115 年境外生輔導人員研習', '2026 adviser training course'),
      agency: Text2('內政部移民署', 'National Immigration Agency'),
      publisher: _publisher,
      url: 'https://www.nisa.moe.gov.tw/faq.new/view/sn/1070/menu_sn/13',
    ),
    'nisa-1001': FaqDetail(
      summary: FaqSummary(
        id: 'nisa-1001',
        categoryId: 'work',
        identities: ['foreign', 'overseas-chinese'],
        question: Text2('在學期間可以打工嗎？', 'Can I work part-time while studying?'),
        excerpt: Text2('須先申請工作許可。', 'You need a work permit first.'),
        postedOn: '2026-07-01',
        review: FaqReview(
          kind: 'superseded',
          note: Text2(
            '規定已改，請看較新的回覆。',
            'The rule changed; see the newer answer.',
          ),
          supersededBy: 'nisa-1070',
        ),
      ),
      category: Text2('工作', 'Work'),
      answer: Text2(
        '須先向勞動部申請工作許可。',
        'Apply to the Ministry of Labor for a work permit first.',
      ),
      source: Text2('', ''),
      agency: Text2('勞動部', 'Ministry of Labor'),
      publisher: _publisher,
      url: 'https://www.nisa.moe.gov.tw/faq.new/view/sn/1001/menu_sn/13',
    ),
    'nisa-900': FaqDetail(
      summary: FaqSummary(
        id: 'nisa-900',
        categoryId: 'insurance',
        identities: ['mainland'],
        question: Text2('陸生可以加入全民健保嗎？', '陸生可以加入全民健保嗎？'),
        excerpt: Text2('居留滿 6 個月可加保。', '居留滿 6 個月可加保。'),
        postedOn: '2026-05-02',
        hasEnglish: false,
      ),
      category: Text2('健保', 'Health insurance'),
      answer: Text2('在台居留滿 6 個月後，應加入全民健保。', '在台居留滿 6 個月後，應加入全民健保。'),
      source: Text2('', ''),
      agency: Text2('衛生福利部中央健康保險署', 'National Health Insurance Administration'),
      publisher: _publisher,
      url: 'https://www.nisa.moe.gov.tw/faq.new/view/sn/900/menu_sn/13',
    ),
    'nisa-800': FaqDetail(
      summary: FaqSummary(
        id: 'nisa-800',
        categoryId: 'visa-arc',
        identities: ['foreign'],
        question: Text2(
          '學校如何查詢學生的居留資料？',
          'How can schools look up students\' residence records?',
        ),
        excerpt: Text2('透過移民署系統查詢。', 'Use the immigration agency system.'),
        postedOn: '2026-04-01',
        audience: 'school',
      ),
      category: Text2('簽證與居留', 'Visas & residence'),
      answer: Text2(
        '承辦人可透過移民署系統查詢。',
        'Staff can use the immigration agency system.',
      ),
      source: Text2('', ''),
      agency: Text2('內政部移民署', 'National Immigration Agency'),
      publisher: _publisher,
      url: 'https://www.nisa.moe.gov.tw/faq.new/view/sn/800/menu_sn/13',
    ),
  };

  /// Official questions the server would suggest under each student post.
  final Map<String, List<String>> postFaqs = {
    'professor-see': ['nisa-1070'],
  };

  @override
  Future<List<FaqSummary>> relatedFaqs(String postId) async => [
    for (final id in postFaqs[postId] ?? const <String>[])
      ?faqDetails[id]?.summary,
  ];

  /// Student posts the server would suggest under each question.
  final Map<String, List<String>> faqPosts = {
    'nisa-1070': ['professor-see'],
  };

  @override
  Future<FaqCatalog> faqs() async =>
      FaqCatalog(_categories, _identities, faqItems);

  @override
  Future<FaqDetail> faq(String id) async =>
      faqDetails[id] ?? (throw const ApiException(404, 'faq_not_found'));

  @override
  Future<List<ExperienceItem>> faqRelatedPosts(
    String id, {
    String? locale,
    int limit = 3,
  }) async => [
    for (final postId in faqPosts[id] ?? const <String>[])
      ?_experiences[postId],
  ].take(limit).toList();

  @override
  Future<ExperiencePage> explore({
    String? category,
    String? query,
    String? locale,
    String sort = 'new',
    int offset = 0,
  }) async {
    final items = [
      for (final e in _experiences.values)
        if ((category == null || e.categoryKey == category) &&
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
        for (final f in faqItems)
          if (f.matches(query)) f,
      ], (await explore(query: query)).items);

  @override
  Future<List<String>> popularTags() async {
    final error = popularTagsError;
    if (error != null) throw error;
    return const ['#居留證', '#夜市'];
  }

  /// When set, popularTags throws it (e.g. a response the app can't read).
  Object? popularTagsError;

  @override
  Future<ExperienceDetail> experience(String id, {String? locale}) async =>
      ExperienceDetail(
        _experiences[id] ??
            (throw const ApiException(404, 'experience_not_found')),
        const [],
        null,
      );

  /// When set, the next reaction or save fails with it (then clears).
  ApiException? reactError;
  ApiException? saveError;

  /// How many times tag suggestions were asked for (each sends the draft to Gemini).
  int suggestCalls = 0;

  @override
  Future<ExperienceItem> react(String id, String kind, bool on) async {
    _requireLogin();
    final error = reactError;
    if (error != null) {
      reactError = null;
      // A conflict means the reaction was already there: the server has it as asked.
      if (error.status == 409) await react(id, kind, on);
      throw error;
    }
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
  );

  /// Make an experience show [name] as its author (what the API does for signed posts).
  void signAs(String id, String name) =>
      _experiences[id] = _copy(_experiences[id]!, authorName: name);

  /// Newest first, like the API.
  final List<String> saved = [];

  @override
  Future<void> setSaved(String id, bool on) async {
    _requireLogin();
    final error = saveError;
    if (error != null) {
      saveError = null;
      // A plain conflict means it already was: apply it. A full list does not.
      if (error.code == 'conflict') await setSaved(id, on);
      throw error;
    }
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

  /// When set, translations fail with it.
  ApiException? translationError;

  @override
  Future<ExperienceDetail> requestTranslation(String id, String locale) {
    final error = translationError;
    if (error != null) throw error;
    return experience(id);
  }

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
    suggestCalls++;
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
  }) async {
    _requireLogin();
    _requireTerms();
    lastPublish = {
      'title': title,
      'voice': voice,
      'category': category,
      'tags': tags,
      'author_display': authorDisplay,
      'different_from_id': differentFromId,
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
    _requireTerms();
    final comment = CommentItem(
      id: 'c-${_ids++}',
      body: body,
      createdAt: DateTime.now(),
      likeCount: 0,
      replyToId: replyToId,
      authorName: authorDisplay == 'nickname' ? nickname : null,
      mine: true,
      removableByMe: true,
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
        removableByMe: c.removableByMe,
      );
    }
    throw const ApiException(404, 'comment_not_found');
  }

  /// A comment by someone else under [experienceId]; [removable] when the reader wrote the post.
  CommentItem addOthersComment(
    String experienceId,
    String body, {
    bool removable = false,
  }) {
    final comment = CommentItem(
      id: 'c-${_ids++}',
      body: body,
      createdAt: DateTime(2026, 10, 20),
      likeCount: 0,
      removableByMe: removable,
    );
    postComments.putIfAbsent(experienceId, () => []).add(comment);
    return comment;
  }

  final List<String> deletedComments = [];

  @override
  Future<void> deleteComment(String commentId) async {
    deletedComments.add(commentId);
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

  /// When set, myExperiences answers only once this completes (a slow network).
  Completer<void>? holdMine;

  @override
  Future<List<MyExperience>> myExperiences() async {
    _requireLogin();
    final items = mine.values.toList();
    await holdMine?.future;
    return items;
  }

  @override
  Future<void> report(String experienceId, String reason, String? note) async =>
      reports.add('$experienceId:$reason');

  @override
  Future<void> blockAuthor(String experienceId) async {
    blocked.add(experienceId);
    _experiences.remove(experienceId);
  }

  final List<String> blockedCommenters = [];

  @override
  Future<void> blockCommenter(String commentId) async {
    _requireLogin();
    blockedCommenters.add(commentId);
    for (final list in postComments.values) {
      list.removeWhere((c) => c.id == commentId);
    }
  }

  @override
  Future<List<BlockInfo>> blocks() async => [
    for (final id in blocked) BlockInfo(id, DateTime(2026, 10, 13)),
  ];

  @override
  Future<void> unblock(String blockId) async => blocked.remove(blockId);

  final List<String> assistantMessages = [];
  AssistantReply Function(String message)? assistantReply;

  /// Told what screen each message was asked from.
  void Function(Map<String, String>? screen)? onAsk;

  @override
  Future<AssistantReply> askAssistant({
    required String message,
    required String locale,
    String? conversationId,
    Map<String, String>? screen,
  }) async {
    assistantMessages.add(message);
    onAsk?.call(screen);
    return assistantReply?.call(message) ??
        AssistantReply(
          conversationId: conversationId ?? 'conv-1',
          text: '依據官方問答「在學期間可以打工嗎？」（勞動部回覆）。',
          cards: const [],
          screenActions: const [],
          fallback: false,
        );
  }

  @override
  Future<void> clearConversation(String conversationId) async {}

  final List<Map<String, Object?>> assistantReports = [];

  @override
  Future<void> reportAssistantAnswer({
    String? conversationId,
    required String question,
    required String answer,
    required String reason,
    String? details,
  }) async {
    _requireLogin();
    assistantReports.add({
      'conversation_id': conversationId,
      'question': question,
      'answer': answer,
      'reason': reason,
      'details': details,
    });
  }
}
