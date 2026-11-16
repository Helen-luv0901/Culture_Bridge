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

  /// Official questions bookmarked on this device (no account needed), newest last.
  late final Set<String> _savedFaqs;
  bool faqSaved(String id) => _savedFaqs.contains(id);

  /// Newest first.
  List<String> get savedFaqIds => _savedFaqs.toList().reversed.toList();
  void toggleSavedFaq(String id) {
    final on = _savedFaqs.add(id);
    if (!on) _savedFaqs.remove(id);
    unawaited(preferences.saveSavedFaqs(_savedFaqs));
    showNotice(
      on
          ? pair('已收藏，在「我的 › 收藏」找得到', 'Saved. Find it under My › Saved.')
          : pair('已取消收藏', 'Removed from saved'),
    );
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
      // A plain conflict: it was already saved (or removed), as asked: done. Any other
      // error, including a full list (409 too_many_saved), is shown.
      if (e.code != 'conflict') {
        showNotice(errorText(e));
        return;
      }
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
        showNotice(_translationError(e));
      }
      return;
    }
    _flipped.contains(item.id)
        ? _flipped.remove(item.id)
        : _flipped.add(item.id);
    notifyListeners();
  }

  /// Why a translation didn't come: offline and today's limit say so; anything else is
  /// a failed translation (not the "draft saved" text of the AI organizing step).
  String _translationError(ApiException e) => switch (e.code) {
    'network_error' ||
    'daily_limit_reached' ||
    'rate_limited' ||
    'experience_not_found' => errorText(e),
    _ => pair('翻譯失敗，請稍後再試', 'Translation failed. Please try again later'),
  };
}
