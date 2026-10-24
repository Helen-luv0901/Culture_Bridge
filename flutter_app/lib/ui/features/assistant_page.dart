import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_shell.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../core/loading.dart';
import 'assistant_panel.dart';
import 'post_cards.dart';

/// The assistant tab: the same chat as the bubble's window, filling the page. The
/// conversation is shared, so a chat started in the window continues here.
class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.signedIn) return const PageFrame(child: _SignInToAsk());
    final layout = AppLayout.of(context);
    final padding = switch (layout) {
      AppLayout.phone => EdgeInsets.zero,
      AppLayout.tablet => const EdgeInsets.fromLTRB(28, 24, 28, 24),
      AppLayout.web => const EdgeInsets.fromLTRB(32, 28, 32, 28),
    };
    return NotebookBackground(
      child: Padding(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppShell.maxContentWidth,
            ),
            child: Material(
              key: const Key('assistant-page'),
              color: Palette.high,
              shape: layout == AppLayout.phone
                  ? const RoundedRectangleBorder()
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                      side: const BorderSide(color: Palette.edge),
                    ),
              child: AssistantPanel(
                uri: GoRouterState.of(context).uri,
                onNavigate: (path) => context.push(path),
                closable: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a guest sees on the assistant page (from a link): sign in first.
class _SignInToAsk extends StatelessWidget {
  const _SignInToAsk();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 760,
      children: [
        EmptyNote(
          key: const Key('assistant-sign-in'),
          title: vm.pair('請先登入', 'Please sign in'),
          body: vm.pair(signInForAssistant.$1, signInForAssistant.$2),
          action: vm.t('signIn'),
          onAction: () => ensureSignedIn(context),
        ),
      ],
    );
  }
}
