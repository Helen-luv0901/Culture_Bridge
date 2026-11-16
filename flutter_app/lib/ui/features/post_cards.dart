import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';

/// Opens a student post and remembers it was read.
void openPost(BuildContext context, String id) {
  BridgeScope.of(context).markRead(id);
  context.push('/experiences/$id');
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

/// "1 comment", "3 comments".
String commentsInEnglish(int n) => n == 1 ? '1 comment' : '$n comments';

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
    child: FocusInk(
      onTap: onTap,
      ringRadius: const BorderRadius.all(Radius.circular(6)),
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

/// The bookmark on student posts and official questions.
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
  Widget build(BuildContext context) => ToggleIconButton(
    label: label,
    on: saved,
    onPressed: onPressed,
    burst: true,
    icon: AppIcon(
      'bookmark',
      size: 20,
      color: saved ? Palette.moss : Palette.muted,
      filled: saved,
    ),
  );
}

/// Student posts as forum cards, one under the other.
class PostList extends StatelessWidget {
  const PostList({super.key, required this.items});
  final List<ExperienceItem> items;
  @override
  Widget build(BuildContext context) => CardList(
    gap: 8,
    children: [for (final item in items) StudentPostCard(item: item)],
  );
}

/// One student post as a forum card: a "me too" vote column on the left, then the
/// category, who and when, the title, two lines of what they wrote, comments and save.
/// The whole card opens the post.
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
    // A body of only "-" or "." shows no excerpt line (emoji still count as words).
    final hasExcerpt =
        excerpt != title &&
        excerpt.replaceAll(RegExp(r'[\p{P}\s]', unicode: true), '').isNotEmpty;
    final same = vm.reacted(item, 'experienced_too');
    return DecoratedBox(
      decoration: paperShadow,
      child: Material(
        color: Palette.high,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: Palette.oat),
        ),
        clipBehavior: Clip.antiAlias,
        // The title is the card's button for keyboards and screen readers; the rest
        // of the card is a mouse and touch target only, so each card is one tab stop.
        child: InkWell(
          key: Key('post-${item.id}'),
          onTap: () => openPost(context, item.id),
          canRequestFocus: false,
          excludeFromSemantics: true,
          // The vote column's tint fills the card's height without measuring it first.
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 48,
                child: ColoredBox(color: Palette.soft),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        ToggleIconButton(
                          key: Key('vote-${item.id}'),
                          label: vm.pair(
                            '我也遇過 ${item.experiencedTooCount}',
                            'Me too ${item.experiencedTooCount}',
                          ),
                          on: same,
                          onPressed: () {
                            if (ensureSignedIn(context)) {
                              vm.toggleReaction(item, 'experienced_too');
                            }
                          },
                          icon: AppIcon(
                            'up',
                            size: 20,
                            filled: same,
                            color: same ? Palette.moss : Palette.muted,
                            strokeWidth: 2,
                          ),
                        ),
                        ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${item.experiencedTooCount}',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: same ? Palette.moss : Palette.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 8, 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The byline, title and excerpt are one button of their own (well
                          // over 44px tall, no change to the look); the vote, comments and
                          // save buttons stay outside it.
                          Semantics(
                            container: true,
                            button: true,
                            child: FocusInk(
                              key: Key('post-title-${item.id}'),
                              onTap: () => openPost(context, item.id),
                              ringRadius: const BorderRadius.all(
                                Radius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: categoryName(
                                            vm,
                                            item.categoryKey,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Palette.ink,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '  ·  ${authorLine(vm, item)}',
                                        ),
                                        if (item.mine)
                                          TextSpan(
                                            text: vm.pair(
                                              '  ·  你的分享',
                                              '  ·  Your post',
                                            ),
                                          ),
                                        if (read)
                                          TextSpan(
                                            text: vm.pair(
                                              '  ·  已看過',
                                              '  ·  Read',
                                            ),
                                          ),
                                      ],
                                    ),
                                    style: mutedStyle.copyWith(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: postTitleStyle(read: read),
                                  ),
                                  if (hasExcerpt) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      excerpt,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: postExcerptStyle,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Palette.muted,
                                      textStyle: const TextStyle(
                                        fontFamily: appFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: () => openPost(context, item.id),
                                    icon: const AppIcon(
                                      'chat',
                                      size: 17,
                                      color: Palette.muted,
                                    ),
                                    label: Text(
                                      vm.pair(
                                        '${item.commentCount} 則留言',
                                        commentsInEnglish(item.commentCount),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              BookmarkButton(
                                saved: item.saved,
                                label: item.saved
                                    ? vm.pair('取消收藏「$title」', 'Unsave "$title"')
                                    : vm.pair('收藏「$title」', 'Save "$title"'),
                                onPressed: () {
                                  if (ensureSignedIn(context)) {
                                    vm.toggleSaved(item);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A post's title in lists.
TextStyle postTitleStyle({bool read = false}) => TextStyle(
  fontSize: 16,
  height: 1.45,
  fontWeight: FontWeight.w700,
  color: read ? Palette.muted : Palette.ink,
);

const postExcerptStyle = TextStyle(
  fontSize: 14,
  height: 1.55,
  color: Palette.inkSoft,
);

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
