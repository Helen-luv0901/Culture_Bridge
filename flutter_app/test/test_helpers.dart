import 'package:culture_bridge/data/preferences_repository.dart';
import 'package:culture_bridge/domain/models.dart';

class MemoryPreferences implements PreferencesRepository {
  @override
  bool? english = false;
  @override
  ShareDraft draft = const ShareDraft();
  @override
  Future<void> saveLanguage(bool value) async {
    english = value;
  }

  @override
  Future<void> saveDraft(ShareDraft value) async {
    draft = value;
  }
}
