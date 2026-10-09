import 'package:freezed_annotation/freezed_annotation.dart';
part 'models.freezed.dart';

@freezed
abstract class ActionItem with _$ActionItem {
  const ActionItem._();
  const factory ActionItem({
    required String id,
    required Map<String, dynamic> content,
  }) = _ActionItem;
  String text(String key, bool english) =>
      (english
              ? (content['translations']?['en']?[key] ?? content[key])
              : content[key])
          ?.toString() ??
      '';
  List<String> list(String key, bool english) => List<String>.from(
    (english
            ? (content['translations']?['en']?[key] ?? content[key])
            : content[key]) ??
        [],
  );
}

@freezed
abstract class Experience with _$Experience {
  const Experience._();
  const factory Experience({
    required String id,
    required Map<String, dynamic> content,
  }) = _Experience;
  String text(String key, bool english) =>
      (english
              ? (content['translations']?['en']?[key] ?? content[key])
              : content[key])
          ?.toString() ??
      '';
  String get topic => content['topicKey'] as String;
  String get identity => content['identityTypeKey'] as String;
  int get helpfulCount => content['helpfulCount'] as int;
  int get reactions => content['reactions'] as int;
}

@freezed
abstract class ShareDraft with _$ShareDraft {
  const factory ShareDraft({
    @Default('') String voice,
    @Default('cultureCommunication') String topic,
    @Default('degreeStudent') String identity,
  }) = _ShareDraft;
}
