import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_shell.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import 'assistant_panel.dart';

/// The assistant tab: the same chat as the bubble's window, filling the page. The
/// conversation is shared, so a chat started in the window continues here.
class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                      borderRadius: BorderRadius.circular(Radii.card),
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
