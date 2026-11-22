import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';
import 'action_pages.dart';
import 'post_cards.dart';

/// Opens an official question and remembers it was read.
void openFaq(BuildContext context, String id) {
  BridgeScope.of(context).markRead('faq:$id');
  context.push('/faqs/${Uri.encodeComponent(id)}');
}

/// The note shown in English where the official site has only Chinese.
String? noEnglishNote(BridgeViewModel vm, FaqSummary faq) =>
    vm.english && !faq.hasEnglish
    ? 'Official English version not available'
    : null;

/// The short label for a question whose answer may no longer hold.
String faqReviewLabel(BridgeViewModel vm, String kind) => switch (kind) {
  'superseded' => vm.pair('可能已過時', 'May be outdated'),
  'time_limited' => vm.pair('已結束的措施', 'Ended measure'),
  'conflict' => vm.pair('說法不一', 'Answers differ'),
  _ => vm.pair('請留意', 'Check carefully'),
};

/// The notice title above an answer that may no longer hold.
String _reviewTitle(BridgeViewModel vm, String kind) => switch (kind) {
  'superseded' => vm.pair('已有較新的回覆', 'A newer answer exists'),
  'time_limited' => vm.pair('這項措施已經結束', 'This measure has ended'),
  'conflict' => vm.pair('回覆之間說法不一致', 'Official answers differ'),
  _ => vm.pair('這則回覆請留意', 'Read this answer with care'),
};

const _intro = (
  '教育部 NISA 計畫整理的境外生常見問題，由內政部移民署、勞動部等政府機關回覆。辦理前請以最新公告為準。',
  'Common questions from international students, collected by the Ministry of Education '
      'NISA Office and answered by government agencies such as the National Immigration '
      'Agency. Check the latest notices before you apply.',
);

/// The 問答 tab: the step-by-step procedures first, then the official Q&A, every question
/// the MOE NISA site lists, filtered by its categories and by who it applies to, and
/// searched on the device.
class FaqsPage extends StatefulWidget {
  const FaqsPage({super.key, this.category});

  /// A category id to start on (/faqs?cat=visa-arc).
  final String? category;
  @override
  State<FaqsPage> createState() => _FaqsPageState();
}

class _FaqsPageState extends State<FaqsPage> {
  static const _pageSize = 30;
  late String _category = widget.category ?? 'all';
  String? _identity;
  final _search = TextEditingController();
  int _shown = _pageSize;

  @override
  void didUpdateWidget(FaqsPage old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      _category = widget.category ?? 'all';
      _shown = _pageSize;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) => setState(() {
    change();
    _shown = _pageSize;
  });

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      gap: 18,
      children: [
        const ProcedureSection(),
        const SizedBox(height: 8),
        Column(
          key: const Key('faqs-intro'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTitle(vm.pair('官方問答', 'Official Q&A')),
            const SizedBox(height: 6),
            Text(
              vm.pair(_intro.$1, _intro.$2),
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
          ],
        ),
        TextField(
          key: const Key('faq-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _set(() {}),
          decoration: InputDecoration(
            constraints: const BoxConstraints(minHeight: 44),
            hintText: vm.pair('搜尋官方問答', 'Search the official Q&A'),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 12, right: 8),
              child: AppIcon('search', size: 20, color: Palette.muted),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: vm.pair('清除搜尋', 'Clear search'),
                    onPressed: () => _set(_search.clear),
                    icon: const AppIcon(
                      'close',
                      size: 18,
                      color: Palette.muted,
                    ),
                  ),
          ),
        ),
        ResourceView<FaqCatalog>(
          resource: (vm) => vm.faqs,
          load: (vm) => vm.loadFaqs(),
          builder: (context, catalog) => _catalog(context, vm, catalog),
        ),
      ],
    );
  }

  Widget _catalog(BuildContext context, BridgeViewModel vm, FaqCatalog all) {
    // School-administration questions are never listed: administrative guidance may appear only
    // once checked and published by Feng Chia University itself. The server leaves them out;
    // this also covers an older server that still sends them.
    // In English, questions without an official English version are left out too.
    final visible = [
      for (final faq in all.items)
        if (vm.faqShown(faq)) faq,
    ];
    // Counts follow the identity filter, so a category chip never leads to 「共 0 則」.
    final forWho = [
      for (final faq in visible)
        if (_identity == null || faq.identities.contains(_identity)) faq,
    ];
    final counts = <String, int>{};
    for (final faq in forWho) {
      counts.update(faq.categoryId, (n) => n + 1, ifAbsent: () => 1);
    }
    final category =
        all.category(_category) == null || (counts[_category] ?? 0) == 0
        ? 'all'
        : _category;
    final found = [
      for (final faq in forWho)
        if ((category == 'all' || faq.categoryId == category) &&
            faq.matches(_search.text))
          faq,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two menus instead of 20-odd chips: the list starts right under the search box.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterMenu(
              key: const Key('faq-cat'),
              label: vm.pair('分類', 'Category'),
              selected: category,
              options: [
                ('all', vm.pair('全部', 'All')),
                for (final c in all.categories)
                  if ((counts[c.id] ?? 0) > 0) (c.id, c.name.of(vm.english)),
              ],
              onSelected: (id) => _set(() => _category = id),
            ),
            if (all.identities.isNotEmpty)
              _FilterMenu(
                key: const Key('faq-who'),
                label: vm.pair('適用身分', 'Applies to'),
                selected: _identity ?? 'all',
                options: [
                  ('all', vm.pair('所有身分', 'Everyone')),
                  for (final who in all.identities)
                    (who.id, who.name.of(vm.english)),
                ],
                onSelected: (id) =>
                    _set(() => _identity = id == 'all' ? null : id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Only as wide as the words, so the paper behind them is not taken for the text's
        // background.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            liveRegion: true,
            child: Text(
              vm.pair('共 ${found.length} 則', '${found.length} questions'),
              style: mutedStyle,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (found.isEmpty)
          EmptyNote(
            title: vm.pair('沒有符合的問題', 'No matching questions'),
            body: vm.pair(
              '換個關鍵字或分類，或問問 AI 助理。',
              'Try other words or another category, or ask the AI assistant.',
            ),
          )
        else ...[
          FaqList(items: found.take(_shown).toList(), catalog: all),
          if (found.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton(
                key: const Key('faq-more'),
                onPressed: () => setState(() => _shown += _pageSize),
                child: Text(vm.t('loadMore')),
              ),
            ),
        ],
      ],
    );
  }
}

/// A row of choice chips that scrolls sideways on phones and wraps on wider screens.
/// A filter as one pill showing its current choice; tapping it lists the choices.
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });
  final String label;
  final String selected;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final current = options
        .firstWhere((o) => o.$1 == selected, orElse: () => options.first)
        .$2;
    final filtered = selected != 'all';
    final colon = BridgeScope.of(context).pair('：', ': ');
    return PopupMenuButton<String>(
      tooltip: label,
      color: Palette.high,
      position: PopupMenuPosition.under,
      initialValue: selected,
      onSelected: onSelected,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 200),
      itemBuilder: (_) => [
        for (final (id, text) in options)
          PopupMenuItem(
            key: Key('${(key as ValueKey<String>).value}-$id'),
            value: id,
            child: Text(
              text,
              style: TextStyle(
                fontWeight: id == selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: '$label$colon$current',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 16, right: 10),
          decoration: ShapeDecoration(
            color: filtered ? Palette.moss : Palette.high,
            shape: StadiumBorder(
              side: BorderSide(
                color: filtered ? Palette.moss : Palette.control,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$label$colon$current',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: filtered ? Palette.onMoss : Palette.ink,
                    fontWeight: filtered ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppIcon(
                'down',
                size: 18,
                color: filtered ? Palette.onMoss : Palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Official questions as one card of rows: the question, its category and date.
/// Category names come from [catalog], or the loaded catalog when not given.
class FaqList extends StatelessWidget {
  const FaqList({super.key, required this.items, this.catalog});
  final List<FaqSummary> items;
  final FaqCatalog? catalog;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (catalog == null && vm.faqs.needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vm.faqs.needsLoad) vm.loadFaqs();
      });
    }
    final names = catalog ?? vm.faqs.data;
    // Never shown anywhere (see FaqsPage); the server leaves them out already.
    final shown = [
      for (final faq in items)
        if (vm.faqShown(faq)) faq,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    // One card per question, spaced like the post list, so each stands apart.
    return CardList(
      gap: 8,
      children: [
        for (final faq in shown)
          NoteCard(
            padding: EdgeInsets.zero,
            child: _FaqRow(
              faq: faq,
              category: names?.category(faq.categoryId)?.name.of(vm.english),
            ),
          ),
      ],
    );
  }
}

class _FaqRow extends StatelessWidget {
  const _FaqRow({required this.faq, this.category});
  final FaqSummary faq;
  final String? category;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final read = vm.isRead('faq:${faq.id}');
    final meta = [
      ?category,
      ?faq.postedOn,
      ?noEnglishNote(vm, faq),
      if (read) vm.pair('已看過', 'Read'),
    ].join(' · ');
    return InkWell(
      key: Key('faq-row-${faq.id}'),
      onTap: () => openFaq(context, faq.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      faq.question.of(vm.english),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(
                        16,
                        color: read ? Palette.muted : Palette.ink,
                      ).copyWith(height: 1.5),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, style: mutedStyle.copyWith(fontSize: 13)),
                    ],
                    if (faq.review case final review?) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          PaperTag(
                            faqReviewLabel(vm, review.kind),
                            key: Key('faq-review-tag-${faq.id}'),
                            color: Palette.ochre,
                          ),
                        ],
                      ),
                    ],
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

/// One official question: the full answer, who answered it and where it comes from, then
/// students' own experiences on the same subject.
class FaqDetailPage extends StatelessWidget {
  const FaqDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => ResourceView<FaqDetail>(
    key: ValueKey(id),
    resource: (vm) => vm.faq(id),
    load: (vm) => vm.loadFaq(id),
    builder: (context, detail) => detail.summary.forSchool
        ? const _NotShown()
        : BridgeScope.of(context).faqShown(detail.summary)
        ? _FaqDetail(detail: detail)
        : const _ChineseOnly(),
  );
}

/// A school-administration question reached by an old link or an older server.
class _NotShown extends StatelessWidget {
  const _NotShown();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 760,
      children: [
        EmptyNote(
          key: const Key('faq-not-shown'),
          title: vm.pair('這則問答不提供', 'This question is not available'),
          body: vm.pair(
            '這是學校行政人員之間的問答，不適用於學生，所以不顯示。有學校相關的問題，請問你學校的國際事務處。',
            "This one was asked between school staff and does not apply to students. "
                "For school matters, ask your school's international office.",
          ),
        ),
      ],
    );
  }
}

/// A question the NISA site answers only in Chinese, opened in English (an old link, a saved
/// question): English shows no Chinese text, so it offers to switch to Chinese.
class _ChineseOnly extends StatelessWidget {
  const _ChineseOnly();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 760,
      children: [
        EmptyNote(
          key: const Key('faq-chinese-only'),
          title: 'Available in Chinese only',
          body: 'The official answer to this question has no English version yet. Switch to Chinese to read it.',
          action: '切換成中文',
          onAction: () => vm.setEnglish(false),
        ),
      ],
    );
  }
}

class _FaqDetail extends StatelessWidget {
  const _FaqDetail({required this.detail});
  final FaqDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final faq = detail.summary;
    vm.markRead('faq:${faq.id}');
    final english = vm.english;
    final question = faq.question.of(english);
    final saved = vm.faqSaved(faq.id);
    final catalog = vm.faqs.data;
    final note = noEnglishNote(vm, faq);
    return FlowBody(
      maxWidth: 760,
      gap: 16,
      children: [
        NoteCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vm.pair(
                        '官方問答 · 政府機關回覆',
                        'Official Q&A · Answered by agencies',
                      ),
                      style: mutedStyle.copyWith(fontSize: 13),
                    ),
                  ),
                  BookmarkButton(
                    key: const Key('save-faq'),
                    saved: saved,
                    label: saved
                        ? vm.pair('取消收藏這則問答', 'Unsave this question')
                        : vm.pair('收藏這則問答', 'Save this question'),
                    onPressed: () => vm.toggleSavedFaq(faq.id),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PageTitle(question, size: 22),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (detail.category.of(english).isNotEmpty)
                    PaperTag(detail.category.of(english)),
                  for (final who in faq.identities)
                    PaperTag(
                      catalog?.identity(who)?.name.of(english) ??
                          _identityName(vm, who),
                    ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 10),
                Text(
                  note,
                  key: const Key('faq-no-english'),
                  style: mutedStyle.copyWith(fontSize: 13),
                ),
              ],
              if (faq.review case final review?) ...[
                const SizedBox(height: 16),
                _ReviewNotice(review: review),
              ],
              const SizedBox(height: 16),
              const DashedRule(),
              const SizedBox(height: 16),
              // Plain text: SelectableText reaches screen readers on the web as an empty box.
              Text(
                detail.answer.of(english),
                key: const Key('faq-answer'),
                style: const TextStyle(fontSize: 16, height: 1.75),
              ),
            ],
          ),
        ),
        _Source(detail: detail),
        _RelatedPosts(id: faq.id),
      ],
    );
  }

  /// Names for the four identities, for when the list hasn't loaded (the NISA site's names, as
  /// the backend serves them).
  static String _identityName(BridgeViewModel vm, String id) => switch (id) {
    'foreign' => vm.pair('外國學生', 'Foreign Student'),
    'overseas-chinese' => vm.pair('僑生', 'Overseas Chinese Student'),
    'hong-kong-macao' => vm.pair('港澳生', 'Students from Hong Kong and Macao'),
    'mainland' => vm.pair('陸生', 'Mainland Chinese Student'),
    _ => id,
  };
}

/// A warning that the answer may no longer hold, with a way to the newer answer.
class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.review});
  final FaqReview review;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final newer = review.supersededBy;
    final note = review.note.of(vm.english);
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const Key('faq-review'),
        decoration: BoxDecoration(
          color: Palette.ochre,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  _reviewTitle(vm, review.kind),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.ochreInk,
                  ),
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Palette.ochreInk,
                  ),
                ),
              ],
              if (newer != null && newer.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    key: const Key('faq-newer'),
                    onPressed: () => openFaq(context, newer),
                    child: Text(vm.pair('看較新的回覆', 'See the newer answer')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Who answered, when, where the question came from, and the original page.
class _Source extends StatelessWidget {
  const _Source({required this.detail});
  final FaqDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final english = vm.english;
    final rows = [
      (vm.pair('回覆機關', 'Answered by'), detail.agency.of(english)),
      (vm.pair('發布日期', 'Posted'), detail.summary.postedOn ?? ''),
      (vm.pair('問題來源', 'Asked at'), detail.source.of(english)),
      (vm.pair('整理單位', 'Published by'), detail.publisher.of(english)),
    ];
    final url = Uri.tryParse(detail.url);
    return NoteCard(
      key: const Key('faq-source'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(vm.pair('官方來源', 'Official source')),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            if (value.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label  ',
                        style: const TextStyle(color: Palette.muted),
                      ),
                      TextSpan(text: value),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
          Text(
            vm.pair(
              '規定可能更新，辦理前請以主管機關最新公告為準。',
              'Rules can change; check the agency\'s latest notice before you apply.',
            ),
            style: mutedStyle.copyWith(fontSize: 13),
          ),
          if (url != null && url.hasScheme)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Link(
                uri: url,
                target: LinkTarget.blank,
                builder: (context, follow) => TextButton(
                  key: const Key('faq-original'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: const TextStyle(
                      fontFamily: appFont,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: Palette.brick,
                    ),
                  ),
                  onPressed: follow,
                  child: Text(
                    vm.pair('到教育部 NISA 網站看原文 ↗', 'View the original on NISA ↗'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Students' posts on the same subject; hidden when there are none (or they can't load).
class _RelatedPosts extends StatelessWidget {
  const _RelatedPosts({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (vm.faqPosts(id).needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vm.faqPosts(id).needsLoad) vm.loadFaqPosts(id);
      });
    }
    final posts = vm.faqPosts(id).data ?? const <ExperienceItem>[];
    if (posts.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('faq-related-posts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          vm.pair('同學的相關經驗', 'Related student posts'),
          note: vm.t('notVerifiedNote'),
        ),
        const SizedBox(height: 10),
        PostList(items: posts),
      ],
    );
  }
}
