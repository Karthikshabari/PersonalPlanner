// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_closure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$InboxClosure {

 InboxCloseKind get kind;/// UTC instant the item was closed.
 DateTime get at;/// Trimmed, 1..200 code points. Required for closed, optional for let go,
/// absent for experiment.
 String? get reason;/// `experiment:<tagId>` id; only for kind experiment.
@JsonKey(name: 'experiment_id') String? get experimentId;/// UTC instant of Bring back; null while closed. Only the last event may
/// be null.
@JsonKey(name: 'reopened_at') DateTime? get reopenedAt;
/// Create a copy of InboxClosure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxClosureCopyWith<InboxClosure> get copyWith => _$InboxClosureCopyWithImpl<InboxClosure>(this as InboxClosure, _$identity);

  /// Serializes this InboxClosure to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxClosure&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.at, at) || other.at == at)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.reopenedAt, reopenedAt) || other.reopenedAt == reopenedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,at,reason,experimentId,reopenedAt);

@override
String toString() {
  return 'InboxClosure(kind: $kind, at: $at, reason: $reason, experimentId: $experimentId, reopenedAt: $reopenedAt)';
}


}

/// @nodoc
abstract mixin class $InboxClosureCopyWith<$Res>  {
  factory $InboxClosureCopyWith(InboxClosure value, $Res Function(InboxClosure) _then) = _$InboxClosureCopyWithImpl;
@useResult
$Res call({
 InboxCloseKind kind, DateTime at, String? reason,@JsonKey(name: 'experiment_id') String? experimentId,@JsonKey(name: 'reopened_at') DateTime? reopenedAt
});




}
/// @nodoc
class _$InboxClosureCopyWithImpl<$Res>
    implements $InboxClosureCopyWith<$Res> {
  _$InboxClosureCopyWithImpl(this._self, this._then);

  final InboxClosure _self;
  final $Res Function(InboxClosure) _then;

/// Create a copy of InboxClosure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? at = null,Object? reason = freezed,Object? experimentId = freezed,Object? reopenedAt = freezed,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InboxCloseKind,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,experimentId: freezed == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String?,reopenedAt: freezed == reopenedAt ? _self.reopenedAt : reopenedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxClosure].
extension InboxClosurePatterns on InboxClosure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxClosure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxClosure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxClosure value)  $default,){
final _that = this;
switch (_that) {
case _InboxClosure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxClosure value)?  $default,){
final _that = this;
switch (_that) {
case _InboxClosure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InboxCloseKind kind,  DateTime at,  String? reason, @JsonKey(name: 'experiment_id')  String? experimentId, @JsonKey(name: 'reopened_at')  DateTime? reopenedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxClosure() when $default != null:
return $default(_that.kind,_that.at,_that.reason,_that.experimentId,_that.reopenedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InboxCloseKind kind,  DateTime at,  String? reason, @JsonKey(name: 'experiment_id')  String? experimentId, @JsonKey(name: 'reopened_at')  DateTime? reopenedAt)  $default,) {final _that = this;
switch (_that) {
case _InboxClosure():
return $default(_that.kind,_that.at,_that.reason,_that.experimentId,_that.reopenedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InboxCloseKind kind,  DateTime at,  String? reason, @JsonKey(name: 'experiment_id')  String? experimentId, @JsonKey(name: 'reopened_at')  DateTime? reopenedAt)?  $default,) {final _that = this;
switch (_that) {
case _InboxClosure() when $default != null:
return $default(_that.kind,_that.at,_that.reason,_that.experimentId,_that.reopenedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _InboxClosure implements InboxClosure {
  const _InboxClosure({required this.kind, required this.at, this.reason, @JsonKey(name: 'experiment_id') this.experimentId, @JsonKey(name: 'reopened_at') this.reopenedAt});
  factory _InboxClosure.fromJson(Map<String, dynamic> json) => _$InboxClosureFromJson(json);

@override final  InboxCloseKind kind;
/// UTC instant the item was closed.
@override final  DateTime at;
/// Trimmed, 1..200 code points. Required for closed, optional for let go,
/// absent for experiment.
@override final  String? reason;
/// `experiment:<tagId>` id; only for kind experiment.
@override@JsonKey(name: 'experiment_id') final  String? experimentId;
/// UTC instant of Bring back; null while closed. Only the last event may
/// be null.
@override@JsonKey(name: 'reopened_at') final  DateTime? reopenedAt;

/// Create a copy of InboxClosure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxClosureCopyWith<_InboxClosure> get copyWith => __$InboxClosureCopyWithImpl<_InboxClosure>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$InboxClosureToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxClosure&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.at, at) || other.at == at)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.reopenedAt, reopenedAt) || other.reopenedAt == reopenedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,at,reason,experimentId,reopenedAt);

@override
String toString() {
  return 'InboxClosure(kind: $kind, at: $at, reason: $reason, experimentId: $experimentId, reopenedAt: $reopenedAt)';
}


}

/// @nodoc
abstract mixin class _$InboxClosureCopyWith<$Res> implements $InboxClosureCopyWith<$Res> {
  factory _$InboxClosureCopyWith(_InboxClosure value, $Res Function(_InboxClosure) _then) = __$InboxClosureCopyWithImpl;
@override @useResult
$Res call({
 InboxCloseKind kind, DateTime at, String? reason,@JsonKey(name: 'experiment_id') String? experimentId,@JsonKey(name: 'reopened_at') DateTime? reopenedAt
});




}
/// @nodoc
class __$InboxClosureCopyWithImpl<$Res>
    implements _$InboxClosureCopyWith<$Res> {
  __$InboxClosureCopyWithImpl(this._self, this._then);

  final _InboxClosure _self;
  final $Res Function(_InboxClosure) _then;

/// Create a copy of InboxClosure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? at = null,Object? reason = freezed,Object? experimentId = freezed,Object? reopenedAt = freezed,}) {
  return _then(_InboxClosure(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InboxCloseKind,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,experimentId: freezed == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String?,reopenedAt: freezed == reopenedAt ? _self.reopenedAt : reopenedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
