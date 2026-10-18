// Reviewer/admin data (backend/app/services/admin_actions.py, moderation.py).

import 'api_models.dart';

class AdminActionItem {
  const AdminActionItem({
    required this.id,
    required this.title,
    required this.archived,
    required this.latestVersion,
    required this.latestPublished,
    required this.hasDraft,
    required this.status,
  });
  factory AdminActionItem.fromJson(Json json) => AdminActionItem(
    id: json['id'] as String,
    title: Text2.fromJson(json['title'] as Json),
    archived: json['archived_at'] != null,
    latestVersion: json['latest_version_number'] as int,
    latestPublished: json['latest_published_version_number'] as int?,
    hasDraft: json['has_draft'] as bool,
    status: json['verification_status'] as String,
  );
  final String id;
  final Text2 title;
  final bool archived;
  final int latestVersion;
  final int? latestPublished;
  final bool hasDraft;
  final String status;
}

class AdminStep {
  const AdminStep(this.titleZh, this.titleEn, this.notes, [this.notesEn]);
  factory AdminStep.fromJson(Json json) => AdminStep(
    json['title_zh'] as String,
    json['title_en'] as String,
    json['notes'] as String?,
    json['notes_en'] as String?,
  );
  final String titleZh;
  final String titleEn;
  final String? notes;
  final String? notesEn;
  Json toJson() => {
    'title_zh': titleZh,
    'title_en': titleEn,
    'notes': notes,
    'notes_en': notesEn,
  };
}

class AdminSource {
  const AdminSource({
    required this.id,
    required this.title,
    required this.url,
    required this.publisher,
    required this.kind,
    required this.evidenceNote,
  });
  factory AdminSource.fromJson(Json json) => AdminSource(
    id: json['id'] as String,
    title: json['title'] as String,
    url: json['url'] as String,
    publisher: json['publisher'] as String,
    kind: json['kind'] as String,
    evidenceNote: json['evidence_note'] as String?,
  );
  final String id;
  final String title;
  final String url;
  final String publisher;
  final String kind;
  final String? evidenceNote;
}

class AdminVerification {
  const AdminVerification(this.decision, this.note, this.checkedAt);
  factory AdminVerification.fromJson(Json json) => AdminVerification(
    json['decision'] as String,
    json['note'] as String,
    DateTime.parse(json['checked_at'] as String).toLocal(),
  );
  final String decision;
  final String note;
  final DateTime checkedAt;
}

class AdminVersion {
  const AdminVersion({
    required this.id,
    required this.number,
    required this.content,
    required this.status,
    required this.publishedAt,
    required this.steps,
    required this.sources,
    required this.verifications,
  });
  factory AdminVersion.fromJson(Json json) => AdminVersion(
    id: json['id'] as String,
    number: json['version_number'] as int,
    content: {
      for (final key in [
        'title_zh',
        'title_en',
        'description_zh',
        'description_en',
        'applicable_to',
        'applicable_to_en',
        'location',
        'location_en',
      ])
        key: json[key] as String? ?? '',
      // The "what to bring" list, edited as one item per line in each language.
      'documents_zh': _documentLines(json, 'zh'),
      'documents_en': _documentLines(json, 'en'),
    },
    status: json['verification_status'] as String,
    publishedAt: json['published_at'] == null
        ? null
        : DateTime.parse(json['published_at'] as String).toLocal(),
    steps: [
      for (final s in json['steps'] as List) AdminStep.fromJson(s as Json),
    ],
    sources: [
      for (final s in json['sources'] as List) AdminSource.fromJson(s as Json),
    ],
    verifications: [
      for (final v in json['verifications'] as List)
        AdminVerification.fromJson(v as Json),
    ],
  );
  final String id;
  final int number;
  final Map<String, String> content;
  final String status;
  final DateTime? publishedAt;
  final List<AdminStep> steps;
  final List<AdminSource> sources;
  final List<AdminVerification> verifications;
  bool get isDraft => publishedAt == null;
}

String _documentLines(Json json, String lang) => [
  for (final d in json['documents'] as List? ?? const [])
    (d as Json)[lang] as String? ?? '',
].join('\n');

class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.actionId,
    required this.actionTitle,
    required this.versionNumber,
    required this.stepTitle,
    required this.kind,
    required this.category,
    required this.voice,
    required this.createdAt,
  });
  factory FeedbackItem.fromJson(Json json) => FeedbackItem(
    id: json['id'] as String,
    actionId: json['action_id'] as String,
    actionTitle: Text2.fromJson(json['action_title'] as Json),
    versionNumber: json['version_number'] as int,
    stepTitle: json['step_title'] == null
        ? null
        : Text2.fromJson(json['step_title'] as Json),
    kind: json['kind'] as String,
    category: json['category'] as String?,
    voice: json['original_voice'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
  final String id;
  final String actionId;
  final Text2 actionTitle;
  final int versionNumber;
  final Text2? stepTitle;
  final String kind;
  final String? category;
  final String? voice;
  final DateTime createdAt;
}

class ReportedItem {
  const ReportedItem({
    this.targetType = 'experience',
    required this.reportId,
    required this.targetId,
    required this.targetStatus,
    required this.voice,
    required this.reasons,
    required this.notes,
    required this.count,
  });
  factory ReportedItem.fromJson(Json json) => ReportedItem(
    targetType: json['target_type'] as String? ?? 'experience',
    reportId: json['report_id'] as String,
    targetId: json['target_id'] as String,
    targetStatus: json['target_status'] as String?,
    voice: json['original_voice'] as String?,
    reasons: Map<String, int>.from(json['reasons'] as Map),
    notes: List<String>.from(json['notes'] as List),
    count: json['report_count'] as int,
  );

  /// 'experience' (a post) or 'comment'.
  final String targetType;
  final String reportId;
  final String targetId;
  final String? targetStatus;
  final String? voice;
  final Map<String, int> reasons;
  final List<String> notes;
  final int count;
}

class KbDocument {
  const KbDocument(
    this.id,
    this.title,
    this.publisher,
    this.active,
    this.chunks,
  );
  factory KbDocument.fromJson(Json json) => KbDocument(
    json['id'] as String,
    json['title'] as String,
    json['publisher'] as String,
    json['active'] as bool,
    json['chunk_count'] as int,
  );
  final String id;
  final String title;
  final String publisher;
  final bool active;
  final int chunks;
}

/// AI overview of students' reports for one procedure (D-7). Counts come from the database;
/// overview, themes and checks are AI advice for the reviewer and change nothing by themselves.
class FeedbackSummary {
  const FeedbackSummary({
    required this.feedbackCount,
    required this.counts,
    required this.overview,
    required this.themes,
    required this.checks,
    required this.modelName,
  });
  factory FeedbackSummary.fromJson(Json json) => FeedbackSummary(
    feedbackCount: json['feedback_count'] as int,
    counts: [
      for (final c in json['counts'] as List)
        (
          step: (c as Json)['step_title'] == null
              ? null
              : Text2.fromJson(c['step_title'] as Json),
          kind: c['kind'] as String,
          count: c['count'] as int,
        ),
    ],
    overview: json['overview'] as String?,
    themes: [
      for (final t in json['themes'] as List)
        (
          title: (t as Json)['title'] as String,
          detail: t['detail'] as String,
          reports: (t['feedback_ids'] as List).length,
        ),
    ],
    checks: [for (final c in json['suggested_checks'] as List) c as String],
    modelName: json['model_name'] as String?,
  );
  final int feedbackCount;
  final List<({Text2? step, String kind, int count})> counts;
  final String? overview;
  final List<({String title, String detail, int reports})> themes;
  final List<String> checks;
  final String? modelName;
}

class StaffMember {
  const StaffMember({required this.id, required this.role});
  factory StaffMember.fromJson(Json json) =>
      StaffMember(id: json['id'] as String, role: json['role'] as String);
  final String id;
  final String role;
}

/// Numbers for the MVP success signals (D-19). Rates are null when there is no sample.
class UsageStats {
  const UsageStats(this.json);
  final Json json;
  int count(String key) => json[key] as int;
  double? rate(String key) => (json[key] as num?)?.toDouble();
  Map<String, int> get outcomes => {
    for (final e in (json['outcomes'] as Json).entries) e.key: e.value as int,
  };
  List<({Text2 action, Text2? step, int count})> get stuckSteps => [
    for (final s in json['top_stuck_steps'] as List)
      (
        action: Text2.fromJson((s as Json)['action_title'] as Json),
        step: s['step_title'] == null
            ? null
            : Text2.fromJson(s['step_title'] as Json),
        count: s['count'] as int,
      ),
  ];
}
