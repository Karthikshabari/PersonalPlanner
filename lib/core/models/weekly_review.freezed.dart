// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'weekly_review.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WeeklyReview {

 String get id; DateTime get weekStartDate; String? get reflection; int? get overallRating; List<String> get goalsMet; List<String> get goalsMissed; List<String> get nextWeekFocus; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of WeeklyReview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WeeklyReviewCopyWith<WeeklyReview> get copyWith => _$WeeklyReviewCopyWithImpl<WeeklyReview>(this as WeeklyReview, _$identity);

  /// Serializes this WeeklyReview to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WeeklyReview&&(identical(other.id, id) || other.id == id)&&(identical(other.weekStartDate, weekStartDate) || other.weekStartDate == weekStartDate)&&(identical(other.reflection, reflection) || other.reflection == reflection)&&(identical(other.overallRating, overallRating) || other.overallRating == overallRating)&&const DeepCollectionEquality().equals(other.goalsMet, goalsMet)&&const DeepCollectionEquality().equals(other.goalsMissed, goalsMissed)&&const DeepCollectionEquality().equals(other.nextWeekFocus, nextWeekFocus)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,weekStartDate,reflection,overallRating,const DeepCollectionEquality().hash(goalsMet),const DeepCollectionEquality().hash(goalsMissed),const DeepCollectionEquality().hash(nextWeekFocus),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'WeeklyReview(id: $id, weekStartDate: $weekStartDate, reflection: $reflection, overallRating: $overallRating, goalsMet: $goalsMet, goalsMissed: $goalsMissed, nextWeekFocus: $nextWeekFocus, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $WeeklyReviewCopyWith<$Res>  {
  factory $WeeklyReviewCopyWith(WeeklyReview value, $Res Function(WeeklyReview) _then) = _$WeeklyReviewCopyWithImpl;
@useResult
$Res call({
 String id, DateTime weekStartDate, String? reflection, int? overallRating, List<String> goalsMet, List<String> goalsMissed, List<String> nextWeekFocus, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$WeeklyReviewCopyWithImpl<$Res>
    implements $WeeklyReviewCopyWith<$Res> {
  _$WeeklyReviewCopyWithImpl(this._self, this._then);

  final WeeklyReview _self;
  final $Res Function(WeeklyReview) _then;

/// Create a copy of WeeklyReview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? weekStartDate = null,Object? reflection = freezed,Object? overallRating = freezed,Object? goalsMet = null,Object? goalsMissed = null,Object? nextWeekFocus = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,weekStartDate: null == weekStartDate ? _self.weekStartDate : weekStartDate // ignore: cast_nullable_to_non_nullable
as DateTime,reflection: freezed == reflection ? _self.reflection : reflection // ignore: cast_nullable_to_non_nullable
as String?,overallRating: freezed == overallRating ? _self.overallRating : overallRating // ignore: cast_nullable_to_non_nullable
as int?,goalsMet: null == goalsMet ? _self.goalsMet : goalsMet // ignore: cast_nullable_to_non_nullable
as List<String>,goalsMissed: null == goalsMissed ? _self.goalsMissed : goalsMissed // ignore: cast_nullable_to_non_nullable
as List<String>,nextWeekFocus: null == nextWeekFocus ? _self.nextWeekFocus : nextWeekFocus // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [WeeklyReview].
extension WeeklyReviewPatterns on WeeklyReview {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WeeklyReview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WeeklyReview() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WeeklyReview value)  $default,){
final _that = this;
switch (_that) {
case _WeeklyReview():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WeeklyReview value)?  $default,){
final _that = this;
switch (_that) {
case _WeeklyReview() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime weekStartDate,  String? reflection,  int? overallRating,  List<String> goalsMet,  List<String> goalsMissed,  List<String> nextWeekFocus,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WeeklyReview() when $default != null:
return $default(_that.id,_that.weekStartDate,_that.reflection,_that.overallRating,_that.goalsMet,_that.goalsMissed,_that.nextWeekFocus,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime weekStartDate,  String? reflection,  int? overallRating,  List<String> goalsMet,  List<String> goalsMissed,  List<String> nextWeekFocus,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _WeeklyReview():
return $default(_that.id,_that.weekStartDate,_that.reflection,_that.overallRating,_that.goalsMet,_that.goalsMissed,_that.nextWeekFocus,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime weekStartDate,  String? reflection,  int? overallRating,  List<String> goalsMet,  List<String> goalsMissed,  List<String> nextWeekFocus,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _WeeklyReview() when $default != null:
return $default(_that.id,_that.weekStartDate,_that.reflection,_that.overallRating,_that.goalsMet,_that.goalsMissed,_that.nextWeekFocus,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WeeklyReview implements WeeklyReview {
  const _WeeklyReview({required this.id, required this.weekStartDate, this.reflection, this.overallRating, this.goalsMet = const [], this.goalsMissed = const [], this.nextWeekFocus = const [], required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _WeeklyReview.fromJson(Map<String, dynamic> json) => _$WeeklyReviewFromJson(json);

@override final  String id;
@override final  DateTime weekStartDate;
@override final  String? reflection;
@override final  int? overallRating;
@override@JsonKey() final  List<String> goalsMet;
@override@JsonKey() final  List<String> goalsMissed;
@override@JsonKey() final  List<String> nextWeekFocus;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of WeeklyReview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WeeklyReviewCopyWith<_WeeklyReview> get copyWith => __$WeeklyReviewCopyWithImpl<_WeeklyReview>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WeeklyReviewToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WeeklyReview&&(identical(other.id, id) || other.id == id)&&(identical(other.weekStartDate, weekStartDate) || other.weekStartDate == weekStartDate)&&(identical(other.reflection, reflection) || other.reflection == reflection)&&(identical(other.overallRating, overallRating) || other.overallRating == overallRating)&&const DeepCollectionEquality().equals(other.goalsMet, goalsMet)&&const DeepCollectionEquality().equals(other.goalsMissed, goalsMissed)&&const DeepCollectionEquality().equals(other.nextWeekFocus, nextWeekFocus)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,weekStartDate,reflection,overallRating,const DeepCollectionEquality().hash(goalsMet),const DeepCollectionEquality().hash(goalsMissed),const DeepCollectionEquality().hash(nextWeekFocus),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'WeeklyReview(id: $id, weekStartDate: $weekStartDate, reflection: $reflection, overallRating: $overallRating, goalsMet: $goalsMet, goalsMissed: $goalsMissed, nextWeekFocus: $nextWeekFocus, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$WeeklyReviewCopyWith<$Res> implements $WeeklyReviewCopyWith<$Res> {
  factory _$WeeklyReviewCopyWith(_WeeklyReview value, $Res Function(_WeeklyReview) _then) = __$WeeklyReviewCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime weekStartDate, String? reflection, int? overallRating, List<String> goalsMet, List<String> goalsMissed, List<String> nextWeekFocus, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$WeeklyReviewCopyWithImpl<$Res>
    implements _$WeeklyReviewCopyWith<$Res> {
  __$WeeklyReviewCopyWithImpl(this._self, this._then);

  final _WeeklyReview _self;
  final $Res Function(_WeeklyReview) _then;

/// Create a copy of WeeklyReview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? weekStartDate = null,Object? reflection = freezed,Object? overallRating = freezed,Object? goalsMet = null,Object? goalsMissed = null,Object? nextWeekFocus = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_WeeklyReview(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,weekStartDate: null == weekStartDate ? _self.weekStartDate : weekStartDate // ignore: cast_nullable_to_non_nullable
as DateTime,reflection: freezed == reflection ? _self.reflection : reflection // ignore: cast_nullable_to_non_nullable
as String?,overallRating: freezed == overallRating ? _self.overallRating : overallRating // ignore: cast_nullable_to_non_nullable
as int?,goalsMet: null == goalsMet ? _self.goalsMet : goalsMet // ignore: cast_nullable_to_non_nullable
as List<String>,goalsMissed: null == goalsMissed ? _self.goalsMissed : goalsMissed // ignore: cast_nullable_to_non_nullable
as List<String>,nextWeekFocus: null == nextWeekFocus ? _self.nextWeekFocus : nextWeekFocus // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
