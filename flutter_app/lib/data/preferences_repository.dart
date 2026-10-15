import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

abstract class PreferencesRepository {
  bool? get english;
  ShareDraft get draft;
  Future<void> saveLanguage(bool english);
  Future<void> saveDraft(ShareDraft draft);

  /// Posts and guides the reader has opened; lists show them dimmed.
  Set<String> get readIds;
  Future<void> saveReadIds(Set<String> ids);

  /// Official guides bookmarked on this device (student posts are saved on the server).
  Set<String> get savedGuides;
  Future<void> saveSavedGuides(Set<String> ids);
}

class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this.preferences);
  final SharedPreferences preferences;

  /// Keeps the read list small; the oldest entries drop off first.
  static const maxReadIds = 500;

  @override
  bool? get english => preferences.getBool('english');
  @override
  ShareDraft get draft {
    try {
      return ShareDraft.fromJson(
        jsonDecode(preferences.getString('draft') ?? '{}')
            as Map<String, dynamic>,
      );
    } on FormatException {
      return const ShareDraft();
    } on TypeError {
      return const ShareDraft();
    }
  }

  @override
  Future<void> saveLanguage(bool english) async {
    await preferences.setBool('english', english);
  }

  @override
  Future<void> saveDraft(ShareDraft draft) async {
    await preferences.setString('draft', jsonEncode(draft.toJson()));
  }

  @override
  Set<String> get readIds => {...?preferences.getStringList('readIds')};
  @override
  Future<void> saveReadIds(Set<String> ids) async {
    final list = ids.toList();
    await preferences.setStringList(
      'readIds',
      list.length > maxReadIds ? list.sublist(list.length - maxReadIds) : list,
    );
  }

  @override
  Set<String> get savedGuides => {...?preferences.getStringList('savedGuides')};
  @override
  Future<void> saveSavedGuides(Set<String> ids) async {
    await preferences.setStringList('savedGuides', ids.toList());
  }
}
