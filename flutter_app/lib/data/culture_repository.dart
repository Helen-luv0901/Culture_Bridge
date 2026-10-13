import '../domain/api_models.dart';
import 'api_client.dart';

/// Everything the app reads and writes. [ApiCultureRepository] talks to the backend; tests use
/// an in-memory fake.
abstract class CultureRepository {
  Future<Profile> me();
  Future<Profile> updateLocale(String locale);
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
    String? topic,
    String? query,
    String? locale,
    int offset = 0,
  });
  Future<ExperienceDetail> experience(String id, {String? locale});
  Future<ExperienceItem> react(String id, String kind, bool on);
  Future<ExperienceDetail> requestTranslation(String id, String locale);
  Future<MyExperience> createDraft({
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
    String? differentFromId,
  });
  Future<MyExperience> updateDraft(
    String id, {
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
  });
  Future<SummaryDraftInfo> summarize(String experienceId);
  Future<MyExperience> publish(
    String experienceId,
    String summaryId, {
    String? situation,
    String? feelingOrAttempt,
    String? reminder,
  });
  Future<void> deleteExperience(String id);
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
    String? topic,
    String? query,
    String? locale,
    int offset = 0,
  }) async => ExperiencePage.fromJson(
    await api.get('/experiences', {
      'topic': ?topic,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'locale': ?locale,
      'offset': '$offset',
    }),
  );
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
  Future<ExperienceDetail> requestTranslation(String id, String locale) async =>
      ExperienceDetail.fromJson(
        await api.post('/experiences/$id/translations', {'locale': locale}),
      );
  @override
  Future<MyExperience> createDraft({
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
    String? differentFromId,
  }) async => MyExperience.fromJson(
    await api.post('/experiences', {
      'topic_id': topic,
      'identity_type': identityType,
      'original_voice': voice,
      'source_locale': sourceLocale,
      'different_from_id': ?differentFromId,
    }),
  );
  @override
  Future<MyExperience> updateDraft(
    String id, {
    required String topic,
    required String identityType,
    required String voice,
    required String sourceLocale,
  }) async => MyExperience.fromJson(
    await api.patch('/experiences/$id', {
      'topic_id': topic,
      'identity_type': identityType,
      'original_voice': voice,
      'source_locale': sourceLocale,
    }),
  );
  @override
  Future<SummaryDraftInfo> summarize(String experienceId) async =>
      SummaryDraftInfo.fromJson(
        await api.post('/experiences/$experienceId/summaries'),
      );
  @override
  Future<MyExperience> publish(
    String experienceId,
    String summaryId, {
    String? situation,
    String? feelingOrAttempt,
    String? reminder,
  }) async => MyExperience.fromJson(
    await api.post('/experiences/$experienceId/publish', {
      'summary_id': summaryId,
      'situation': ?situation,
      'feeling_or_attempt': ?feelingOrAttempt,
      'reminder': ?reminder,
    }),
  );
  @override
  Future<void> deleteExperience(String id) => api.delete('/experiences/$id');
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
