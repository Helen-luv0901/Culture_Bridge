import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system.dart';
import '../../domain/models.dart';

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
          for (final action in vm.actions) ...[
            ActionSlip(action: action),
            const SizedBox(height: 10),
          ],
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

class ActionSlip extends StatelessWidget {
  const ActionSlip({super.key, required this.action});
  final ActionItem action;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final icons = {
      'work-permit': 'permit',
      'arc': 'arc',
      'insurance': 'nhi',
      'bank': 'bank',
      'enrollment': 'enroll',
    };
    final status = action.text('status', false) == 'Needs Review'
        ? 'needsReview'
        : action.text('status', false) == 'Community Supported'
        ? 'communitySupported'
        : 'verified';
    return PaperCard(
      padding: const EdgeInsets.all(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        leading: Container(
          color: Palette.oat,
          padding: const EdgeInsets.all(10),
          child: InkIcon(icons[action.id] ?? 'enroll'),
        ),
        title: Text(
          action.text('title', vm.english),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              '${vm.t('lastUpdated')}: ${action.text('verifiedAt', false)}',
              style: const TextStyle(
                fontFamily: 'CourierPrime',
                fontFamilyFallback: ['NotoSerifTC'],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            PaperTag(
              vm.t(status),
              color: status == 'needsReview' ? Palette.ochre : Palette.paleMoss,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/actions/${action.id}'),
      ),
    );
  }
}

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key, required this.topic});
  final String topic;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final items = vm.filtered(topic);
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
        const SizedBox(height: 18),
        Text(
          vm.t('exploreNote'),
          style: const TextStyle(
            color: Palette.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 24),
        if (items.isEmpty)
          Text(
            vm.pair(
              '目前沒有此分類的經驗，可以分享你的第一則。',
              'No experiences yet. Share the first one.',
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final columns =
                MediaQuery.sizeOf(context).width > 1100 && c.maxWidth > 800
                ? 2
                : 1;
            final width = (c.maxWidth - (columns - 1) * 24) / columns;
            return Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: ExperienceCard(
                      experience: item,
                      from: '/explore${topic == 'all' ? '' : '?topic=$topic'}',
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
  final Experience experience;
  final String from;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final translated = vm.translated(experience.id);
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
              PaperTag(vm.t(experience.topic)),
              PaperTag(vm.t(experience.identity)),
              PaperTag(vm.t('anonymousShare')),
            ],
          ),
          if (translated)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                vm.t('translatedFrom'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            '「${experience.text('originalVoice', translated)}」',
            style: const TextStyle(
              fontSize: 21,
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${vm.t('aiSummary')}: ${experience.text('summary', translated)}',
          ),
          const SizedBox(height: 16),
          const Divider(color: Palette.edge),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${experience.reactions} ${vm.t('reactions')}',
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
              TextButton.icon(
                onPressed: () => vm.toggleHelpful(experience.id),
                icon: Icon(
                  vm.helpful(experience.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 18,
                ),
                label: Text(
                  '${experience.helpfulCount + (vm.helpful(experience.id) ? 1 : 0)} ${vm.t('foundHelpful')}',
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => vm.toggleTranslation(experience.id),
              child: Text(
                translated
                    ? vm.t('showOriginal')
                    : vm.english
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
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = vm.experience(id);
    if (item == null) return const MissingContent();
    final translated = vm.translated(id);
    final others = vm.experiences.where(
      (e) => e.topic == item.topic && e.id != id,
    );
    return FlowBody(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PaperTag(vm.t(item.topic)),
            PaperTag(vm.t(item.identity)),
            PaperTag(vm.t('anonymousShare')),
          ],
        ),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('originalShare')),
              Text(
                '「${item.text('originalVoice', translated)}」',
                style: const TextStyle(
                  fontSize: 25,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
              TextButton(
                onPressed: () => vm.toggleTranslation(id),
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
              Text(item.text('summary', translated)),
              const SizedBox(height: 18),
              Text(
                vm.t('reminder'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(item.text('reminder', translated)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaperHeading(vm.t('differentExperiences')),
            if (others.isEmpty)
              Text(
                vm.pair(
                  '目前尚無其他同主題的補充經驗。',
                  'No other stories in this topic yet.',
                ),
              ),
            for (final other in others)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PaperTag(vm.t(other.identity)),
                      const SizedBox(height: 12),
                      Text(other.text('originalVoice', vm.english)),
                      TextButton(
                        onPressed: () => context.push(
                          '/experiences/${other.id}?from=${Uri.encodeComponent('/experiences/$id')}',
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
          onPressed: () => context.go('/share'),
          child: Text(vm.t('myExperienceDifferent')),
        ),
        Wrap(
          spacing: 12,
          children: [
            FilterChip(
              label: Text(vm.t('iAlsoExperienced')),
              selected: vm.experienced(id),
              onSelected: (_) => vm.toggleExperienced(id),
            ),
            FilterChip(
              label: Text(vm.t('helpful')),
              selected: vm.helpful(id),
              onSelected: (_) => vm.toggleHelpful(id),
            ),
          ],
        ),
      ],
    );
  }
}

class MissingContent extends StatelessWidget {
  const MissingContent({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Text(
          vm.pair(
            '找不到這筆內容，請回首頁選擇。',
            'This content could not be found. Choose an item from Home.',
          ),
        ),
        TextButton(onPressed: () => context.go('/'), child: Text(vm.t('home'))),
      ],
    );
  }
}
