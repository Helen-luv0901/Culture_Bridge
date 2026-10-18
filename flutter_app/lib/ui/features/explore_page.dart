import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../core/loading.dart';
import 'assistant_panel.dart';
import 'home_page.dart';
import 'post_cards.dart';

/// Explore: category tabs, search across guides and posts, student posts by
/// newest or most popular, and hot tags. Official posts live on /official.
class ExplorePage extends StatelessWidget {
  const ExplorePage({
    super.key,
    required this.category,
    required this.query,
    this.sort = 'new',
  });

  /// 'all', 'official' (older links) or one of [postCategories].
  final String category;
  final String query;

  /// 'new' or 'hot'.
  final String sort;

  static String location(String category, String query, [String sort = 'new']) {
    final params = {
      if (category != 'all') 'cat': category,
      if (query.trim().isNotEmpty) 'q': query,
      if (sort == 'hot') 'sort': sort,
    };
    return Uri(
      path: '/explore',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final q = query.trim();
    final sidebar = AppLayout.of(context) != AppLayout.phone;
    return FlowBody(
      gap: 16,
      children: [
        _CategoryTabs(
          category: category,
          query: query,
          sort: sort,
          wrap: sidebar,
        ),
        // Wide layouts search from the header instead.
        if (!sidebar)
          SearchField(
            key: const Key('explore-search'),
            initial: query,
            category: category,
          ),
        if (q.isEmpty && category == 'official') const _OfficialFeed(),
        if (q.isEmpty && category != 'official')
          _PostFeed(category: category, sort: sort),
        if (q.isNotEmpty) ...[
          _AskAssistantRow(query: q),
          _SearchResults(query: q, category: category),
        ],
        if (q.isEmpty && category == 'all')
          _PopularTags(title: vm.pair('熱門標籤', 'Popular tags')),
      ],
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.category,
    required this.query,
    required this.sort,
    required this.wrap,
  });
  final String category;
  final String query;
  final String sort;
  final bool wrap;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final chips = [
      // Official posts have their own page (the official account), so no tab here.
      for (final key in categoryLabels.keys)
        if (key != 'official')
          NoteChip(
            key: Key('cat-$key'),
            label: categoryName(vm, key),
            selected: category == key,
            onTap: () => context.go(ExplorePage.location(key, query, sort)),
          ),
    ];
    return Semantics(
      label: vm.pair('分類', 'Categories'),
      container: true,
      child: wrap
          ? Wrap(spacing: 8, runSpacing: 8, children: chips)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, chip) in chips.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chip,
                  ],
                ],
              ),
            ),
    );
  }
}

/// Search box that keeps the query in the address (so back and links work).
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.initial,
    required this.category,
    this.compact = false,
  });
  final String initial;
  final String category;

  /// The header version on wide screens.
  final bool compact;
  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _controller = TextEditingController(text: widget.initial);
  Timer? _debounce;

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    // Follow the address when it changes elsewhere (a tag link, the category tabs).
    if (widget.initial != _controller.text && _debounce?.isActive != true) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(String value) {
    _debounce?.cancel();
    context.go(ExplorePage.location(widget.category, value));
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _go(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: _changed,
      onSubmitted: _go,
      decoration: InputDecoration(
        isDense: widget.compact,
        hintText: vm.pair('搜尋貼文、指南或 #標籤', 'Search posts, guides or #tags'),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: AppIcon('search', size: 20, color: Palette.muted),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 28),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: vm.pair('清除搜尋', 'Clear search'),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  _go('');
                },
                icon: const AppIcon('close', size: 18, color: Palette.muted),
              ),
      ),
    );
  }
}

class _OfficialFeed extends StatelessWidget {
  const _OfficialFeed();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return ResourceView<List<ActionSummary>>(
      resource: (vm) => vm.actions,
      load: (vm) => vm.loadActions(),
      builder: (context, actions) {
        final sorted = [...actions]
          ..sort(
            (a, b) => (b.publishedAt ?? DateTime(2000)).compareTo(
              a.publishedAt ?? DateTime(2000),
            ),
          );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              vm.pair('官方', 'Official'),
              note: vm.pair(
                '${sorted.length + 1} 篇 · 新的在上面',
                '${sorted.length + 1} · newest first',
              ),
            ),
            const SizedBox(height: 12),
            CardList(
              gap: 16,
              children: [
                OfficialPostCard(
                  id: welcomeGuideId,
                  title: vm.pair(welcomeTitle.$1, welcomeTitle.$2),
                  pinned: true,
                ),
                for (final a in sorted)
                  OfficialPostCard(
                    id: a.id,
                    title: a.title.of(vm.english),
                    publishedAt: a.publishedAt,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Student posts in a category (or all of them), newest or most popular first.
class _PostFeed extends StatelessWidget {
  const _PostFeed({required this.category, required this.sort});
  final String category;
  final String sort;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final all = category == 'all';
    final filter = all ? null : category;
    final name = all
        ? vm.pair('學生分享', 'Student posts')
        : categoryName(vm, category);
    return ResourceView<ExperiencePage>(
      key: ValueKey('$category-$sort'),
      resource: (vm) => vm.posts(filter, sort),
      load: (vm) => vm.loadPosts(filter, false, sort),
      builder: (context, page) {
        if (page.items.isEmpty) {
          return EmptyNote(
            title: all
                ? vm.pair('還沒有同學分享', 'No student posts yet')
                : vm.pair('「$name」還沒有貼文', 'No posts in $name yet'),
            body: vm.pair(
              '遇過相關的事嗎？寫一句話，幫下一位學生。',
              'Been through something like this? A sentence helps the next student.',
            ),
            action: all
                ? vm.pair('去分享', 'Share something')
                : vm.pair('分享到「$name」', 'Share in $name'),
            onAction: () {
              if (!all) vm.updateDraft(category: category);
              context.go('/share');
            },
          );
        }
        final more = page.nextOffset != null ? '+' : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                SectionLabel(
                  name,
                  note: vm.pair(
                    '${page.items.length}$more 篇',
                    '${page.items.length}$more',
                  ),
                ),
                _SortChips(category: category, sort: sort),
              ],
            ),
            const SizedBox(height: 12),
            CardList(
              children: [for (final e in page.items) StudentPostCard(item: e)],
            ),
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
      },
    );
  }
}

/// 最新 / 熱門: newest first, or by "me too" taps and comments.
class _SortChips extends StatelessWidget {
  const _SortChips({required this.category, required this.sort});
  final String category;
  final String sort;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Semantics(
      label: vm.pair('排序', 'Sort'),
      container: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (value, zh, en) in [
            ('new', '最新', 'Newest'),
            ('hot', '熱門', 'Popular'),
          ])
            NoteChip(
              key: Key('sort-$value'),
              label: vm.pair(zh, en),
              selected: sort == value,
              onTap: () =>
                  context.go(ExplorePage.location(category, '', value)),
            ),
        ],
      ),
    );
  }
}

class _AskAssistantRow extends StatelessWidget {
  const _AskAssistantRow({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return NoteCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: const Key('ask-assistant'),
        onTap: () => openAssistantFor(context, question: query),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Palette.paleMoss,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: AppIcon('spark', size: 20, color: Palette.moss),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.pair('問 AI 助理', 'Ask the AI assistant'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text('「$query」', style: mutedStyle),
                  ],
                ),
              ),
              const AppIcon('chevron', size: 18, color: Palette.control),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.category});
  final String query;
  final String category;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return ResourceView<SearchResults>(
      key: ValueKey(query),
      resource: (vm) => vm.search(query),
      load: (vm) => vm.loadSearch(query),
      builder: (context, results) {
        // A picked category narrows the search: 官方 only guides, a student category only its posts.
        final guides = category == 'all' || category == 'official'
            ? results.actions
            : const <ActionSummary>[];
        final posts = category == 'official'
            ? const <ExperienceItem>[]
            : [
                for (final e in results.experiences)
                  if (category == 'all' || e.categoryKey == category) e,
              ];
        if (guides.isEmpty && posts.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  vm.pair(
                    '找不到「$query」。換個關鍵字，或點下面的熱門標籤看看。',
                    'Nothing found for "$query". Try other words or a popular tag below.',
                  ),
                  style: const TextStyle(color: Palette.muted),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              _PopularTags(title: vm.pair('熱門標籤', 'Popular tags')),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (guides.isNotEmpty) ...[
              SectionLabel(
                vm.pair('官方指南', 'Official guides'),
                note: vm.pair('${guides.length} 篇', '${guides.length}'),
              ),
              const SizedBox(height: 10),
              GuideList(actions: guides),
              const SizedBox(height: 18),
            ],
            if (posts.isNotEmpty) ...[
              SectionLabel(
                vm.pair('學生分享', 'Student posts'),
                note: vm.pair('${posts.length} 篇', '${posts.length}'),
              ),
              const SizedBox(height: 10),
              CardList(
                children: [for (final e in posts) StudentPostCard(item: e)],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PopularTags extends StatelessWidget {
  const _PopularTags({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => ResourceView<List<String>>(
    resource: (vm) => vm.popularTags,
    load: (vm) => vm.loadPopularTags(),
    builder: (context, tags) {
      if (tags.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              for (final tag in tags)
                TagLink(tag, large: true, onTap: () => searchTag(context, tag)),
            ],
          ),
        ],
      );
    },
  );
}
