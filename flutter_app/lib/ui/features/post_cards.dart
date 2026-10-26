import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';

/// The old pinned welcome post; saved copies of it now open the official guides.
const welcomeGuideId = 'welcome';

/// Opens a student post and remembers it was read.
void openPost(BuildContext context, String id) {
  BridgeScope.of(context).markRead(id);
  context.push('/experiences/$id');
}

/// Opens an official guide and remembers it was read.
void openGuide(BuildContext context, String id) {
  BridgeScope.of(context).markRead('guide:$id');
  if (id == welcomeGuideId) {
    context.go('/guides');
  } else {
    context.push('/actions/$id');
  }
}

/// Every official guide (the official avatar links there).
void showOfficial(BuildContext context) {
  if (GoRouterState.of(context).uri.path != '/guides') context.go('/guides');
}

/// Writing a post; guests are asked to sign in first.
void startSharing(BuildContext context) {
  if (BridgeScope.of(context).signedIn) {
    context.go('/share');
  } else {
    askToSignIn(context, signInForSharing, next: '/share');
  }
}

/// Explore, searching for a tag.
void searchTag(BuildContext context, String tag) =>
    context.go('/explore?q=${Uri.encodeQueryComponent(tag)}');

String categoryName(BridgeViewModel vm, String key) {
  final label = categoryLabels[key];
  return label == null ? key : vm.pair(label.$1, label.$2);
}

/// "Culture Bridge" with the official seal, and when it was posted.
class OfficialByline extends StatelessWidget {
  const OfficialByline({super.key, required this.when, this.trailing});
  final String when;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Row(
      children: [
        Tooltip(
          message: vm.pair('看全部官方指南', 'See all official guides'),
          child: InkResponse(
            onTap: () => showOfficial(context),
            radius: 24,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: Avatar()),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Culture Bridge',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              Text(when, style: mutedStyle.copyWith(fontSize: 12)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A card title that opens the post. Lists show only the title.
class CardTitle extends StatelessWidget {
  const CardTitle(
    this.text, {
    super.key,
    required this.onTap,
    this.read = false,
  });
  final String text;
  final VoidCallback onTap;
  final bool read;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              text,
              style: displayStyle(
                17,
                color: read ? Palette.readInk : Palette.ink,
              ).copyWith(height: 1.5),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A plain, straight strip of tape on the pinned card.
class _PinTape extends StatelessWidget {
  const _PinTape();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 74,
      height: 18,
      color: Palette.brick.withValues(alpha: .28),
    ),
  );
}

/// An official guide in a list.
class OfficialPostCard extends StatelessWidget {
  const OfficialPostCard({
    super.key,
    required this.id,
    required this.title,
    this.publishedAt,
    this.pinned = false,
  });
  final String id;
  final String title;
  final DateTime? publishedAt;
  final bool pinned;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final read = vm.isRead('guide:$id');
    final when = [
      if (pinned)
        vm.pair('置頂', 'Pinned')
      else if (publishedAt != null)
        timeAgo(vm, publishedAt!),
      if (read) vm.pair('已看過', 'Read'),
    ].join(' · ');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NoteCard(
          key: Key('guide-$id'),
          read: read,
          onTap: () => openGuide(context, id),
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OfficialByline(when: when),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: CardTitle(
                  title,
                  read: read,
                  onTap: () => openGuide(context, id),
                ),
              ),
            ],
          ),
        ),
        if (pinned) const Positioned(top: -9, left: 22, child: _PinTape()),
      ],
    );
  }
}

/// Who wrote a student post: the chosen name, or anonymous with the student type.
String authorLine(BridgeViewModel vm, ExperienceItem item) {
  final type = item.identityType == 'other'
      ? null
      : vm.t(identityKey(item.identityType));
  final who = item.authorName ?? vm.pair('匿名', 'Anonymous');
  return [who, ?type, timeAgo(vm, item.publishedAt)].join(' · ');
}

String authorInitial(BridgeViewModel vm, String? name) =>
    name == null || name.isEmpty ? vm.pair('匿', 'A') : name.characters.first;

/// The bookmark on student posts and guides.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({
    super.key,
    required this.saved,
    required this.onPressed,
    required this.label,
  });
  final bool saved;
  final VoidCallback onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    isSelected: saved,
    onPressed: onPressed,
    icon: AppIcon(
      'bookmark',
      size: 20,
      color: saved ? Palette.moss : Palette.muted,
      filled: saved,
    ),
  );
}

/// Student posts as one sheet of rows, like a forum's thread list: no card per post.
class PostList extends StatelessWidget {
  const PostList({super.key, required this.items});
  final List<ExperienceItem> items;
  @override
  Widget build(BuildContext context) => NoteCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0)
            const DashedRule(padding: EdgeInsets.symmetric(horizontal: 16)),
          StudentPostCard(item: item),
        ],
      ],
    ),
  );
}

/// One student post in a list: category and who, the title, two lines of what they wrote,
/// then responses and the bookmark. The whole row opens the post.
class StudentPostCard extends StatelessWidget {
  const StudentPostCard({super.key, required this.item});
  final ExperienceItem item;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final read = vm.isRead(item.id);
    final translated = vm.translated(item);
    final title = item.heading(translated);
    final excerpt = item
        .voice(translated)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final parts = [
      if (item.mine) vm.pair('你的分享', 'Your post'),
      vm.pair(
        '我也遇過 ${item.experiencedTooCount}',
        'Me too ${item.experiencedTooCount}',
      ),
      vm.pair('留言 ${item.commentCount}', '${item.commentCount} comments'),
      if (read) vm.pair('已看過', 'Read'),
    ];
    return InkWell(
      key: Key('post-${item.id}'),
      onTap: () => openPost(context, item.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  PaperTag(categoryName(vm, item.categoryKey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      authorLine(vm, item),
                      style: mutedStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Semantics(
                button: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: displayStyle(
                    17,
                    color: read ? Palette.muted : Palette.ink,
                  ).copyWith(height: 1.45),
                ),
              ),
            ),
            if (excerpt.isNotEmpty && excerpt != title) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: read ? Palette.muted : Palette.ink,
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(child: Text(parts.join(' · '), style: mutedStyle)),
                BookmarkButton(
                  saved: item.saved,
                  label: item.saved
                      ? vm.pair('取消收藏「$title」', 'Unsave "$title"')
                      : vm.pair('收藏「$title」', 'Save "$title"'),
                  onPressed: () {
                    if (ensureSignedIn(context)) vm.toggleSaved(item);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 1px dashed hairline, as under the card titles in the trial.
class DashedRule extends StatelessWidget {
  const DashedRule({
    super.key,
    this.padding = EdgeInsets.zero,
    this.color = Palette.oat,
  });
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashPainter(color),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, .5), Offset(x + 4, .5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A column of cards with even gaps.
class CardList extends StatelessWidget {
  const CardList({super.key, required this.children, this.gap = 12});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );
}

/// A centred empty state with one action.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.primary = true,
  });
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final bool primary;
  @override
  Widget build(BuildContext context) => NoteCard(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    child: Column(
      children: [
        Sticker(title.length, size: 88),
        const SizedBox(height: 10),
        Text(title, style: displayStyle(16), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          body,
          style: mutedStyle.copyWith(fontSize: 14),
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          primary
              ? FilledButton(onPressed: onAction, child: Text(action!))
              : OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}
