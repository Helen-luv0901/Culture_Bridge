part of 'bridge_view_model.dart';

mixin _BridgeProcedures on _BridgeCore {
  // ---------- procedures ----------

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

  Resource<List<Execution>> executions = const Resource();
  Future<void> loadExecutions() async {
    if (!signedIn) return;
    await _load(
      () => executions,
      (r) => executions = r,
      repository.myExecutions,
    );
  }

  Execution? openExecution(String actionId) => executions.data
      ?.where((e) => e.actionId == actionId && !e.finished)
      .firstOrNull;

  void _replaceExecution(Execution updated) {
    final list = [...?executions.data]..removeWhere((e) => e.id == updated.id);
    if (!updated.finished) list.insert(0, updated);
    executions = Resource(data: list);
    notifyListeners();
  }

  /// Starts (or resumes) the procedure. Null with a notice when it failed.
  Future<Execution?> startAction(String actionId) async {
    try {
      final execution = await repository.startExecution(actionId, 'other');
      _replaceExecution(execution);
      return execution;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return null;
    }
  }

  Future<void> setStepDone(
    Execution execution,
    String stepId,
    bool done,
  ) async {
    try {
      _replaceExecution(
        await repository.setStep(
          execution.id,
          stepId,
          done ? 'done' : 'pending',
        ),
      );
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }

  Future<bool> reportStuck(
    Execution execution,
    String stepId,
    String reasonKey,
    String? text,
  ) async {
    try {
      await repository.sendFeedback(
        execution.id,
        kind: 'stuck',
        stepId: stepId,
        category: BridgeViewModel.stuckCategories[reasonKey],
        text: text,
      );
      _replaceExecution(
        (await repository.myExecutions()).firstWhere(
          (e) => e.id == execution.id,
        ),
      );
      showNotice(t('feedbackSubmitted'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    } on StateError {
      return true;
    }
  }

  /// Records the outcome; "different" also sends one report per changed category.
  Future<bool> finishAction(
    Execution execution,
    String outcome, {
    Set<String> differences = const {},
    String? text,
  }) async {
    try {
      final categories = differences.isEmpty
          ? <String?>[null]
          : differences.toList();
      if (outcome == 'different') {
        for (final category in categories) {
          await repository.sendFeedback(
            execution.id,
            kind: 'different',
            category: category,
            text: category == categories.first ? text : null,
          );
        }
      }
      _replaceExecution(
        await repository.finishExecution(execution.id, outcome),
      );
      _actions.remove(execution.actionId); // completion counts changed
      actions = const Resource();
      showNotice(t('feedbackThanks'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }
}
