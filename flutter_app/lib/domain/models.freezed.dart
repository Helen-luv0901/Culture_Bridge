// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShareDraft {

 String get voice; String get topic; String get identity;/// The server-side draft once the AI has been asked to organize it.
 String? get serverId;/// Set when this answers another experience ("my experience was different").
 String? get differentFromId;
/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareDraftCopyWith<ShareDraft> get copyWith => _$ShareDraftCopyWithImpl<ShareDraft>(this as ShareDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShareDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareDraft&&(identical(other.voice, _this.voice) || other.voice == _this.voice)&&(identical(other.topic, _this.topic) || other.topic == _this.topic)&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.serverId, _this.serverId) || other.serverId == _this.serverId)&&(identical(other.differentFromId, _this.differentFromId) || other.differentFromId == _this.differentFromId));
}


@override
int get hashCode {
  final _this = this as ShareDraft;
  return Object.hash(runtimeType,_this.voice,_this.topic,_this.identity,_this.serverId,_this.differentFromId);
}

@override
String toString() {
  final _this = this as ShareDraft;
  return 'ShareDraft(voice: ${_this.voice}, topic: ${_this.topic}, identity: ${_this.identity}, serverId: ${_this.serverId}, differentFromId: ${_this.differentFromId})';
}


}

/// @nodoc
abstract mixin class $ShareDraftCopyWith<$Res>  {
  factory $ShareDraftCopyWith(ShareDraft value, $Res Function(ShareDraft) _then) = _$ShareDraftCopyWithImpl;
@useResult
$Res call({
 String voice, String topic, String identity, String? serverId, String? differentFromId
});




}
/// @nodoc
class _$ShareDraftCopyWithImpl<$Res>
    implements $ShareDraftCopyWith<$Res> {
  _$ShareDraftCopyWithImpl(this._self, this._then);

  final ShareDraft _self;
  final $Res Function(ShareDraft) _then;

/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? voice = null,Object? topic = null,Object? identity = null,Object? serverId = freezed,Object? differentFromId = freezed,}) {
  return _then(ShareDraft(
voice: null == voice ? _self.voice : voice // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as String,serverId: freezed == serverId ? _self.serverId : serverId // ignore: cast_nullable_to_non_nullable
as String?,differentFromId: freezed == differentFromId ? _self.differentFromId : differentFromId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShareDraft].
extension ShareDraftPatterns on ShareDraft {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShareDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShareDraft value)  $default,){
final _that = this;
switch (_that) {
case _ShareDraft():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShareDraft value)?  $default,){
final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String voice,  String topic,  String identity,  String? serverId,  String? differentFromId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that.voice,_that.topic,_that.identity,_that.serverId,_that.differentFromId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String voice,  String topic,  String identity,  String? serverId,  String? differentFromId)  $default,) {final _that = this;
switch (_that) {
case _ShareDraft():
return $default(_that.voice,_that.topic,_that.identity,_that.serverId,_that.differentFromId);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String voice,  String topic,  String identity,  String? serverId,  String? differentFromId)?  $default,) {final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that.voice,_that.topic,_that.identity,_that.serverId,_that.differentFromId);case _:
  return null;

}
}

}

/// @nodoc


class _ShareDraft implements ShareDraft {
  const _ShareDraft({this.voice = '', this.topic = 'cultureCommunication', this.identity = 'degreeStudent', this.serverId, this.differentFromId});
  

@override@JsonKey() final  String voice;
@override@JsonKey() final  String topic;
@override@JsonKey() final  String identity;
/// The server-side draft once the AI has been asked to organize it.
@override final  String? serverId;
/// Set when this answers another experience ("my experience was different").
@override final  String? differentFromId;

/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareDraftCopyWith<_ShareDraft> get copyWith => __$ShareDraftCopyWithImpl<_ShareDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShareDraft&&(identical(other.voice, voice) || other.voice == voice)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.serverId, serverId) || other.serverId == serverId)&&(identical(other.differentFromId, differentFromId) || other.differentFromId == differentFromId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,voice,topic,identity,serverId,differentFromId);
}

@override
String toString() {
    return 'ShareDraft(voice: $voice, topic: $topic, identity: $identity, serverId: $serverId, differentFromId: $differentFromId)';
}


}

/// @nodoc
abstract mixin class _$ShareDraftCopyWith<$Res> implements $ShareDraftCopyWith<$Res> {
  factory _$ShareDraftCopyWith(_ShareDraft value, $Res Function(_ShareDraft) _then) = __$ShareDraftCopyWithImpl;
@override @useResult
$Res call({
 String voice, String topic, String identity, String? serverId, String? differentFromId
});




}
/// @nodoc
class __$ShareDraftCopyWithImpl<$Res>
    implements _$ShareDraftCopyWith<$Res> {
  __$ShareDraftCopyWithImpl(this._self, this._then);

  final _ShareDraft _self;
  final $Res Function(_ShareDraft) _then;

/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? voice = null,Object? topic = null,Object? identity = null,Object? serverId = freezed,Object? differentFromId = freezed,}) {
  return _then(_ShareDraft(
voice: null == voice ? _self.voice : voice // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as String,serverId: freezed == serverId ? _self.serverId : serverId // ignore: cast_nullable_to_non_nullable
as String?,differentFromId: freezed == differentFromId ? _self.differentFromId : differentFromId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
