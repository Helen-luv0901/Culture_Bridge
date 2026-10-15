import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_service.dart';
import '../core/design_system.dart';
import '../core/loading.dart';

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
