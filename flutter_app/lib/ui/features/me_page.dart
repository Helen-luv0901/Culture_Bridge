import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'account_pages.dart';
import 'browse_pages.dart';
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
            Avatar(initial: name.characters.first, size: 54),
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
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final published = item.status == 'published';
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : item.originalVoice.length > 24
        ? '${item.originalVoice.substring(0, 24)}…'
        : item.originalVoice;
    final parts = [
      switch (item.status) {
        'draft' => vm.pair('草稿（舊版流程）', 'Draft (old flow)'),
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
            title,
            onTap: published
                ? () => openPost(context, item.id)
                : () => vm.showNotice(
                    vm.pair('這篇沒有公開。', 'This post is not public.'),
                  ),
          ),
          const DashedRule(padding: EdgeInsets.only(top: 4)),
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(parts.join(' · '), style: mutedStyle),
            ),
          ),
        ],
      ),
    );
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
          vm.pair('初次來台灣？先看這篇', 'New to Taiwan? Start here'),
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
                  title: Text(
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
