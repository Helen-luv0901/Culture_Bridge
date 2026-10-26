part of 'bridge_view_model.dart';

mixin _BridgeSharing on _BridgeCore, _BridgePosts, _BridgeModeration {
  // ---------- sharing ----------

  late ShareDraft _draft;
  ShareDraft get draft => _draft;
  Timer? _saveTimer;

  void _storeDraft(ShareDraft value) {
    _draft = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(preferences.saveDraft(_draft)),
    );
    notifyListeners();
  }

  void updateDraft({
    String? title,
    String? voice,
    String? category,
    String? authorDisplay,
  }) {
    _storeDraft(
      _draft.copyWith(
        title: title,
        voice: voice,
        category: category,
        authorDisplay: authorDisplay,
      ),
    );
    if (title != null || voice != null) _scheduleTagSuggestions();
  }

  void toggleChosenTag(String tag) {
    final chosen = [..._draft.chosenTags];
    if (!chosen.remove(tag)) {
      if (draftTags.length >= BridgeViewModel.maxTags) {
        showNotice(pair('最多 8 個標籤', 'At most 8 tags'));
        return;
      }
      chosen.add(tag);
    }
    _storeDraft(_draft.copyWith(chosenTags: chosen));
  }

  /// Adds a tag the student typed; null when added, else why not.
  String? addCustomTag(String raw) {
    final word = raw
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (word.isEmpty) return pair('先輸入標籤文字', 'Type a tag first');
    if (word.length > BridgeViewModel.maxTagLength) {
      return pair('標籤最多 12 個字', 'Tags are at most 12 characters');
    }
    final tag = '#$word';
    if (draftTags.length >= BridgeViewModel.maxTags &&
        !draftTags.contains(tag)) {
      return pair('最多 8 個標籤', 'At most 8 tags');
    }
    if (!_draft.customTags.contains(tag)) {
      _storeDraft(_draft.copyWith(customTags: [..._draft.customTags, tag]));
    }
    return null;
  }

  void removeCustomTag(String tag) => _storeDraft(
    _draft.copyWith(
      customTags: [
        for (final t in _draft.customTags)
          if (t != tag) t,
      ],
    ),
  );

  /// Tags that go out with the post: ticked suggestions first, then the student's own.
  List<String> get draftTags => [
    for (final t in _draft.chosenTags)
      if (!_draft.customTags.contains(t)) t,
    ..._draft.customTags,
  ].take(BridgeViewModel.maxTags).toList();

  ShareDraft _relinked({String? differentFromId, String? actionId}) =>
      ShareDraft(
        title: _draft.title,
        voice: _draft.voice,
        category: _draft.category,
        chosenTags: _draft.chosenTags,
        customTags: _draft.customTags,
        authorDisplay: _draft.authorDisplay,
        differentFromId: differentFromId,
        actionId: actionId,
      );

  /// Start a post that answers [experienceId] ("my experience was different").
  void startDifferentExperience(String experienceId, {String? category}) {
    final next = _relinked(differentFromId: experienceId);
    _storeDraft(
      next.category == null && category != null
          ? next.copyWith(category: category)
          : next,
    );
  }

  /// Start a post that also shows under the official guide [actionId].
  void startPostForAction(String actionId) =>
      _storeDraft(_relinked(actionId: actionId));

  void unlinkDraft({bool post = false, bool guide = false}) =>
      _storeDraft(_draft.unlinked(post: post, guide: guide));

  // AI tag suggestions follow the text, a moment after typing stops.
  List<String> tagSuggestions = const [];
  bool suggestingTags = false;
  Timer? _suggestTimer;
  String _suggestedFor = '';

  /// Bumped for every request (and on publish or sign-out) so a late answer is ignored.
  int _suggestRequest = 0;
  static const _minSuggestLength = 8;

  void _scheduleTagSuggestions() {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(refreshTagSuggestions()),
    );
  }

  Future<void> refreshTagSuggestions() async {
    final title = _draft.title.trim();
    final text = _draft.voice.trim();
    final key = '$title\n$text';
    if (key == _suggestedFor || !signedIn) return;
    if ((title + text).length < _minSuggestLength) {
      _suggestedFor = key;
      tagSuggestions = const [];
      notifyListeners();
      return;
    }
    final request = ++_suggestRequest;
    suggestingTags = true;
    notifyListeners();
    try {
      final tags = await repository.suggestTags(
        title: title,
        text: text,
        category: _draft.category,
      );
      if (request != _suggestRequest) return;
      tagSuggestions = tags;
      _suggestedFor = key;
    } on ApiException {
      // Suggestions are optional; the student can still add tags by hand.
    } finally {
      if (request == _suggestRequest) {
        suggestingTags = false;
        notifyListeners();
      }
    }
  }

  bool publishing = false;

  /// Continue an unpublished post (saved on the server) in Share.
  void continueDraft(MyExperience item) {
    _draft = ShareDraft(
      title: item.title,
      voice: item.originalVoice,
      category: item.category ?? categoryFor(null, item.topicId),
      customTags: item.tags,
      authorDisplay: _draft.authorDisplay,
      resumesId: item.id,
    );
    unawaited(preferences.saveDraft(_draft));
    tagSuggestions = const [];
    _suggestedFor = '';
    _suggestRequest++;
    suggestingTags = false;
    notifyListeners();
    _scheduleTagSuggestions();
  }

  /// Publishes the draft exactly as written. Returns an error message, or the new post.
  Future<(String?, ExperienceItem?)> publishDraft() async {
    final title = _draft.title.trim();
    final voice = _draft.voice.trim();
    final category = _draft.category;
    if (title.isEmpty || voice.isEmpty || category == null) {
      return (pair('標題、內文和分類都要填', 'Add a title, text and category'), null);
    }
    publishing = true;
    notifyListeners();
    try {
      final item = await repository.publishPost(
        title: title,
        voice: voice,
        category: category,
        tags: draftTags,
        sourceLocale: RegExp(r'[㐀-鿿]').hasMatch(title + voice)
            ? 'zh-Hant'
            : 'en',
        authorDisplay: _draft.authorDisplay,
        differentFromId: _draft.differentFromId,
        actionId: _draft.actionId,
      );
      final replaced = _draft.resumesId;
      if (replaced != null) {
        try {
          // The unpublished copy it continued is no longer needed.
          await repository.deleteExperience(replaced);
        } on ApiException {
          // Already gone, or offline: the new post is published either way.
        }
      }
      _draft = ShareDraft(authorDisplay: _draft.authorDisplay);
      unawaited(preferences.saveDraft(_draft));
      tagSuggestions = const [];
      _suggestedFor = '';
      _suggestRequest++;
      suggestingTags = false;
      _dropLists();
      popularTags = const Resource();
      mine = const Resource();
      final label = categoryLabels[category];
      showNotice(
        item.actionId != null
            ? pair('已發布，也貼在官方指南底下', 'Published, also under the guide')
            : pair(
                '已發布，首頁和「${label?.$1}」看得到',
                'Published. It shows on Home and in ${label?.$2}.',
              ),
      );
      return (null, item);
    } on ApiException catch (e) {
      return (errorText(e), null);
    } finally {
      publishing = false;
      notifyListeners();
    }
  }
}
