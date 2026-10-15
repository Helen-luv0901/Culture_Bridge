import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_service.dart';
import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'browse_pages.dart';

class SharePage extends StatefulWidget {
  const SharePage({super.key});
  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _form = GlobalKey<FormState>();
  final _focus = FocusNode();
  TextEditingController? _controller;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= TextEditingController(
      text: BridgeScope.of(context).draft.voice,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _organize() async {
    final vm = BridgeScope.of(context);
    if (!_form.currentState!.validate()) {
      _focus.requestFocus();
      return;
    }
    if (!ensureSignedIn(context)) return;
    final error = await vm.prepareReview();
    if (!mounted) return;
    setState(() => _error = error == '' ? null : error);
    if (error == null) context.go('/review');
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperTag(vm.t('anonymousByDefault')),
            const SizedBox(height: 16),
            Text(vm.t('whatHappened'), style: displayStyle(28)),
            const SizedBox(height: 12),
            Text(
              vm.t('oneSentence'),
              style: const TextStyle(color: Palette.muted),
            ),
            if (vm.draft.differentFromId != null) ...[
              const SizedBox(height: 12),
              PaperTag(vm.t('respondingTo'), color: Palette.paleMoss),
            ],
          ],
        ),
        Form(
          key: _form,
          child: TextFormField(
            key: const Key('share-voice'),
            controller: _controller,
            focusNode: _focus,
            minLines: 6,
            maxLines: 12,
            maxLength: 2000,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: vm.t('yourOriginalVoice'),
              alignLabelWithHint: true,
            ),
            onChanged: (value) => vm.updateDraft(voice: value),
            validator: (value) => value == null || value.trim().isEmpty
                ? vm.pair(
                    '請先寫下發生了什麼事，再整理你的經驗。',
                    'Write what happened before reviewing your experience.',
                  )
                : null,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('topic')),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final topic in ['lifeAdaptation', 'cultureCommunication'])
                  ChoiceChip(
                    label: Text(vm.t(topic)),
                    selected: vm.draft.topic == topic,
                    onSelected: (_) => vm.updateDraft(topic: topic),
                  ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('identityType')),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final identity in [
                  'degreeStudent',
                  'exchangeStudent',
                  'languageStudent',
                  'otherIdentity',
                ])
                  ChoiceChip(
                    label: Text(vm.t(identity)),
                    selected: vm.draft.identity == identity,
                    onSelected: (_) => vm.updateDraft(identity: identity),
                  ),
              ],
            ),
          ],
        ),
        Text(
          vm.t('anonymousNote'),
          style: const TextStyle(fontSize: 14, color: Palette.muted),
        ),
        if (_error != null) ErrorPanel(message: _error!),
        FilledButton(
          key: const Key('review-draft'),
          onPressed: vm.organizing ? null : _organize,
          child: vm.organizing
              ? Text(vm.t('loading'))
              : Text(vm.t('askAiToOrganize')),
        ),
        Text(
          vm.t('aiOrganizeHelp'),
          style: const TextStyle(fontSize: 14, color: Palette.muted),
        ),
      ],
    );
  }
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final TextEditingController _situation;
  late final TextEditingController _feeling;
  late final TextEditingController _reminder;
  bool _publishing = false;
  String? _error;
  String _authorDisplay = 'anonymous';

  @override
  void initState() {
    super.initState();
    _situation = TextEditingController();
    _feeling = TextEditingController();
    _reminder = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final summary = BridgeScope.of(context).reviewSummary;
    if (summary != null && _situation.text.isEmpty && _reminder.text.isEmpty) {
      _situation.text = summary.situation;
      _feeling.text = summary.feelingOrAttempt;
      _reminder.text = summary.reminder;
    }
  }

  @override
  void dispose() {
    _situation.dispose();
    _feeling.dispose();
    _reminder.dispose();
    super.dispose();
  }

  Future<void> _publish(SummaryDraftInfo summary) async {
    final vm = BridgeScope.of(context);
    if (_situation.text.trim().isEmpty || _reminder.text.trim().isEmpty) {
      setState(
        () => _error = vm.pair(
          '情境和提醒不能空白。',
          'Situation and reminder are required.',
        ),
      );
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    final error = await vm.publish(
      situation: _situation.text,
      feelingOrAttempt: _feeling.text,
      reminder: _reminder.text,
      authorDisplay: _authorDisplay,
    );
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _error = error;
    });
    if (error == null) context.go('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final summary = vm.reviewSummary;
    if (summary == null) return const SizedBox.shrink();
    return FlowBody(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vm.t('reviewTitle'), style: displayStyle(28)),
            const SizedBox(height: 12),
            Text(vm.t('reviewNote')),
          ],
        ),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('yourOriginalVoice')),
              Text('「${vm.draft.voice.trim()}」'),
            ],
          ),
        ),
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaperHeading(vm.t('aiDraft')),
              TextField(
                key: const Key('summary-situation'),
                controller: _situation,
                maxLines: null,
                maxLength: 1000,
                decoration: InputDecoration(labelText: vm.t('situation')),
              ),
              TextField(
                controller: _feeling,
                maxLines: null,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: vm.pair(
                    '感受或嘗試（選填）',
                    'Feeling or what you tried (optional)',
                  ),
                ),
              ),
              TextField(
                key: const Key('summary-reminder'),
                controller: _reminder,
                maxLines: null,
                maxLength: 1000,
                decoration: InputDecoration(labelText: vm.t('reminder')),
              ),
              Text(
                vm.pair(
                  'AI 可能誤解你的意思，可以直接修改，確認後才會發布。',
                  'The AI can misread you. Edit freely; nothing is published until you confirm.',
                ),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ],
          ),
        ),
        _AuthorChoice(
          value: _authorDisplay,
          onChanged: (value) => setState(() => _authorDisplay = value),
        ),
        if (_error != null) ErrorPanel(message: _error!),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            OutlinedButton(
              key: const Key('edit-draft'),
              onPressed: () => context.go('/share'),
              child: Text(vm.t('editOriginal')),
            ),
            FilledButton(
              key: const Key('publish'),
              onPressed: _publishing ? null : () => _publish(summary),
              child: Text(vm.t('publishAnonymously')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sign an experience anonymously, with the nickname or with the real name.
class _AuthorChoice extends StatelessWidget {
  const _AuthorChoice({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final nickname = vm.profile?.nickname;
    final realName = vm.profile?.realName;
    final options = [
      ('anonymous', vm.t('asAnonymous'), true),
      (
        'nickname',
        nickname == null
            ? vm.t('asNickname')
            : '${vm.t('asNickname')}：$nickname',
        nickname != null,
      ),
      (
        'real_name',
        realName == null
            ? vm.t('asRealName')
            : '${vm.t('asRealName')}：$realName',
        realName != null,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaperHeading(vm.t('postAs')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (key, label, enabled) in options)
              ChoiceChip(
                key: Key('post-as-$key'),
                label: Text(label),
                selected: value == key,
                onSelected: enabled ? (_) => onChanged(key) : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (nickname == null || realName == null)
          Text(
            vm.t('needNameHint'),
            style: const TextStyle(fontSize: 13, color: Palette.muted),
          ),
        if (value == 'real_name')
          Text(
            vm.t('realNameWarning'),
            style: const TextStyle(fontSize: 13, color: Palette.brickDeep),
          ),
      ],
    );
  }
}

/// Optional nickname and real name (on My, and once after the first sign-in).
class NamesForm extends StatefulWidget {
  const NamesForm({super.key, required this.onSaved, this.later});
  final VoidCallback onSaved;

  /// Shown as a "Maybe later" button when set (the welcome page).
  final VoidCallback? later;
  @override
  State<NamesForm> createState() => _NamesFormState();
}

class _NamesFormState extends State<NamesForm> {
  late final _nickname = TextEditingController(
    text: BridgeScope.of(context).profile?.nickname ?? '',
  );
  late final _realName = TextEditingController(
    text: BridgeScope.of(context).profile?.realName ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    _realName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await BridgeScope.of(context)
        .saveNames(_nickname.text, _realName.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.t('namesNote'),
          style: const TextStyle(fontSize: 14, color: Palette.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('nickname'),
          controller: _nickname,
          maxLength: 30,
          decoration: InputDecoration(labelText: vm.t('nickname')),
        ),
        TextField(
          key: const Key('real-name'),
          controller: _realName,
          maxLength: 50,
          decoration: InputDecoration(labelText: vm.t('realName')),
        ),
        if (_error != null) ErrorPanel(message: _error!),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          children: [
            if (widget.later != null)
              TextButton(
                key: const Key('names-later'),
                onPressed: widget.later,
                child: Text(vm.t('welcomeLater')),
              ),
            FilledButton(
              key: const Key('save-names'),
              onPressed: _busy ? null : _save,
              child: Text(vm.t('saveNames')),
            ),
          ],
        ),
      ],
    );
  }
}

/// Asked once right after signing in, while no name is set.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, this.next});
  final String? next;
  String get _next {
    final n = next;
    return n != null && n.startsWith('/') && !n.startsWith('//') ? n : '/';
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Text(vm.t('welcomeTitle'), style: displayStyle(28)),
        NamesForm(
          onSaved: () => context.go(_next),
          later: () => context.go(_next),
        ),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 880,
      children: [
        Row(
          children: [
            const CircleAvatar(
              backgroundColor: Palette.paleMoss,
              foregroundColor: Palette.moss,
              child: Text('Y'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.profile?.realName ?? vm.t('anonymousShare'),
                    style: const TextStyle(color: Palette.muted, fontSize: 14),
                  ),
                  Text(
                    vm.profile?.nickname ?? vm.t('anonymousStudent'),
                    style: displayStyle(23),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!vm.signedIn) ...[
          Text(vm.t('signInNeeded')),
          FilledButton(
            key: const Key('profile-sign-in'),
            onPressed: () => ensureSignedIn(context),
            child: Text(vm.t('signIn')),
          ),
        ] else ...[
          PaperHeading(vm.t('mySharedExperiences')),
          ResourceView<List<MyExperience>>(
            resource: (vm) => vm.mine,
            load: (vm) => vm.loadMine(),
            builder: (context, mine) => _MyExperiences(items: mine),
          ),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperHeading(vm.t('profileNames')),
                NamesForm(onSaved: () => vm.showNotice(vm.t('namesSaved'))),
              ],
            ),
          ),
          PaperHeading(vm.t('savedExperiences')),
          ResourceView<List<ExperienceItem>>(
            resource: (vm) => vm.saved,
            load: (vm) => vm.loadSaved(),
            builder: (context, items) => _SavedExperiences(items: items),
          ),
          const _AccountPanel(),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(vm.t('language')),
            ChoiceChip(
              label: const Text('繁中'),
              selected: !vm.english,
              onSelected: (_) => vm.setEnglish(false),
            ),
            ChoiceChip(
              label: const Text('English'),
              selected: vm.english,
              onSelected: (_) => vm.setEnglish(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _MyExperiences extends StatelessWidget {
  const _MyExperiences({required this.items});
  final List<MyExperience> items;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final published = items.where((e) => e.status == 'published').toList();
    final helpful = published.fold(0, (sum, e) => sum + e.impact.helpful);
    final people = published.fold(0, (sum, e) => sum + e.impact.peopleReached);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty) Text(vm.t('noShares')),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      PaperTag(vm.t(topicKey(item.topicId))),
                      PaperTag(
                        vm.t(item.status),
                        color: item.status == 'published'
                            ? Palette.paleMoss
                            : Palette.ochre,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.originalVoice,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.status == 'published') ...[
                    const SizedBox(height: 8),
                    Text(
                      '${item.impact.helpful} ${vm.t('foundHelpful')} · '
                      '${item.impact.different} ${vm.t('reactions')}',
                      style: const TextStyle(color: Palette.muted),
                    ),
                  ],
                  Wrap(
                    children: [
                      if (item.status == 'published')
                        TextButton(
                          onPressed: () => context.push(
                            '/experiences/${item.id}?from=${Uri.encodeComponent('/profile')}',
                          ),
                          child: Text(vm.t('similarSituations')),
                        ),
                      TextButton(
                        onPressed: () async {
                          if (await confirmDialog(
                            context,
                            vm.t('delete'),
                            vm.pair('要刪除這則經驗嗎？', 'Delete this experience?'),
                          )) {
                            await vm.deleteExperience(item.id);
                          }
                        },
                        child: Text(vm.t('delete')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaperHeading(vm.t('yourImpact')),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    _Stat(
                      width: (c.maxWidth - 24) / 2,
                      value: published.length,
                      label: vm.pair('則匿名分享', 'anonymous shares'),
                    ),
                    _Stat(
                      width: (c.maxWidth - 24) / 2,
                      value: helpful,
                      label: vm.pair('次「有幫助」', '"helpful" reactions'),
                    ),
                    _Stat(
                      width: (c.maxWidth - 24) / 2,
                      value: people,
                      label: vm.pair('位學生有回應', 'students responded'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedExperiences extends StatelessWidget {
  const _SavedExperiences({required this.items});
  final List<ExperienceItem> items;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (items.isEmpty) {
      return Text(
        vm.t('noSaved'),
        style: const TextStyle(color: Palette.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            key: Key('saved-${item.id}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '「${item.voice(vm.translated(item))}」',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vm.t(topicKey(item.topicId)),
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => vm.toggleSaved(item),
                        child: Text(vm.t('unsave')),
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          '/experiences/${item.id}?from=${Uri.encodeComponent('/profile')}',
                        ),
                        child: Text(vm.t('openSaved')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.width, required this.value, required this.label});
  final double width;
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: displayStyle(48).copyWith(color: Palette.moss)),
        Text(label),
      ],
    ),
  );
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PaperHeading(vm.t('account')),
          if (vm.profile != null)
            SelectableText(
              '${vm.pair('帳號編號', 'Account ID')}: ${vm.profile!.id}',
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          if (vm.isStaff)
            TextButton(
              onPressed: () => context.push('/admin'),
              child: const Text('Admin'),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
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
                  child: Text(vm.pair('沒有封鎖任何作者。', 'No blocked authors.')),
                ),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                key: const Key('sign-out'),
                onPressed: vm.signOut,
                child: Text(vm.t('signOut')),
              ),
              TextButton(
                key: const Key('delete-account'),
                style: TextButton.styleFrom(foregroundColor: Palette.brickDeep),
                onPressed: () async {
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
                child: Text(vm.t('deleteAccount')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.next});
  final String? next;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _next {
    final next = widget.next;
    return next != null && next.startsWith('/') && !next.startsWith('//')
        ? next
        : '/';
  }

  Future<void> _run(Future<void> Function() signIn) async {
    final vm = BridgeScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await signIn();
      await vm.loadProfile();
      if (!mounted) return;
      final profile = vm.profile;
      final unnamed =
          profile != null &&
          profile.nickname == null &&
          profile.realName == null;
      context.go(
        unnamed ? '/welcome?next=${Uri.encodeComponent(_next)}' : _next,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = BridgeScope.of(context).t('genericError'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Text(vm.t('signInNeeded')),
        Text(
          vm.pair(
            '你分享的經驗預設匿名；只有你選擇時才會顯示暱稱或真名，學校和帳號永遠不會公開。',
            'What you share is anonymous by default; a nickname or real name shows only if you choose, and your school and account never do.',
          ),
          style: const TextStyle(color: Palette.muted),
        ),
        if (vm.auth case DevAuthService(enabled: false))
          ErrorPanel(
            message: vm.pair(
              '登入服務尚未設定，請聯絡管理者。',
              'Sign-in is not set up yet. Please contact the team.',
            ),
          )
        else if (vm.auth.usesDevLogin) ...[
          Text(vm.t('devLoginNote'), style: const TextStyle(fontSize: 14)),
          TextField(
            key: const Key('dev-name'),
            controller: _name,
            decoration: InputDecoration(labelText: vm.t('yourName')),
            onSubmitted: (_) => _run(() => vm.auth.signInAsDev(_name.text)),
          ),
          FilledButton(
            key: const Key('dev-sign-in'),
            onPressed: _busy
                ? null
                : () => _run(() => vm.auth.signInAsDev(_name.text)),
            child: Text(vm.t('signIn')),
          ),
        ] else
          FilledButton.icon(
            key: const Key('google-sign-in'),
            onPressed: _busy ? null : () => _run(vm.auth.signInWithGoogle),
            icon: const Icon(Icons.login),
            label: Text(vm.t('signInWithGoogle')),
          ),
        if (_error != null) ErrorPanel(message: _error!),
      ],
    );
  }
}
