part of 'bridge_view_model.dart';

mixin _BridgeComments on _BridgeCore {
  // ---------- comments ----------

  final Map<String, Resource<List<CommentItem>>> _comments = {};
  Resource<List<CommentItem>> comments(String experienceId) =>
      _comments[experienceId] ?? const Resource();
  Future<void> loadComments(String experienceId) => _load(
    () => comments(experienceId),
    (r) => _comments[experienceId] = r,
    () => repository.comments(experienceId),
  );

  /// Null when sent; otherwise the message to show under the box.
  Future<String?> addComment(
    String experienceId,
    String body, {
    String? replyToId,
    bool signed = false,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return pair('先寫點什麼再送出', 'Write something first');
    try {
      final comment = await repository.addComment(
        experienceId,
        body: text,
        replyToId: replyToId,
        authorDisplay: signed ? 'nickname' : 'anonymous',
      );
      _comments[experienceId] = Resource(
        data: [...?_comments[experienceId]?.data, comment],
      );
      _bumpCommentCount(experienceId, 1);
      showNotice(pair('已留言', 'Comment posted'));
      return null;
    } on ApiException catch (e) {
      return errorText(e);
    }
  }

  void _bumpCommentCount(String experienceId, int by) {
    final item = _experiences[experienceId]?.data?.item;
    if (item != null) {
      _updateItem(item.copyWith(commentCount: item.commentCount + by));
    }
  }

  Future<void> toggleCommentLike(String experienceId, CommentItem c) async {
    try {
      final updated = await repository.likeComment(c.id, !c.liked);
      _comments[experienceId] = Resource(
        data: [
          for (final e in _comments[experienceId]?.data ?? <CommentItem>[])
            e.id == c.id ? updated : e,
        ],
      );
      notifyListeners();
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  Future<void> deleteComment(String experienceId, CommentItem c) async {
    try {
      await repository.deleteComment(c.id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return;
    }
    // Replies to a deleted comment go with it on the server too.
    final before = _comments[experienceId]?.data ?? <CommentItem>[];
    final kept = [
      for (final e in before)
        if (e.id != c.id && e.replyToId != c.id) e,
    ];
    _comments[experienceId] = Resource(data: kept);
    _bumpCommentCount(experienceId, kept.length - before.length);
    showNotice(pair('已刪除留言', 'Comment deleted'));
  }

  Future<bool> reportComment(
    String commentId,
    String reason,
    String? note,
  ) async {
    try {
      await repository.reportComment(commentId, reason, note);
      showNotice(t('reportSent'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }
}
