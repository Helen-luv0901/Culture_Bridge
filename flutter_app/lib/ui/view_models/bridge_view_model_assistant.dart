part of 'bridge_view_model.dart';

mixin _BridgeAssistant on _BridgeCore, _BridgeProcedures {
  // ---------- assistant ----------

  String? conversationId;
  final List<ChatEntry> chat = [];
  bool asking = false;

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

  /// Send a message with what the user is looking at, so "this procedure" can be resolved.
  Future<void> ask(String text, {Map<String, String>? screen}) async {
    final message = text.trim();
    if (message.isEmpty || asking) return;
    chat.add(ChatEntry.user(message));
    asking = true;
    notifyListeners();
    try {
      final reply = await repository.askAssistant(
        message: message,
        locale: locale,
        conversationId: conversationId,
        screen: screen,
      );
      conversationId = reply.conversationId;
      chat.add(ChatEntry.assistant(reply));
    } on ApiException catch (e) {
      chat.add(
        ChatEntry.error(e.needsLogin ? t('signInNeeded') : errorText(e)),
      );
    } finally {
      asking = false;
      notifyListeners();
    }
  }

  Future<void> clearChat() async {
    final id = conversationId;
    chat.clear();
    conversationId = null;
    notifyListeners();
    if (id != null) await _quietly(() => repository.clearConversation(id));
  }

  /// Confirm or cancel a write the assistant prepared (A-17); the user always decides.
  Future<void> resolveOperation(
    PendingOperation operation,
    bool confirm,
  ) async {
    try {
      final result = confirm
          ? await repository.confirmOperation(operation.id)
          : await repository.cancelOperation(operation.id);
      operationStates[operation.id] = result.status;
      if (result.status == 'confirmed') {
        await loadExecutions();
        showNotice(pair('已開始辦理。', 'Started.'));
      }
    } on ApiException catch (e) {
      operationStates[operation.id] = e.code.replaceFirst('operation_', '');
      showNotice(errorText(e));
    }
    notifyListeners();
  }

  /// Latest known status of each pending operation shown in the chat.
  final Map<String, String> operationStates = {};
}

/// One line in the assistant panel.
class ChatEntry {
  ChatEntry.user(this.text) : fromUser = true, reply = null, failed = false;
  ChatEntry.assistant(AssistantReply this.reply)
    : text = reply.text,
      fromUser = false,
      failed = false;
  ChatEntry.error(this.text) : fromUser = false, reply = null, failed = true;
  final String text;
  final bool fromUser;
  final AssistantReply? reply;
  final bool failed;
}
