part of 'admin_pages.dart';

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

  /// Admins only: the author can no longer post, comment or react (reading still works).
  Future<void> _suspendAuthor(
    BuildContext context,
    ReportedItem r,
    VoidCallback reload,
  ) async {
    final vm = BridgeScope.of(context);
    if (!await confirmDialog(
          context,
          vm.pair('停權這位作者？', 'Suspend this author?'),
          vm.pair(
            '對方將不能再發文、留言、按讚或使用助理，但仍可瀏覽。內容是否隱藏請另外處理。',
            'They can no longer post, comment, react or use the assistant, but can still '
                'read. Hide the content separately.',
          ),
          confirm: vm.pair('停權', 'Suspend'),
          danger: true,
        ) ||
        !context.mounted) {
      return;
    }
    await _guard(context, () async {
      await admin.suspendReportAuthor(r.reportId);
      vm.showNotice(vm.pair('已停權這位作者', 'Author suspended'));
      reload();
    });
  }

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
                      '${r.targetType == 'comment' ? vm.pair('留言', 'Comment') : vm.pair('貼文', 'Post')} · '
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
                        if (vm.isAdmin && r.authorRef != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Palette.danger,
                            ),
                            onPressed: () => _suspendAuthor(context, r, reload),
                            child: Text(vm.pair('停權作者', 'Suspend author')),
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

/// Students' reports about assistant answers (wrong, offensive, harmful), newest first;
/// 「已處理」 once someone has looked at it.
class _AssistantReportQueue extends StatelessWidget {
  const _AssistantReportQueue({required this.admin});
  final AdminRepository admin;

  static const _reasons = {
    'inaccurate': ('不正確', 'Inaccurate'),
    'offensive': ('冒犯', 'Offensive'),
    'harmful': ('有害', 'Harmful'),
    'other': ('其他', 'Other'),
  };

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    const muted = TextStyle(fontSize: 13, color: Palette.muted);
    return _Loaded<List<AssistantReportItem>>(
      load: () => admin.assistantReports('open'),
      builder: (context, items, reload) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty)
            Text(
              vm.pair('沒有待處理的 AI 回答回報。', 'No open reports about AI answers.'),
            ),
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        switch (_reasons[r.reason]) {
                          final (String, String) label => vm.pair(
                            label.$1,
                            label.$2,
                          ),
                          null => r.reason,
                        },
                        formatDate(r.createdAt),
                      ].join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(vm.pair('問題', 'Question'), style: muted),
                    Text(r.question),
                    const SizedBox(height: 6),
                    Text(
                      vm.pair('助理的回答', "The assistant's answer"),
                      style: muted,
                    ),
                    Text('「${r.answer}」'),
                    if ((r.details ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(vm.pair('補充說明', 'Details'), style: muted),
                      Text(r.details!),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => _guard(context, () async {
                          await admin.resolveAssistantReport(r.id);
                          reload();
                        }),
                        child: Text(vm.pair('已處理', 'Handled')),
                      ),
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
