// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'day_context.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DayContext {

 String get id; String get date; DayContextKind get kind; String? get customLabel; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt; int get revision;
/// Create a copy of DayContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DayContextCopyWith<DayContext> get copyWith => _$DayContextCopyWithImpl<DayContext>(this as DayContext, _$identity);

  /// Serializes this DayContext to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DayContext&&(identical(other.id, id) || other.id == id)&&(identical(other.date, date) || other.date == date)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.customLabel, customLabel) || other.customLabel == customLabel)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.revision, revision) || other.revision == revision));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,date,kind,customLabel,createdAt,updatedAt,deletedAt,revision);

@override
String toString() {
  return 'DayContext(id: $id, date: $date, kind: $kind, customLabel: $customLabel, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $DayContextCopyWith<$Res>  {
  factory $DayContextCopyWith(DayContext value, $Res Function(DayContext) _then) = _$DayContextCopyWithImpl;
@useResult
$Res call({
 String id, String date, DayContextKind kind, String? customLabel, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt, int revision
});




}
/// @nodoc
class _$DayContextCopyWithImpl<$Res>
    implements $DayContextCopyWith<$Res> {
  _$DayContextCopyWithImpl(this._self, this._then);

  final DayContext _self;
  final $Res Function(DayContext) _then;

/// Create a copy of DayContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? date = null,Object? kind = null,Object? customLabel = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,Object? revision = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DayContextKind,customLabel: freezed == customLabel ? _self.customLabel : customLabel // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DayContext].
extension DayContextPatterns on DayContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DayContext value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DayContext() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DayContext value)  $default,){
final _that = this;
switch (_that) {
case _DayContext():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DayContext value)?  $default,){
final _that = this;
switch (_that) {
case _DayContext() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String date,  DayContextKind kind,  String? customLabel,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DayContext() when $default != null:
return $default(_that.id,_that.date,_that.kind,_that.customLabel,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String date,  DayContextKind kind,  String? customLabel,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt,  int revision)  $default,) {final _that = this;
switch (_that) {
case _DayContext():
return $default(_that.id,_that.date,_that.kind,_that.customLabel,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String date,  DayContextKind kind,  String? customLabel,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _DayContext() when $default != null:
return $default(_that.id,_that.date,_that.kind,_that.customLabel,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.revision);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DayContext implements DayContext {
  const _DayContext({required this.id, required this.date, required this.kind, this.customLabel, required this.createdAt, required this.updatedAt, this.deletedAt, this.revision = 1});
  factory _DayContext.fromJson(Map<String, dynamic> json) => _$DayContextFromJson(json);

@override final  String id;
@override final  String date;
@override final  DayContextKind kind;
@override final  String? customLabel;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;
@override@JsonKey() final  int revision;

/// Create a copy of DayContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DayContextCopyWith<_DayContext> get copyWith => __$DayContextCopyWithImpl<_DayContext>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DayContextToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DayContext&&(identical(other.id, id) || other.id == id)&&(identical(other.date, date) || other.date == date)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.customLabel, customLabel) || other.customLabel == customLabel)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.revision, revision) || other.revision == revision));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,date,kind,customLabel,createdAt,updatedAt,deletedAt,revision);

@override
String toString() {
  return 'DayContext(id: $id, date: $date, kind: $kind, customLabel: $customLabel, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$DayContextCopyWith<$Res> implements $DayContextCopyWith<$Res> {
  factory _$DayContextCopyWith(_DayContext value, $Res Function(_DayContext) _then) = __$DayContextCopyWithImpl;
@override @useResult
$Res call({
 String id, String date, DayContextKind kind, String? customLabel, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt, int revision
});




}
/// @nodoc
class __$DayContextCopyWithImpl<$Res>
    implements _$DayContextCopyWith<$Res> {
  __$DayContextCopyWithImpl(this._self, this._then);

  final _DayContext _self;
  final $Res Function(_DayContext) _then;

/// Create a copy of DayContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? date = null,Object? kind = null,Object? customLabel = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,Object? revision = null,}) {
  return _then(_DayContext(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as DayContextKind,customLabel: freezed == customLabel ? _self.customLabel : customLabel // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
