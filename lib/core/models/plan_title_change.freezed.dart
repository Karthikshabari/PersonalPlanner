// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_title_change.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PlanTitleChange {

 String get id;@JsonKey(name: 'previous_title') String get previousTitle;@JsonKey(name: 'new_title') String get newTitle;@JsonKey(name: 'changed_at') DateTime get changedAt;@JsonKey(name: 'reverted_at') DateTime? get revertedAt;
/// Create a copy of PlanTitleChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanTitleChangeCopyWith<PlanTitleChange> get copyWith => _$PlanTitleChangeCopyWithImpl<PlanTitleChange>(this as PlanTitleChange, _$identity);

  /// Serializes this PlanTitleChange to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanTitleChange&&(identical(other.id, id) || other.id == id)&&(identical(other.previousTitle, previousTitle) || other.previousTitle == previousTitle)&&(identical(other.newTitle, newTitle) || other.newTitle == newTitle)&&(identical(other.changedAt, changedAt) || other.changedAt == changedAt)&&(identical(other.revertedAt, revertedAt) || other.revertedAt == revertedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,previousTitle,newTitle,changedAt,revertedAt);

@override
String toString() {
  return 'PlanTitleChange(id: $id, previousTitle: $previousTitle, newTitle: $newTitle, changedAt: $changedAt, revertedAt: $revertedAt)';
}


}

/// @nodoc
abstract mixin class $PlanTitleChangeCopyWith<$Res>  {
  factory $PlanTitleChangeCopyWith(PlanTitleChange value, $Res Function(PlanTitleChange) _then) = _$PlanTitleChangeCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'previous_title') String previousTitle,@JsonKey(name: 'new_title') String newTitle,@JsonKey(name: 'changed_at') DateTime changedAt,@JsonKey(name: 'reverted_at') DateTime? revertedAt
});




}
/// @nodoc
class _$PlanTitleChangeCopyWithImpl<$Res>
    implements $PlanTitleChangeCopyWith<$Res> {
  _$PlanTitleChangeCopyWithImpl(this._self, this._then);

  final PlanTitleChange _self;
  final $Res Function(PlanTitleChange) _then;

/// Create a copy of PlanTitleChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? previousTitle = null,Object? newTitle = null,Object? changedAt = null,Object? revertedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,previousTitle: null == previousTitle ? _self.previousTitle : previousTitle // ignore: cast_nullable_to_non_nullable
as String,newTitle: null == newTitle ? _self.newTitle : newTitle // ignore: cast_nullable_to_non_nullable
as String,changedAt: null == changedAt ? _self.changedAt : changedAt // ignore: cast_nullable_to_non_nullable
as DateTime,revertedAt: freezed == revertedAt ? _self.revertedAt : revertedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlanTitleChange].
extension PlanTitleChangePatterns on PlanTitleChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanTitleChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanTitleChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanTitleChange value)  $default,){
final _that = this;
switch (_that) {
case _PlanTitleChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanTitleChange value)?  $default,){
final _that = this;
switch (_that) {
case _PlanTitleChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'previous_title')  String previousTitle, @JsonKey(name: 'new_title')  String newTitle, @JsonKey(name: 'changed_at')  DateTime changedAt, @JsonKey(name: 'reverted_at')  DateTime? revertedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanTitleChange() when $default != null:
return $default(_that.id,_that.previousTitle,_that.newTitle,_that.changedAt,_that.revertedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'previous_title')  String previousTitle, @JsonKey(name: 'new_title')  String newTitle, @JsonKey(name: 'changed_at')  DateTime changedAt, @JsonKey(name: 'reverted_at')  DateTime? revertedAt)  $default,) {final _that = this;
switch (_that) {
case _PlanTitleChange():
return $default(_that.id,_that.previousTitle,_that.newTitle,_that.changedAt,_that.revertedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'previous_title')  String previousTitle, @JsonKey(name: 'new_title')  String newTitle, @JsonKey(name: 'changed_at')  DateTime changedAt, @JsonKey(name: 'reverted_at')  DateTime? revertedAt)?  $default,) {final _that = this;
switch (_that) {
case _PlanTitleChange() when $default != null:
return $default(_that.id,_that.previousTitle,_that.newTitle,_that.changedAt,_that.revertedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlanTitleChange implements PlanTitleChange {
  const _PlanTitleChange({required this.id, @JsonKey(name: 'previous_title') required this.previousTitle, @JsonKey(name: 'new_title') required this.newTitle, @JsonKey(name: 'changed_at') required this.changedAt, @JsonKey(name: 'reverted_at') this.revertedAt});
  factory _PlanTitleChange.fromJson(Map<String, dynamic> json) => _$PlanTitleChangeFromJson(json);

@override final  String id;
@override@JsonKey(name: 'previous_title') final  String previousTitle;
@override@JsonKey(name: 'new_title') final  String newTitle;
@override@JsonKey(name: 'changed_at') final  DateTime changedAt;
@override@JsonKey(name: 'reverted_at') final  DateTime? revertedAt;

/// Create a copy of PlanTitleChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanTitleChangeCopyWith<_PlanTitleChange> get copyWith => __$PlanTitleChangeCopyWithImpl<_PlanTitleChange>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlanTitleChangeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanTitleChange&&(identical(other.id, id) || other.id == id)&&(identical(other.previousTitle, previousTitle) || other.previousTitle == previousTitle)&&(identical(other.newTitle, newTitle) || other.newTitle == newTitle)&&(identical(other.changedAt, changedAt) || other.changedAt == changedAt)&&(identical(other.revertedAt, revertedAt) || other.revertedAt == revertedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,previousTitle,newTitle,changedAt,revertedAt);

@override
String toString() {
  return 'PlanTitleChange(id: $id, previousTitle: $previousTitle, newTitle: $newTitle, changedAt: $changedAt, revertedAt: $revertedAt)';
}


}

/// @nodoc
abstract mixin class _$PlanTitleChangeCopyWith<$Res> implements $PlanTitleChangeCopyWith<$Res> {
  factory _$PlanTitleChangeCopyWith(_PlanTitleChange value, $Res Function(_PlanTitleChange) _then) = __$PlanTitleChangeCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'previous_title') String previousTitle,@JsonKey(name: 'new_title') String newTitle,@JsonKey(name: 'changed_at') DateTime changedAt,@JsonKey(name: 'reverted_at') DateTime? revertedAt
});




}
/// @nodoc
class __$PlanTitleChangeCopyWithImpl<$Res>
    implements _$PlanTitleChangeCopyWith<$Res> {
  __$PlanTitleChangeCopyWithImpl(this._self, this._then);

  final _PlanTitleChange _self;
  final $Res Function(_PlanTitleChange) _then;

/// Create a copy of PlanTitleChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? previousTitle = null,Object? newTitle = null,Object? changedAt = null,Object? revertedAt = freezed,}) {
  return _then(_PlanTitleChange(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,previousTitle: null == previousTitle ? _self.previousTitle : previousTitle // ignore: cast_nullable_to_non_nullable
as String,newTitle: null == newTitle ? _self.newTitle : newTitle // ignore: cast_nullable_to_non_nullable
as String,changedAt: null == changedAt ? _self.changedAt : changedAt // ignore: cast_nullable_to_non_nullable
as DateTime,revertedAt: freezed == revertedAt ? _self.revertedAt : revertedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
