import '../domain/api_models.dart';
import 'api_client.dart';

/// Everything the app reads and writes. [ApiCultureRepository] talks to the backend; tests use
/// an in-memory fake.
abstract class CultureRepository {
  Future<Profile> me();
  Future<Profile> updateLocale(String locale);
  Future<Profile> updateNames({String? nickname, String? realName});
  Future<void> deleteAccount();

  Future<List<ActionSummary>> actions();
  Future<ActionDetail> action(String id);
  Future<Execution> startExecution(String actionId, String identityType);
  Future<List<Execution>> myExecutions({bool includeFinished = false});
  Future<Execution> setStep(String executionId, String stepId, String state);
  Future<Execution> finishExecution(String executionId, String outcome);
  Future<void> sendFeedback(
    String executionId, {
    required String kind,
    String? stepId,
    String? category,
    String? text,
  });

  Future<ExperiencePage> explore({
    String? category,
    String? query,
    String? locale,
    String? actionId,
    String sort = 'new',
    int offset = 0,
  });
  Future<SearchResults> search(String query, {String? locale});
  Future<List<String>> popularTags();
  Future<ExperienceDetail> experience(String id, {String? locale});
  Future<ExperienceItem> react(String id, String kind, bool on);
  Future<void> setSaved(String id, bool on);
  Future<List<ExperienceItem>> savedExperiences({String? locale});
  Future<ExperienceDetail> requestTranslation(String id, String locale);

  /// Tags the AI suggests for a post being written; it never rewrites the post.
  Future<List<String>> suggestTags({
    required String title,
    required String text,
    String? category,
  });

  /// Publishes the post exactly as written.
  Future<ExperienceItem> publishPost({
    required String title,
    required String voice,
    required String category,
    required List<String> tags,
    required String sourceLocale,
    String authorDisplay = 'anonymous',
    String? differentFromId,
    String? actionId,
  });
  Future<void> deleteExperience(String id);

  Future<List<CommentItem>> comments(String experienceId);
  Future<CommentItem> addComment(
    String experienceId, {
    required String body,
    String? replyToId,
    String authorDisplay = 'anonymous',
  });
  Future<CommentItem> likeComment(String commentId, bool on);
  Future<void> deleteComment(String commentId);
  Future<void> reportComment(String commentId, String reason, String? note);
  Future<List<MyExperience>> myExperiences();

  Future<void> report(String experienceId, String reason, String? note);
  Future<void> blockAuthor(String experienceId);
  Future<List<BlockInfo>> blocks();
  Future<void> unblock(String blockId);

  Future<AssistantReply> askAssistant({
    required String message,
    required String locale,
    String? conversationId,
    Map<String, String>? screen,
  });
  Future<void> clearConversation(String conversationId);
  Future<PendingOperation> confirmOperation(String id);
  Future<PendingOperation> cancelOperation(String id);
}

class ApiCultureRepository implements CultureRepository {
  ApiCultureRepository(this.api);
  final ApiClient api;

  @override
  Future<Profile> me() async => Profile.fromJson(await api.get('/me'));
  @override
  Future<Profile> updateLocale(String locale) async =>
      Profile.fromJson(await api.patch('/me', {'preferred_locale': locale}));
  @override
  Future<Profile> updateNames({String? nickname, String? realName}) async =>
      Profile.fromJson(
        await api.patch('/me', {'nickname': nickname, 'real_name': realName}),
      );
  @override
  Future<void> deleteAccount() => api.delete('/me');

  @override
  Future<List<ActionSummary>> actions() async => [
    for (final item in await api.get('/actions') as List)
      ActionSummary.fromJson(item as Json),
  ];
  @override
  Future<ActionDetail> action(String id) async =>
      ActionDetail.fromJson(await api.get('/actions/$id'));
  @override
  Future<Execution> startExecution(
    String actionId,
    String identityType,
  ) async => Execution.fromJson(
    await api.post('/actions/$actionId/executions', {
      'identity_type': identityType,
    }),
  );
  @override
  Future<List<Execution>> myExecutions({bool includeFinished = false}) async =>
      [
        for (final item in await api.get('/me/executions', {
          if (includeFinished) 'include_finished': 'true',
        }) as List)
          Execution.fromJson(item as Json),
      ];
  @override
  Future<Execution> setStep(
    String executionId,
    String stepId,
    String state,
  ) async => Execution.fromJson(
    await api.put('/executions/$executionId/steps/$stepId', {'state': state}),
  );
  @override
  Future<Execution> finishExecution(String executionId, String outcome) async =>
      Execution.fromJson(
        await api.post('/executions/$executionId/finish', {'outcome': outcome}),
      );
  @override
  Future<void> sendFeedback(
    String executionId, {
    required String kind,
    String? stepId,
    String? category,
    String? text,
  }) => api.post('/executions/$executionId/feedback', {
    'kind': kind,
    'step_id': ?stepId,
    'category': ?category,
    if (text != null && text.trim().isNotEmpty) 'original_voice': text.trim(),
  });

  @override
  Future<ExperiencePage> explore({
    String? category,
    String? query,
    String? locale,
    String? actionId,
    String sort = 'new',
    int offset = 0,
  }) async => ExperiencePage.fromJson(
    await api.get('/experiences', {
      'category': ?category,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'locale': ?locale,
      'action_id': ?actionId,
      if (sort != 'new') 'sort': sort,
      'offset': '$offset',
    }),
  );
  @override
  Future<SearchResults> search(String query, {String? locale}) async =>
      SearchResults.fromJson(
        await api.get('/search', {'q': query.trim(), 'locale': ?locale}),
      );
  @override
  Future<List<String>> popularTags() async => [
    for (final tag in await api.get('/tags/popular') as List) tag as String,
  ];
  @override
  Future<ExperienceDetail> experience(String id, {String? locale}) async =>
      ExperienceDetail.fromJson(
        await api.get('/experiences/$id', {'locale': ?locale}),
      );
  @override
  Future<ExperienceItem> react(String id, String kind, bool on) async =>
      ExperienceItem.fromJson(
        on
            ? await api.put('/experiences/$id/reactions/$kind')
            : await api.delete('/experiences/$id/reactions/$kind'),
      );
  @override
  Future<void> setSaved(String id, bool on) => on
      ? api.put('/experiences/$id/saved')
      : api.delete('/experiences/$id/saved');
  @override
  Future<List<ExperienceItem>> savedExperiences({String? locale}) async => [
    for (final item in await api.get('/me/saved', {'locale': ?locale}) as List)
      ExperienceItem.fromJson(item as Json),
  ];
  @override
  Future<ExperienceDetail> requestTranslation(String id, String locale) async =>
      ExperienceDetail.fromJson(
        await api.post('/experiences/$id/translations', {'locale': locale}),
      );
  @override
  Future<List<String>> suggestTags({
    required String title,
    required String text,
    String? category,
  }) async {
    final json = await api.post('/experiences/tag-suggestions', {
      'title': title,
      'text': text,
      'category': ?category,
    });
    return [for (final tag in (json as Json)['tags'] as List) tag as String];
  }

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
  }) async => ExperienceItem.fromJson(
    await api.post('/posts', {
      'title': title,
      'original_voice': voice,
      'category': category,
      'tags': tags,
      'source_locale': sourceLocale,
      'author_display': authorDisplay,
      'different_from_id': ?differentFromId,
      'action_id': ?actionId,
    }),
  );
  @override
  Future<void> deleteExperience(String id) => api.delete('/experiences/$id');
  @override
  Future<List<CommentItem>> comments(String experienceId) async => [
    for (final item
        in await api.get('/experiences/$experienceId/comments') as List)
      CommentItem.fromJson(item as Json),
  ];
  @override
  Future<CommentItem> addComment(
    String experienceId, {
    required String body,
    String? replyToId,
    String authorDisplay = 'anonymous',
  }) async => CommentItem.fromJson(
    await api.post('/experiences/$experienceId/comments', {
      'body': body,
      'reply_to_id': ?replyToId,
      'author_display': authorDisplay,
    }),
  );
  @override
  Future<CommentItem> likeComment(String commentId, bool on) async =>
      CommentItem.fromJson(
        on
            ? await api.put('/comments/$commentId/like')
            : await api.delete('/comments/$commentId/like'),
      );
  @override
  Future<void> deleteComment(String commentId) =>
      api.delete('/comments/$commentId');
  @override
  Future<void> reportComment(String commentId, String reason, String? note) =>
      api.post('/reports', {
        'comment_id': commentId,
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<List<MyExperience>> myExperiences() async => [
    for (final item in await api.get('/me/experiences') as List)
      MyExperience.fromJson(item as Json),
  ];

  @override
  Future<void> report(String experienceId, String reason, String? note) =>
      api.post('/reports', {
        'experience_id': experienceId,
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
  @override
  Future<void> blockAuthor(String experienceId) =>
      api.post('/blocks', {'experience_id': experienceId});
  @override
  Future<List<BlockInfo>> blocks() async => [
    for (final item in await api.get('/me/blocks') as List)
      BlockInfo.fromJson(item as Json),
  ];
  @override
  Future<void> unblock(String blockId) => api.delete('/me/blocks/$blockId');

  @override
  Future<AssistantReply> askAssistant({
    required String message,
    required String locale,
    String? conversationId,
    Map<String, String>? screen,
  }) async => AssistantReply.fromJson(
    await api.post('/assistant/message', {
      'message': message,
      'locale': locale,
      'conversation_id': ?conversationId,
      'screen': ?screen,
    }),
  );
  @override
  Future<void> clearConversation(String conversationId) =>
      api.delete('/assistant/conversations/$conversationId');
  @override
  Future<PendingOperation> confirmOperation(String id) async =>
      PendingOperation.fromJson(
        await api.post('/assistant/operations/$id/confirm'),
      );
  @override
  Future<PendingOperation> cancelOperation(String id) async =>
      PendingOperation.fromJson(
        await api.post('/assistant/operations/$id/cancel'),
      );
}
