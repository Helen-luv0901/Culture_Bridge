import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'account_pages.dart';
import 'browse_pages.dart';
import 'home_page.dart' show welcomeTitle;
import 'post_cards.dart';

/// 我的: who I am, my posts and what I saved. Settings are one tap away.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.tab = 'posts'});

  /// 'posts' or 'saved'.
  final String tab;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final name = vm.profile?.nickname ?? vm.pair('匿名學生', 'Anonymous student');
    final postCount = vm.mine.data
        ?.where((e) => e.status == 'published')
        .length;
    final savedCount = vm.signedIn
        ? (vm.saved.data?.length ?? 0) + vm.savedGuideIds.length
        : vm.savedGuideIds.length;
    return FlowBody(
      children: [
        Row(
          children: [
            Avatar(
              initial: name.characters.first,
              size: 54,
              imageUrl: vm.imageUrl(vm.profile?.avatarUrl),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: displayStyle(19)),
                  Text(
                    vm.pair(
                      '分享 ${postCount ?? '–'} · 收藏 $savedCount',
                      'Posts ${postCount ?? '–'} · Saved $savedCount',
                    ),
                    style: mutedStyle,
                  ),
                ],
              ),
            ),
            Tooltip(
              message: vm.pair('設定', 'Settings'),
              child: OutlinedButton(
                key: const Key('open-settings'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => context.push('/profile/settings'),
                child: const AppIcon('settings', size: 20),
              ),
            ),
          ],
        ),
        _Tabs(tab: tab),
        if (!vm.signedIn && tab == 'posts')
          EmptyNote(
            title: vm.t('signInNeeded'),
            body: vm.pair(
              '登入後，你分享的經驗和收藏會在這裡。',
              'Sign in to see your posts and saved posts here.',
            ),
            action: vm.t('signIn'),
            onAction: () => ensureSignedIn(context),
          )
        else if (tab == 'posts')
          ResourceView<List<MyExperience>>(
            resource: (vm) => vm.mine,
            load: (vm) => vm.loadMine(),
            builder: (context, mine) => _MyPosts(items: mine),
          )
        else
          const _Saved(),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab});
  final String tab;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        children: [
          for (final (key, label) in [
            ('posts', vm.pair('我的分享', 'My posts')),
            ('saved', vm.pair('收藏', 'Saved')),
          ])
            Expanded(
              child: Semantics(
                selected: tab == key,
                button: true,
                child: InkWell(
                  key: Key('me-tab-$key'),
                  onTap: () => context.go(
                    key == 'posts' ? '/profile' : '/profile?tab=saved',
                  ),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: tab == key
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: tab == key ? Palette.ink : Palette.muted,
                          ),
                        ),
                        if (tab == key)
                          Positioned(
                            bottom: 0,
                            child: Container(
                              width: 44,
                              height: 2,
                              color: Palette.moss,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyPosts extends StatelessWidget {
  const _MyPosts({required this.items});
  final List<MyExperience> items;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (items.isEmpty) {
      return EmptyNote(
        title: vm.pair('還沒有分享過經驗', "You haven't shared anything yet"),
        body: vm.pair(
          '辦完一件事、遇到文化差異，都可以寫一句話幫下一位學生。',
          'Finished a procedure or met a culture difference? One sentence helps the next student.',
        ),
        action: vm.pair('寫第一篇', 'Write your first post'),
        onAction: () => context.go('/share'),
      );
    }
    return CardList(
      children: [for (final item in items) _MyPostCard(item: item)],
    );
  }
}

class _MyPostCard extends StatelessWidget {
  const _MyPostCard({required this.item});
  final MyExperience item;

  /// Open Share with this draft; asks first if Share already has other unsent words.
  Future<void> _continue(BuildContext context) async {
    final vm = BridgeScope.of(context);
    final current = vm.draft;
    if (!current.isEmpty && current.resumesId != item.id) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(vm.pair('取代分享頁的內容？', 'Replace what is in Share?')),
          content: Text(
            vm.pair(
              '分享頁還有尚未發布的內容。要改成編輯這篇草稿嗎？',
              'Share has words you have not published. Edit this draft instead?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(vm.t('cancel')),
            ),
            FilledButton(
              key: const Key('replace-draft'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(vm.pair('編輯這篇草稿', 'Edit this draft')),
            ),
          ],
        ),
      );
      if (replace != true || !context.mounted) return;
    }
    if (current.resumesId != item.id) vm.continueDraft(item);
    context.go('/share');
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : item.originalVoice.length > 24
        ? '${item.originalVoice.substring(0, 24)}…'
        : item.originalVoice;
    final parts = [
      switch (item.status) {
        'draft' => vm.pair('草稿，點標題繼續編輯', 'Draft. Tap the title to continue'),
        'hidden' => vm.pair('已被隱藏', 'Hidden by moderators'),
        _ => vm.pair('你的分享', 'Your post'),
      },
      if (item.impact.experiencedToo > 0)
        vm.pair(
          '我也遇過 ${item.impact.experiencedToo}',
          'Me too ${item.impact.experiencedToo}',
        ),
      if (item.commentCount > 0)
        vm.pair('${item.commentCount} 則留言', '${item.commentCount} comments'),
      if (item.publishedAt != null) timeAgo(vm, item.publishedAt!),
    ];
    return NoteCard(
      key: Key('mine-${item.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: PaperTag(categoryName(vm, item.categoryKey)),
          ),
          CardTitle(
            title.isEmpty ? vm.pair('（還沒有標題）', '(no title yet)') : title,
            onTap: switch (item.status) {
              'published' => () => openPost(context, item.id),
              'draft' => () => _continue(context),
              _ => () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    vm.pair(
                      '這篇已被管理員隱藏，目前不公開。',
                      'Moderators hid this post; it is not public.',
                    ),
                  ),
                ),
              ),
            },
          ),
          const DashedRule(padding: EdgeInsets.only(top: 4)),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    parts.join(' · '),
                    style: mutedStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.status == 'draft')
                  TextButton(
                    key: Key('delete-draft-${item.id}'),
                    onPressed: () => _delete(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Palette.brickDeep,
                    ),
                    child: Text(vm.pair('刪除', 'Delete')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final vm = BridgeScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(vm.pair('刪除這篇草稿？', 'Delete this draft?')),
        content: Text(vm.pair('刪除後無法復原。', 'This cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(vm.t('cancel')),
          ),
          FilledButton(
            key: const Key('confirm-delete-draft'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(vm.pair('刪除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) await vm.deleteExperience(item.id);
  }
}

class _Saved extends StatelessWidget {
  const _Saved();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final guideIds = vm.savedGuideIds;
    final guides = guideIds.isEmpty
        ? const <Widget>[]
        : [
            ResourceView<List<ActionSummary>>(
              resource: (vm) => vm.actions,
              load: (vm) => vm.loadActions(),
              builder: (context, actions) => CardList(
                children: [
                  for (final id in guideIds)
                    if (id == welcomeGuideId || actions.any((a) => a.id == id))
                      _SavedGuide(id: id, actions: actions),
                ],
              ),
            ),
          ];
    final posts = !vm.signedIn
        ? const <Widget>[]
        : [
            ResourceView<List<ExperienceItem>>(
              resource: (vm) => vm.saved,
              load: (vm) => vm.loadSaved(),
              builder: (context, items) => CardList(
                children: [for (final e in items) StudentPostCard(item: e)],
              ),
            ),
          ];
    final nothing =
        guideIds.isEmpty && (!vm.signedIn || (vm.saved.data?.isEmpty ?? false));
    if (nothing) {
      return EmptyNote(
        title: vm.pair('還沒有收藏', 'Nothing saved yet'),
        body: vm.pair(
          '看到有用的貼文，按書籤就會存在這裡。',
          'Tap the bookmark on a useful post to keep it here.',
        ),
        action: vm.pair('去首頁看看', 'Go to Home'),
        primary: false,
        onAction: () => context.go('/'),
      );
    }
    return CardList(children: [...guides, ...posts]);
  }
}

class _SavedGuide extends StatelessWidget {
  const _SavedGuide({required this.id, required this.actions});
  final String id;
  final List<ActionSummary> actions;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final action = actions.where((a) => a.id == id).firstOrNull;
    return OfficialPostCard(
      id: id,
      pinned: id == welcomeGuideId,
      title:
          action?.title.of(vm.english) ??
          vm.pair(welcomeTitle.$1, welcomeTitle.$2),
      publishedAt: action?.publishedAt,
    );
  }
}

/// Settings: names, language, blocked authors, sign-out and account deletion.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 760,
      gap: 20,
      children: [
        if (vm.signedIn) ...[
          SectionLabel(vm.pair('個人資料', 'Profile')),
          const NoteCard(child: _PhotoSetting()),
          NoteCard(
            child: NamesForm(onSaved: () => vm.showNotice(vm.t('namesSaved'))),
          ),
        ],
        SectionLabel(vm.t('language')),
        Row(
          children: [
            for (final (english, label) in [(false, '繁體中文'), (true, 'English')])
              Expanded(
                child: NoteChip(
                  key: Key(english ? 'locale-en' : 'locale-zh'),
                  label: label,
                  selected: vm.english == english,
                  onTap: () => vm.setEnglish(english),
                ),
              ),
          ].expand((w) => [w, const SizedBox(width: 8)]).toList()..removeLast(),
        ),
        if (vm.signedIn)
          const _AccountPanel()
        else
          FilledButton(
            key: const Key('profile-sign-in'),
            onPressed: () => ensureSignedIn(context),
            child: Text(vm.t('signIn')),
          ),
      ],
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return NoteCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            title: Text(vm.t('blockedAuthors')),
            onExpansionChanged: (open) {
              if (open) vm.loadBlocks();
            },
            children: [
              for (final block in vm.blocks.data ?? const <BlockInfo>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (block.persona) {
                    'named' => vm.pair('具名作者', 'Named author'),
                    'anonymous' => vm.pair('匿名作者', 'Anonymous author'),
                    _ => vm.pair('作者', 'Author'),
                  }),
                  subtitle: Text(
                    '${vm.pair('封鎖於', 'Blocked on')} ${formatDate(block.createdAt)}',
                  ),
                  trailing: TextButton(
                    onPressed: () => vm.unblock(block.id),
                    child: Text(vm.t('unblock')),
                  ),
                ),
              if ((vm.blocks.data ?? const []).isEmpty && !vm.blocks.loading)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      vm.pair('沒有封鎖任何作者。', 'No blocked authors.'),
                      style: mutedStyle,
                    ),
                  ),
                ),
            ],
          ),
          const DashedRule(),
          if (vm.isStaff) ...[
            _Row(
              label: vm.pair('審查與管理', 'Review & admin'),
              onTap: () => context.push('/admin'),
            ),
            const DashedRule(),
          ],
          _Row(
            key: const Key('sign-out'),
            label: vm.t('signOut'),
            onTap: vm.signOut,
          ),
          const DashedRule(),
          _Row(
            key: const Key('delete-account'),
            label: vm.t('deleteAccount'),
            danger: true,
            onTap: () async {
              if (await confirmDialog(
                    context,
                    vm.t('deleteAccount'),
                    vm.t('deleteAccountConfirm'),
                  ) &&
                  await vm.deleteAccount() &&
                  context.mounted) {
                context.go('/');
              }
            },
          ),
          if (vm.profile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(
                '${vm.pair('帳號編號', 'Account ID')}: ${vm.profile!.id}',
                style: mutedStyle.copyWith(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(color: danger ? Palette.danger : Palette.ink),
        ),
      ),
    ),
  );
}

/// Picks a photo from the gallery, already shrunk to at most 1024px; tests replace it.
Future<Uint8List?> Function() pickAvatarPhoto = () async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 90,
  );
  return file?.readAsBytes();
};

/// The profile photo: change or remove it.
class _PhotoSetting extends StatelessWidget {
  const _PhotoSetting();

  Future<void> _change(BuildContext context) async {
    final vm = BridgeScope.of(context);
    final bytes = await pickAvatarPhoto();
    if (bytes == null) return;
    final error = await vm.setAvatar(bytes);
    vm.showNotice(error ?? vm.pair('大頭貼已更新', 'Photo updated'));
  }

  Future<void> _remove(BuildContext context) async {
    final vm = BridgeScope.of(context);
    final error = await vm.setAvatar(null);
    vm.showNotice(error ?? vm.pair('已移除大頭貼', 'Photo removed'));
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final name = vm.profile?.nickname ?? vm.pair('匿', 'A');
    final photo = vm.profile?.avatarUrl;
    return Row(
      children: [
        Avatar(
          key: const Key('my-avatar'),
          initial: name.characters.first,
          size: 72,
          imageUrl: vm.imageUrl(photo),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vm.pair('大頭貼', 'Profile photo'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                vm.pair(
                  '只會出現在你署名的貼文和留言旁，匿名發布時不會顯示。',
                  'Shown only next to posts and comments you sign, never on anonymous ones.',
                ),
                style: mutedStyle.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    key: const Key('change-avatar'),
                    onPressed: vm.updatingAvatar
                        ? null
                        : () => _change(context),
                    child: Text(
                      vm.updatingAvatar
                          ? vm.pair('上傳中…', 'Uploading…')
                          : vm.pair('更換大頭貼', 'Change photo'),
                    ),
                  ),
                  if (photo != null)
                    TextButton(
                      key: const Key('remove-avatar'),
                      onPressed: vm.updatingAvatar
                          ? null
                          : () => _remove(context),
                      child: Text(vm.pair('移除', 'Remove')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
