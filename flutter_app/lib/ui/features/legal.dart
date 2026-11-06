import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import '../core/design_system.dart';

/// Said wherever the assistant answers: the answers are generated and can be wrong.
const aiMayBeWrong = (
  'AI 回答可能有誤，請以官方公告為準。',
  'AI answers can be wrong; check the official source.',
);

/// Who processes what people write (the same wording in the terms sheet and AI notice).
const geminiProcessing = (
  '你的貼文和給助理的訊息會交給 Google Gemini 處理，用來翻譯、建議標籤、搜尋和產生助理的回答。',
  'Your posts and messages to the assistant are processed by Google Gemini for '
      'translation, tag suggestions, search and the assistant’s answers.',
);

/// Privacy policy, terms of use and (when the server has one) the support email, opened in
/// the browser. [dense]: one line of small links (sign-in, the terms sheet); otherwise
/// rows (settings).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.dense = false, this.keyPrefix = 'link-'});
  final bool dense;

  /// Keys are `<prefix>privacy`, `<prefix>terms` and `<prefix>support`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final email = vm.config.supportEmail;
    final links = [
      (
        'privacy',
        vm.pair('隱私權政策', 'Privacy policy'),
        vm.siteUri(vm.config.privacyPath),
      ),
      (
        'terms',
        vm.pair('使用條款', 'Terms of use'),
        vm.siteUri(vm.config.termsPath),
      ),
      if (email != null)
        (
          'support',
          vm.pair('聯絡我們：$email', 'Contact us: $email'),
          Uri(scheme: 'mailto', path: email),
        ),
    ];
    Widget link((String, String, Uri) entry) {
      final (name, label, uri) = entry;
      return Link(
        key: Key('$keyPrefix$name'),
        uri: uri,
        target: LinkTarget.blank,
        builder: (context, follow) => dense
            ? TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(
                    fontFamily: appFont,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: Palette.brick,
                  ),
                ),
                onPressed: follow,
                child: Text(label),
              )
            : InkWell(
                onTap: follow,
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      const Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: Palette.muted,
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    if (dense) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (final entry in links) link(entry)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, entry) in links.indexed) ...[
          if (i > 0) const Divider(),
          link(entry),
        ],
      ],
    );
  }
}

/// True when the current terms are accepted; otherwise shows the terms sheet first (before
/// the first post or comment, or after the server refused one). False when declined.
Future<bool> ensureTermsAccepted(BuildContext context) async {
  final vm = BridgeScope.of(context);
  if (!vm.needsTerms) return true;
  FocusManager.instance.primaryFocus?.unfocus();
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Palette.high,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const TermsSheet(),
  );
  return accepted ?? false;
}

/// The rules in short, what AI does with posts, links to the full terms and privacy policy,
/// and 「同意並繼續」.
class TermsSheet extends StatefulWidget {
  const TermsSheet({super.key});
  @override
  State<TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<TermsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    final vm = BridgeScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await vm.acceptTerms();
    if (!mounted) return;
    if (error == null) return Navigator.pop(context, true);
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final points = [
      vm.pair(
        '零容忍：不允許令人反感的內容（色情、暴力、仇恨、騷擾等），也不容許霸凌或騷擾其他使用者。',
        'Zero tolerance: no objectionable content (sexual, violent, hateful, harassing) '
            'and no abusive users.',
      ),
      vm.pair(
        '被檢舉的內容會在 24 小時內審查；違規內容會被移除，違規的帳號會被停權。',
        'Reported content is reviewed within 24 hours; offending content is removed and '
            'offending accounts are suspended.',
      ),
      vm.pair(geminiProcessing.$1, geminiProcessing.$2),
      vm.pair(aiMayBeWrong.$1, aiMayBeWrong.$2),
    ];
    return SingleChildScrollView(
      key: const Key('terms-sheet'),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              vm.pair('發文前，請先看看使用條款', 'Before you post: the terms of use'),
              style: displayStyle(19),
            ),
          ),
          const SizedBox(height: 12),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: Palette.brick)),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          const LegalLinks(dense: true, keyPrefix: 'terms-link-'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: Palette.danger),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                key: const Key('terms-decline'),
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(vm.pair('先不要', 'Not now')),
              ),
              FilledButton(
                key: const Key('terms-accept'),
                onPressed: _busy ? null : _accept,
                child: Text(vm.pair('同意並繼續', 'Agree and continue')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// True once the AI notice was seen; shows it the first time (before the first question).
Future<bool> ensureAiNoticeSeen(BuildContext context) async {
  final vm = BridgeScope.of(context);
  if (vm.aiNoticeSeen) return true;
  FocusManager.instance.primaryFocus?.unfocus();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('ai-notice'),
      title: Text(
        vm.pair('關於 AI 助理', 'About the AI assistant'),
        style: displayStyle(18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vm.pair(geminiProcessing.$1, geminiProcessing.$2)),
            const SizedBox(height: 8),
            Text(vm.pair(aiMayBeWrong.$1, aiMayBeWrong.$2)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(vm.t('cancel')),
        ),
        FilledButton(
          key: const Key('ai-notice-ok'),
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(vm.pair('知道了', 'Got it')),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  vm.acknowledgeAiNotice();
  return true;
}
