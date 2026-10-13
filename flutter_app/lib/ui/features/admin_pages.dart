import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';
import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'browse_pages.dart';

/// Reviewer/admin console (C-14..C-16). Same paper look as the rest (C-17).
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.tab});
  final String tab;
  static const tabs = [
    'actions',
    'feedback',
    'reports',
    'documents',
    'accounts',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.isStaff) {
      return Text(vm.pair('只有審查者與管理者可以使用。', 'Reviewers and admins only.'));
    }
    final admin = vm.admin!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final t in tabs)
              if (t != 'accounts' || vm.isAdmin)
                ChoiceChip(
                  label: Text(switch (t) {
                    'actions' => vm.pair('流程', 'Procedures'),
                    'feedback' => vm.pair('回報審查', 'Reports from students'),
                    'reports' => vm.pair('檢舉', 'Content reports'),
                    'accounts' => vm.pair('權限', 'Access'),
                    _ => vm.pair('官方文件', 'Official documents'),
                  }),
                  selected: tab == t,
                  onSelected: (_) => context.go('/admin?tab=$t'),
                ),
          ],
        ),
        const SizedBox(height: 24),
        switch (tab) {
          'feedback' => _FeedbackQueue(admin: admin),
          'reports' => _ReportQueue(admin: admin),
          'documents' => _Documents(admin: admin),
          'accounts' when vm.isAdmin => _Accounts(admin: admin),
          _ => _ActionList(admin: admin),
        },
      ],
    );
  }
}

/// Loads with a future and offers retry; simpler than view-model resources for staff screens.
class _Loaded<T> extends StatefulWidget {
  const _Loaded({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload)
  builder;
  @override
  State<_Loaded<T>> createState() => _LoadedState<T>();
}

class _LoadedState<T> extends State<_Loaded<T>> {
  late Future<T> _future = widget.load();
  void _reload() => setState(() => _future = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ErrorPanel(
          message: BridgeScope.of(context).errorText(snapshot.error),
          onRetry: _reload,
        );
      }
      if (!snapshot.hasData) return const LoadingNote();
      return widget.builder(context, snapshot.data as T, _reload);
    },
  );
}

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  final vm = BridgeScope.of(context);
  try {
    await action();
  } on ApiException catch (e) {
    vm.showNotice(e.message ?? '${vm.errorText(e)} (${e.code})');
  }
}

// ---------- procedures ----------

class _ActionList extends StatelessWidget {
  const _ActionList({required this.admin});
  final AdminRepository admin;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return _Loaded<List<AdminActionItem>>(
      load: admin.actions,
      builder: (context, items, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => context.push('/admin/actions/new'),
              icon: const Icon(Icons.add),
              label: Text(vm.pair('新增流程', 'New procedure')),
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PaperCard(
                padding: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(item.title.of(vm.english)),
                  subtitle: Text(
                    [
                      'v${item.latestVersion}',
                      if (item.latestPublished != null)
                        '${vm.t('published')} v${item.latestPublished}',
                      if (item.hasDraft) vm.t('draft'),
                      if (item.archived) vm.pair('已封存', 'Archived'),
                    ].join(' · '),
                  ),
                  leading: StatusTag(item.status),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/admin/actions/${item.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminActionPage extends StatelessWidget {
  const AdminActionPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.isStaff || vm.admin == null) return const MissingContent();
    final admin = vm.admin!;
    if (id == 'new') return VersionEditor(admin: admin, version: null);
    return _Loaded<List<AdminVersion>>(
      key: ValueKey(id),
      load: () => admin.versions(id),
      builder: (context, versions, reload) {
        final latest = versions.first;
        return FlowBody(
          maxWidth: 900,
          children: [
            Text(
              '${latest.content['title_zh']} / ${latest.content['title_en']}',
              style: displayStyle(25),
            ),
            if (latest.isDraft)
              VersionEditor(
                admin: admin,
                version: latest,
                actionId: id,
                onChanged: reload,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    vm.pair('建立新版本來修改', 'Create a new version to edit'),
                  ),
                  onPressed: () => _guard(context, () async {
                    await admin.newVersion(id);
                    reload();
                  }),
                ),
              ),
            _VerificationPanel(
              admin: admin,
              version: latest,
              onChanged: reload,
            ),
            PaperHeading(vm.pair('版本紀錄', 'Version history')),
            for (final v in versions)
              Text(
                'v${v.number} · ${v.isDraft ? vm.t('draft') : '${vm.t('published')} ${formatDate(v.publishedAt)}'}'
                ' · ${vm.t(_statusKey(v.status))} · ${v.steps.length} ${vm.pair('步驟', 'steps')}',
              ),
            TextButton(
              onPressed: () => _guard(context, () async {
                await admin.archive(id, true);
                if (context.mounted) context.go('/admin');
              }),
              child: Text(vm.pair('封存這個流程', 'Archive this procedure')),
            ),
          ],
        );
      },
    );
  }
}

String _statusKey(String status) => switch (status) {
  'needs_review' => 'needsReview',
  'community_supported' => 'communitySupported',
  _ => status,
};

/// Edits a draft version (or creates a procedure when [version] is null).
class VersionEditor extends StatefulWidget {
  const VersionEditor({
    super.key,
    required this.admin,
    required this.version,
    this.actionId,
    this.onChanged,
  });
  final AdminRepository admin;
  final AdminVersion? version;
  final String? actionId;
  final VoidCallback? onChanged;
  @override
  State<VersionEditor> createState() => _VersionEditorState();
}

class _VersionEditorState extends State<VersionEditor> {
  static const fields = {
    'title_zh': ('標題（中文）', 'Title (Chinese)'),
    'title_en': ('標題（英文）', 'Title (English)'),
    'description_zh': ('說明（中文）', 'Description (Chinese)'),
    'description_en': ('說明（英文）', 'Description (English)'),
    'applicable_to': ('適用對象（中文）', 'Applies to (Chinese)'),
    'applicable_to_en': ('適用對象（英文）', 'Applies to (English)'),
    'location': ('地點（中文）', 'Location (Chinese)'),
    'location_en': ('地點（英文）', 'Location (English)'),
  };
  late final Map<String, TextEditingController> _fields = {
    for (final key in fields.keys)
      key: TextEditingController(text: widget.version?.content[key] ?? ''),
  };
  final _slug = TextEditingController();
  late final List<(TextEditingController, TextEditingController)> _steps = [
    for (final s in widget.version?.steps ?? const <AdminStep>[])
      (
        TextEditingController(text: s.titleZh),
        TextEditingController(text: s.titleEn),
      ),
  ];

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final (zh, en) in _steps) {
      zh.dispose();
      en.dispose();
    }
    _slug.dispose();
    super.dispose();
  }

  Json _content() => {
    for (final e in _fields.entries)
      e.key: e.key.startsWith('location') && e.value.text.trim().isEmpty
          ? null
          : e.value.text.trim(),
    'steps': [
      for (final (zh, en) in _steps)
        if (zh.text.trim().isNotEmpty)
          {
            'title_zh': zh.text.trim(),
            'title_en': en.text.trim().isEmpty
                ? zh.text.trim()
                : en.text.trim(),
          },
    ],
  };

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final creating = widget.version == null;
    return PaperCard(
      color: Palette.high,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(
            creating
                ? vm.pair('新增流程', 'New procedure')
                : '${vm.t('draft')} v${widget.version!.number}',
          ),
          if (creating)
            TextField(
              controller: _slug,
              decoration: InputDecoration(
                labelText: vm.pair(
                  '網址代稱（英文小寫與 -）',
                  'Slug (lowercase letters and -)',
                ),
              ),
            ),
          for (final e in fields.entries)
            TextField(
              controller: _fields[e.key],
              maxLines: e.key.startsWith('description') ? 4 : 1,
              decoration: InputDecoration(
                labelText: vm.pair(e.value.$1, e.value.$2),
              ),
            ),
          const SizedBox(height: 16),
          PaperHeading(vm.t('stepPreview')),
          for (final (i, (zh, en)) in _steps.indexed)
            Row(
              children: [
                PaperTag('${i + 1}'),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: zh,
                    decoration: const InputDecoration(labelText: '中文'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: en,
                    decoration: const InputDecoration(labelText: 'English'),
                  ),
                ),
                IconButton(
                  tooltip: vm.t('delete'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _steps.removeAt(i)),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(
                () => _steps.add((
                  TextEditingController(),
                  TextEditingController(),
                )),
              ),
              icon: const Icon(Icons.add),
              label: Text(vm.pair('新增步驟', 'Add step')),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _guard(context, () async {
                  if (creating) {
                    final slug = _slug.text.trim();
                    await widget.admin.createAction(slug, _content());
                    // A procedure's id is its slug.
                    if (context.mounted) context.go('/admin/actions/$slug');
                  } else {
                    await widget.admin.saveDraft(
                      widget.version!.id,
                      _content(),
                    );
                    vm.showNotice(vm.pair('草稿已儲存。', 'Draft saved.'));
                    widget.onChanged?.call();
                  }
                }),
                child: Text(
                  creating
                      ? vm.pair('建立草稿', 'Create draft')
                      : vm.pair('儲存草稿', 'Save draft'),
                ),
              ),
              if (!creating)
                OutlinedButton(
                  onPressed: () => _guard(context, () async {
                    await widget.admin.saveDraft(
                      widget.version!.id,
                      _content(),
                    );
                    await widget.admin.publish(widget.version!.id);
                    vm.showNotice(
                      vm.pair(
                        '已發布；內容從此凍結。',
                        'Published; this version is now frozen.',
                      ),
                    );
                    widget.onChanged?.call();
                  }),
                  child: Text(vm.pair('儲存並發布', 'Save and publish')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sources and verification for the newest version. "Verified" needs a source and a reviewer.
class _VerificationPanel extends StatefulWidget {
  const _VerificationPanel({
    required this.admin,
    required this.version,
    required this.onChanged,
  });
  final AdminRepository admin;
  final AdminVersion version;
  final VoidCallback onChanged;
  @override
  State<_VerificationPanel> createState() => _VerificationPanelState();
}

class _VerificationPanelState extends State<_VerificationPanel> {
  String? _source;
  String _decision = 'verified';
  final _note = TextEditingController();
  final _newTitle = TextEditingController();
  final _newUrl = TextEditingController();
  final _newPublisher = TextEditingController();
  final _evidence = TextEditingController();

  @override
  void dispose() {
    for (final c in [_note, _newTitle, _newUrl, _newPublisher, _evidence]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final v = widget.version;
    return PaperCard(
      color: Palette.oat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(vm.t('sources'), badge: vm.t(_statusKey(v.status))),
          for (final s in v.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.title),
              subtitle: Text(
                '${s.publisher} · ${s.url}\n${s.evidenceNote ?? ''}',
              ),
            ),
          if (v.isDraft) ...[
            Text(vm.pair('新增來源（發布前）', 'Add a source (before publishing)')),
            TextField(
              controller: _newTitle,
              decoration: InputDecoration(
                labelText: vm.pair('文件名稱', 'Document title'),
              ),
            ),
            TextField(
              controller: _newUrl,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            TextField(
              controller: _newPublisher,
              decoration: InputDecoration(
                labelText: vm.pair('發布單位', 'Publisher'),
              ),
            ),
            TextField(
              controller: _evidence,
              decoration: InputDecoration(
                labelText: vm.pair('這份來源證明了什麼', 'What this source supports'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _guard(context, () async {
                  final source = await widget.admin.createSource({
                    'title': _newTitle.text.trim(),
                    'url': _newUrl.text.trim(),
                    'publisher': _newPublisher.text.trim(),
                    'kind': 'official',
                    'accessed_at': DateTime.now().toUtc().toIso8601String(),
                  });
                  await widget.admin.attachSource(
                    v.id,
                    source.id,
                    _evidence.text.trim(),
                  );
                  widget.onChanged();
                }),
                child: Text(vm.pair('加入來源', 'Attach source')),
              ),
            ),
          ],
          if (!v.isDraft && v.sources.isNotEmpty) ...[
            const Divider(color: Palette.edge),
            Text(
              vm.pair(
                '審查紀錄（依來源核對後填寫）',
                'Review (after checking against a source)',
              ),
            ),
            DropdownButton<String>(
              value: _source,
              hint: Text(vm.t('sources')),
              isExpanded: true,
              items: [
                for (final s in v.sources)
                  DropdownMenuItem(value: s.id, child: Text(s.title)),
              ],
              onChanged: (value) => setState(() => _source = value),
            ),
            DropdownButton<String>(
              value: _decision,
              isExpanded: true,
              items: [
                for (final d in ['verified', 'needs_review', 'outdated'])
                  DropdownMenuItem(value: d, child: Text(vm.t(_statusKey(d)))),
              ],
              onChanged: (value) => setState(() => _decision = value!),
            ),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: vm.pair('審查說明', 'Review note'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _source == null
                    ? null
                    : () => _guard(context, () async {
                        await widget.admin.verify(
                          v.id,
                          _source!,
                          _decision,
                          _note.text.trim(),
                        );
                        widget.onChanged();
                      }),
                child: Text(vm.pair('記錄審查', 'Record review')),
              ),
            ),
          ],
          for (final r in v.verifications)
            Text(
              '${formatDate(r.checkedAt)} · ${vm.t(_statusKey(r.decision))} · ${r.note}',
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['community_supported', 'unverified'])
                TextButton(
                  onPressed: () => _guard(context, () async {
                    await widget.admin.setStatus(v.id, s);
                    widget.onChanged();
                  }),
                  child: Text(
                    '${vm.pair('標為', 'Mark')} ${vm.t(_statusKey(s))}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- queues ----------

class _FeedbackQueue extends StatelessWidget {
  const _FeedbackQueue({required this.admin});
  final AdminRepository admin;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return _Loaded<List<FeedbackItem>>(
      load: () => admin.feedback('pending'),
      builder: (context, items, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            Text(vm.pair('沒有待審的回報。', 'Nothing waiting for review.')),
          if (items.isNotEmpty) ...[
            Text(
              vm.pair(
                'AI 整理：把同一個流程的待審回報歸納成重點，只供參考，不會改動流程。',
                'AI overview: groups pending reports per procedure. Advice only; nothing changes.',
              ),
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in {for (final f in items) f.actionId: f}.values)
                  OutlinedButton(
                    onPressed: () => _guard(context, () async {
                      final summary = await admin.summarizeFeedback(
                        f.actionId,
                        english: vm.english,
                      );
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (_) => _FeedbackSummaryDialog(
                          title: f.actionTitle.of(vm.english),
                          summary: summary,
                        ),
                      );
                    }),
                    child: Text(
                      '${vm.pair('AI 整理', 'Summarize')}：${f.actionTitle.of(vm.english)}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          for (final f in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.actionTitle.of(vm.english)} v${f.versionNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        f.kind,
                        ?f.category,
                        if (f.stepTitle != null) f.stepTitle!.of(vm.english),
                        formatDate(f.createdAt),
                      ].join(' · '),
                    ),
                    if (f.voice != null) Text('「${f.voice}」'),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _guard(context, () async {
                            await admin.reviewFeedback(f.id, 'reviewed');
                            reload();
                          }),
                          child: Text(vm.pair('已審查（採納）', 'Reviewed')),
                        ),
                        TextButton(
                          onPressed: () => _guard(context, () async {
                            await admin.reviewFeedback(f.id, 'dismissed');
                            reload();
                          }),
                          child: Text(vm.pair('駁回', 'Dismiss')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackSummaryDialog extends StatelessWidget {
  const _FeedbackSummaryDialog({required this.title, required this.summary});
  final String title;
  final FeedbackSummary summary;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    const muted = TextStyle(fontSize: 13, color: Palette.muted);
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vm.pair(
                '${summary.feedbackCount} 則回報',
                '${summary.feedbackCount} reports',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final c in summary.counts)
              Text(
                '${c.step?.of(vm.english) ?? vm.pair('整體', 'Overall')} · ${c.kind} · ${c.count}',
              ),
            if (summary.overview != null) ...[
              const SizedBox(height: 12),
              Text(summary.overview!),
            ],
            for (final t in summary.themes) ...[
              const SizedBox(height: 8),
              Text(
                '${t.title}（${vm.pair('${t.reports} 則', '${t.reports} reports')}）',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(t.detail),
            ],
            if (summary.checks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                vm.pair('建議確認', 'Worth checking'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final c in summary.checks) Text('• $c'),
            ],
            const SizedBox(height: 12),
            Text(
              vm.pair(
                'AI 整理（${summary.modelName ?? '—'}），內容來自學生回報，不是已驗證的事實。是否開新版本由你決定。',
                'AI summary (${summary.modelName ?? '—'}) of student reports, not verified facts. You decide whether to open a new version.',
              ),
              style: muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(vm.pair('關閉', 'Close')),
        ),
      ],
    );
  }
}

class _ReportQueue extends StatelessWidget {
  const _ReportQueue({required this.admin});
  final AdminRepository admin;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return _Loaded<List<ReportedItem>>(
      load: () => admin.reports('pending'),
      builder: (context, items, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty) Text(vm.pair('沒有待處理的檢舉。', 'No open reports.')),
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.count} ${vm.pair('則檢舉', 'reports')} · ${r.reasons.entries.map((e) => '${e.key} ${e.value}').join(', ')}'
                      ' · ${r.targetStatus ?? '—'}',
                    ),
                    if (r.voice != null) Text('「${r.voice}」'),
                    for (final note in r.notes)
                      Text(
                        note,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Palette.muted,
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _guard(context, () async {
                            await admin.resolveReport(r.reportId, 'hide');
                            reload();
                          }),
                          child: Text(vm.pair('隱藏內容', 'Hide content')),
                        ),
                        TextButton(
                          onPressed: () => _guard(context, () async {
                            await admin.resolveReport(r.reportId, 'dismiss');
                            reload();
                          }),
                          child: Text(vm.pair('檢舉不成立', 'Dismiss')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Documents extends StatefulWidget {
  const _Documents({required this.admin});
  final AdminRepository admin;
  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _publisher = TextEditingController();
  final _action = TextEditingController();
  final _text = TextEditingController();
  int _version = 0;

  @override
  void dispose() {
    for (final c in [_title, _url, _publisher, _action, _text]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.pair(
            '貼上官方文件全文，助理就能依段落引用。過時的文件請停用。',
            'Paste the full text of an official document so the assistant can cite it. Retire outdated ones.',
          ),
        ),
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: vm.pair('文件名稱', 'Title')),
        ),
        TextField(
          controller: _url,
          decoration: const InputDecoration(labelText: 'URL'),
        ),
        TextField(
          controller: _publisher,
          decoration: InputDecoration(labelText: vm.pair('發布單位', 'Publisher')),
        ),
        TextField(
          controller: _action,
          decoration: InputDecoration(
            labelText: vm.pair(
              '相關流程 id（選填）',
              'Related procedure id (optional)',
            ),
          ),
        ),
        TextField(
          controller: _text,
          maxLines: 8,
          decoration: InputDecoration(labelText: vm.pair('全文', 'Full text')),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => _guard(context, () async {
              await widget.admin.addDocument({
                'title': _title.text.trim(),
                'url': _url.text.trim(),
                'publisher': _publisher.text.trim(),
                if (_action.text.trim().isNotEmpty)
                  'action_id': _action.text.trim(),
                'text': _text.text,
              });
              _text.clear();
              setState(() => _version++);
            }),
            child: Text(vm.pair('加入文件', 'Add document')),
          ),
        ),
        const SizedBox(height: 16),
        _Loaded<List<KbDocument>>(
          key: ValueKey(_version),
          load: widget.admin.documents,
          builder: (context, docs, reload) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final d in docs)
                ListTile(
                  title: Text(d.title),
                  subtitle: Text(
                    '${d.publisher} · ${d.chunks} ${vm.pair('段', 'passages')}',
                  ),
                  trailing: TextButton(
                    onPressed: () => _guard(context, () async {
                      await widget.admin.setDocumentActive(d.id, !d.active);
                      reload();
                    }),
                    child: Text(
                      d.active
                          ? vm.pair('停用', 'Retire')
                          : vm.pair('恢復', 'Restore'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- access (admin only) ----------

class _Accounts extends StatefulWidget {
  const _Accounts({required this.admin});
  final AdminRepository admin;
  @override
  State<_Accounts> createState() => _AccountsState();
}

class _AccountsState extends State<_Accounts> {
  final _id = TextEditingController();
  String _role = 'reviewer';
  int _version = 0;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  String _roleName(String role) {
    final vm = BridgeScope.of(context);
    return switch (role) {
      'admin' => vm.pair('管理者', 'Admin'),
      'reviewer' => vm.pair('審查者', 'Reviewer'),
      _ => vm.pair('學生', 'Student'),
    };
  }

  Future<void> _set(String id, String role) => _guard(context, () async {
    await widget.admin.setRole(id, role);
    setState(() => _version++);
  });

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.pair(
            '請組員登入後到「我的」→「帳號」複製帳號編號給你，再在這裡設定角色。',
            'Ask the teammate to sign in and copy their account ID from Me → Account, then set a role here.',
          ),
        ),
        TextField(
          controller: _id,
          decoration: InputDecoration(labelText: vm.pair('帳號編號', 'Account ID')),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final role in ['reviewer', 'admin', 'student'])
              ChoiceChip(
                label: Text(_roleName(role)),
                selected: _role == role,
                onSelected: (_) => setState(() => _role = role),
              ),
            FilledButton(
              onPressed: () {
                final id = _id.text.trim();
                if (id.isEmpty) return;
                _set(id, _role).then((_) => _id.clear());
              },
              child: Text(vm.pair('設定角色', 'Set role')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Loaded<List<StaffMember>>(
          key: ValueKey(_version),
          load: widget.admin.staff,
          builder: (context, staff, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in staff)
                ListTile(
                  title: SelectableText(m.id),
                  subtitle: Text(_roleName(m.role)),
                  trailing: m.id == vm.profile?.id
                      ? Text(vm.pair('（你）', '(you)'))
                      : TextButton(
                          onPressed: () => _set(m.id, 'student'),
                          child: Text(vm.pair('移除權限', 'Remove access')),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
