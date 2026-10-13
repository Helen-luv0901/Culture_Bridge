import 'package:freezed_annotation/freezed_annotation.dart';
part 'models.freezed.dart';

/// What the student is writing on the Share page. Kept on the device until published.
@freezed
abstract class ShareDraft with _$ShareDraft {
  const factory ShareDraft({
    @Default('') String voice,
    @Default('cultureCommunication') String topic,
    @Default('degreeStudent') String identity,

    /// The server-side draft once the AI has been asked to organize it.
    String? serverId,

    /// Set when this answers another experience ("my experience was different").
    String? differentFromId,
  }) = _ShareDraft;
}
