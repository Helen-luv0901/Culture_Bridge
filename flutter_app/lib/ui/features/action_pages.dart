import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';
import 'faq_pages.dart';
import 'post_cards.dart';

/// Opens a procedure and remembers it was read.
void openProcedure(BuildContext context, String id) {
  BridgeScope.of(context).markRead('guide:$id');
  context.push('/actions/${Uri.encodeComponent(id)}');
}

/// Loads the reader's procedures in progress once (signed out there is nothing to load).
void _loadExecutions(BridgeViewModel vm) {
  if (!vm.signedIn || !vm.executions.needsLoad) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (vm.signedIn && vm.executions.needsLoad) vm.loadExecutions();
  });
}

/// 辦證件步驟: every official procedure as one compact card of rows, the ones being done
/// first. Shown at the top of the 問答 tab, above the official Q&A.
class ProcedureSection extends StatefulWidget {
  const ProcedureSection({super.key});
  @override
  State<ProcedureSection> createState() => _ProcedureSectionState();
}

class _ProcedureSectionState extends State<ProcedureSection> {
  /// Rows shown before "see all", so the official Q&A stays close below.
  static const _folded = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    _loadExecutions(vm);
    return Column(
      key: const Key('procedures-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only as wide as the words, so the paper beside them is not taken for the text's
        // background.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              headingLevel: 2,
              child: Text(
                vm.pair('辦證件步驟', 'Step-by-step procedures'),
                style: displayStyle(22),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              vm.pair(
                '居留證、健保、工作許可、開戶等，從官方公告整理成一步一步的清單，還會記下你做到哪一步。',
                'Residence permit, health insurance, work permit, a bank account and more, '
                    'laid out step by step from official notices. Your progress is kept.',
              ),
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ResourceView<List<ActionSummary>>(
          resource: (vm) => vm.actions,
          load: (vm) => vm.loadActions(),
          builder: (context, actions) {
            if (actions.isEmpty) return const SizedBox.shrink();
            // Being done first, then the usual order.
            final doing = [
              for (final a in actions)
                if (vm.openExecution(a.id) != null) a,
            ];
            final sorted = [
              ...doing,
              for (final a in actions)
                if (vm.openExecution(a.id) == null) a,
            ];
            final shown = _all
                ? sorted
                : sorted
                      .take(doing.length > _folded ? doing.length : _folded)
                      .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProcedureList(actions: shown),
                if (shown.length < sorted.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton(
                      key: const Key('procedures-more'),
                      onPressed: () => setState(() => _all = true),
                      child: Text(
                        vm.pair(
                          '看全部 ${sorted.length} 項步驟',
                          'See all ${sorted.length} procedures',
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Procedures as one card of rows: the title, and how far the reader got.
class ProcedureList extends StatelessWidget {
  const ProcedureList({super.key, required this.actions});
  final List<ActionSummary> actions;
  @override
  // One card per procedure, spaced like the official Q&A list (faint dashed rules were too subtle).
  Widget build(BuildContext context) => CardList(
    gap: 8,
    children: [
      for (final a in actions)
        NoteCard(
          padding: EdgeInsets.zero,
          child: _ProcedureRow(action: a),
        ),
    ],
  );
}

class _ProcedureRow extends StatelessWidget {
  const _ProcedureRow({required this.action});
  final ActionSummary action;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final execution = vm.openExecution(action.id);
    final doing = execution != null;
    final read = vm.isRead('guide:${action.id}');
    final status = execution != null
        ? vm.pair(
            '辦理中 · ${execution.doneCount} / ${execution.steps.length}',
            'In progress · ${execution.doneCount} of ${execution.steps.length}',
          )
        : read
        ? vm.pair('已看過', 'Read')
        : null;
    return InkWell(
      key: Key('procedure-row-${action.id}'),
      onTap: () => openProcedure(context, action.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title.of(vm.english),
                      style: displayStyle(
                        16,
                        color: read && !doing ? Palette.muted : Palette.ink,
                      ).copyWith(height: 1.5),
                    ),
                    if (status != null)
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: doing ? FontWeight.w700 : FontWeight.w400,
                          color: doing ? Palette.moss : Palette.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const AppIcon('chevron', size: 18, color: Palette.control),
            ],
          ),
        ),
      ),
    );
  }
}

class ActionDetailPage extends StatelessWidget {
  const ActionDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => ResourceView<ActionDetail>(
    key: ValueKey(id),
    resource: (vm) => vm.action(id),
    load: (vm) => vm.loadAction(id),
    builder: (context, detail) => _ActionDetail(detail: detail),
  );
}

/// Drops "（內政部移民署）" after each sentence: the sources are listed once, under 資料來源.
String withoutCitations(String text, List<SourceInfo> sources) {
  var out = text;
  for (final source in sources) {
    for (final name in {source.publisher, source.publisherEn}) {
      if (name.trim().isEmpty) continue;
      out = out
          .replaceAll('（$name）', '')
          .replaceAll(' ($name)', '')
          .replaceAll('($name)', '');
    }
  }
  return out;
}

class _ActionDetail extends StatefulWidget {
  const _ActionDetail({required this.detail});
  final ActionDetail detail;
  @override
  State<_ActionDetail> createState() => _ActionDetailState();
}

class _ActionDetailState extends State<_ActionDetail> {
  bool _starting = false;

  Future<void> _track() async {
    final vm = BridgeScope.of(context);
    final id = widget.detail.summary.id;
    if (vm.openExecution(id) != null) {
      context.push('/actions/$id/progress');
      return;
    }
    if (!ensureSignedIn(context)) return;
    setState(() => _starting = true);
    final started = await vm.startAction(id);
    if (!mounted) return;
    setState(() => _starting = false);
    if (started != null && context.mounted) {
      context.push('/actions/$id/progress');
    }
  }

  /// Whether the guide was checked by a person, said once beside its sources.
  String _checked(BridgeViewModel vm) {
    final action = widget.detail.summary;
    if (action.verificationStatus == 'verified') {
      final date = formatDate(action.lastVerifiedAt);
      return vm.pair('已驗證 · 最後確認 $date', 'Verified · last checked $date');
    }
    return vm.pair(
      'Culture Bridge 從官方公告整理，還在逐項人工確認；辦理前請以這些來源為準。',
      'Culture Bridge put this together from official notices and is still '
          'checking it line by line; the sources have the final say.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final detail = widget.detail;
    final action = detail.summary;
    vm.markRead('guide:${action.id}');
    _loadExecutions(vm);
    final description = withoutCitations(
      action.description.of(vm.english),
      detail.sources,
    );
    final doing = vm.openExecution(action.id) != null;
    return FlowBody(
      maxWidth: 760,
      children: [
        // Only as wide as the words (see ProcedureSection).
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            vm.pair('辦證件步驟 · 從官方公告整理', 'Procedure · From official notices'),
            style: mutedStyle.copyWith(fontSize: 13),
          ),
        ),
        PageTitle(action.title.of(vm.english)),
        if (description.isNotEmpty)
          ExpandableText(
            description,
            style: const TextStyle(fontSize: 16, height: 1.75),
          ),
        _KeyFacts(detail: detail),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('start-action'),
              onPressed: _starting ? null : _track,
              child: Text(
                doing
                    ? vm.t('continueAction')
                    : vm.pair('開始逐步辦理', 'Start, step by step'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              vm.pair(
                '會記下你做到哪一步，下次回來接著做。',
                'Your progress is kept, so you can pick up where you left off.',
              ),
              style: mutedStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        if (detail.steps.isNotEmpty)
          _Steps(steps: detail.steps, sources: detail.sources),
        if (detail.documents.isNotEmpty)
          _Documents(actionId: action.id, documents: detail.documents),
        _Sources(sources: detail.sources, checked: _checked(vm)),
        _RelatedFaqs(actionId: action.id),
      ],
    );
  }
}

/// Who it is for, where to go, and how much there is to do, before the details.
class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.detail});
  final ActionDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final action = detail.summary;
    final size = [
      if (detail.steps.isNotEmpty)
        vm.pair('${detail.steps.length} 個步驟', '${detail.steps.length} steps'),
      if (detail.documents.isNotEmpty)
        vm.pair(
          '要帶 ${detail.documents.length} 份文件',
          '${detail.documents.length} documents to bring',
        ),
    ].join(vm.english ? ' · ' : '・');
    String clean(String text) => withoutCitations(text, detail.sources);
    final facts = [
      if (size.isNotEmpty) (vm.pair('要做的事', 'What it takes'), size),
      if (action.location != null)
        (vm.pair('地點', 'Where'), clean(action.location!.of(vm.english))),
      (vm.t('applicableTo'), clean(action.applicableTo.of(vm.english))),
    ];
    // With large text the labels go above their values instead of being squeezed.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;
    const labelText = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Palette.muted,
      height: 1.6,
    );
    const valueText = TextStyle(fontSize: 15, height: 1.6);
    return NoteCard(
      key: const Key('guide-key-facts'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        children: [
          for (final (i, (label, value)) in facts.indexed) ...[
            if (i > 0) const DashedRule(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: labelText),
                        ExpandableText(value, maxLines: 2, style: valueText),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: vm.english ? 104 : 72,
                          child: Text(label, style: labelText),
                        ),
                        Expanded(
                          child: ExpandableText(
                            value,
                            maxLines: 2,
                            style: valueText,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The official sources, folded away under one line, with how far the guide was checked.
class _Sources extends StatelessWidget {
  const _Sources({required this.sources, required this.checked});
  final List<SourceInfo> sources;
  final String checked;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    // Its own Material: the tile's ink stays with this page, not the shell's Material that
    // the pages above it share.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('guide-sources'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: Palette.ink,
          collapsedIconColor: Palette.ink,
          title: Text(
            sources.isEmpty
                ? vm.pair('資料來源（待補上）', 'Sources (to be added)')
                : vm.pair(
                    '資料來源（${sources.length}）',
                    'Sources (${sources.length})',
                  ),
            style: displayStyle(16),
          ),
          subtitle: Text(checked, style: mutedStyle),
          children: [
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SourceLine(source: source),
              ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.sources});
  final List<ActionStepInfo> steps;
  final List<SourceInfo> sources;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(vm.pair('步驟', 'Steps')),
        const SizedBox(height: 12),
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Palette.high,
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.moss, width: 1.5),
                  ),
                  child: Text(
                    '${step.position}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Palette.moss,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title.of(vm.english),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.6,
                        ),
                      ),
                      if ((step.notesFor(vm.english) ?? '').isNotEmpty)
                        ExpandableText(
                          withoutCitations(step.notesFor(vm.english)!, sources),
                          maxLines: 2,
                          style: mutedStyle.copyWith(fontSize: 14),
                        ),
                      if (step.recentStuckCount > 0)
                        Text(
                          '${step.recentStuckCount} ${vm.t('recentStuck')}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Palette.brickDeep,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 要帶的文件: a checklist to tick before going.
class _Documents extends StatelessWidget {
  const _Documents({required this.actionId, required this.documents});
  final String actionId;
  final List<Text2> documents;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final ready = vm.documentsReady(actionId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          vm.pair('要帶的文件', 'What to bring'),
          note: vm.pair(
            '已備妥 $ready / ${documents.length}',
            '$ready of ${documents.length} ready',
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            vm.pair('出門前逐項勾一次。', 'Tick each one before you leave.'),
            style: mutedStyle,
          ),
        ),
        const SizedBox(height: 10),
        NoteCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, doc) in documents.indexed) ...[
                if (i > 0) const DashedRule(),
                _DocumentRow(
                  key: Key('document-$i'),
                  label: doc.of(vm.english),
                  ready: vm.documentReady(actionId, i),
                  onTap: () => vm.toggleDocument(actionId, i),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    super.key,
    required this.label,
    required this.ready,
    required this.onTap,
  });
  final String label;
  final bool ready;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Semantics(
      checked: ready,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: ready ? Palette.paleMoss : Palette.high,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: ready ? Palette.moss : Palette.control,
                      width: 1.5,
                    ),
                  ),
                  child: ready
                      ? const Icon(Icons.check, size: 18, color: Palette.moss)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: ready ? Palette.muted : Palette.ink,
                          decoration: ready
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      if (ready)
                        Text(
                          vm.pair('已備妥', 'Ready'),
                          style: mutedStyle.copyWith(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 相關官方問答: official questions on the same subject; hidden when there are none (or
/// they can't load).
class _RelatedFaqs extends StatelessWidget {
  const _RelatedFaqs({required this.actionId});
  final String actionId;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (vm.actionFaqs(actionId).needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vm.actionFaqs(actionId).needsLoad) vm.loadActionFaqs(actionId);
      });
    }
    // FaqList leaves out questions that aren't shown (school administration, no English).
    final faqs = [
      for (final faq in vm.actionFaqs(actionId).data ?? const <FaqSummary>[])
        if (vm.faqShown(faq)) faq,
    ].take(3).toList();
    if (faqs.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('procedure-related-faqs'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(vm.pair('相關官方問答', 'Related official Q&A')),
        const SizedBox(height: 10),
        FaqList(items: faqs),
      ],
    );
  }
}

class SourceLine extends StatelessWidget {
  const SourceLine({super.key, required this.source});
  final SourceInfo source;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          source.title,
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
        // The evidence note is a reviewer's note in Chinese, so English shows the source only.
        Text(
          vm.english
              ? source.publisherFor(true)
              : '${source.publisher} · ${source.evidenceNote}',
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ],
    );
    final uri = Uri.tryParse(source.url);
    if (uri == null || !uri.hasScheme) return label;
    return Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, follow) => InkWell(onTap: follow, child: label),
    );
  }
}

/// Resolves the student's open execution for this procedure (loading it if needed).
class _ExecutionView extends StatelessWidget {
  const _ExecutionView({required this.actionId, required this.builder});
  final String actionId;
  final Widget Function(BuildContext context, Execution execution) builder;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.signedIn) {
      return FlowBody(
        children: [
          Text(vm.t('signInNeeded')),
          FilledButton(
            onPressed: () => ensureSignedIn(context),
            child: Text(vm.t('signIn')),
          ),
        ],
      );
    }
    return ResourceView<List<Execution>>(
      resource: (vm) => vm.executions,
      load: (vm) => vm.loadExecutions(),
      builder: (context, _) {
        final execution = vm.openExecution(actionId);
        if (execution == null) {
          return FlowBody(
            children: [
              Text(vm.t('noProgressYet')),
              FilledButton(
                onPressed: () => context.go('/actions/$actionId'),
                child: Text(vm.t('startAction')),
              ),
            ],
          );
        }
        return builder(context, execution);
      },
    );
  }
}

class ActionProgressPage extends StatelessWidget {
  const ActionProgressPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => _ExecutionView(
    actionId: id,
    builder: (context, execution) => _Progress(execution: execution),
  );
}

class _Progress extends StatefulWidget {
  const _Progress({required this.execution});
  final Execution execution;
  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  String? _stuckStep;
  String? _reason;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final e = widget.execution;
    return FlowBody(
      children: [
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('myActionProgress')),
              Text(e.title.of(vm.english), style: displayStyle(25)),
              const SizedBox(height: 14),
              Text('${vm.t('progress')}: ${e.doneCount} / ${e.steps.length}'),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: e.steps.isEmpty ? 0 : e.doneCount / e.steps.length,
                backgroundColor: Palette.edge,
                color: Palette.moss,
                minHeight: 8,
              ),
              if (e.newerVersionAvailable) ...[
                const SizedBox(height: 12),
                Text(
                  vm.t('startedNewer'),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        for (final (i, step) in e.steps.indexed)
          PaperCard(
            color: switch (step.state) {
              'done' => Palette.paleMoss,
              'stuck' => Palette.ochre,
              _ => Palette.high,
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  key: Key('step-$i'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(step.title.of(vm.english)),
                  value: step.state == 'done',
                  onChanged: (value) =>
                      vm.setStepDone(e, step.stepId, value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (step.state != 'done' && _stuckStep != step.stepId)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: Key('stuck-$i'),
                      onPressed: () => setState(() {
                        _stuckStep = step.stepId;
                        _reason = null;
                        _text.clear();
                      }),
                      child: Text(vm.t('imStuck')),
                    ),
                  ),
                if (_stuckStep == step.stepId) ...[
                  Text(vm.t('actionWhatHappened')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final reason in [
                        'dontUnderstandStep',
                        'documentsDifferent',
                        'websiteDoesNotWork',
                      ])
                        ChoiceChip(
                          label: Text(vm.t(reason)),
                          selected: _reason == reason,
                          onSelected: (_) => setState(() => _reason = reason),
                        ),
                    ],
                  ),
                  TextField(
                    controller: _text,
                    maxLength: 2000,
                    decoration: InputDecoration(labelText: vm.t('tellMore')),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _reason == null || vm.reportingStuck
                          ? null
                          : () async {
                              final ok = await vm.reportStuck(
                                e,
                                step.stepId,
                                _reason!,
                                _text.text,
                              );
                              if (ok && mounted) {
                                setState(() => _stuckStep = null);
                              }
                            },
                      child: Text(vm.t('send')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        FilledButton(
          key: const Key('complete-action'),
          onPressed: () => context.push('/actions/${e.actionId}/complete'),
          child: Text(vm.t('completeAction')),
        ),
      ],
    );
  }
}

class ActionCompletionPage extends StatelessWidget {
  const ActionCompletionPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => _ExecutionView(
    actionId: id,
    builder: (context, execution) => _Completion(execution: execution),
  );
}

class _Completion extends StatefulWidget {
  const _Completion({required this.execution});
  final Execution execution;
  @override
  State<_Completion> createState() => _CompletionState();
}

class _CompletionState extends State<_Completion> {
  String? _outcome;
  final Set<String> _differences = {};
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final e = widget.execution;
    return FlowBody(
      children: [
        Text(
          vm
              .t('completionQuestion')
              .replaceAll('{action}', e.title.of(vm.english)),
          style: displayStyle(25),
        ),
        Text(vm.t('feedbackHelpsNext')),
        for (final outcome in ['success', 'different', 'failed'])
          PaperCard(
            color: _outcome == outcome ? Palette.paleMoss : Palette.high,
            padding: EdgeInsets.zero,
            child: RadioGroup<String>(
              groupValue: _outcome,
              onChanged: (value) => setState(() => _outcome = value),
              child: RadioListTile<String>(
                value: outcome,
                title: Text(
                  vm.t(
                    {
                      'success': 'completionSuccess',
                      'different': 'completionDifferent',
                      'failed': 'completionFailed',
                    }[outcome]!,
                  ),
                ),
                subtitle: Text(
                  vm.t(
                    {
                      'success': 'completionSuccessDetail',
                      'different': 'completionDifferentDetail',
                      'failed': 'completionFailedDetail',
                    }[outcome]!,
                  ),
                ),
              ),
            ),
          ),
        if (_outcome == 'different')
          PaperCard(
            color: Palette.oat,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PaperHeading(vm.t('whatWasDifferent')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in [
                      'documents',
                      'fee',
                      'location',
                      'process',
                      'eligibility',
                    ])
                      FilterChip(
                        label: Text(vm.t(category)),
                        selected: _differences.contains(category),
                        onSelected: (_) => setState(
                          () => _differences.contains(category)
                              ? _differences.remove(category)
                              : _differences.add(category),
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: _text,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: vm.t('tellMore')),
                ),
              ],
            ),
          ),
        if (_outcome != null)
          FilledButton(
            key: const Key('send-outcome'),
            onPressed: _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    final outcome = _outcome == 'failed' ? 'failed' : _outcome!;
                    final ok = await vm.finishAction(
                      e,
                      outcome,
                      differences: _differences,
                      text: _text.text,
                    );
                    if (!mounted) return;
                    setState(() => _sending = false);
                    if (ok && context.mounted) context.go('/faqs');
                  },
            child: Text(vm.t('send')),
          ),
      ],
    );
  }
}
