import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../view_models/bridge_view_model.dart';
import 'browse_pages.dart';

/// The floating assistant (C-11): a bottom sheet on phones, a side panel on wide screens.
/// It scrolls and closes independently of the page underneath.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key, required this.uri, required this.mobile});
  final Uri uri;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FloatingActionButton.extended(
      key: const Key('assistant-button'),
      backgroundColor: Palette.moss,
      foregroundColor: Palette.high,
      icon: const Icon(Icons.chat_bubble_outline),
      label: Text(vm.pair('問助理', 'Ask')),
      tooltip: vm.pair('AI 助理', 'AI assistant'),
      onPressed: () {
        if (mobile) {
          final router = GoRouter.of(context);
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Palette.high,
            builder: (sheet) => BridgeScope(
              viewModel: vm,
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: AssistantPanel(
                  uri: uri,
                  onNavigate: (path) {
                    Navigator.pop(sheet);
                    router.push(path);
                  },
                  onClose: () => Navigator.pop(sheet),
                ),
              ),
            ),
          );
        } else {
          Scaffold.of(context).openEndDrawer();
        }
      },
    );
  }
}

class AssistantDrawer extends StatelessWidget {
  const AssistantDrawer({super.key, required this.uri});
  final Uri uri;
  @override
  Widget build(BuildContext context) => Drawer(
    width: 440,
    backgroundColor: Palette.high,
    child: SafeArea(
      child: AssistantPanel(
        uri: uri,
        onNavigate: (path) => context.push(path),
        onClose: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.uri,
    required this.onNavigate,
    required this.onClose,
  });
  final Uri uri;
  final void Function(String path) onNavigate;
  final VoidCallback onClose;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, String> _screen() {
    final segments = widget.uri.pathSegments;
    return {
      'route': widget.uri.path,
      if (segments.length >= 2 && segments[0] == 'actions')
        'action_id': segments[1],
      if (segments.length >= 2 && segments[0] == 'experiences')
        'experience_id': segments[1],
    };
  }

  Future<void> _send() async {
    final vm = BridgeScope.of(context);
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await vm.ask(text, screen: _screen());
    if (_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  vm.pair('AI 助理', 'AI assistant'),
                  style: displayStyle(22),
                ),
              ),
              // Icons, not text buttons: with large text a labelled button squeezed the title
              // into a tall column and pushed the input off a phone screen.
              if (vm.chat.isNotEmpty)
                IconButton(
                  key: const Key('assistant-clear'),
                  tooltip: vm.pair('清除對話', 'Clear conversation'),
                  onPressed: vm.clearChat,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              IconButton(
                tooltip: vm.pair('關閉', 'Close'),
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(color: Palette.edge, height: 1),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (vm.chat.isEmpty)
                Text(
                  vm.pair(
                    '可以問我辦理流程、學生經驗或 App 的使用方式。我會附上依據與驗證狀態；不確定的事會直接說。',
                    'Ask about procedures, student experiences or how to use the app. I cite my sources and verification status, and say so when I don\'t know.',
                  ),
                  style: const TextStyle(color: Palette.muted),
                ),
              for (final entry in vm.chat)
                _Entry(entry: entry, onNavigate: widget.onNavigate),
              if (vm.asking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(
                    color: Palette.moss,
                    backgroundColor: Palette.edge,
                  ),
                ),
            ],
          ),
        ),
        const Divider(color: Palette.edge, height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            8,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('assistant-input'),
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: vm.pair(
                      '例如：工作證要準備什麼？',
                      'e.g. What do I need for a work permit?',
                    ),
                    hintMaxLines: 2,
                    counterText: '',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                key: const Key('assistant-send'),
                tooltip: vm.t('send'),
                onPressed: vm.asking ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.onNavigate});
  final ChatEntry entry;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final reply = entry.reply;
    return Align(
      alignment: entry.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(12),
        color: entry.fromUser
            ? Palette.paleMoss
            : entry.failed
            ? Palette.ochre
            : Palette.oat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(entry.text),
            if (reply != null) ...[
              for (final card in reply.cards)
                _AnswerCard(card: card, onNavigate: onNavigate),
              for (final action in reply.screenActions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(_actionLabel(vm, action)),
                    onPressed: () {
                      final path = screenActionPath(action);
                      if (path != null) onNavigate(path);
                    },
                  ),
                ),
              for (final operation in reply.pendingOperations)
                _OperationCard(operation: operation, onNavigate: onNavigate),
            ],
          ],
        ),
      ),
    );
  }

  String _actionLabel(BridgeViewModel vm, ScreenAction action) =>
      switch (action.type) {
        'open_action' => vm.pair('打開流程', 'Open procedure'),
        'open_progress' => vm.pair('打開辦理進度', 'Open progress'),
        'open_experience' => vm.pair('打開這則經驗', 'Open experience'),
        'open_explore' => vm.pair('去探索', 'Go to Explore'),
        'open_share' => vm.pair('去分享', 'Go to Share'),
        _ => action.type,
      };
}

/// Whitelisted screen actions only (A-16, C-13); anything else is ignored.
String? screenActionPath(ScreenAction action) {
  final id = action.targetId == null
      ? null
      : Uri.encodeComponent(action.targetId!);
  return switch (action.type) {
    'open_action' when id != null => '/actions/$id',
    'open_progress' when id != null => '/actions/$id/progress',
    'open_experience' when id != null => '/experiences/$id',
    'open_explore' =>
      action.topic != null && topicKeys.containsKey(action.topic)
          ? '/explore?topic=${topicKeys[action.topic]}'
          : '/explore',
    'open_share' => '/share',
    _ => null,
  };
}

/// Procedure or experience the answer relied on (C-12).
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.card, required this.onNavigate});
  final AssistantCard card;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (card.type == 'experience') {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: PaperCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperTag(
                vm.pair('學生經驗（非官方）', 'Student experience (not official)'),
              ),
              const SizedBox(height: 8),
              Text(card.reminder ?? ''),
              TextButton(
                onPressed: () => onNavigate('/experiences/${card.id}'),
                child: Text(vm.t('similarSituations')),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PaperCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vm.pair('依據', 'Based on')}: ${card.title}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            StatusTag(card.verificationStatus ?? 'unverified'),
            const SizedBox(height: 6),
            Text(
              card.lastVerifiedAt != null
                  ? '${vm.t('lastOfficialUpdate')}: ${card.lastVerifiedAt}'
                  : vm.t('notYetVerified'),
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              card.recentSuccessCount > 0
                  ? '${card.recentSuccessCount} ${vm.t('recentlyCompleted')}'
                  : vm.t('noRecentCompletions'),
              style: const TextStyle(fontSize: 13),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => onNavigate('/actions/${card.id}'),
                  child: Text(vm.t('startAction')),
                ),
                TextButton(
                  onPressed: () => onNavigate('/actions/${card.id}'),
                  child: Text(vm.pair('看來源', 'View sources')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A write the assistant prepared; nothing happens until the user confirms (A-17, C-13).
class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation, required this.onNavigate});
  final PendingOperation operation;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final status = vm.operationStates[operation.id] ?? operation.status;
    final expired =
        status == 'pending' && DateTime.now().isAfter(operation.expiresAt);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PaperCard(
        color: Palette.paleMoss,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              operation.summary,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (status == 'pending' && !expired)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: Key('confirm-${operation.id}'),
                    onPressed: () => vm.resolveOperation(operation, true),
                    child: Text(vm.t('confirm')),
                  ),
                  TextButton(
                    onPressed: () => vm.resolveOperation(operation, false),
                    child: Text(vm.t('cancel')),
                  ),
                ],
              )
            else if (status == 'confirmed')
              TextButton(
                onPressed: () =>
                    onNavigate('/actions/${operation.targetId}/progress'),
                child: Text(vm.pair('已開始，打開進度', 'Started. Open progress')),
              )
            else
              Text(switch (expired ? 'expired' : status) {
                'cancelled' => vm.pair('已取消', 'Cancelled'),
                'expired' => vm.pair('已過期，請再問一次', 'Expired. Ask again.'),
                _ => vm.pair('無法完成', 'Could not be done'),
              }, style: const TextStyle(color: Palette.muted)),
          ],
        ),
      ),
    );
  }
}
