import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system.dart';
import 'browse_pages.dart';

class ActionDetailPage extends StatelessWidget {
  const ActionDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = vm.action(id);
    if (item == null) return const MissingContent();
    final steps = item.list('steps', vm.english);
    return FlowBody(
      children: [
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.text('title', vm.english), style: displayStyle(25)),
              const SizedBox(height: 12),
              PaperTag(
                vm.t(
                  item.text('status', false) == 'Needs Review'
                      ? 'needsReview'
                      : item.text('status', false) == 'Community Supported'
                      ? 'communitySupported'
                      : 'verified',
                ),
                color: Palette.paleMoss,
              ),
              const SizedBox(height: 16),
              Text(
                '${item.text('recentCompletions', false)} ${vm.t('recentlyCompleted')}',
              ),
              Text(
                '${vm.t('lastOfficialUpdate')}: ${item.text('verifiedAt', false)}',
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('applicableTo')),
            Text(item.text('applicableTo', vm.english)),
            Text(item.text('location', vm.english)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaperHeading(vm.t('stepPreview')),
            for (int i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PaperTag('${i + 1}'),
                    const SizedBox(width: 12),
                    Expanded(child: Text(steps[i])),
                  ],
                ),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('sources')),
            for (final source in item.list('sources', vm.english))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(source),
              ),
            Text(
              vm.pair(
                '來源名稱沿用原型，尚未連接實際驗證服務。',
                'Source labels are sample content; verification services are not connected.',
              ),
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          ],
        ),
        FilledButton(
          key: const Key('start-action'),
          onPressed: () {
            vm.startAction(id);
            context.push('/actions/$id/progress');
          },
          child: Text(vm.t('startAction')),
        ),
      ],
    );
  }
}

class ActionProgressPage extends StatelessWidget {
  const ActionProgressPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = vm.action(id);
    if (item == null) return const MissingContent();
    final steps = item.list('steps', vm.english);
    final done = vm.completed(id);
    return FlowBody(
      children: [
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('myActionProgress')),
              Text(item.text('title', vm.english), style: displayStyle(25)),
              const SizedBox(height: 14),
              Text('${vm.t('progress')}: ${done.length} / ${steps.length}'),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: steps.isEmpty ? 0 : done.length / steps.length,
                backgroundColor: Palette.edge,
                color: Palette.moss,
                minHeight: 8,
              ),
            ],
          ),
        ),
        for (int i = 0; i < steps.length; i++)
          PaperCard(
            color: done.contains(i) ? Palette.paleMoss : Palette.high,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  key: Key('step-$i'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(steps[i]),
                  value: done.contains(i),
                  onChanged: (_) => vm.toggleStep(id, i),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!done.contains(i))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => vm.setStuck(id, i),
                      child: Text(vm.t('imStuck')),
                    ),
                  ),
                if (vm.stuck(id) == i) ...[
                  Text(vm.t('actionWhatHappened')),
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
                          selected: vm.differences('$id:$i').contains(reason),
                          onSelected: (_) =>
                              vm.toggleDifference('$id:$i', reason),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        FilledButton(
          key: const Key('complete-action'),
          onPressed: () => context.push('/actions/$id/complete'),
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
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = vm.action(id);
    if (item == null) return const MissingContent();
    return FlowBody(
      children: [
        Text(
          vm
              .t('completionQuestion')
              .replaceAll('{action}', item.text('title', vm.english)),
          style: displayStyle(25),
        ),
        Text(vm.t('feedbackHelpsNext')),
        for (final outcome in ['success', 'different', 'failed'])
          PaperCard(
            color: vm.outcome(id) == outcome ? Palette.paleMoss : Palette.high,
            padding: EdgeInsets.zero,
            child: RadioGroup<String>(
              groupValue: vm.outcome(id),
              onChanged: (value) => vm.setOutcome(id, value!),
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
        if (vm.outcome(id) == 'different')
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
                        selected: vm.differences(id).contains(category),
                        onSelected: (_) => vm.toggleDifference(id, category),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (vm.outcome(id) != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              vm.pair(
                '已記錄本次預覽回饋，尚未送交審核。',
                'Your preview feedback is recorded in this session; it has not been submitted.',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => context.go('/'),
            child: Text(vm.t('home')),
          ),
        ],
      ],
    );
  }
}
