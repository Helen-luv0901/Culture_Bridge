part of 'bridge_view_model.dart';

mixin _BridgeAssistant on _BridgeCore {
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

  /// Send a message with what the user is looking at, so "this question" can be resolved.
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
