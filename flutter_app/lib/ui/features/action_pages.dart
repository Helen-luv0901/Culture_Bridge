import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'browse_pages.dart';

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

class _ActionDetail extends StatefulWidget {
  const _ActionDetail({required this.detail});
  final ActionDetail detail;
  @override
  State<_ActionDetail> createState() => _ActionDetailState();
}

class _ActionDetailState extends State<_ActionDetail> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final action = widget.detail.summary;
    final open = vm.openExecution(action.id);
    return FlowBody(
      children: [
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action.title.of(vm.english), style: displayStyle(25)),
              const SizedBox(height: 12),
              StatusTag(action.verificationStatus),
              const SizedBox(height: 16),
              Text(
                action.recentSuccessCount > 0
                    ? '${action.recentSuccessCount} ${vm.t('recentlyCompleted')}'
                    : vm.t('noRecentCompletions'),
              ),
              Text(
                action.lastVerifiedAt != null
                    ? '${vm.t('lastOfficialUpdate')}: ${formatDate(action.lastVerifiedAt)}'
                    : vm.t('notYetVerified'),
              ),
              if (action.description.of(vm.english).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(action.description.of(vm.english)),
              ],
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('applicableTo')),
            Text(action.applicableTo.of(vm.english)),
            if (action.location != null) Text(action.location!.of(vm.english)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaperHeading(vm.t('stepPreview')),
            for (final step in widget.detail.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PaperTag('${step.position}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title.of(vm.english)),
                          if (step.notes != null && step.notes!.isNotEmpty)
                            Text(
                              step.notes!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Palette.muted,
                              ),
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
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('sources')),
            for (final source in widget.detail.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SourceLine(source: source),
              ),
          ],
        ),
        FilledButton(
          key: const Key('start-action'),
          onPressed: _starting
              ? null
              : () async {
                  if (open != null) {
                    context.push('/actions/${action.id}/progress');
                    return;
                  }
                  if (!ensureSignedIn(context)) return;
                  setState(() => _starting = true);
                  final started = await vm.startAction(action.id);
                  if (!mounted) return;
                  setState(() => _starting = false);
                  if (started != null && context.mounted) {
                    context.push('/actions/${action.id}/progress');
                  }
                },
          child: Text(
            open != null ? vm.t('continueAction') : vm.t('startAction'),
          ),
        ),
      ],
    );
  }
}

class SourceLine extends StatelessWidget {
  const SourceLine({super.key, required this.source});
  final SourceInfo source;
  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          source.title,
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
        Text(
          '${source.publisher} · ${source.evidenceNote}',
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
                      onPressed: _reason == null
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
                    if (ok && context.mounted) context.go('/');
                  },
            child: Text(vm.t('send')),
          ),
      ],
    );
  }
}
