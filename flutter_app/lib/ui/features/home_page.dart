import 'package:flutter/material.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../core/loading.dart';
import 'post_cards.dart';

/// Home, like a forum's front page: the boards, then students' posts as cards, newest or
/// popular.
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
                              fontFamily: appFont,
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
          watch: (vm, on) => vm.watchPosts(filter, _sort, on),
          retry: (vm) => vm.loadPosts(
            filter,
            vm.posts(filter, _sort).data?.nextOffset != null,
            _sort,
          ),
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
