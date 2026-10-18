import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../view_models/bridge_view_model.dart';
import 'post_cards.dart';

/// Opens the assistant. Only signed-in users may use it; guests are asked to sign in first.
Future<void> openAssistantFor(BuildContext context, {String? question}) async {
  final vm = BridgeScope.of(context);
  if (vm.signedIn) {
    vm.openAssistant(question: question);
    return;
  }
  final router = GoRouter.of(context);
  final here = router.routerDelegate.currentConfiguration.uri.toString();
  final signIn = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('assistant-sign-in'),
      title: Text(vm.pair('請先登入', 'Please sign in first')),
      content: Text(
        vm.pair('登入後才可以使用 AI 助理。', 'Sign in to use the AI assistant.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(vm.t('cancel')),
        ),
        FilledButton(
          key: const Key('assistant-sign-in-go'),
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(vm.t('signIn')),
        ),
      ],
    ),
  );
  if (signIn == true) router.push('/signin?next=${Uri.encodeComponent(here)}');
}

/// The round chat bubble at the bottom right; it opens and closes the assistant.
class AssistantBubble extends StatelessWidget {
  const AssistantBubble({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Semantics(
      button: true,
      expanded: vm.assistantOpen,
      label: vm.pair('AI 助理', 'AI assistant'),
      excludeSemantics: true,
      child: Tooltip(
        message: vm.pair('AI 助理', 'AI assistant'),
        child: Material(
          key: const Key('assistant-button'),
          color: Palette.moss,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Palette.ink.withValues(alpha: .5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: vm.assistantOpen
                ? vm.closeAssistant
                : () => openAssistantFor(context),
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: AppIcon('chat', size: 26, color: Palette.onMoss),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The open assistant: a near-full-height panel on phones, a floating window elsewhere.
class AssistantOverlay extends StatelessWidget {
  const AssistantOverlay({
    super.key,
    required this.uri,
    required this.onNavigate,
  });
  final Uri uri;
  final void Function(String path) onNavigate;

  static const windowSize = Size(380, 540);

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final phone = AppLayout.of(context) == AppLayout.phone;
    final panel = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): vm.closeAssistant,
      },
      child: FocusScope(
        autofocus: true,
        child: AssistantPanel(
          uri: uri,
          onNavigate: (path) {
            if (phone) vm.closeAssistant();
            onNavigate(path);
          },
        ),
      ),
    );
    if (!phone) {
      final size = MediaQuery.sizeOf(context);
      return Positioned(
        right: 28,
        bottom: 96,
        width: windowSize.width,
        height: (size.height - 96 - 80).clamp(320, windowSize.height),
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          label: vm.pair('Culture Bridge 助理', 'Culture Bridge assistant'),
          child: Container(
            decoration: BoxDecoration(
              color: Palette.high,
              border: Border.all(color: Palette.edge),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Palette.ink.withValues(alpha: .12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Palette.ink.withValues(alpha: .3),
                  blurRadius: 36,
                  spreadRadius: -16,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Material(type: MaterialType.transparency, child: panel),
          ),
        ),
      );
    }
    final top = MediaQuery.paddingOf(context).top + 72;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: vm.closeAssistant,
              child: ColoredBox(color: Palette.ink.withValues(alpha: .38)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: top,
            bottom: 0,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: vm.pair('Culture Bridge 助理', 'Culture Bridge assistant'),
              child: Material(
                color: Palette.high,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                  side: BorderSide(color: Palette.oat),
                ),
                child: SafeArea(top: false, child: panel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _suggested = [
  ('居留證要準備什麼？', 'What do I need for an ARC?'),
  ('怎麼加入健保？', 'How do I join NHI?'),
  ('租屋要注意什麼？', 'What should I check when renting?'),
];

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.uri,
    required this.onNavigate,
  });
  final Uri uri;
  final void Function(String path) onNavigate;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _seen = 0;

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

  Future<void> _ask(String text) async {
    final vm = BridgeScope.of(context);
    if (text.trim().isEmpty || vm.asking) return;
    _input.clear();
    await vm.ask(text, screen: _screen());
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final count = vm.chat.length + (vm.asking ? 1 : 0);
    if (count != _seen) {
      _seen = count;
      _scrollToEnd();
    }
    // With large text the emergency line scrolls with the chat, so the input stays visible.
    final urgentInLog = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Avatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    vm.pair('Culture Bridge 助理', 'Culture Bridge assistant'),
                    style: displayStyle(16),
                  ),
                ),
              ),
              if (vm.chat.isNotEmpty)
                IconButton(
                  key: const Key('assistant-clear'),
                  tooltip: vm.pair('清除對話', 'Clear conversation'),
                  onPressed: vm.clearChat,
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Palette.muted,
                  ),
                ),
              IconButton(
                key: const Key('assistant-close'),
                tooltip: vm.pair('關閉', 'Close'),
                onPressed: vm.closeAssistant,
                icon: const AppIcon('close', size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Semantics(
              liveRegion: true,
              // Built in full (chats are short) so scrolling to the end is exact.
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Bubble(
                      text: vm.pair(
                        '嗨！我是 Culture Bridge 助理，在台灣生活遇到問題都可以問我。',
                        "Hi! I'm the Culture Bridge assistant. Ask me anything about life in Taiwan.",
                      ),
                    ),
                    if (vm.chat.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          direction: Axis.vertical,
                          spacing: 8,
                          children: [
                            for (final q in _suggested)
                              NoteChip(
                                label: vm.pair(q.$1, q.$2),
                                selected: false,
                                onTap: () => _ask(vm.pair(q.$1, q.$2)),
                              ),
                          ],
                        ),
                      ),
                    for (final entry in vm.chat)
                      _Entry(entry: entry, onNavigate: widget.onNavigate),
                    if (vm.asking)
                      _Bubble(text: vm.pair('想一下…', 'Thinking…'), muted: true),
                    if (urgentInLog)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: _UrgentLine(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const DashedRule(color: Palette.edge),
          const SizedBox(height: 6),
          if (!urgentInLog) ...[const _UrgentLine(), const SizedBox(height: 4)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('assistant-input'),
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: vm.pair('輸入你的問題…', 'Type your question…'),
                    counterText: '',
                  ),
                  onSubmitted: _ask,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('assistant-send'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: vm.asking ? null : () => _ask(_input.text),
                child: Text(vm.pair('送出', 'Send')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Emergency or a real person: the 1990 hotline and the university's international office.
class _UrgentLine extends StatelessWidget {
  const _UrgentLine();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          vm.pair('緊急或需要真人：', 'Urgent, or need a person: '),
          style: mutedStyle.copyWith(fontSize: 12),
        ),
        Link(
          uri: Uri.parse('tel:1990'),
          builder: (context, follow) => InkWell(
            onTap: follow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                vm.pair('1990 外國人生活諮詢熱線', '1990 foreigner hotline'),
                style: const TextStyle(
                  fontSize: 12,
                  color: Palette.brickDeep,
                  decoration: TextDecoration.underline,
                  decorationColor: Palette.brick,
                ),
              ),
            ),
          ),
        ),
        Text(
          vm.pair(
            '（免付費，24 小時）· 逢甲大學國際事務處（行政二館 303 室）',
            ' (free, 24 h) · FCU Office of International Affairs (Admin Bldg II, Rm 303)',
          ),
          style: mutedStyle.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, this.mine = false, this.muted = false});
  final String text;
  final bool mine;
  final bool muted;
  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: .86,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? Palette.moss : Palette.bubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(mine ? 12 : 4),
              bottomRight: Radius.circular(mine ? 4 : 12),
            ),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: mine
                  ? Palette.onMoss
                  : muted
                  ? Palette.muted
                  : Palette.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.onNavigate});
  final ChatEntry entry;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final reply = entry.reply;
    final links = <(String, String)>[
      if (reply != null) ...[
        for (final card in reply.cards)
          card.type == 'action'
              ? (
                  card.title ?? vm.pair('官方指南', 'Official guide'),
                  '/actions/${card.id}',
                )
              : (
                  vm.pair('看這篇學生分享', 'Read this student post'),
                  '/experiences/${card.id}',
                ),
        for (final action in reply.screenActions)
          if (screenActionPath(action) case final path?)
            (_actionLabel(vm, action), path),
      ],
    ];
    return Column(
      crossAxisAlignment: entry.fromUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _Bubble(text: entry.text, mine: entry.fromUser, muted: entry.failed),
        for (final (label, path) in links)
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: const TextStyle(
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Palette.brick,
              ),
            ),
            onPressed: () => onNavigate(path),
            child: Text('$label →'),
          ),
        if (reply != null)
          for (final operation in reply.pendingOperations)
            _OperationCard(operation: operation, onNavigate: onNavigate),
      ],
    );
  }

  String _actionLabel(BridgeViewModel vm, ScreenAction action) =>
      switch (action.type) {
        'open_action' => vm.pair('打開官方指南', 'Open the guide'),
        'open_progress' => vm.pair('打開辦理進度', 'Open progress'),
        'open_experience' => vm.pair('看這篇學生分享', 'Read this student post'),
        'open_explore' => vm.pair('去探索看看', 'Go to Explore'),
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
    'open_explore' => switch (action.topic) {
      'life_adaptation' => '/explore?cat=life',
      'culture_communication' => '/explore?cat=culture',
      final String key when categoryLabels.containsKey(key) =>
        '/explore?cat=$key',
      _ => '/explore',
    },
    'open_share' => '/share',
    _ => null,
  };
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
      padding: const EdgeInsets.only(bottom: 10),
      child: NoteCard(
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
