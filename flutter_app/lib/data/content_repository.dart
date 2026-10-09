import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models.dart';

abstract class ContentRepository {
  List<ActionItem> get actions;
  List<Experience> get experiences;
  String message(String key, bool english);
}

class AssetContentRepository implements ContentRepository {
  AssetContentRepository._(this.actions, this.experiences, this._messages);
  @override
  final List<ActionItem> actions;
  @override
  final List<Experience> experiences;
  final Map<String, dynamic> _messages;
  static Future<AssetContentRepository> load() async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/data/content.json'),
    ) as Map<String, dynamic>;
    final messages = jsonDecode(
      await rootBundle.loadString('assets/data/messages.json'),
    ) as Map<String, dynamic>;
    return AssetContentRepository._(
      List.unmodifiable(
        (data['actionCards'] as List).map(
          (e) => ActionItem(id: e['id'], content: Map<String, dynamic>.from(e)),
        ),
      ),
      List.unmodifiable(
        (data['experiences'] as List).map(
          (e) => Experience(id: e['id'], content: Map<String, dynamic>.from(e)),
        ),
      ),
      messages,
    );
  }

  @override
  String message(String key, bool english) =>
      _messages[english ? 'en' : 'zh-Hant'][key]?.toString() ?? key;
}
