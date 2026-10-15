import 'package:flutter/material.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'post_cards.dart';

/// Home: every post, newest first, with the welcome guide pinned on top.
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      gap: 16,
      children: [
        OfficialPostCard(
          id: welcomeGuideId,
          title: vm.pair(welcomeTitle.$1, welcomeTitle.$2),
          pinned: true,
        ),
        ResourceView<List<ActionSummary>>(
          resource: (vm) => vm.actions,
          load: (vm) => vm.loadActions(),
          builder: (context, actions) => ResourceView<ExperiencePage>(
            resource: (vm) => vm.posts(),
            load: (vm) => vm.loadPosts(),
            builder: (context, page) => _Feed(actions: actions, page: page),
          ),
        ),
      ],
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.actions, required this.page});
  final List<ActionSummary> actions;
  final ExperiencePage page;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final oldestPost = page.items.isEmpty ? null : page.items.last.publishedAt;
    // Guides older than the last loaded post wait until more posts are loaded,
    // so the order stays newest first as the list grows.
    final guides = [
      for (final a in actions)
        if (page.nextOffset == null ||
            oldestPost == null ||
            !(a.publishedAt ?? DateTime(2000)).isBefore(oldestPost))
          a,
    ];
    final entries = <(DateTime, Widget)>[
      for (final a in guides)
        (
          a.publishedAt ?? DateTime(2000),
          OfficialPostCard(
            id: a.id,
            title: a.title.of(vm.english),
            publishedAt: a.publishedAt,
          ),
        ),
      for (final e in page.items) (e.publishedAt, StudentPostCard(item: e)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardList(gap: 16, children: [for (final e in entries) e.$2]),
        if (page.nextOffset != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton(
              onPressed: vm.posts().loading
                  ? null
                  : () => vm.loadPosts(null, true),
              child: Text(vm.t('loadMore')),
            ),
          ),
      ],
    );
  }
}

const welcomeTitle = ('初次來台灣？先看這篇', 'New to Taiwan? Start here');
const _welcomeBody = (
  '先從機場到校園安頓好，接著申請在學證明，再申請居留證。開銀行帳戶、打工都要先有居留證，'
      '順序對了可以少跑很多趟。下面幾篇官方指南，照需要的時候看就好。',
  'Settle in on campus first, then get a certificate of enrollment and apply '
      'for your ARC. Opening a bank account and part-time work both need the ARC, '
      'so doing things in this order saves trips. Read the official guides below '
      'when you need them.',
);

/// The pinned welcome guide: a short note and every official guide.
class WelcomeGuidePage extends StatelessWidget {
  const WelcomeGuidePage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        OfficialByline(when: vm.pair('置頂', 'Pinned')),
        PageTitle(vm.pair(welcomeTitle.$1, welcomeTitle.$2)),
        Text(
          vm.pair(_welcomeBody.$1, _welcomeBody.$2),
          style: const TextStyle(fontSize: 16, height: 1.75),
        ),
        SectionLabel(vm.pair('官方指南', 'Official guides')),
        ResourceView<List<ActionSummary>>(
          resource: (vm) => vm.actions,
          load: (vm) => vm.loadActions(),
          builder: (context, actions) => GuideList(actions: actions),
        ),
      ],
    );
  }
}

/// Official guides as one card of rows (search results, the welcome guide).
class GuideList extends StatelessWidget {
  const GuideList({super.key, required this.actions});
  final List<ActionSummary> actions;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return NoteCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const DashedRule(),
            InkWell(
              key: Key('guide-row-${a.id}'),
              onTap: () => openGuide(context, a.id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Avatar(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          a.title.of(vm.english),
                          style: displayStyle(
                            15,
                            color: vm.isRead('guide:${a.id}')
                                ? Palette.readInk
                                : Palette.ink,
                          ),
                        ),
                      ),
                      const AppIcon(
                        'chevron',
                        size: 18,
                        color: Palette.control,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
