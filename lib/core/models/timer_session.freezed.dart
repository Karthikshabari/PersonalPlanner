// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timer_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TimerSession {

 String get id; String get taskId; DateTime get startedAt; DateTime? get endedAt; int get durationSec; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of TimerSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimerSessionCopyWith<TimerSession> get copyWith => _$TimerSessionCopyWithImpl<TimerSession>(this as TimerSession, _$identity);

  /// Serializes this TimerSession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimerSession&&(identical(other.id, id) || other.id == id)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.durationSec, durationSec) || other.durationSec == durationSec)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,taskId,startedAt,endedAt,durationSec,createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'TimerSession(id: $id, taskId: $taskId, startedAt: $startedAt, endedAt: $endedAt, durationSec: $durationSec, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $TimerSessionCopyWith<$Res>  {
  factory $TimerSessionCopyWith(TimerSession value, $Res Function(TimerSession) _then) = _$TimerSessionCopyWithImpl;
@useResult
$Res call({
 String id, String taskId, DateTime startedAt, DateTime? endedAt, int durationSec, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$TimerSessionCopyWithImpl<$Res>
    implements $TimerSessionCopyWith<$Res> {
  _$TimerSessionCopyWithImpl(this._self, this._then);

  final TimerSession _self;
  final $Res Function(TimerSession) _then;

/// Create a copy of TimerSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? taskId = null,Object? startedAt = null,Object? endedAt = freezed,Object? durationSec = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationSec: null == durationSec ? _self.durationSec : durationSec // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TimerSession].
extension TimerSessionPatterns on TimerSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimerSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimerSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimerSession value)  $default,){
final _that = this;
switch (_that) {
case _TimerSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimerSession value)?  $default,){
final _that = this;
switch (_that) {
case _TimerSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String taskId,  DateTime startedAt,  DateTime? endedAt,  int durationSec,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimerSession() when $default != null:
return $default(_that.id,_that.taskId,_that.startedAt,_that.endedAt,_that.durationSec,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String taskId,  DateTime startedAt,  DateTime? endedAt,  int durationSec,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _TimerSession():
return $default(_that.id,_that.taskId,_that.startedAt,_that.endedAt,_that.durationSec,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String taskId,  DateTime startedAt,  DateTime? endedAt,  int durationSec,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _TimerSession() when $default != null:
return $default(_that.id,_that.taskId,_that.startedAt,_that.endedAt,_that.durationSec,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TimerSession implements TimerSession {
  const _TimerSession({required this.id, required this.taskId, required this.startedAt, this.endedAt, this.durationSec = 0, required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _TimerSession.fromJson(Map<String, dynamic> json) => _$TimerSessionFromJson(json);

@override final  String id;
@override final  String taskId;
@override final  DateTime startedAt;
@override final  DateTime? endedAt;
@override@JsonKey() final  int durationSec;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of TimerSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimerSessionCopyWith<_TimerSession> get copyWith => __$TimerSessionCopyWithImpl<_TimerSession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TimerSessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimerSession&&(identical(other.id, id) || other.id == id)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.durationSec, durationSec) || other.durationSec == durationSec)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,taskId,startedAt,endedAt,durationSec,createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'TimerSession(id: $id, taskId: $taskId, startedAt: $startedAt, endedAt: $endedAt, durationSec: $durationSec, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$TimerSessionCopyWith<$Res> implements $TimerSessionCopyWith<$Res> {
  factory _$TimerSessionCopyWith(_TimerSession value, $Res Function(_TimerSession) _then) = __$TimerSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String taskId, DateTime startedAt, DateTime? endedAt, int durationSec, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$TimerSessionCopyWithImpl<$Res>
    implements _$TimerSessionCopyWith<$Res> {
  __$TimerSessionCopyWithImpl(this._self, this._then);

  final _TimerSession _self;
  final $Res Function(_TimerSession) _then;

/// Create a copy of TimerSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? taskId = null,Object? startedAt = null,Object? endedAt = freezed,Object? durationSec = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_TimerSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationSec: null == durationSec ? _self.durationSec : durationSec // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
