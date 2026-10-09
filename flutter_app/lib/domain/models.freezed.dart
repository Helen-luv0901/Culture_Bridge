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
mixin _$ActionItem {

 String get id; Map<String, dynamic> get content;
/// Create a copy of ActionItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionItemCopyWith<ActionItem> get copyWith => _$ActionItemCopyWithImpl<ActionItem>(this as ActionItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActionItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionItem&&(identical(other.id, _this.id) || other.id == _this.id)&&const DeepCollectionEquality().equals(other.content, _this.content));
}


@override
int get hashCode {
  final _this = this as ActionItem;
  return Object.hash(runtimeType,_this.id,const DeepCollectionEquality().hash(_this.content));
}

@override
String toString() {
  final _this = this as ActionItem;
  return 'ActionItem(id: ${_this.id}, content: ${_this.content})';
}


}

/// @nodoc
abstract mixin class $ActionItemCopyWith<$Res>  {
  factory $ActionItemCopyWith(ActionItem value, $Res Function(ActionItem) _then) = _$ActionItemCopyWithImpl;
@useResult
$Res call({
 String id, Map<String, dynamic> content
});




}
/// @nodoc
class _$ActionItemCopyWithImpl<$Res>
    implements $ActionItemCopyWith<$Res> {
  _$ActionItemCopyWithImpl(this._self, this._then);

  final ActionItem _self;
  final $Res Function(ActionItem) _then;

/// Create a copy of ActionItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? content = null,}) {
  return _then(ActionItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [ActionItem].
extension ActionItemPatterns on ActionItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActionItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActionItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActionItem value)  $default,){
final _that = this;
switch (_that) {
case _ActionItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActionItem value)?  $default,){
final _that = this;
switch (_that) {
case _ActionItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  Map<String, dynamic> content)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActionItem() when $default != null:
return $default(_that.id,_that.content);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  Map<String, dynamic> content)  $default,) {final _that = this;
switch (_that) {
case _ActionItem():
return $default(_that.id,_that.content);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  Map<String, dynamic> content)?  $default,) {final _that = this;
switch (_that) {
case _ActionItem() when $default != null:
return $default(_that.id,_that.content);case _:
  return null;

}
}

}

/// @nodoc


class _ActionItem extends ActionItem {
  const _ActionItem({required this.id, required  Map<String, dynamic> content}): _content = content,super._();
  

@override final  String id;
 final  Map<String, dynamic> _content;
@override Map<String, dynamic> get content {
  if (_content is EqualUnmodifiableMapView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_content);
}


/// Create a copy of ActionItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionItemCopyWith<_ActionItem> get copyWith => __$ActionItemCopyWithImpl<_ActionItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionItem&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.content, _content));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_content));
}

@override
String toString() {
    return 'ActionItem(id: $id, content: $content)';
}


}

/// @nodoc
abstract mixin class _$ActionItemCopyWith<$Res> implements $ActionItemCopyWith<$Res> {
  factory _$ActionItemCopyWith(_ActionItem value, $Res Function(_ActionItem) _then) = __$ActionItemCopyWithImpl;
@override @useResult
$Res call({
 String id, Map<String, dynamic> content
});




}
/// @nodoc
class __$ActionItemCopyWithImpl<$Res>
    implements _$ActionItemCopyWith<$Res> {
  __$ActionItemCopyWithImpl(this._self, this._then);

  final _ActionItem _self;
  final $Res Function(_ActionItem) _then;

/// Create a copy of ActionItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? content = null,}) {
  return _then(_ActionItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$Experience {

 String get id; Map<String, dynamic> get content;
/// Create a copy of Experience
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExperienceCopyWith<Experience> get copyWith => _$ExperienceCopyWithImpl<Experience>(this as Experience, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Experience;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Experience&&(identical(other.id, _this.id) || other.id == _this.id)&&const DeepCollectionEquality().equals(other.content, _this.content));
}


@override
int get hashCode {
  final _this = this as Experience;
  return Object.hash(runtimeType,_this.id,const DeepCollectionEquality().hash(_this.content));
}

@override
String toString() {
  final _this = this as Experience;
  return 'Experience(id: ${_this.id}, content: ${_this.content})';
}


}

/// @nodoc
abstract mixin class $ExperienceCopyWith<$Res>  {
  factory $ExperienceCopyWith(Experience value, $Res Function(Experience) _then) = _$ExperienceCopyWithImpl;
@useResult
$Res call({
 String id, Map<String, dynamic> content
});




}
/// @nodoc
class _$ExperienceCopyWithImpl<$Res>
    implements $ExperienceCopyWith<$Res> {
  _$ExperienceCopyWithImpl(this._self, this._then);

  final Experience _self;
  final $Res Function(Experience) _then;

/// Create a copy of Experience
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? content = null,}) {
  return _then(Experience(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [Experience].
extension ExperiencePatterns on Experience {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Experience value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Experience() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Experience value)  $default,){
final _that = this;
switch (_that) {
case _Experience():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Experience value)?  $default,){
final _that = this;
switch (_that) {
case _Experience() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  Map<String, dynamic> content)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Experience() when $default != null:
return $default(_that.id,_that.content);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  Map<String, dynamic> content)  $default,) {final _that = this;
switch (_that) {
case _Experience():
return $default(_that.id,_that.content);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  Map<String, dynamic> content)?  $default,) {final _that = this;
switch (_that) {
case _Experience() when $default != null:
return $default(_that.id,_that.content);case _:
  return null;

}
}

}

/// @nodoc


class _Experience extends Experience {
  const _Experience({required this.id, required  Map<String, dynamic> content}): _content = content,super._();
  

@override final  String id;
 final  Map<String, dynamic> _content;
@override Map<String, dynamic> get content {
  if (_content is EqualUnmodifiableMapView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_content);
}


/// Create a copy of Experience
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExperienceCopyWith<_Experience> get copyWith => __$ExperienceCopyWithImpl<_Experience>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Experience&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.content, _content));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_content));
}

@override
String toString() {
    return 'Experience(id: $id, content: $content)';
}


}

/// @nodoc
abstract mixin class _$ExperienceCopyWith<$Res> implements $ExperienceCopyWith<$Res> {
  factory _$ExperienceCopyWith(_Experience value, $Res Function(_Experience) _then) = __$ExperienceCopyWithImpl;
@override @useResult
$Res call({
 String id, Map<String, dynamic> content
});




}
/// @nodoc
class __$ExperienceCopyWithImpl<$Res>
    implements _$ExperienceCopyWith<$Res> {
  __$ExperienceCopyWithImpl(this._self, this._then);

  final _Experience _self;
  final $Res Function(_Experience) _then;

/// Create a copy of Experience
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? content = null,}) {
  return _then(_Experience(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$ShareDraft {

 String get voice; String get topic; String get identity;
/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareDraftCopyWith<ShareDraft> get copyWith => _$ShareDraftCopyWithImpl<ShareDraft>(this as ShareDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShareDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareDraft&&(identical(other.voice, _this.voice) || other.voice == _this.voice)&&(identical(other.topic, _this.topic) || other.topic == _this.topic)&&(identical(other.identity, _this.identity) || other.identity == _this.identity));
}


@override
int get hashCode {
  final _this = this as ShareDraft;
  return Object.hash(runtimeType,_this.voice,_this.topic,_this.identity);
}

@override
String toString() {
  final _this = this as ShareDraft;
  return 'ShareDraft(voice: ${_this.voice}, topic: ${_this.topic}, identity: ${_this.identity})';
}


}

/// @nodoc
abstract mixin class $ShareDraftCopyWith<$Res>  {
  factory $ShareDraftCopyWith(ShareDraft value, $Res Function(ShareDraft) _then) = _$ShareDraftCopyWithImpl;
@useResult
$Res call({
 String voice, String topic, String identity
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
@pragma('vm:prefer-inline') @override $Res call({Object? voice = null,Object? topic = null,Object? identity = null,}) {
  return _then(ShareDraft(
voice: null == voice ? _self.voice : voice // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as String,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String voice,  String topic,  String identity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that.voice,_that.topic,_that.identity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String voice,  String topic,  String identity)  $default,) {final _that = this;
switch (_that) {
case _ShareDraft():
return $default(_that.voice,_that.topic,_that.identity);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String voice,  String topic,  String identity)?  $default,) {final _that = this;
switch (_that) {
case _ShareDraft() when $default != null:
return $default(_that.voice,_that.topic,_that.identity);case _:
  return null;

}
}

}

/// @nodoc


class _ShareDraft implements ShareDraft {
  const _ShareDraft({this.voice = '', this.topic = 'cultureCommunication', this.identity = 'degreeStudent'});
  

@override@JsonKey() final  String voice;
@override@JsonKey() final  String topic;
@override@JsonKey() final  String identity;

/// Create a copy of ShareDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareDraftCopyWith<_ShareDraft> get copyWith => __$ShareDraftCopyWithImpl<_ShareDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShareDraft&&(identical(other.voice, voice) || other.voice == voice)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.identity, identity) || other.identity == identity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,voice,topic,identity);
}

@override
String toString() {
    return 'ShareDraft(voice: $voice, topic: $topic, identity: $identity)';
}


}

/// @nodoc
abstract mixin class _$ShareDraftCopyWith<$Res> implements $ShareDraftCopyWith<$Res> {
  factory _$ShareDraftCopyWith(_ShareDraft value, $Res Function(_ShareDraft) _then) = __$ShareDraftCopyWithImpl;
@override @useResult
$Res call({
 String voice, String topic, String identity
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
@override @pragma('vm:prefer-inline') $Res call({Object? voice = null,Object? topic = null,Object? identity = null,}) {
  return _then(_ShareDraft(
voice: null == voice ? _self.voice : voice // ignore: cast_nullable_to_non_nullable
as String,topic: null == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
