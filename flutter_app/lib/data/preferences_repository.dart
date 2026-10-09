import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

abstract class PreferencesRepository {
  bool? get english;
  ShareDraft get draft;
  Future<void> saveLanguage(bool english);
  Future<void> saveDraft(ShareDraft draft);
}

class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this.preferences);
  final SharedPreferences preferences;
  @override
  bool? get english => preferences.getBool('english');
  @override
  ShareDraft get draft {
    try {
      final data = jsonDecode(
        preferences.getString('draft') ?? '{}',
      ) as Map<String, dynamic>;
      return ShareDraft(
        voice: data['voice'] as String? ?? '',
        topic: data['topic'] as String? ?? 'cultureCommunication',
        identity: data['identity'] as String? ?? 'degreeStudent',
      );
    } catch (_) {
      return const ShareDraft();
    }
  }

  @override
  Future<void> saveLanguage(bool english) async {
    await preferences.setBool('english', english);
  }

  @override
  Future<void> saveDraft(ShareDraft draft) async {
    await preferences.setString(
      'draft',
      jsonEncode({
        'voice': draft.voice,
        'topic': draft.topic,
        'identity': draft.identity,
      }),
    );
  }
}
