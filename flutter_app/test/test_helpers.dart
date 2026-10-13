import 'dart:convert';
import 'dart:io';

import 'package:culture_bridge/data/auth_service.dart';
import 'package:culture_bridge/data/messages.dart';
import 'package:culture_bridge/data/preferences_repository.dart';
import 'package:culture_bridge/domain/models.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';

import 'fake_repository.dart';

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

MessageCatalog loadMessages() => MessageCatalog(
  jsonDecode(File('assets/data/messages.json').readAsStringSync())
      as Map<String, dynamic>,
);

class TestApp {
  TestApp({bool signedIn = true})
    : auth = DevAuthService(null),
      preferences = MemoryPreferences() {
    repository = FakeCultureRepository(auth);
    vm = BridgeViewModel(
      repository: repository,
      auth: auth,
      messages: loadMessages(),
      preferences: preferences,
    );
    if (signedIn) auth.signInAsDev('test');
  }
  final DevAuthService auth;
  final MemoryPreferences preferences;
  late final FakeCultureRepository repository;
  late final BridgeViewModel vm;
}
