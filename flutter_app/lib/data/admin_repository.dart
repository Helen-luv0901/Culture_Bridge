import '../domain/admin_models.dart';
import '../domain/api_models.dart';
import 'api_client.dart';

/// Reviewer/admin operations (/api/admin). The server checks the role on every call.
class AdminRepository {
  AdminRepository(this.api);
  final ApiClient api;

  Future<List<AdminActionItem>> actions() async => [
    for (final a in await api.get('/admin/actions') as List)
      AdminActionItem.fromJson(a as Json),
  ];
  Future<AdminVersion> createAction(String slug, Json content) async =>
      AdminVersion.fromJson(
        await api.post('/admin/actions', {'slug': slug, ...content}),
      );
  Future<List<AdminVersion>> versions(String actionId) async => [
    for (final v in await api.get('/admin/actions/$actionId/versions') as List)
      AdminVersion.fromJson(v as Json),
  ];
  Future<AdminVersion> newVersion(String actionId) async =>
      AdminVersion.fromJson(
        await api.post('/admin/actions/$actionId/versions'),
      );
  Future<void> archive(String actionId, bool archived) =>
      api.post('/admin/actions/$actionId/archive?archived=$archived');
  Future<AdminVersion> saveDraft(String versionId, Json content) async =>
      AdminVersion.fromJson(
        await api.put('/admin/versions/$versionId', content),
      );
  Future<AdminVersion> publish(String versionId) async => AdminVersion.fromJson(
    await api.post('/admin/versions/$versionId/publish'),
  );
  Future<AdminVersion> attachSource(
    String versionId,
    String sourceId,
    String note,
  ) async => AdminVersion.fromJson(
    await api.put('/admin/versions/$versionId/sources/$sourceId', {
      'evidence_note': note,
    }),
  );
  Future<AdminVersion> verify(
    String versionId,
    String sourceId,
    String decision,
    String note,
  ) async => AdminVersion.fromJson(
    await api.post('/admin/versions/$versionId/verifications', {
      'source_id': sourceId,
      'decision': decision,
      'note': note,
    }),
  );
  Future<AdminVersion> setStatus(String versionId, String status) async =>
      AdminVersion.fromJson(
        await api.put('/admin/versions/$versionId/status', {'status': status}),
      );
  Future<List<AdminSource>> sources() async => [
    for (final s in await api.get('/admin/sources') as List)
      AdminSource.fromJson(s as Json),
  ];
  Future<AdminSource> createSource(Json source) async =>
      AdminSource.fromJson(await api.post('/admin/sources', source));

  Future<List<FeedbackItem>> feedback(String state) async => [
    for (final f in await api.get('/admin/feedback', {'state': state}) as List)
      FeedbackItem.fromJson(f as Json),
  ];
  Future<FeedbackSummary> summarizeFeedback(
    String actionId, {
    required bool english,
  }) async => FeedbackSummary.fromJson(
    await api.post(
      '/admin/actions/$actionId/feedback-summary',
      {'locale': english ? 'en' : 'zh-Hant'},
      // The server tries Gemini up to twice, 30 s each.
      const Duration(seconds: 75),
    ),
  );
  Future<void> reviewFeedback(String id, String state) =>
      api.post('/admin/feedback/$id', {'review_state': state});

  Future<List<ReportedItem>> reports(String status) async => [
    for (final r in await api.get('/admin/reports', {'status': status}) as List)
      ReportedItem.fromJson(r as Json),
  ];
  Future<void> resolveReport(String reportId, String action) =>
      api.post('/admin/reports/$reportId/resolve', {'action': action});

  Future<UsageStats> stats(int days) async =>
      UsageStats(await api.get('/admin/stats', {'days': '$days'}) as Json);
  Future<List<StaffMember>> staff() async => [
    for (final u in await api.get('/admin/users') as List)
      StaffMember.fromJson(u as Json),
  ];
  Future<void> setRole(String userId, String role) => api.put(
    '/admin/users/${Uri.encodeComponent(userId)}/role',
    {'role': role},
  );

  Future<List<KbDocument>> documents() async => [
    for (final d in await api.get('/admin/kb/documents') as List)
      KbDocument.fromJson(d as Json),
  ];
  Future<void> addDocument(Json document) =>
      api.post('/admin/kb/documents', document);
  Future<void> setDocumentActive(String id, bool active) =>
      api.post('/admin/kb/documents/$id/active?active=$active');
}
