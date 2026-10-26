part of 'bridge_view_model.dart';

mixin _BridgeModeration on _BridgeCore, _BridgeLibrary, _BridgeComments {
  // ---------- reports and blocks ----------

  Future<bool> report(String experienceId, String reason, String? note) async {
    try {
      await repository.report(experienceId, reason, note);
      showNotice(t('reportSent'));
      return true;
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
  }

  Future<bool> blockAuthor(String experienceId) async {
    try {
      await repository.blockAuthor(experienceId);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
    _dropLists();
    _comments.clear();
    blocks = const Resource();
    saved = const Resource();
    showNotice(t('blocked'));
    return true;
  }

  Resource<List<BlockInfo>> blocks = const Resource();
  Future<void> loadBlocks() =>
      _load(() => blocks, (r) => blocks = r, repository.blocks);
  Future<void> unblock(String id) async {
    try {
      await repository.unblock(id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
    _dropLists();
    _comments.clear();
    await loadBlocks();
  }

  // ---------- my posts ----------

  Resource<List<MyExperience>> mine = const Resource();
  Future<void> loadMine() async {
    if (!signedIn) return;
    await _load(() => mine, (r) => mine = r, repository.myExperiences);
  }

  Future<bool> deleteExperience(String id) async {
    try {
      await repository.deleteExperience(id);
    } on ApiException catch (e) {
      showNotice(errorText(e));
      return false;
    }
    _dropLists();
    _comments.remove(id);
    saved = const Resource();
    await loadMine();
    showNotice(pair('已刪除這篇分享', 'Post deleted'));
    return true;
  }
}
