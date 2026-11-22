part of 'bridge_view_model.dart';

mixin _BridgeProcedures on _BridgeCore {
  // ---------- procedures (辦理證件) ----------

  Resource<List<ActionSummary>> actions = const Resource();
  Future<void> loadActions() =>
      _load(() => actions, (r) => actions = r, repository.actions);

  final Map<String, Resource<ActionDetail>> _actions = {};
  Resource<ActionDetail> action(String id) => _actions[id] ?? const Resource();
  Future<void> loadAction(String id) => _load(
    () => action(id),
    (r) => _actions[id] = r,
    () => repository.action(id),
  );

  /// Official questions on the same subject as the procedure [actionId].
  final Map<String, Resource<List<FaqSummary>>> _actionFaqs = {};
  Resource<List<FaqSummary>> actionFaqs(String actionId) =>
      _actionFaqs[actionId] ?? const Resource();
  Future<void> loadActionFaqs(String actionId) => _load(
    () => actionFaqs(actionId),
    (r) => _actionFaqs[actionId] = r,
    () => repository.actionRelatedFaqs(actionId),
  );

  /// Ticked items of a procedure's "what to bring" list (kept while the app is open).
  final Map<String, Set<int>> _documents = {};
  bool documentReady(String actionId, int index) =>
      _documents[actionId]?.contains(index) ?? false;
  int documentsReady(String actionId) => _documents[actionId]?.length ?? 0;
  void toggleDocument(String actionId, int index) {
    final ready = _documents.putIfAbsent(actionId, () => {});
    if (!ready.remove(index)) ready.add(index);
    notifyListeners();
  }
}
