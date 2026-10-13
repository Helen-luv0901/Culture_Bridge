import 'dart:convert';

import 'package:flutter/services.dart';

/// Interface strings in both languages (assets/data/messages.json).
class MessageCatalog {
  const MessageCatalog(this._messages);
  final Map<String, dynamic> _messages;

  static Future<MessageCatalog> load() async => MessageCatalog(
    jsonDecode(await rootBundle.loadString('assets/data/messages.json'))
        as Map<String, dynamic>,
  );

  String get(String key, bool english) =>
      _messages[english ? 'en' : 'zh-Hant']?[key]?.toString() ?? key;
}
