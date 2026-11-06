import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';

import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/layout.dart';
import '../core/loading.dart';
import '../core/motion.dart';
import '../view_models/bridge_view_model.dart';
import 'browse_pages.dart' show showReportDialog;
import 'legal.dart';
import 'post_cards.dart';

/// Opens the assistant. Only signed-in users may use it; guests are asked to sign in first.
Future<void> openAssistantFor(BuildContext context, {String? question}) async {
  final vm = BridgeScope.of(context);
  // Guests see the panel too: suggestions that search the guides, and a sign-in line
  // where the input would be, instead of a sign-in dialog in front of everything.
  final ask = vm.signedIn ? question : null;
  if (ask == null || vm.aiNoticeSeen) return vm.openAssistant(question: ask);
  // The first question waits for the AI notice.
  vm.openAssistant();
  if (await ensureAiNoticeSeen(context)) await vm.ask(ask);
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
class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay({
    super.key,
    required this.uri,
    required this.onNavigate,
    required this.animation,
  });
  final Uri uri;
  final void Function(String path) onNavigate;

  /// 0 = gone, 1 = open (AnimatedPresence in the shell). A drag on the phone sheet
  /// moves it by hand.
  final AnimationController animation;

  static const windowSize = Size(380, 540);

  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay> {
  late BridgeViewModel _vm;
  ModalRoute<Object?>? _route;

  /// While a finger moves the sheet (and its spring settles), it follows 1:1, no curve.
  var _byHand = false;
  late final _sheetOffset = _SheetOffset(widget.animation, () => _byHand);

  void _dragStart(DragStartDetails _) {
    widget.animation.stop();
    setState(() => _byHand = true);
  }

  void _dragUpdate(DragUpdateDetails details, double height) {
    final moved = (details.primaryDelta ?? 0) / height;
    widget.animation.value = (widget.animation.value - moved).clamp(0.0, 1.0);
  }

  /// Let go: the finger's speed carries into a spring (apple-design, velocity handoff).
  /// A quick flick down, or a sheet already more than half way down, closes.
  Future<void> _dragEnd(DragEndDetails details, double height) async {
    final speed = details.velocity.pixelsPerSecond.dy;
    final value = widget.animation.value;
    final close = speed > 700 || (speed > -300 && value < 0.55);
    final simulation = SpringSimulation(
      _sheetSpring,
      value,
      close ? 0 : 1,
      -speed / height,
    );
    await widget.animation.animateWith(simulation);
    if (!mounted) return;
    // A spring stops within a hair of its target; land exactly on it.
    widget.animation.value = close ? 0 : 1;
    setState(() => _byHand = false);
    if (close) _vm.closeAssistant();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vm = BridgeScope.of(context);
    _route = ModalRoute.of(context);
  }

  // Esc closes the assistant even when the focus is still on the page behind it, but
  // not while a dialog or menu is open over the page: Esc is that one's to close.
  bool _onKey(KeyEvent event) {
    if (!mounted ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        _route?.isCurrent == false) {
      return false;
    }
    _vm.closeAssistant();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = widget.uri;
    final onNavigate = widget.onNavigate;
    final vm = BridgeScope.of(context);
    final phone = AppLayout.of(context) == AppLayout.phone;
    final panel = FocusScope(
      autofocus: true,
      child: AssistantPanel(
        uri: uri,
        // Opening a guide or post closes the chat, so the page isn't covered.
        onNavigate: (path) {
          vm.closeAssistant();
          onNavigate(path);
        },
      ),
    );
    if (!phone) {
      final size = MediaQuery.sizeOf(context);
      return Positioned(
        right: 28,
        bottom: 96,
        width: AssistantOverlay.windowSize.width,
        height: (size.height - 96 - 80).clamp(
          320,
          AssistantOverlay.windowSize.height,
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: widget.animation,
            curve: Motion.easeOut,
            reverseCurve: Motion.easeOut.flipped,
          ),
          child: ScaleTransition(
            key: const Key('assistant-window-motion'),
            // Grows out of the bubble below it, not from the middle of the screen.
            alignment: Alignment.bottomRight,
            scale: Tween(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(
                parent: widget.animation,
                curve: Motion.easeOut,
                reverseCurve: Motion.easeOut.flipped,
              ),
            ),
            child: Semantics(
              role: SemanticsRole.dialog,
              scopesRoute: true,
              explicitChildNodes: true,
              label: vm.pair('Culture Bridge 助理', 'Culture Bridge assistant'),
              child: Container(
                decoration: BoxDecoration(
                  color: Palette.high,
                  border: Border.all(color: Palette.edge),
                  borderRadius: BorderRadius.circular(Radii.card),
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
          ),
        ),
      );
    }
    // With the keyboard up (reported as an inset, or a page shrunk to what it leaves)
    // the sheet takes the whole height above it, so the chat stays big enough to read.
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final top = keyboardUp(context)
        ? media.padding.top
        : media.padding.top + 72;
    return Positioned.fill(
      child: Stack(
        children: [
          // The panel covers the page, so screen readers leave the page behind it.
          const BlockSemantics(),
          // The scrim is for taps; screen readers close with the panel's own button.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: vm.closeAssistant,
                child: FadeTransition(
                  opacity: widget.animation,
                  child: ColoredBox(color: Palette.ink.withValues(alpha: .38)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: top,
            bottom: keyboard,
            child: LayoutBuilder(
              builder: (context, constraints) => SlideTransition(
                key: const Key('assistant-sheet-motion'),
                position: _sheetOffset,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Semantics(
                        role: SemanticsRole.dialog,
                        scopesRoute: true,
                        namesRoute: true,
                        explicitChildNodes: true,
                        label: vm.pair(
                          'Culture Bridge 助理',
                          'Culture Bridge assistant',
                        ),
                        child: Material(
                          color: Palette.high,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            side: BorderSide(color: Palette.oat),
                          ),
                          child: SafeArea(top: false, child: panel),
                        ),
                      ),
                    ),
                    // The top edge is the handle: drag the sheet down to close it.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 22,
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          key: const Key('assistant-grabber'),
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragStart: _dragStart,
                          onVerticalDragUpdate: (d) =>
                              _dragUpdate(d, constraints.maxHeight),
                          onVerticalDragEnd: (d) =>
                              _dragEnd(d, constraints.maxHeight),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Palette.oat,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A critically damped spring that settles in about a third of a second, no bounce.
const _sheetSpring = SpringDescription(mass: 1, stiffness: 320, damping: 36);

/// Where the phone sheet sits: below the screen at 0, in place at 1. It eases in and out
/// on the iOS sheet curve, but follows the finger (and its spring) without a curve.
class _SheetOffset extends Animation<Offset>
    with AnimationWithParentMixin<double> {
  _SheetOffset(this.parent, this.byHand);
  @override
  final Animation<double> parent;
  final bool Function() byHand;

  @override
  Offset get value {
    final t = parent.value;
    final shown = byHand()
        ? t
        : parent.status == AnimationStatus.reverse
        ? Motion.drawer.flipped.transform(t)
        : Motion.drawer.transform(t);
    return Offset(0, 1 - shown);
  }
}

/// Suggested questions, and what a guest searches for instead of asking.
const _suggested = [
  ('居留證要準備什麼？', 'What do I need for an ARC?', '居留證'),
  ('怎麼加入健保？', 'How do I join NHI?', '健保'),
  ('租屋要注意什麼？', 'What should I check when renting?', '租屋'),
];

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.uri,
    required this.onNavigate,
    this.closable = true,
  });
  final Uri uri;
  final void Function(String path) onNavigate;

  /// The window has a close button; the assistant tab's page does not.
  final bool closable;

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
    // Before the first question: who answers (Google Gemini) and that it can be wrong.
    if (!await ensureAiNoticeSeen(context) || !mounted) return;
    _input.clear();
    await vm.ask(text, screen: _screen());
  }

  /// Whether the keyboard was up at the last build (to scroll down when it opens).
  var _keyboard = false;

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
    // With large text or the keyboard up the emergency line scrolls with the chat (at its
    // end), so the input and the conversation keep their room.
    final keyboard = keyboardUp(context);
    // The keyboard just opened: show the latest message right above it.
    if (keyboard && !_keyboard) _scrollToEnd();
    _keyboard = keyboard;
    final urgentInLog =
        MediaQuery.textScalerOf(context).scale(1) > 1.3 || keyboard;
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
              if (widget.closable)
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
                key: const Key('assistant-log'),
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
                                onTap: vm.signedIn
                                    ? () => _ask(vm.pair(q.$1, q.$2))
                                    : () {
                                        if (widget.closable) {
                                          vm.closeAssistant();
                                        }
                                        widget.onNavigate(
                                          '/explore?q=${Uri.encodeQueryComponent(q.$3)}',
                                        );
                                      },
                              ),
                          ],
                        ),
                      ),
                    for (final (i, entry) in vm.chat.indexed)
                      _Entry(
                        entry: entry,
                        index: i,
                        onNavigate: widget.onNavigate,
                      ),
                    if (vm.asking)
                      _Bubble(
                        text: vm.pair('想一下…', 'Thinking…'),
                        muted: true,
                        thinking: true,
                      ),
                    if (urgentInLog)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: _Disclaimers(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const DashedRule(color: Palette.edge),
          const SizedBox(height: 6),
          if (!urgentInLog) ...[
            const _Disclaimers(),
            const SizedBox(height: 4),
          ],
          if (!vm.signedIn)
            Row(
              key: const Key('assistant-sign-in'),
              children: [
                Expanded(
                  child: Text(
                    vm.pair(
                      '登入後就能直接問助理；沒登入也可以點上面的問題，看相關的指南和分享。',
                      'Sign in to ask the assistant. You can still tap a question above '
                          'to see related guides and posts.',
                    ),
                    style: mutedStyle,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    vm.closeAssistant();
                    ensureSignedIn(context);
                  },
                  child: Text(vm.t('signIn')),
                ),
              ],
            )
          else
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

/// Always under the chat: AI answers can be wrong, and where to find a person.
class _Disclaimers extends StatelessWidget {
  const _Disclaimers();
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.pair(aiMayBeWrong.$1, aiMayBeWrong.$2),
          style: mutedStyle.copyWith(fontSize: 12),
        ),
        const _UrgentLine(),
      ],
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
            // 44 px tall to hit easily, but only as wide as its words, so the line still flows.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                widthFactor: 1,
                alignment: AlignmentDirectional.centerStart,
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
  const _Bubble({
    required this.text,
    this.mine = false,
    this.muted = false,
    this.thinking = false,
  });
  final String text;
  final bool mine;
  final bool muted;

  /// Dots that rise in turn instead of the text (still read out as [text]).
  final bool thinking;
  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: .86,
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        // On the full-width assistant page, long lines stay readable.
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
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
          child: thinking
              ? ThinkingDots(label: text, color: Palette.muted)
              : SelectionArea(
                  child: Text(
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
    ),
  );
}

/// Reasons a student can give when reporting an assistant answer (zh, en).
const _answerReasons = {
  'inaccurate': ('不正確', 'Inaccurate'),
  'offensive': ('冒犯', 'Offensive'),
  'harmful': ('有害', 'Harmful'),
  'other': ('其他', 'Other'),
};

class _Entry extends StatelessWidget {
  const _Entry({
    required this.entry,
    required this.index,
    required this.onNavigate,
  });
  final ChatEntry entry;

  /// Its place in the chat (keys the report button).
  final int index;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final reply = entry.reply;
    // Official guides first, then student posts: each a card that opens it.
    final cards = [
      for (final type in ['action', 'experience'])
        for (final card in reply?.cards ?? const <AssistantCard>[])
          if (card.type == type) card,
    ];
    final links = <(String, String)>[
      if (reply != null) ...[
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
        if (reply != null)
          Transform.translate(
            offset: const Offset(0, -8),
            child: TextButton(
              key: Key('report-answer-$index'),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: Palette.muted,
                textStyle: const TextStyle(fontFamily: appFont, fontSize: 12),
              ),
              onPressed: () => showReportDialog(
                context,
                (reason, details) => vm.reportAnswer(entry, reason, details),
                reasons: _answerReasons,
                title: ('回報這個回答', 'Report this answer'),
                noteKey: const Key('answer-report-details'),
              ),
              child: Text(vm.pair('回報', 'Report')),
            ),
          ),
        for (final (label, path) in links)
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: const TextStyle(
                fontFamily: appFont,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Palette.brick,
              ),
            ),
            onPressed: () => onNavigate(path),
            child: Text('$label →'),
          ),
        if (cards.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4, left: 2),
            child: Text(
              vm.pair('相關貼文', 'Related posts'),
              style: mutedStyle.copyWith(fontSize: 12),
            ),
          ),
          for (final card in cards)
            _PostCard(
              card: card,
              onTap: () => onNavigate(
                card.type == 'action'
                    ? '/actions/${card.id}'
                    : '/experiences/${card.id}',
              ),
            ),
        ],
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
        'open_explore' => vm.pair('去看板看看', 'Go to Boards'),
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
                    onPressed: vm.resolvingOperation(operation.id)
                        ? null
                        : () => vm.resolveOperation(operation, true),
                    child: Text(vm.t('confirm')),
                  ),
                  TextButton(
                    onPressed: vm.resolvingOperation(operation.id)
                        ? null
                        : () => vm.resolveOperation(operation, false),
                    child: Text(vm.t('cancel')),
                  ),
                  if (vm.operationRetryable(operation.id))
                    Padding(
                      key: Key('operation-retry-${operation.id}'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        vm.pair(
                          '剛才沒有連上，還沒有辦理；可以再按一次。',
                          "That didn't go through; nothing was done yet. Try again.",
                        ),
                        style: mutedStyle,
                      ),
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

/// A guide or student post the assistant found, as a small card that opens it.
/// Official guides carry the Culture Bridge logo and name.
class _PostCard extends StatelessWidget {
  const _PostCard({required this.card, required this.onTap});
  final AssistantCard card;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final category = card.category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.high,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: const BorderSide(color: Palette.edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('assistant-post-${card.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (card.type == 'action')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Avatar(size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Culture Bridge',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mutedStyle.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        card.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                      if (card.excerpt.isNotEmpty && card.excerpt != card.title)
                        Text(
                          card.excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: mutedStyle.copyWith(fontSize: 13),
                        ),
                      if (category != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: PaperTag(categoryName(vm, category)),
                        ),
                    ],
                  ),
                ),
                const AppIcon('chevron', size: 18, color: Palette.control),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether a phone keyboard is taking the bottom of the screen: reported as an inset, or
/// the page itself shrunk to what the keyboard leaves (browsers do either).
bool keyboardUp(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.viewInsets.bottom > 0 || media.size.height < 600;
}
