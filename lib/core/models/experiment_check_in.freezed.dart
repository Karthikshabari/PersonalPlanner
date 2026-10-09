// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'experiment_check_in.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExperimentCheckIn {

 String get id; String get experimentId; String get slotDate; String get note; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of ExperimentCheckIn
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExperimentCheckInCopyWith<ExperimentCheckIn> get copyWith => _$ExperimentCheckInCopyWithImpl<ExperimentCheckIn>(this as ExperimentCheckIn, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExperimentCheckIn&&(identical(other.id, id) || other.id == id)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.slotDate, slotDate) || other.slotDate == slotDate)&&(identical(other.note, note) || other.note == note)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,experimentId,slotDate,note,createdAt,updatedAt);

@override
String toString() {
  return 'ExperimentCheckIn(id: $id, experimentId: $experimentId, slotDate: $slotDate, note: $note, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ExperimentCheckInCopyWith<$Res>  {
  factory $ExperimentCheckInCopyWith(ExperimentCheckIn value, $Res Function(ExperimentCheckIn) _then) = _$ExperimentCheckInCopyWithImpl;
@useResult
$Res call({
 String id, String experimentId, String slotDate, String note, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$ExperimentCheckInCopyWithImpl<$Res>
    implements $ExperimentCheckInCopyWith<$Res> {
  _$ExperimentCheckInCopyWithImpl(this._self, this._then);

  final ExperimentCheckIn _self;
  final $Res Function(ExperimentCheckIn) _then;

/// Create a copy of ExperimentCheckIn
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? experimentId = null,Object? slotDate = null,Object? note = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,experimentId: null == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String,slotDate: null == slotDate ? _self.slotDate : slotDate // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [ExperimentCheckIn].
extension ExperimentCheckInPatterns on ExperimentCheckIn {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExperimentCheckIn value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExperimentCheckIn() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExperimentCheckIn value)  $default,){
final _that = this;
switch (_that) {
case _ExperimentCheckIn():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExperimentCheckIn value)?  $default,){
final _that = this;
switch (_that) {
case _ExperimentCheckIn() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String experimentId,  String slotDate,  String note,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExperimentCheckIn() when $default != null:
return $default(_that.id,_that.experimentId,_that.slotDate,_that.note,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String experimentId,  String slotDate,  String note,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ExperimentCheckIn():
return $default(_that.id,_that.experimentId,_that.slotDate,_that.note,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String experimentId,  String slotDate,  String note,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ExperimentCheckIn() when $default != null:
return $default(_that.id,_that.experimentId,_that.slotDate,_that.note,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ExperimentCheckIn implements ExperimentCheckIn {
  const _ExperimentCheckIn({required this.id, required this.experimentId, required this.slotDate, required this.note, required this.createdAt, required this.updatedAt});
  

@override final  String id;
@override final  String experimentId;
@override final  String slotDate;
@override final  String note;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of ExperimentCheckIn
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExperimentCheckInCopyWith<_ExperimentCheckIn> get copyWith => __$ExperimentCheckInCopyWithImpl<_ExperimentCheckIn>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExperimentCheckIn&&(identical(other.id, id) || other.id == id)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.slotDate, slotDate) || other.slotDate == slotDate)&&(identical(other.note, note) || other.note == note)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,experimentId,slotDate,note,createdAt,updatedAt);

@override
String toString() {
  return 'ExperimentCheckIn(id: $id, experimentId: $experimentId, slotDate: $slotDate, note: $note, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ExperimentCheckInCopyWith<$Res> implements $ExperimentCheckInCopyWith<$Res> {
  factory _$ExperimentCheckInCopyWith(_ExperimentCheckIn value, $Res Function(_ExperimentCheckIn) _then) = __$ExperimentCheckInCopyWithImpl;
@override @useResult
$Res call({
 String id, String experimentId, String slotDate, String note, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$ExperimentCheckInCopyWithImpl<$Res>
    implements _$ExperimentCheckInCopyWith<$Res> {
  __$ExperimentCheckInCopyWithImpl(this._self, this._then);

  final _ExperimentCheckIn _self;
  final $Res Function(_ExperimentCheckIn) _then;

/// Create a copy of ExperimentCheckIn
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? experimentId = null,Object? slotDate = null,Object? note = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_ExperimentCheckIn(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,experimentId: null == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String,slotDate: null == slotDate ? _self.slotDate : slotDate // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
