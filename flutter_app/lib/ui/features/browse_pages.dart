import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/loading.dart';

export '../core/loading.dart' show MissingContent;

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final actionPanel = PaperCard(
      tape: true,
      color: Palette.paleMoss,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(vm.t('startAction'), badge: vm.t('officialProcess')),
          ResourceView<List<ActionSummary>>(
            resource: (vm) => vm.actions,
            load: (vm) => vm.loadActions(),
            builder: (context, actions) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final action in actions) ...[
                  ActionSlip(action: action),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final lifePanel = PaperCard(
      tape: true,
      color: Palette.slate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(vm.t('lifeInTaiwan'), badge: vm.t('studentExperiences')),
          for (final topic in ['lifeAdaptation', 'cultureCommunication']) ...[
            PaperCard(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: InkIcon(topic == 'lifeAdaptation' ? 'sprout' : 'talk'),
                title: Text(vm.t(topic)),
                subtitle: Text(
                  vm.t(
                    topic == 'lifeAdaptation'
                        ? 'lifeDescription'
                        : 'cultureDescription',
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/explore?topic=$topic'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperCard(
          color: Palette.oat,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.pair(
                        '讓在台灣的生活，慢慢變得熟悉。',
                        'Make yourself at home in Taiwan.',
                      ),
                      style: displayStyle(28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vm.pair(
                        '找到下一步，也看看其他學生如何經歷相似的情境。',
                        'Find your next step, or see how other students experienced a similar situation.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go('/explore'),
                      child: Text(
                        '${vm.pair('探索學生的生活經驗', 'Explore student experiences')} →',
                      ),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 767)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Image.asset(
                    'assets/images/botanical-4.png',
                    width: 80,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          ),
        ),
        if (vm.signedIn) ...[
          const SizedBox(height: 24),
          const MyProgressPanel(),
        ],
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, c) {
            if (MediaQuery.sizeOf(context).width > 1100 && c.maxWidth > 800) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: actionPanel),
                  const SizedBox(width: 28),
                  Expanded(flex: 10, child: lifePanel),
                ],
              );
            }
            return Column(
              children: [actionPanel, const SizedBox(height: 24), lifePanel],
            );
          },
        ),
      ],
    );
  }
}

/// "My procedures" on Home (product-map §17A): the procedures in progress.
class MyProgressPanel extends StatelessWidget {
  const MyProgressPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return ResourceView<List<Execution>>(
      resource: (vm) => vm.executions,
      load: (vm) => vm.loadExecutions(),
      builder: (context, executions) {
        if (executions.isEmpty) return const SizedBox.shrink();
        return PaperCard(
          color: Palette.high,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaperHeading(vm.t('myActionProgress')),
              for (final e in executions)
                Padding(
                  key: Key('progress-${e.actionId}'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title.of(vm.english),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${vm.t('progress')}: ${e.doneCount} / ${e.steps.length}',
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: e.steps.isEmpty
                            ? 0
                            : e.doneCount / e.steps.length,
                        backgroundColor: Palette.edge,
                        color: Palette.moss,
                        minHeight: 6,
                      ),
                      // Below the bar, not beside it, so long labels and large text fit.
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              context.push('/actions/${e.actionId}/progress'),
                          child: Text(vm.t('continueAction')),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => PaperTag(
    BridgeScope.of(context).t(statusKey(status)),
    color: switch (status) {
      'verified' => Palette.paleMoss,
      'needs_review' || 'outdated' => Palette.ochre,
      _ => Palette.oat,
    },
  );
}

class ActionSlip extends StatelessWidget {
  const ActionSlip({super.key, required this.action});
  final ActionSummary action;
  static const _icons = {
    'work-permit': 'permit',
    'arc': 'arc',
    'insurance': 'nhi',
    'bank': 'bank',
    'certificate': 'enroll',
    'transport': 'compass',
  };
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return PaperCard(
      padding: const EdgeInsets.all(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        leading: Container(
          color: Palette.oat,
          padding: const EdgeInsets.all(10),
          child: InkIcon(_icons[action.id] ?? 'enroll'),
        ),
        title: Text(
          action.title.of(vm.english),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            if (action.lastVerifiedAt != null)
              Text(
                '${vm.t('lastUpdated')}: ${formatDate(action.lastVerifiedAt)}',
                style: const TextStyle(
                  fontFamily: 'CourierPrime',
                  fontFamilyFallback: ['NotoSerifTC'],
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 6),
            StatusTag(action.verificationStatus),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/actions/${action.id}'),
      ),
    );
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.topic});
  final String topic;
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final topic = widget.topic;
    final from = '/explore${topic == 'all' ? '' : '?topic=$topic'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final filter in [
              'all',
              'lifeAdaptation',
              'cultureCommunication',
            ])
              ChoiceChip(
                label: Text(vm.t(filter)),
                selected: topic == filter,
                onSelected: (_) => context.go(
                  '/explore${filter == 'all' ? '' : '?topic=$filter'}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('explore-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: vm.t('searchExperiences'),
            prefixIcon: const Icon(Icons.search),
          ),
          onSubmitted: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 18),
        Text(
          vm.t('exploreNote'),
          style: const TextStyle(
            color: Palette.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 24),
        ResourceView<ExperiencePage>(
          key: ValueKey('$topic|$_query'),
          resource: (vm) => vm.explore(topic, _query),
          load: (vm) => vm.loadExplore(topic, query: _query),
          builder: (context, page) {
            if (page.items.isEmpty) {
              return Text(
                vm.pair(
                  '目前沒有符合的經驗，可以分享你的第一則。',
                  'No experiences here yet. Share the first one.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final columns =
                        MediaQuery.sizeOf(context).width > 1100 &&
                            c.maxWidth > 800
                        ? 2
                        : 1;
                    final width = (c.maxWidth - (columns - 1) * 24) / columns;
                    return Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      children: [
                        for (final item in page.items)
                          SizedBox(
                            width: width,
                            child: ExperienceCard(experience: item, from: from),
                          ),
                      ],
                    );
                  },
                ),
                if (page.nextOffset != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: OutlinedButton(
                      onPressed: vm.explore(topic, _query).loading
                          ? null
                          : () => vm.loadExplore(
                              topic,
                              query: _query,
                              more: true,
                            ),
                      child: Text(vm.t('loadMore')),
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

class ExperienceCard extends StatelessWidget {
  const ExperienceCard({
    super.key,
    required this.experience,
    this.from = '/explore',
  });
  final ExperienceItem experience;
  final String from;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final translated = vm.translated(experience);
    return PaperCard(
      tape: true,
      color: Palette.slate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PaperTag(vm.t(topicKey(experience.topicId))),
              PaperTag(vm.t(identityKey(experience.identityType))),
              PaperTag(vm.t('anonymousShare')),
            ],
          ),
          if (translated)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                vm.t('aiTranslated'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            '「${experience.voice(translated)}」',
            style: const TextStyle(
              fontSize: 21,
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Text('${vm.t('aiSummary')}: ${experience.summaryText(translated)}'),
          const SizedBox(height: 16),
          const Divider(color: Palette.edge),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${experience.differentCount} ${vm.t('reactions')}',
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
              SaveButton(item: experience),
              TextButton.icon(
                onPressed: () {
                  if (ensureSignedIn(context)) {
                    vm.toggleReaction(experience, 'helpful');
                  }
                },
                icon: Icon(
                  vm.reacted(experience, 'helpful')
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 18,
                ),
                label: Text(
                  '${experience.helpfulCount} ${vm.t('foundHelpful')}',
                ),
              ),
              TextButton(
                onPressed: () => context.push(
                  '/experiences/${experience.id}?from=${Uri.encodeComponent(from)}',
                ),
                child: Text(vm.t('similarSituations')),
              ),
            ],
          ),
          if (vm.canTranslate(experience))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => vm.toggleTranslation(experience),
                child: Text(
                  translated
                      ? vm.t('showOriginal')
                      : experience.translation != null
                      ? vm.t('showTranslation')
                      : vm.t('translate'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ExperienceDetailPage extends StatelessWidget {
  const ExperienceDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => ResourceView<ExperienceDetail>(
    key: ValueKey(id),
    resource: (vm) => vm.experience(id),
    load: (vm) => vm.loadExperience(id),
    builder: (context, detail) => _ExperienceDetail(detail: detail),
  );
}

class _ExperienceDetail extends StatelessWidget {
  const _ExperienceDetail({required this.detail});
  final ExperienceDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = detail.item;
    final translated = vm.translated(item);
    return FlowBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PaperTag(vm.t(topicKey(item.topicId))),
                  PaperTag(vm.t(identityKey(item.identityType))),
                  PaperTag(vm.t('anonymousShare')),
                ],
              ),
            ),
            SaveButton(item: item),
            ModerationMenu(experienceId: item.id),
          ],
        ),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('originalShare')),
              Text(
                '「${item.voice(translated)}」',
                style: const TextStyle(
                  fontSize: 25,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
              if (translated)
                Text(
                  vm.t('aiTranslated'),
                  style: const TextStyle(fontSize: 13, color: Palette.muted),
                ),
              if (vm.canTranslate(item))
                TextButton(
                  onPressed: () => vm.toggleTranslation(item),
                  child: Text(
                    translated ? vm.t('showOriginal') : vm.t('translate'),
                  ),
                ),
            ],
          ),
        ),
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('aiSummaryConfirmed')),
              Text(item.summaryText(translated)),
              const SizedBox(height: 18),
              Text(
                vm.t('reminder'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(item.reminderText(translated)),
              const SizedBox(height: 12),
              Text(
                vm.t('notVerifiedNote'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaperHeading(vm.t('differentExperiences')),
            if (detail.different.isEmpty)
              Text(
                vm.pair(
                  '還沒有學生分享不同的經驗。',
                  'No one has shared a different experience yet.',
                ),
              ),
            for (final other in detail.different)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PaperTag(vm.t(identityKey(other.identityType))),
                      const SizedBox(height: 12),
                      Text(other.voice(vm.translated(other))),
                      TextButton(
                        onPressed: () => context.push(
                          '/experiences/${other.id}?from=${Uri.encodeComponent('/experiences/${item.id}')}',
                        ),
                        child: Text(vm.t('similarSituations')),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        FilledButton(
          onPressed: () {
            if (!ensureSignedIn(context)) return;
            vm.startDifferentExperience(item.id);
            context.go('/share');
          },
          child: Text(vm.t('myExperienceDifferent')),
        ),
        Wrap(
          spacing: 12,
          children: [
            FilterChip(
              label: Text(
                '${vm.t('iAlsoExperienced')} · ${item.experiencedTooCount}',
              ),
              selected: vm.reacted(item, 'experienced_too'),
              onSelected: (_) {
                if (ensureSignedIn(context)) {
                  vm.toggleReaction(item, 'experienced_too');
                }
              },
            ),
            FilterChip(
              label: Text('${vm.t('helpful')} · ${item.helpfulCount}'),
              selected: vm.reacted(item, 'helpful'),
              onSelected: (_) {
                if (ensureSignedIn(context)) vm.toggleReaction(item, 'helpful');
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Bookmark: keeps an experience in the reader's private "read later" list under My.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.item});
  final ExperienceItem item;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return IconButton(
      key: Key('save-${item.id}'),
      tooltip: item.saved ? vm.t('unsave') : vm.t('save'),
      isSelected: item.saved,
      color: Palette.moss,
      icon: const Icon(Icons.bookmark_border),
      selectedIcon: const Icon(Icons.bookmark),
      onPressed: () {
        if (ensureSignedIn(context)) vm.toggleSaved(item);
      },
    );
  }
}

/// Report or block from an experience (B-18, B-19; Google Play UGC policy).
class ModerationMenu extends StatelessWidget {
  const ModerationMenu({super.key, required this.experienceId});
  final String experienceId;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return PopupMenuButton<String>(
      key: const Key('moderation-menu'),
      tooltip: vm.t('report'),
      icon: const Icon(Icons.more_horiz),
      onSelected: (choice) async {
        if (!ensureSignedIn(context)) return;
        if (choice == 'report') {
          await showDialog<void>(
            context: context,
            builder: (_) => BridgeScope(
              viewModel: vm,
              child: ReportDialog(experienceId: experienceId),
            ),
          );
        } else {
          final ok = await confirmDialog(
            context,
            vm.t('blockAuthor'),
            vm.t('blockConfirm'),
          );
          if (ok && await vm.blockAuthor(experienceId) && context.mounted) {
            context.go('/explore');
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'report', child: Text(vm.t('report'))),
        PopupMenuItem(value: 'block', child: Text(vm.t('blockAuthor'))),
      ],
    );
  }
}

class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key, required this.experienceId});
  final String experienceId;
  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _reason;
  final _note = TextEditingController();
  static const reasons = {
    'spam': ('垃圾訊息或廣告', 'Spam or advertising'),
    'harassment': ('騷擾或霸凌', 'Harassment or bullying'),
    'hate': ('仇恨或歧視', 'Hate or discrimination'),
    'sexual': ('色情內容', 'Sexual content'),
    'personal_info': ('洩漏個人資料', 'Personal information'),
    'misinformation': ('錯誤或誤導的資訊', 'False or misleading information'),
    'other': ('其他', 'Other'),
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return AlertDialog(
      title: Text(vm.t('reportTitle')),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _reason,
          onChanged: (value) => setState(() => _reason = value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in reasons.entries)
                RadioListTile<String>(
                  value: entry.key,
                  title: Text(vm.pair(entry.value.$1, entry.value.$2)),
                ),
              TextField(
                controller: _note,
                maxLength: 1000,
                decoration: InputDecoration(labelText: vm.t('tellMore')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(vm.t('cancel')),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () async {
                  await vm.report(widget.experienceId, _reason!, _note.text);
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(vm.t('send')),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String body,
) async {
  final vm = BridgeScope.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(vm.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(vm.t('confirm')),
            ),
          ],
        ),
      ) ??
      false;
}
