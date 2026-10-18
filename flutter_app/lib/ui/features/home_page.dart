import 'package:flutter/material.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'post_cards.dart';

/// Home: the official account pinned on top, then students' posts, newest first.
/// Official guides live on the official account's page, not in this feed.
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
        ResourceView<ExperiencePage>(
          resource: (vm) => vm.posts(),
          load: (vm) => vm.loadPosts(),
          builder: (context, page) => _Feed(page: page),
        ),
      ],
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.page});
  final ExperiencePage page;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardList(
          gap: 16,
          children: [for (final e in page.items) StudentPostCard(item: e)],
        ),
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

const welcomeTitle = ('初次來台灣？可以來這邊看看', 'New to Taiwan? Have a look here');
const _welcomeBody = (
  '先從機場到校園安頓好，接著申請在學證明，再申請居留證。開銀行帳戶、打工都要先有居留證，'
      '順序對了可以少跑很多趟。下面是官方發的貼文，照需要的時候看就好。',
  'Settle in on campus first, then get a certificate of enrollment and apply '
      'for your ARC. Opening a bank account and part-time work both need the ARC, '
      'so doing things in this order saves trips. Below are the official posts; '
      'read them when you need them.',
);

/// The official account: who it is, a short note for new arrivals, and its posts.
class OfficialAccountPage extends StatelessWidget {
  const OfficialAccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      gap: 16,
      children: [
        NoteCard(
          key: const Key('official-account'),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Avatar(size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Culture Bridge',
                            style: displayStyle(20),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _OfficialBadge(vm.pair('官方帳號', 'Official account')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                vm.pair(welcomeTitle.$1, welcomeTitle.$2),
                style: displayStyle(17),
              ),
              const SizedBox(height: 6),
              Text(
                vm.pair(_welcomeBody.$1, _welcomeBody.$2),
                style: const TextStyle(fontSize: 15, height: 1.75),
              ),
            ],
          ),
        ),
        ResourceView<List<ActionSummary>>(
          resource: (vm) => vm.actions,
          load: (vm) => vm.loadActions(),
          builder: (context, actions) => _OfficialPosts(actions: actions),
        ),
      ],
    );
  }
}

class _OfficialPosts extends StatelessWidget {
  const _OfficialPosts({required this.actions});
  final List<ActionSummary> actions;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final newest = [...actions]
      ..sort(
        (a, b) => (b.publishedAt ?? DateTime(2000)).compareTo(
          a.publishedAt ?? DateTime(2000),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          vm.pair('官方貼文', 'Official posts'),
          note: vm.pair('${newest.length} 篇', '${newest.length}'),
        ),
        const SizedBox(height: 12),
        CardList(
          gap: 16,
          children: [
            for (final a in newest)
              OfficialPostCard(
                id: a.id,
                title: a.title.of(vm.english),
                publishedAt: a.publishedAt,
              ),
          ],
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

/// 「官方帳號」 in golden yellow letters with a light sweeping across them.
/// The shine plays twice, then rests; it is skipped when the system asks for less motion.
class _OfficialBadge extends StatefulWidget {
  const _OfficialBadge(this.label);
  final String label;
  @override
  State<_OfficialBadge> createState() => _OfficialBadgeState();
}

class _OfficialBadgeState extends State<_OfficialBadge>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFE0A100);
  static const _glint = Color(0xFFFFE680);
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shine.value = 1;
    } else if (!_shine.isAnimating && _shine.value == 0) {
      _shine
          .forward()
          .then((_) => _shine.forward(from: 0))
          .catchError((_) {}, test: (e) => e is TickerCanceled);
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shine,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final x = -1 + 3 * _shine.value;
        return LinearGradient(
          begin: Alignment(x - .5, 0),
          end: Alignment(x + .5, 0),
          colors: const [_gold, _glint, _gold],
          stops: const [.35, .5, .65],
        ).createShader(bounds);
      },
      child: child,
    ),
    child: Text(
      widget.label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
        color: _gold,
        // A faint edge so the yellow letters hold up on the cream card.
        shadows: [Shadow(color: Color(0x33000000), blurRadius: .5)],
      ),
    ),
  );
}
