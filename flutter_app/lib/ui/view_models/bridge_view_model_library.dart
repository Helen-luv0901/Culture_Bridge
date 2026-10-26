part of 'bridge_view_model.dart';

mixin _BridgeLibrary on _BridgeCore {
  // ---------- read and bookmarked ----------

  late final Set<String> _read;

  /// Opened before; lists show it dimmed with an "already read" note.
  bool isRead(String id) => _read.contains(id);
  void markRead(String id) {
    if (!_read.add(id)) return;
    unawaited(preferences.saveReadIds(_read));
    // Lists rebuild when the reader comes back, so no notify is needed here.
  }

  late final Set<String> _savedGuides;
  bool guideSaved(String actionId) => _savedGuides.contains(actionId);
  List<String> get savedGuideIds => _savedGuides.toList().reversed.toList();
  void toggleSavedGuide(String actionId) {
    final on = _savedGuides.add(actionId);
    if (!on) _savedGuides.remove(actionId);
    unawaited(preferences.saveSavedGuides(_savedGuides));
    showNotice(
      on
          ? pair('已收藏，在「我的 › 收藏」找得到', 'Saved. Find it under My › Saved.')
          : pair('已取消收藏', 'Removed from saved'),
    );
  }

  /// Ticked items of a guide's "what to bring" list (kept while the app is open).
  final Map<String, Set<int>> _documents = {};
  bool documentReady(String actionId, int index) =>
      _documents[actionId]?.contains(index) ?? false;
  int documentsReady(String actionId) => _documents[actionId]?.length ?? 0;
  void toggleDocument(String actionId, int index) {
    final ready = _documents.putIfAbsent(actionId, () => {});
    if (!ready.remove(index)) ready.add(index);
    notifyListeners();
  }

  // ---------- saved for later ----------

  Resource<List<ExperienceItem>> saved = const Resource();
  Future<void> loadSaved() async {
    if (!signedIn) return;
    await _load(
      () => saved,
      (r) => saved = r,
      () => repository.savedExperiences(locale: locale),
    );
  }

  Future<void> toggleSaved(ExperienceItem item) async {
    final on = !item.saved;
    try {
      await repository.setSaved(item.id, on);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return;
    }
    final list = saved.data;
    saved = on || list == null
        ? const Resource() // reloads, newest first, next time the list is shown
        : Resource(
            data: [
              for (final e in list)
                if (e.id != item.id) e,
            ],
          );
    showNotice(
      on
          ? pair('已收藏，在「我的 › 收藏」找得到', 'Saved. Find it under My › Saved.')
          : pair('已取消收藏', 'Removed from saved'),
    );
    _updateItem(item.withSaved(on));
  }

  final Set<String> _flipped = {};

  /// Whether the card shows the translation: by default when the reader's language differs
  /// from the author's, and the reader can flip it.
  bool translated(ExperienceItem item) {
    final otherLanguage = (item.sourceLocale == 'en') != _english;
    return otherLanguage != _flipped.contains(item.id) &&
        item.translation != null;
  }

  bool canTranslate(ExperienceItem item) =>
      item.translation != null || (item.sourceLocale == 'en') != _english;

  Future<void> toggleTranslation(ExperienceItem item) async {
    if (item.translation == null) {
      try {
        final target = item.sourceLocale == 'en' ? 'zh-Hant' : 'en';
        final detail = await repository.requestTranslation(item.id, target);
        _experiences[item.id] = Resource(data: detail);
        _updateItem(detail.item);
        _flipped.remove(item.id);
      } on ApiException catch (e) {
        showNotice(errorText(e));
      }
      return;
    }
    _flipped.contains(item.id)
        ? _flipped.remove(item.id)
        : _flipped.add(item.id);
    notifyListeners();
  }
}
