part of 'bridge_view_model.dart';

mixin _BridgeAssistant on _BridgeCore, _BridgeProcedures {
  // ---------- assistant ----------

  String? conversationId;
  final List<ChatEntry> chat = [];
  bool asking = false;

  /// Bumped when the chat is cleared (or its owner signs out): a reply to a question asked
  /// before that has nowhere to go.
  int _chatGeneration = 0;

  void _forgetChat() {
    _chatGeneration++;
    chat.clear();
    conversationId = null;
    asking = false;
  }

  /// The chat window over the page; the round bubble opens and closes it.
  bool assistantOpen = false;
  void openAssistant({String? question}) {
    assistantOpen = true;
    notifyListeners();
    if (question != null && question.trim().isNotEmpty) {
      unawaited(ask(question));
    }
  }

  void closeAssistant() {
    assistantOpen = false;
    notifyListeners();
  }

  bool _aiNoticeSeen = false;

  /// The "answers come from Google Gemini and can be wrong" notice was shown on this device.
  bool get aiNoticeSeen => _aiNoticeSeen || preferences.aiNoticeSeen;
  void acknowledgeAiNotice() {
    _aiNoticeSeen = true;
    unawaited(preferences.saveAiNoticeSeen());
    notifyListeners();
  }

  /// Send a message with what the user is looking at, so "this procedure" can be resolved.
  Future<void> ask(String text, {Map<String, String>? screen}) async {
    final message = text.trim();
    if (message.isEmpty || asking) return;
    chat.add(ChatEntry.user(message));
    asking = true;
    final generation = _chatGeneration;
    notifyListeners();
    ChatEntry entry;
    String? newConversation;
    try {
      final reply = await repository.askAssistant(
        message: message,
        locale: locale,
        conversationId: conversationId,
        screen: screen,
      );
      newConversation = reply.conversationId;
      entry = ChatEntry.assistant(reply, question: message);
    } on ApiException catch (e) {
      entry = ChatEntry.error(e.needsLogin ? t('signInNeeded') : errorText(e));
    } on Object catch (error, stack) {
      // A reply the app can't read: say so instead of thinking forever, and report it.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'api'),
      );
      entry = ChatEntry.error(errorText(null));
    }
    // Cleared or signed out meanwhile: the reply has nowhere to go.
    if (generation != _chatGeneration) return;
    if (newConversation != null) conversationId = newConversation;
    chat.add(entry);
    asking = false;
    notifyListeners();
  }

  Future<void> clearChat() async {
    final id = conversationId;
    _forgetChat();
    notifyListeners();
    if (id != null) await _quietly(() => repository.clearConversation(id));
  }

  /// Report an answer (wrong, offensive, harmful, other) for staff to review.
  Future<bool> reportAnswer(
    ChatEntry entry,
    String reason,
    String? details,
  ) async {
    final reply = entry.reply;
    if (reply == null) return false;
    try {
      await repository.reportAssistantAnswer(
        conversationId: reply.conversationId,
        question: entry.question ?? '',
        answer: reply.text,
        reason: reason,
        details: details,
      );
      showNotice(pair('謝謝回報，我們會檢查這個回答。', "Thanks. We'll look at this answer."));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }

  /// Confirm or cancel a write the assistant prepared (A-17); the user always decides.
  Future<void> resolveOperation(
    PendingOperation operation,
    bool confirm,
  ) async {
    // A second tap while the first is on its way would fail and hide its result.
    if (!_resolving.add(operation.id)) return;
    notifyListeners();
    try {
      final result = confirm
          ? await repository.confirmOperation(operation.id)
          : await repository.cancelOperation(operation.id);
      operationStates[operation.id] = result.status;
      _retryable.remove(operation.id);
      if (result.status == 'confirmed') {
        await loadExecutions();
        showNotice(pair('已開始辦理。', 'Started.'));
      }
    } on ApiException catch (e) {
      // Offline or a busy server: nothing happened yet, so the buttons stay to try again.
      if (_transient(e)) {
        _retryable.add(operation.id);
      } else {
        _retryable.remove(operation.id);
        operationStates[operation.id] = e.code.replaceFirst('operation_', '');
      }
      showNotice(errorText(e));
    } finally {
      _resolving.remove(operation.id);
    }
    notifyListeners();
  }

  final Set<String> _resolving = {};
  final Set<String> _retryable = {};

  static bool _transient(ApiException e) =>
      e.code == 'network_error' ||
      e.code == 'internal_error' ||
      e.code == 'bad_response' ||
      (e.code.startsWith('http_') && e.status >= 500);

  /// The last confirm or cancel of [id] didn't reach the server; it can be tried again.
  bool operationRetryable(String id) => _retryable.contains(id);

  /// Whether a confirm or cancel of [id] is on its way (its buttons wait).
  bool resolvingOperation(String id) => _resolving.contains(id);

  /// Latest known status of each pending operation shown in the chat.
  final Map<String, String> operationStates = {};
}

/// One line in the assistant panel.
class ChatEntry {
  ChatEntry.user(this.text)
    : fromUser = true,
      reply = null,
      failed = false,
      question = null;
  ChatEntry.assistant(AssistantReply this.reply, {this.question})
    : text = reply.text,
      fromUser = false,
      failed = false;
  ChatEntry.error(this.text)
    : fromUser = false,
      reply = null,
      failed = true,
      question = null;
  final String text;

  /// For an answer: the question it answers (sent along when the answer is reported).
  final String? question;
  final bool fromUser;
  final AssistantReply? reply;
  final bool failed;
}
