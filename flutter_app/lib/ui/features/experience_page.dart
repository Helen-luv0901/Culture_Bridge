import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import '../view_models/bridge_view_model.dart';
import 'browse_pages.dart';
import 'post_cards.dart';

/// A student post: the author's own words, reactions and comments.
class ExperienceDetailPage extends StatelessWidget {
  const ExperienceDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => ResourceView<ExperienceDetail>(
    key: ValueKey(id),
    resource: (vm) => vm.experience(id),
    load: (vm) => vm.loadExperience(id),
    builder: (context, detail) => _Post(detail: detail),
  );
}

class _Post extends StatelessWidget {
  const _Post({required this.detail});
  final ExperienceDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = detail.item;
    vm.markRead(item.id);
    return FlowBody(
      maxWidth: 760,
      gap: 16,
      children: [
        _PostCard(detail: detail),
        if (item.mine)
          OutlinedButton(
            key: const Key('delete-post'),
            style: OutlinedButton.styleFrom(foregroundColor: Palette.danger),
            onPressed: () async {
              if (await confirmDialog(
                    context,
                    vm.pair('刪除這篇分享？', 'Delete this post?'),
                    vm.pair(
                      '底下的留言也會一起刪除，刪了就不能復原。',
                      'Its comments are deleted too. This cannot be undone.',
                    ),
                    confirm: vm.t('delete'),
                    danger: true,
                  ) &&
                  await vm.deleteExperience(item.id) &&
                  context.mounted) {
                context.go('/profile');
              }
            },
            child: Text(vm.t('delete')),
          )
        else
          _Reactions(item: item),
        if (detail.different.isNotEmpty) ...[
          SectionLabel(
            vm.pair('不一樣的經驗', 'Different experiences'),
            note: vm.pair(
              '${detail.different.length} 篇',
              '${detail.different.length}',
            ),
          ),
          CardList(
            children: [
              for (final e in detail.different) StudentPostCard(item: e),
            ],
          ),
        ],
        _Comments(post: item),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.detail});
  final ExperienceDetail detail;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final item = detail.item;
    final translated = vm.translated(item);
    final respondsTo = detail.respondsToId;
    return NoteCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                initial: authorInitial(vm, item.authorName),
                imageUrl: vm.imageUrl(item.authorAvatarUrl),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(authorLine(vm, item), style: mutedStyle)),
              PaperTag(categoryName(vm, item.categoryKey)),
              if (!item.mine) ModerationMenu(experienceId: item.id),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PageTitle(item.heading(translated)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SelectableText(
              item.voice(translated),
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
          ),
          if (translated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(vm.t('aiTranslated'), style: mutedStyle),
            ),
          if (vm.canTranslate(item))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => vm.toggleTranslation(item),
                child: Text(
                  translated
                      ? vm.t('showOriginal')
                      : item.translation != null
                      ? vm.t('showTranslation')
                      : vm.t('translate'),
                ),
              ),
            ),
          if (respondsTo != null)
            _LinkLine(
              text: vm.pair('回應另一篇分享的不同經驗 ›', 'Answers another post ›'),
              onTap: () => openPost(context, respondsTo),
            ),
          if (item.actionId != null)
            _LinkLine(
              text: vm.pair('相關官方指南 ›', 'Related official guide ›'),
              onTap: () => openGuide(context, item.actionId!),
            ),
          if (item.tags.isNotEmpty)
            Wrap(
              children: [
                for (final tag in item.tags)
                  TagLink(tag, onTap: () => searchTag(context, tag)),
              ],
            ),
        ],
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        textStyle: const TextStyle(
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: Palette.brick,
        ),
      ),
      onPressed: onTap,
      child: Text(text),
    ),
  );
}

/// 我也遇過 / 我的經驗不一樣 / 收藏.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.item});
  final ExperienceItem item;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final same = vm.reacted(item, 'experienced_too');
    ButtonStyle toggle(bool on) => OutlinedButton.styleFrom(
      backgroundColor: on ? Palette.moss : Palette.high,
      foregroundColor: on ? Palette.onMoss : Palette.ink,
      side: BorderSide(color: on ? Palette.moss : Palette.control),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    final buttons = [
      Semantics(
        selected: same,
        child: OutlinedButton(
          key: const Key('me-too'),
          style: toggle(same),
          onPressed: () {
            if (ensureSignedIn(context)) {
              vm.toggleReaction(item, 'experienced_too');
            }
          },
          child: Text(
            vm.pair(
              '我也遇過 ${item.experiencedTooCount}',
              'Me too ${item.experiencedTooCount}',
            ),
          ),
        ),
      ),
      OutlinedButton(
        key: const Key('share-different'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () {
          if (!ensureSignedIn(context)) return;
          vm.startDifferentExperience(item.id, category: item.categoryKey);
          context.go('/share');
        },
        child: Text(vm.pair('我的經驗不一樣', 'Mine was different')),
      ),
      Semantics(
        selected: item.saved,
        child: OutlinedButton(
          key: const Key('save-post'),
          style: toggle(item.saved),
          onPressed: () {
            if (ensureSignedIn(context)) vm.toggleSaved(item);
          },
          child: Text(
            item.saved ? vm.pair('已收藏', 'Saved') : vm.pair('收藏', 'Save'),
          ),
        ),
      ),
    ];
    // Narrow screens and large text stack the buttons instead of squeezing them.
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            b,
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 10, child: buttons[0]),
        const SizedBox(width: 8),
        Expanded(flex: 13, child: buttons[1]),
        const SizedBox(width: 8),
        Expanded(flex: 8, child: buttons[2]),
      ],
    );
  }
}

class _Comments extends StatefulWidget {
  const _Comments({required this.post});
  final ExperienceItem post;
  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  CommentItem? _replyTo;
  bool _signed = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final vm = BridgeScope.of(context);
    if (!ensureSignedIn(context)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await vm.addComment(
      widget.post.id,
      _text.text,
      replyToId: _replyTo?.id,
      signed: _signed,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null) {
        _text.clear();
        _replyTo = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final postId = widget.post.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        SectionLabel(
          vm.pair('留言', 'Comments'),
          note: vm.pair(
            '${widget.post.commentCount} 則',
            '${widget.post.commentCount}',
          ),
        ),
        const SizedBox(height: 10),
        ResourceView<List<CommentItem>>(
          key: ValueKey('comments-$postId'),
          resource: (vm) => vm.comments(postId),
          load: (vm) => vm.loadComments(postId),
          builder: (context, comments) => NoteCard(
            padding: EdgeInsets.zero,
            child: comments.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      vm.pair(
                        '還沒有留言，留下第一則吧。',
                        'No comments yet. Be the first.',
                      ),
                      style: mutedStyle.copyWith(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, c) in _threaded(comments).indexed) ...[
                        if (i > 0) const DashedRule(),
                        _CommentTile(
                          comment: c,
                          postId: postId,
                          onReply: () {
                            setState(
                              () => _replyTo = c.replyToId == null
                                  ? c
                                  : comments
                                            .where((p) => p.id == c.replyToId)
                                            .firstOrNull ??
                                        c,
                            );
                            _focus.requestFocus();
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        NoteCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyTo != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vm.pair(
                          '回覆 ${_commenter(vm, _replyTo!)}',
                          'Replying to ${_commenter(vm, _replyTo!)}',
                        ),
                        style: mutedStyle,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _replyTo = null),
                      child: Text(vm.t('cancel')),
                    ),
                  ],
                ),
              TextField(
                key: const Key('comment-box'),
                controller: _text,
                focusNode: _focus,
                minLines: 2,
                maxLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: _replyTo != null
                      ? vm.pair('寫下你的回覆…', 'Write your reply…')
                      : vm.pair(
                          '也遇過嗎？分享你的做法…',
                          'Been there? Share what you did…',
                        ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 13, color: Palette.danger),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      children: [
                        NoteChip(
                          dense: true,
                          label: vm.pair('匿名', 'Anonymous'),
                          selected: !_signed,
                          onTap: () => setState(() => _signed = false),
                        ),
                        NoteChip(
                          dense: true,
                          label: vm.profile?.nickname == null
                              ? vm.pair('暱稱（未設定）', 'Nickname (not set)')
                              : vm.pair(
                                  '暱稱：${vm.profile!.nickname}',
                                  'Nickname: ${vm.profile!.nickname}',
                                ),
                          selected: _signed,
                          onTap: vm.profile?.nickname == null
                              ? () => setState(
                                  () => _error = vm.pair(
                                    '要用暱稱，先到「我的 › 設定」填寫',
                                    'Set a nickname in My › Settings first',
                                  ),
                                )
                              : () => setState(() => _signed = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('send-comment'),
                    onPressed: _sending ? null : _send,
                    child: Text(vm.pair('送出', 'Send')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            vm.pair(
              '請友善討論，不要留下電話、帳號等個人資料。',
              'Be kind. Do not post phone numbers, accounts or other personal details.',
            ),
            style: mutedStyle.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Top-level comments in order, each followed by its replies.
  static List<CommentItem> _threaded(List<CommentItem> all) => [
    for (final top in all.where((c) => c.replyToId == null)) ...[
      top,
      ...all.where((r) => r.replyToId == top.id),
    ],
    // Replies whose parent is gone stay visible at the end.
    ...all.where(
      (r) => r.replyToId != null && !all.any((p) => p.id == r.replyToId),
    ),
  ];
}

String _commenter(BridgeViewModel vm, CommentItem c) =>
    c.authorName ?? vm.pair('匿名學生', 'Anonymous student');

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.postId,
    required this.onReply,
  });
  final CommentItem comment;
  final String postId;
  final VoidCallback onReply;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final c = comment;
    final small = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: Palette.muted,
      textStyle: const TextStyle(fontSize: 13),
    );
    return Padding(
      key: Key('comment-${c.id}'),
      padding: EdgeInsets.fromLTRB(c.replyToId == null ? 16 : 58, 14, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            initial: authorInitial(vm, c.authorName),
            imageUrl: vm.imageUrl(c.authorAvatarUrl),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _commenter(vm, c),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: [
                          '',
                          timeAgo(vm, c.createdAt),
                          if (c.byPostAuthor) vm.pair('作者', 'Author'),
                        ].join(' · '),
                        style: const TextStyle(color: Palette.muted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  c.body,
                  style: const TextStyle(fontSize: 15, height: 1.65),
                ),
                Transform.translate(
                  offset: const Offset(-10, 0),
                  child: Wrap(
                    children: [
                      Semantics(
                        selected: c.liked,
                        child: TextButton(
                          style: small.copyWith(
                            foregroundColor: WidgetStatePropertyAll(
                              c.liked ? Palette.moss : Palette.muted,
                            ),
                          ),
                          onPressed: () {
                            if (ensureSignedIn(context)) {
                              vm.toggleCommentLike(postId, c);
                            }
                          },
                          child: Text(
                            vm.pair('有同感', 'Same here') +
                                (c.likeCount > 0 ? ' ${c.likeCount}' : ''),
                            style: TextStyle(
                              fontWeight: c.liked
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        style: small,
                        onPressed: onReply,
                        child: Text(vm.pair('回覆', 'Reply')),
                      ),
                      if (c.mine)
                        TextButton(
                          style: small,
                          onPressed: () async {
                            if (await confirmDialog(
                              context,
                              vm.pair('刪除留言？', 'Delete comment?'),
                              vm.pair(
                                '底下的回覆也會一起刪除。',
                                'Replies to it are deleted too.',
                              ),
                              confirm: vm.t('delete'),
                              danger: true,
                            )) {
                              await vm.deleteComment(postId, c);
                            }
                          },
                          child: Text(vm.t('delete')),
                        )
                      else
                        TextButton(
                          style: small,
                          onPressed: () {
                            if (!ensureSignedIn(context)) return;
                            showReportDialog(
                              context,
                              (reason, note) =>
                                  vm.reportComment(c.id, reason, note),
                            );
                          },
                          child: Text(vm.t('report')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
