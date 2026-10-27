import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';
import 'guide_stages.dart';
import 'post_cards.dart';

/// Home, like a forum's front page: the boards, one pinned row for the first-month checklist
/// (students who have lived here a while can close it), then students' posts as cards,
/// newest or popular.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _category = 'all';
  String _sort = 'new';
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final filter = _category == 'all' ? null : _category;
    return FlowBody(
      gap: 22,
      children: [
        Semantics(
          label: vm.pair('看板', 'Boards'),
          container: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final key in categoryLabels.keys)
                  if (key != 'official')
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: NoteChip(
                        key: Key('home-board-$key'),
                        dense: true,
                        label: categoryName(vm, key),
                        selected: _category == key,
                        onTap: () => setState(() => _category = key),
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (!vm.settled) const _PinnedChecklist(),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: vm.pair('排序', 'Sort'),
              container: true,
              child: Wrap(
                spacing: 4,
                children: [
                  for (final (value, zh, en) in [
                    ('new', '最新', 'Newest'),
                    ('hot', '熱門', 'Popular'),
                  ])
                    MergeSemantics(
                      child: Semantics(
                        selected: _sort == value,
                        child: TextButton(
                          key: Key('home-sort-$value'),
                          style: TextButton.styleFrom(
                            backgroundColor: _sort == value
                                ? Palette.high
                                : Colors.transparent,
                            foregroundColor: _sort == value
                                ? Palette.ink
                                : Palette.muted,
                            textStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: _sort == value
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: () => setState(() => _sort = value),
                          child: Text(vm.pair(zh, en)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Wider screens write from the header's button.
            if (AppLayout.of(context) == AppLayout.phone)
              TextButton(
                key: const Key('home-share'),
                onPressed: () => startSharing(context),
                child: Text(vm.pair('發文', 'Write a post')),
              ),
          ],
        ),
        ResourceView<ExperiencePage>(
          key: ValueKey('home-$_category-$_sort'),
          resource: (vm) => vm.posts(filter, _sort),
          load: (vm) => vm.loadPosts(filter, false, _sort),
          builder: (context, page) => page.items.isEmpty
              ? EmptyNote(
                  title: vm.pair('這個看板還沒有貼文', 'No posts here yet'),
                  body: vm.pair(
                    '遇過相關的事嗎？寫一句話，幫下一位學生。',
                    'Been through something like this? A sentence helps the next student.',
                  ),
                  action: vm.pair('發文', 'Write a post'),
                  onAction: () => startSharing(context),
                )
              : _Feed(page: page, filter: filter, sort: _sort),
        ),
      ],
    );
  }
}

/// The first-month checklist as one pinned card with its progress; the × hides it for
/// settled students.
class _PinnedChecklist extends StatefulWidget {
  const _PinnedChecklist();
  @override
  State<_PinnedChecklist> createState() => _PinnedChecklistState();
}

class _PinnedChecklistState extends State<_PinnedChecklist> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = BridgeScope.of(context);
      if (vm.actions.needsLoad) vm.loadActions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final firstMonth = [
      for (final (stage, guides) in guidesByStage(vm.actions.data ?? const []))
        if (guideStages.indexOf(stage) case final i
            when i >= 0 && i < firstMonthStages)
          ...guides,
    ];
    final read = firstMonth.where((g) => vm.isRead('guide:${g.id}')).length;
    // A strip of tape holds the pinned card, like a note in a scrapbook.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: paperShadow,
          child: Material(
            key: const Key('pinned-checklist'),
            color: Palette.high,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.card),
              side: const BorderSide(color: Palette.oat),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('open-checklist'),
                    onTap: () => context.go('/guides'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          const AppIcon('guide', size: 22, color: Palette.moss),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vm.pair(
                                    '來台第一個月要辦的事',
                                    'Your first month in Taiwan',
                                  ),
                                  style: displayStyle(15),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          Radii.pill,
                                        ),
                                        child: LinearProgressIndicator(
                                          value: firstMonth.isEmpty
                                              ? 0
                                              : read / firstMonth.length,
                                          minHeight: 6,
                                          color: Palette.moss,
                                          backgroundColor: Palette.chip,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        vm.pair(
                                          '已看 $read / ${firstMonth.length}',
                                          '$read of ${firstMonth.length} read',
                                        ),
                                        style: mutedStyle.copyWith(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('i-am-settled'),
                  tooltip: vm.pair(
                    '我在台灣一段時間了，不用顯示',
                    "I've been here a while; hide this",
                  ),
                  onPressed: () => vm.setSettled(true),
                  icon: const AppIcon('close', size: 18, color: Palette.muted),
                ),
              ],
            ),
          ),
        ),
        const Positioned(top: -9, left: 28, child: _Tape()),
      ],
    );
  }
}

/// A plain, straight strip of tape.
class _Tape extends StatelessWidget {
  const _Tape();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Container(
        width: 74,
        height: 18,
        color: Palette.brick.withValues(alpha: .28),
      ),
    ),
  );
}

/// The guide to read next in the first month (one being done comes first), or null.
(ActionSummary, GuideStage, bool)? nextGuide(
  BridgeViewModel vm,
  List<ActionSummary> actions,
) {
  final stages = [
    for (final group in guidesByStage(actions))
      if (guideStages.indexOf(group.$1) case final i
          when i >= 0 && i < firstMonthStages)
        group,
  ];
  for (final doing in [true, false]) {
    for (final (stage, guides) in stages) {
      for (final g in guides) {
        final match = doing
            ? vm.openExecution(g.id) != null
            : !vm.isRead('guide:${g.id}');
        if (match) return (g, stage, doing);
      }
    }
  }
  return null;
}

/// The one guide to open now, with a single clear action.
class _NextGuide extends StatelessWidget {
  const _NextGuide({
    required this.guide,
    required this.stage,
    required this.doing,
  });
  final ActionSummary guide;
  final GuideStage stage;
  final bool doing;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    void open() => doing
        ? context.push('/actions/${guide.id}/progress')
        : openGuide(context, guide.id);
    return NoteCard(
      key: const Key('next-guide'),
      borderColor: Palette.moss,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            doing
                ? vm.pair(
                    '繼續辦：${stage.title.$1}',
                    'Carry on: ${stage.title.$2}',
                  )
                : vm.pair('下一步：${stage.title.$1}', 'Next: ${stage.title.$2}'),
            style: mutedStyle,
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(guide.title.of(vm.english), style: displayStyle(21)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('open-next-guide'),
            onPressed: open,
            child: Text(
              doing
                  ? vm.pair('繼續辦理', 'Continue')
                  : vm.pair('從這篇開始', 'Start with this guide'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable row inside a card of rows, with a chevron.
class _ListRow extends StatelessWidget {
  const _ListRow({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 8),
            const AppIcon('chevron', size: 18, color: Palette.control),
          ],
        ),
      ),
    ),
  );
}

/// A numbered circle for an ordered step.
class StepNumber extends StatelessWidget {
  const StepNumber(this.number, {super.key});
  final int number;
  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Palette.high,
      shape: BoxShape.circle,
      border: Border.all(color: Palette.moss, width: 1.5),
    ),
    child: Text(
      '$number',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Palette.moss,
        height: 1,
      ),
    ),
  );
}

class _Feed extends StatelessWidget {
  const _Feed({required this.page, required this.filter, required this.sort});
  final ExperiencePage page;
  final String? filter;
  final String sort;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostList(items: page.items),
        if (page.nextOffset != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton(
              onPressed: vm.posts(filter, sort).loading
                  ? null
                  : () => vm.loadPosts(filter, true, sort),
              child: Text(vm.t('loadMore')),
            ),
          ),
      ],
    );
  }
}

/// The title of the old pinned welcome post (still in some students' saved list).
const welcomeTitle = ('初次來台灣？可以來這邊看看', 'New to Taiwan? Have a look here');
const _guidesNote = (
  '依來台後常見的順序排好；每篇都附原始公告，辦理前以公告為準。',
  'In the order most students need them. Each guide links its official sources.',
);

/// Every official guide, grouped by stage in the order they are usually done.
/// [stage] scrolls to that stage (/guides?stage=papers).
class GuidesPage extends StatelessWidget {
  const GuidesPage({super.key, this.stage});
  final String? stage;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      gap: 24,
      children: [
        Column(
          key: const Key('official-account'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTitle(vm.pair('官方指南', 'Official guides')),
            const SizedBox(height: 6),
            Text(
              vm.pair(_guidesNote.$1, _guidesNote.$2),
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
          ],
        ),
        ResourceView<List<ActionSummary>>(
          resource: (vm) => vm.actions,
          load: (vm) => vm.loadActions(),
          builder: (context, actions) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (nextGuide(vm, actions) case (final g, final st, final doing))
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _NextGuide(guide: g, stage: st, doing: doing),
                ),
              _StageSections(actions: actions, scrollTo: stage),
            ],
          ),
        ),
        if (vm.settled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('i-am-new'),
              onPressed: () => vm.setSettled(false),
              child: Text(
                vm.pair(
                  '把「來台第一個月」放回首頁置頂',
                  'Pin "Your first month" on Home again',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StageSections extends StatefulWidget {
  const _StageSections({required this.actions, this.scrollTo});
  final List<ActionSummary> actions;
  final String? scrollTo;
  @override
  State<_StageSections> createState() => _StageSectionsState();
}

class _StageSectionsState extends State<_StageSections> {
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _scrollToStage();
  }

  @override
  void didUpdateWidget(_StageSections old) {
    super.didUpdateWidget(old);
    if (old.scrollTo != widget.scrollTo) _scrollToStage();
  }

  void _scrollToStage() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = _keys[widget.scrollTo]?.currentContext;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final groups = guidesByStage(widget.actions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (stage, guides)) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 28),
          Row(
            key: _keys.putIfAbsent(stage.key, GlobalKey.new),
            children: [
              if (guideStages.indexOf(stage) case final n
                  when n >= 0 && n < firstMonthStages) ...[
                StepNumber(n + 1),
                const SizedBox(width: 12),
              ],
              Expanded(
                // Only as wide as the words, so the paper grid beside them is not
                // taken for the text's background.
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    header: true,
                    child: Text(
                      vm.pair(stage.title.$1, stage.title.$2),
                      style: displayStyle(19),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GuideList(actions: guides),
        ],
      ],
    );
  }
}

/// Official guides as one card of rows: the title, and whether it is being done or read.
class GuideList extends StatelessWidget {
  const GuideList({super.key, required this.actions});
  final List<ActionSummary> actions;
  @override
  Widget build(BuildContext context) => NoteCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const DashedRule(),
          _GuideRow(guide: a),
        ],
      ],
    ),
  );
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.guide});
  final ActionSummary guide;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final doing = vm.openExecution(guide.id) != null;
    final read = vm.isRead('guide:${guide.id}');
    final status = doing
        ? vm.pair('辦理中', 'In progress')
        : read
        ? vm.pair('已看過', 'Read')
        : null;
    return _ListRow(
      key: Key('guide-row-${guide.id}'),
      onTap: () => openGuide(context, guide.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            guide.title.of(vm.english),
            style: displayStyle(
              16,
              color: read && !doing ? Palette.muted : Palette.ink,
            ),
          ),
          if (status != null) ...[
            Text(
              status,
              style: TextStyle(
                fontSize: 13,
                fontWeight: doing ? FontWeight.w700 : FontWeight.w400,
                color: doing ? Palette.moss : Palette.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
