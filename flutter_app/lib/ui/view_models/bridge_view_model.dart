import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/admin_repository.dart';
import '../../data/api_client.dart';
import '../../data/auth_service.dart';
import '../../data/culture_repository.dart';
import '../../data/messages.dart';
import '../../data/preferences_repository.dart';
import '../../domain/api_models.dart';
import '../../domain/keys.dart';
import '../../domain/models.dart';

part 'bridge_view_model_account.dart';
part 'bridge_view_model_assistant.dart';
part 'bridge_view_model_comments.dart';
part 'bridge_view_model_core.dart';
part 'bridge_view_model_library.dart';
part 'bridge_view_model_moderation.dart';
part 'bridge_view_model_posts.dart';
part 'bridge_view_model_procedures.dart';
part 'bridge_view_model_share.dart';

/// Data loaded from the API: the last value, whether a load is running, and the last error.
@immutable
class Resource<T> {
  const Resource({this.data, this.error, this.loading = false});
  final T? data;
  final ApiException? error;
  final bool loading;
  bool get needsLoad => data == null && !loading && error == null;
}

/// App state for every screen: language, sign-in, cached API data and the share flow.
///
/// Each feature lives in its own part file as a mixin; this class wires them together
/// and owns what crosses all of them (sign-in changes and disposal).
class BridgeViewModel extends _BridgeCore
    with
        _BridgeProcedures,
        _BridgePosts,
        _BridgeLibrary,
        _BridgeComments,
        _BridgeModeration,
        _BridgeSharing,
        _BridgeAccount,
        _BridgeAssistant {
  BridgeViewModel({
    required super.repository,
    required super.auth,
    required super.messages,
    required super.preferences,
    super.admin,
    bool systemEnglish = false,
    super.livePostsEvery,
  }) {
    _english = preferences.english ?? systemEnglish;
    _draft = preferences.draft;
    _read = preferences.readIds;
    _savedGuides = preferences.savedGuides;
    _wasSignedIn = auth.signedIn;
    auth.addListener(_onAuthChanged);
  }

  static const stuckCategories = {
    'dontUnderstandStep': 'process',
    'documentsDifferent': 'documents',
    'websiteDoesNotWork': 'website',
  };

  static const maxTagLength = 12;
  static const maxTags = 8;

  // ---------- sign-in changes ----------

  late bool _wasSignedIn;

  void _onAuthChanged() {
    if (auth.signedIn == _wasSignedIn) return;
    _wasSignedIn = auth.signedIn;
    _clearPersonalData();
    if (auth.signedIn) unawaited(loadProfile());
    notifyListeners();
  }

  void _clearPersonalData() {
    profile = null;
    chat.clear();
    conversationId = null;
    executions = const Resource();
    mine = const Resource();
    blocks = const Resource();
    saved = const Resource();
    // Lists and details carry "my reactions" and block filtering.
    _dropLists();
    _comments.clear();
    tagSuggestions = const [];
    _suggestedFor = '';
    _suggestRequest++;
    suggestingTags = false;
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    _saveTimer?.cancel();
    _suggestTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }
}
