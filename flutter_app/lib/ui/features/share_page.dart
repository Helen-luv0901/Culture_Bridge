import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'post_cards.dart';

/// Share: one page. Title and text are required, one category, AI-suggested tags.
/// The post is published exactly as written; the AI only suggests tags.
/// Sharing needs an account, so guests are asked to sign in first.
class SharePage extends StatelessWidget {
  const SharePage({super.key});
  @override
  Widget build(BuildContext context) => BridgeScope.of(context).signedIn
      ? const _ShareForm()
      : const _SignInToShare();
}

class _ShareForm extends StatefulWidget {
  const _ShareForm();
  @override
  State<_ShareForm> createState() => _ShareFormState();
}

class _ShareFormState extends State<_ShareForm> {
  late final _title = TextEditingController(
    text: BridgeScope.of(context).draft.title,
  );
  late final _voice = TextEditingController(
    text: BridgeScope.of(context).draft.voice,
  );
  final _customTag = TextEditingController();
  final _titleFocus = FocusNode();
  final _voiceFocus = FocusNode();
  String? _titleError;
  String? _voiceError;
  String? _categoryError;
  String? _tagError;
  String? _authorError;
  String? _publishError;

  @override
  void dispose() {
    _title.dispose();
    _voice.dispose();
    _customTag.dispose();
    _titleFocus.dispose();
    _voiceFocus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final vm = BridgeScope.of(context);
    final draft = vm.draft;
    setState(() {
      _titleError = draft.title.trim().isEmpty
          ? vm.pair('先寫一個標題', 'Add a title first')
          : null;
      _voiceError = draft.voice.trim().isEmpty
          ? vm.pair('先寫內文再發布', 'Write the text before publishing')
          : null;
      _categoryError = draft.category == null
          ? vm.pair('選一個分類，大家才找得到', 'Pick a category so others can find it')
          : null;
      _publishError = null;
    });
    if (_titleError != null) return _titleFocus.requestFocus();
    if (_voiceError != null) return _voiceFocus.requestFocus();
    if (_categoryError != null) return;
    if (!ensureSignedIn(context)) return;
    final (error, item) = await vm.publishDraft();
    if (!mounted) return;
    if (error != null || item == null) {
      setState(() => _publishError = error);
      return;
    }
    _title.clear();
    _voice.clear();
    // Land on My (so its tab is the current one), then open the new post over it.
    final router = GoRouter.of(context);
    router.go('/profile');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => router.push('/experiences/${item.id}'),
    );
  }

  void _addTag() {
    final error = BridgeScope.of(context).addCustomTag(_customTag.text);
    setState(() => _tagError = error);
    if (error == null) _customTag.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final draft = vm.draft;
    return FlowBody(
      maxWidth: 760,
      gap: 22,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTitle(vm.pair('想分享什麼？', 'What would you like to share?')),
            Text(
              vm.pair(
                '一句話也可以。會照你寫的原文發布，AI 只會推薦標籤。',
                'One sentence is enough. It is published as you write it; the AI only suggests tags.',
              ),
              style: mutedStyle.copyWith(fontSize: 14),
            ),
          ],
        ),
        if (draft.differentFromId != null)
          _LinkNote(
            text: vm.pair(
              '回應「${_postTitle(draft.differentFromId!)}」的不同經驗',
              'A different experience from "${_postTitle(draft.differentFromId!)}"',
            ),
            removeLabel: vm.pair('不要連結這篇', 'Unlink this post'),
            onRemove: () => vm.unlinkDraft(post: true),
          ),
        if (draft.actionId != null)
          _LinkNote(
            text: vm.pair(
              '也會出現在官方指南「${_guideTitle(draft.actionId!)}」底下',
              'Also shown under the guide "${_guideTitle(draft.actionId!)}"',
            ),
            removeLabel: vm.pair('不要連結這篇指南', 'Unlink this guide'),
            onRemove: () => vm.unlinkDraft(guide: true),
          ),
        _Labeled(
          label: vm.pair('標題', 'Title'),
          error: _titleError,
          child: TextField(
            key: const Key('share-title'),
            controller: _title,
            focusNode: _titleFocus,
            maxLength: 80,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            // No example title: people write their own, unprompted.
            decoration: const InputDecoration(counterText: ''),
            onChanged: (value) {
              vm.updateDraft(title: value);
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
        ),
        _Labeled(
          label: vm.pair('內文', 'Text'),
          error: _voiceError,
          child: _RuledField(
            controller: _voice,
            focusNode: _voiceFocus,
            onChanged: (value) {
              vm.updateDraft(voice: value);
              if (_voiceError != null) setState(() => _voiceError = null);
            },
          ),
        ),
        _Section(
          label: SectionLabel(vm.pair('分類', 'Category')),
          error: _categoryError,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in postCategories)
                NoteChip(
                  key: Key('share-cat-$key'),
                  label: categoryName(vm, key),
                  selected: draft.category == key,
                  onTap: () {
                    vm.updateDraft(category: key);
                    setState(() => _categoryError = null);
                  },
                ),
            ],
          ),
        ),
        _Section(
          label: SectionLabel(
            vm.pair('AI 推薦的標籤', 'Tags the AI suggests'),
            note: vm.pair(
              '已選 ${vm.draftTags.length} 個',
              '${vm.draftTags.length} chosen',
            ),
          ),
          error: _tagError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.tagSuggestions.isEmpty && draft.customTags.isEmpty)
                Text(
                  vm.suggestingTags
                      ? vm.pair('AI 正在看你寫的內容…', 'The AI is reading your post…')
                      : vm.pair(
                          '多寫幾個字，AI 會在這裡推薦標籤。',
                          'Write a little more and the AI will suggest tags here.',
                        ),
                  style: mutedStyle.copyWith(fontSize: 14),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final tag in vm.tagSuggestions)
                    if (!draft.customTags.contains(tag))
                      _SuggestedTag(
                        tag: tag,
                        chosen: draft.chosenTags.contains(tag),
                        onTap: () => vm.toggleChosenTag(tag),
                      ),
                  for (final tag in draft.customTags)
                    Semantics(
                      label: vm.pair('移除 $tag', 'Remove $tag'),
                      button: true,
                      excludeSemantics: true,
                      child: TagLink(
                        '$tag ×',
                        large: true,
                        onTap: () => vm.removeCustomTag(tag),
                      ),
                    ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('custom-tag'),
                      controller: _customTag,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: vm.pair('自己加一個標籤', 'Add your own tag'),
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _addTag,
                    child: Text(vm.pair('加入', 'Add')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                vm.pair('點一下選用，不選也可以發布。', 'Tap to use one. Tags are optional.'),
                style: mutedStyle.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        _Section(
          label: SectionLabel(vm.pair('用什麼名字發布', 'Post as')),
          error: _authorError,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, label, name) in [
                ('anonymous', vm.pair('匿名', 'Anonymous'), ''),
                (
                  'nickname',
                  vm.pair('暱稱', 'Nickname'),
                  vm.profile?.nickname ?? '',
                ),
                (
                  'real_name',
                  vm.pair('真名', 'Real name'),
                  vm.profile?.realName ?? '',
                ),
              ])
                NoteChip(
                  key: Key('post-as-$key'),
                  label: key == 'anonymous'
                      ? label
                      : name.isEmpty
                      ? vm.pair('$label（未設定）', '$label (not set)')
                      : '$label：$name',
                  selected: draft.authorDisplay == key,
                  onTap: () {
                    if (key != 'anonymous' && name.isEmpty) {
                      setState(
                        () => _authorError = vm.pair(
                          '要用$label，先到「我的 › 設定」填寫',
                          'Set your ${label.toLowerCase()} in My › Settings first',
                        ),
                      );
                      return;
                    }
                    vm.updateDraft(authorDisplay: key);
                    setState(() => _authorError = null);
                  },
                ),
            ],
          ),
        ),
        if (!draft.isEmpty)
          _Section(
            label: SectionLabel(vm.pair('發布後會長這樣', 'How it will look')),
            child: _Preview(tags: vm.draftTags),
          ),
        if (_publishError != null) ErrorPanel(message: _publishError!),
        FilledButton(
          key: const Key('publish'),
          onPressed: vm.publishing ? null : _publish,
          child: Text(
            vm.publishing ? vm.t('loading') : vm.pair('發布', 'Publish'),
          ),
        ),
      ],
    );
  }

  String _postTitle(String id) {
    final item = BridgeScope.of(context).experience(id).data?.item;
    if (item == null) return '…';
    final title = item.heading(false);
    return title.length > 14 ? '${title.substring(0, 14)}…' : title;
  }

  String _guideTitle(String id) {
    final v = BridgeScope.of(context);
    final summary =
        v.action(id).data?.summary ??
        v.actions.data?.where((a) => a.id == id).firstOrNull;
    return summary?.title.of(v.english) ?? '…';
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: mutedStyle),
      child,
      if (error != null) _ErrorText(error!),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.error});
  final Widget label;
  final Widget child;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      label,
      const SizedBox(height: 10),
      child,
      if (error != null) _ErrorText(error!),
    ],
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Palette.danger),
      ),
    ),
  );
}

class _LinkNote extends StatelessWidget {
  const _LinkNote({
    required this.text,
    required this.removeLabel,
    required this.onRemove,
  });
  final String text;
  final String removeLabel;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => NoteCard(
    padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
    child: Row(
      children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        IconButton(
          tooltip: removeLabel,
          onPressed: onRemove,
          icon: const AppIcon('close', size: 16, color: Palette.muted),
        ),
      ],
    ),
  );
}

/// Notebook paper: the text sits on ruled lines 28px apart.
class _RuledField extends StatelessWidget {
  const _RuledField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  static const lineHeight = 28.0;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Palette.high,
      border: Border(bottom: BorderSide(color: Palette.control, width: 1.5)),
    ),
    child: CustomPaint(
      painter: const _RulePainter(lineHeight),
      child: TextField(
        key: const Key('share-voice'),
        controller: controller,
        focusNode: focusNode,
        minLines: 5,
        maxLines: 14,
        maxLength: 2000,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 16, height: lineHeight / 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onChanged: onChanged,
      ),
    ),
  );
}

class _RulePainter extends CustomPainter {
  const _RulePainter(this.step);
  final double step;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Palette.oat
      ..strokeWidth = 1;
    for (double y = step - .5; y < size.height - 24; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.step != step;
}

/// A suggested tag: dashed outline until chosen, then a tick.
class _SuggestedTag extends StatelessWidget {
  const _SuggestedTag({
    required this.tag,
    required this.chosen,
    required this.onTap,
  });
  final String tag;
  final bool chosen;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    excludeSemantics: true,
    label: tag,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 44,
        child: Center(
          widthFactor: 1,
          child: CustomPaint(
            painter: chosen ? null : const _DashedBoxPainter(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                '${chosen ? '✓' : '＋'} $tag',
                style: const TextStyle(fontSize: 14, color: Palette.brickDeep),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Palette.control
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      );
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => false;
}

class _Preview extends StatelessWidget {
  const _Preview({required this.tags});
  final List<String> tags;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final draft = vm.draft;
    final name = switch (draft.authorDisplay) {
      'nickname' => vm.profile?.nickname,
      'real_name' => vm.profile?.realName,
      _ => null,
    };
    return NoteCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                initial: authorInitial(vm, name),
                imageUrl: name == null
                    ? null
                    : vm.imageUrl(vm.profile?.avatarUrl),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${name ?? vm.pair('匿名', 'Anonymous')} · ${vm.pair('剛剛', 'just now')}',
                  style: mutedStyle,
                ),
              ),
              PaperTag(
                draft.category == null
                    ? vm.pair('未選分類', 'No category')
                    : categoryName(vm, draft.category!),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            draft.title.trim().isEmpty
                ? vm.pair('（還沒有標題）', '(no title yet)')
                : draft.title.trim(),
            style: displayStyle(17),
          ),
          const SizedBox(height: 6),
          Text(draft.voice, style: const TextStyle(fontSize: 15, height: 1.7)),
          if (tags.isNotEmpty)
            Wrap(children: [for (final t in tags) TagLink(t)]),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

/// What a guest sees on the share page (from a link or a "share" button): sign in first.
class _SignInToShare extends StatelessWidget {
  const _SignInToShare();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 760,
      children: [
        EmptyNote(
          key: const Key('share-sign-in'),
          title: vm.pair('請先登入', 'Please sign in'),
          body: vm.pair(signInForSharing.$1, signInForSharing.$2),
          action: vm.t('signIn'),
          onAction: () => ensureSignedIn(context),
        ),
      ],
    );
  }
}
