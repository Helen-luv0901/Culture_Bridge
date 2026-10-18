import 'package:flutter/foundation.dart';

/// What the student is writing on the Share page. Kept on the device until published.
@immutable
class ShareDraft {
  const ShareDraft({
    this.title = '',
    this.voice = '',
    this.category,
    this.chosenTags = const [],
    this.customTags = const [],
    this.authorDisplay = 'anonymous',
    this.differentFromId,
    this.actionId,
    this.resumesId,
  });

  final String title;
  final String voice;

  /// One of [postCategories]; null until the student picks one.
  final String? category;

  /// AI-suggested tags the student ticked.
  final List<String> chosenTags;

  /// Tags the student typed in themselves.
  final List<String> customTags;
  final String authorDisplay;

  /// Set when this answers another post ("my experience was different").
  final String? differentFromId;

  /// Set when shared from an official guide, so the post also shows under it.
  final String? actionId;

  /// An unpublished post saved on the server that this draft continues; it is
  /// deleted once the draft is published.
  final String? resumesId;

  bool get isEmpty => title.trim().isEmpty && voice.trim().isEmpty;

  ShareDraft copyWith({
    String? title,
    String? voice,
    String? category,
    List<String>? chosenTags,
    List<String>? customTags,
    String? authorDisplay,
  }) => ShareDraft(
    title: title ?? this.title,
    voice: voice ?? this.voice,
    category: category ?? this.category,
    chosenTags: chosenTags ?? this.chosenTags,
    customTags: customTags ?? this.customTags,
    authorDisplay: authorDisplay ?? this.authorDisplay,
    differentFromId: differentFromId,
    actionId: actionId,
    resumesId: resumesId,
  );

  /// The same draft without the link to another post or guide.
  ShareDraft unlinked({bool post = false, bool guide = false}) => ShareDraft(
    title: title,
    voice: voice,
    category: category,
    chosenTags: chosenTags,
    customTags: customTags,
    authorDisplay: authorDisplay,
    differentFromId: post ? null : differentFromId,
    actionId: guide ? null : actionId,
    resumesId: resumesId,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'voice': voice,
    'category': category,
    'chosenTags': chosenTags,
    'customTags': customTags,
    'authorDisplay': authorDisplay,
    'differentFromId': differentFromId,
    'actionId': actionId,
    'resumesId': resumesId,
  };

  factory ShareDraft.fromJson(Map<String, dynamic> json) => ShareDraft(
    title: json['title'] as String? ?? '',
    voice: json['voice'] as String? ?? '',
    category: json['category'] as String?,
    chosenTags: List<String>.from(json['chosenTags'] as List? ?? const []),
    customTags: List<String>.from(json['customTags'] as List? ?? const []),
    authorDisplay: json['authorDisplay'] as String? ?? 'anonymous',
    differentFromId: json['differentFromId'] as String?,
    actionId: json['actionId'] as String?,
    resumesId: json['resumesId'] as String?,
  );
}
