// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'daily_review.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DailyReview {

 String get id; DateTime get date; String? get reflection; int? get energyLevel; int? get productivityRating; int? get planningAccuracyRating; List<String> get wins; List<String> get improvements; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DailyReviewCopyWith<DailyReview> get copyWith => _$DailyReviewCopyWithImpl<DailyReview>(this as DailyReview, _$identity);

  /// Serializes this DailyReview to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DailyReview&&(identical(other.id, id) || other.id == id)&&(identical(other.date, date) || other.date == date)&&(identical(other.reflection, reflection) || other.reflection == reflection)&&(identical(other.energyLevel, energyLevel) || other.energyLevel == energyLevel)&&(identical(other.productivityRating, productivityRating) || other.productivityRating == productivityRating)&&(identical(other.planningAccuracyRating, planningAccuracyRating) || other.planningAccuracyRating == planningAccuracyRating)&&const DeepCollectionEquality().equals(other.wins, wins)&&const DeepCollectionEquality().equals(other.improvements, improvements)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,date,reflection,energyLevel,productivityRating,planningAccuracyRating,const DeepCollectionEquality().hash(wins),const DeepCollectionEquality().hash(improvements),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'DailyReview(id: $id, date: $date, reflection: $reflection, energyLevel: $energyLevel, productivityRating: $productivityRating, planningAccuracyRating: $planningAccuracyRating, wins: $wins, improvements: $improvements, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $DailyReviewCopyWith<$Res>  {
  factory $DailyReviewCopyWith(DailyReview value, $Res Function(DailyReview) _then) = _$DailyReviewCopyWithImpl;
@useResult
$Res call({
 String id, DateTime date, String? reflection, int? energyLevel, int? productivityRating, int? planningAccuracyRating, List<String> wins, List<String> improvements, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$DailyReviewCopyWithImpl<$Res>
    implements $DailyReviewCopyWith<$Res> {
  _$DailyReviewCopyWithImpl(this._self, this._then);

  final DailyReview _self;
  final $Res Function(DailyReview) _then;

/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? date = null,Object? reflection = freezed,Object? energyLevel = freezed,Object? productivityRating = freezed,Object? planningAccuracyRating = freezed,Object? wins = null,Object? improvements = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,reflection: freezed == reflection ? _self.reflection : reflection // ignore: cast_nullable_to_non_nullable
as String?,energyLevel: freezed == energyLevel ? _self.energyLevel : energyLevel // ignore: cast_nullable_to_non_nullable
as int?,productivityRating: freezed == productivityRating ? _self.productivityRating : productivityRating // ignore: cast_nullable_to_non_nullable
as int?,planningAccuracyRating: freezed == planningAccuracyRating ? _self.planningAccuracyRating : planningAccuracyRating // ignore: cast_nullable_to_non_nullable
as int?,wins: null == wins ? _self.wins : wins // ignore: cast_nullable_to_non_nullable
as List<String>,improvements: null == improvements ? _self.improvements : improvements // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [DailyReview].
extension DailyReviewPatterns on DailyReview {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DailyReview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DailyReview value)  $default,){
final _that = this;
switch (_that) {
case _DailyReview():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DailyReview value)?  $default,){
final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime date,  String? reflection,  int? energyLevel,  int? productivityRating,  int? planningAccuracyRating,  List<String> wins,  List<String> improvements,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
return $default(_that.id,_that.date,_that.reflection,_that.energyLevel,_that.productivityRating,_that.planningAccuracyRating,_that.wins,_that.improvements,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime date,  String? reflection,  int? energyLevel,  int? productivityRating,  int? planningAccuracyRating,  List<String> wins,  List<String> improvements,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _DailyReview():
return $default(_that.id,_that.date,_that.reflection,_that.energyLevel,_that.productivityRating,_that.planningAccuracyRating,_that.wins,_that.improvements,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime date,  String? reflection,  int? energyLevel,  int? productivityRating,  int? planningAccuracyRating,  List<String> wins,  List<String> improvements,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
return $default(_that.id,_that.date,_that.reflection,_that.energyLevel,_that.productivityRating,_that.planningAccuracyRating,_that.wins,_that.improvements,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DailyReview implements DailyReview {
  const _DailyReview({required this.id, required this.date, this.reflection, this.energyLevel, this.productivityRating, this.planningAccuracyRating, this.wins = const [], this.improvements = const [], required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _DailyReview.fromJson(Map<String, dynamic> json) => _$DailyReviewFromJson(json);

@override final  String id;
@override final  DateTime date;
@override final  String? reflection;
@override final  int? energyLevel;
@override final  int? productivityRating;
@override final  int? planningAccuracyRating;
@override@JsonKey() final  List<String> wins;
@override@JsonKey() final  List<String> improvements;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DailyReviewCopyWith<_DailyReview> get copyWith => __$DailyReviewCopyWithImpl<_DailyReview>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DailyReviewToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DailyReview&&(identical(other.id, id) || other.id == id)&&(identical(other.date, date) || other.date == date)&&(identical(other.reflection, reflection) || other.reflection == reflection)&&(identical(other.energyLevel, energyLevel) || other.energyLevel == energyLevel)&&(identical(other.productivityRating, productivityRating) || other.productivityRating == productivityRating)&&(identical(other.planningAccuracyRating, planningAccuracyRating) || other.planningAccuracyRating == planningAccuracyRating)&&const DeepCollectionEquality().equals(other.wins, wins)&&const DeepCollectionEquality().equals(other.improvements, improvements)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,date,reflection,energyLevel,productivityRating,planningAccuracyRating,const DeepCollectionEquality().hash(wins),const DeepCollectionEquality().hash(improvements),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'DailyReview(id: $id, date: $date, reflection: $reflection, energyLevel: $energyLevel, productivityRating: $productivityRating, planningAccuracyRating: $planningAccuracyRating, wins: $wins, improvements: $improvements, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$DailyReviewCopyWith<$Res> implements $DailyReviewCopyWith<$Res> {
  factory _$DailyReviewCopyWith(_DailyReview value, $Res Function(_DailyReview) _then) = __$DailyReviewCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime date, String? reflection, int? energyLevel, int? productivityRating, int? planningAccuracyRating, List<String> wins, List<String> improvements, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$DailyReviewCopyWithImpl<$Res>
    implements _$DailyReviewCopyWith<$Res> {
  __$DailyReviewCopyWithImpl(this._self, this._then);

  final _DailyReview _self;
  final $Res Function(_DailyReview) _then;

/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? date = null,Object? reflection = freezed,Object? energyLevel = freezed,Object? productivityRating = freezed,Object? planningAccuracyRating = freezed,Object? wins = null,Object? improvements = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_DailyReview(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,reflection: freezed == reflection ? _self.reflection : reflection // ignore: cast_nullable_to_non_nullable
as String?,energyLevel: freezed == energyLevel ? _self.energyLevel : energyLevel // ignore: cast_nullable_to_non_nullable
as int?,productivityRating: freezed == productivityRating ? _self.productivityRating : productivityRating // ignore: cast_nullable_to_non_nullable
as int?,planningAccuracyRating: freezed == planningAccuracyRating ? _self.planningAccuracyRating : planningAccuracyRating // ignore: cast_nullable_to_non_nullable
as int?,wins: null == wins ? _self.wins : wins // ignore: cast_nullable_to_non_nullable
as List<String>,improvements: null == improvements ? _self.improvements : improvements // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
