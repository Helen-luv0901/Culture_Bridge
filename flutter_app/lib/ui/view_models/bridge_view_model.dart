import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/content_repository.dart';
import '../../data/preferences_repository.dart';
import '../../domain/models.dart';

class BridgeViewModel extends ChangeNotifier {
  BridgeViewModel({
    required this.content,
    required this.preferences,
    bool systemEnglish = false,
  }) {
    _english = preferences.english ?? systemEnglish;
    _draft = preferences.draft;
  }
  final ContentRepository content;
  final PreferencesRepository preferences;
  late bool _english;
  late ShareDraft _draft;
  ShareDraft? _reviewedDraft;
  Timer? _saveTimer;
  final Map<String, Set<int>> _completed = {};
  final Map<String, int> _stuck = {};
  final Set<String> _helpful = {};
  final Set<String> _experienced = {};
  final Map<String, String> _outcomes = {};
  final Map<String, Set<String>> _differences = {};
  final Set<String> _showOriginal = {};
  String? previewNotice;
  bool get english => _english;
  ShareDraft get draft => _draft;
  ShareDraft? get reviewedDraft => _reviewedDraft;
  List<ActionItem> get actions => content.actions;
  List<Experience> get experiences => content.experiences;
  String t(String key) => content.message(key, _english);
  String pair(String zh, String en) => _english ? en : zh;
  ActionItem? action(String id) => actions.where((a) => a.id == id).firstOrNull;
  Experience? experience(String id) =>
      experiences.where((e) => e.id == id).firstOrNull;
  List<Experience> filtered(String topic) => experiences
      .where((e) => topic == 'all' || e.topic == topic)
      .toList(growable: false);
  void setEnglish(bool value) {
    _english = value;
    unawaited(preferences.saveLanguage(value));
    notifyListeners();
  }

  void updateDraft({String? voice, String? topic, String? identity}) {
    _draft = _draft.copyWith(
      voice: voice ?? _draft.voice,
      topic: topic ?? _draft.topic,
      identity: identity ?? _draft.identity,
    );
    _reviewedDraft = null;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(preferences.saveDraft(_draft)),
    );
    notifyListeners();
  }

  bool prepareReview() {
    if (_draft.voice.trim().isEmpty) return false;
    _reviewedDraft = _draft.copyWith(voice: _draft.voice.trim());
    notifyListeners();
    return true;
  }

  void finishPreview() {
    previewNotice = pair(
      '已完成預覽；你的經驗尚未發布到網路。',
      'Preview complete. Your experience has not been published online.',
    );
    notifyListeners();
  }

  Set<int> completed(String id) => Set.unmodifiable(_completed[id] ?? <int>{});
  void startAction(String id) {
    _completed.putIfAbsent(id, () => {});
    notifyListeners();
  }

  void toggleStep(String id, int step) {
    final steps = _completed.putIfAbsent(id, () => {});
    steps.contains(step) ? steps.remove(step) : steps.add(step);
    _stuck.remove(id);
    notifyListeners();
  }

  int? stuck(String id) => _stuck[id];
  void setStuck(String id, int step) {
    _stuck[id] = step;
    notifyListeners();
  }

  bool helpful(String id) => _helpful.contains(id);
  bool experienced(String id) => _experienced.contains(id);
  void toggleHelpful(String id) {
    _helpful.contains(id) ? _helpful.remove(id) : _helpful.add(id);
    notifyListeners();
  }

  void toggleExperienced(String id) {
    _experienced.contains(id) ? _experienced.remove(id) : _experienced.add(id);
    notifyListeners();
  }

  bool translated(String id) =>
      _english && !_showOriginal.contains(id) ||
      !_english && _showOriginal.contains(id);
  void toggleTranslation(String id) {
    _showOriginal.contains(id)
        ? _showOriginal.remove(id)
        : _showOriginal.add(id);
    notifyListeners();
  }

  String? outcome(String id) => _outcomes[id];
  void setOutcome(String id, String value) {
    _outcomes[id] = value;
    notifyListeners();
  }

  Set<String> differences(String id) =>
      Set.unmodifiable(_differences[id] ?? <String>{});
  void toggleDifference(String id, String value) {
    final set = _differences.putIfAbsent(id, () => {});
    set.contains(value) ? set.remove(value) : set.add(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
