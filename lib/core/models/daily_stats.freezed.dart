// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'daily_stats.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DailyStats {

 DateTime get date; int get totalTasks; int get completedTasks; int get plannedTasks; int get inProgressTasks; int get missedTasks; int get skippedTasks; int get cancelledTasks; int get rescheduledTasks; int get plannedDurationMin; int get actualDurationMin; int get focusDurationMin; int? get energyLevel; int? get productivityRating; double? get planningAccuracyPct; DateTime get computedAt;
/// Create a copy of DailyStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DailyStatsCopyWith<DailyStats> get copyWith => _$DailyStatsCopyWithImpl<DailyStats>(this as DailyStats, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DailyStats&&(identical(other.date, date) || other.date == date)&&(identical(other.totalTasks, totalTasks) || other.totalTasks == totalTasks)&&(identical(other.completedTasks, completedTasks) || other.completedTasks == completedTasks)&&(identical(other.plannedTasks, plannedTasks) || other.plannedTasks == plannedTasks)&&(identical(other.inProgressTasks, inProgressTasks) || other.inProgressTasks == inProgressTasks)&&(identical(other.missedTasks, missedTasks) || other.missedTasks == missedTasks)&&(identical(other.skippedTasks, skippedTasks) || other.skippedTasks == skippedTasks)&&(identical(other.cancelledTasks, cancelledTasks) || other.cancelledTasks == cancelledTasks)&&(identical(other.rescheduledTasks, rescheduledTasks) || other.rescheduledTasks == rescheduledTasks)&&(identical(other.plannedDurationMin, plannedDurationMin) || other.plannedDurationMin == plannedDurationMin)&&(identical(other.actualDurationMin, actualDurationMin) || other.actualDurationMin == actualDurationMin)&&(identical(other.focusDurationMin, focusDurationMin) || other.focusDurationMin == focusDurationMin)&&(identical(other.energyLevel, energyLevel) || other.energyLevel == energyLevel)&&(identical(other.productivityRating, productivityRating) || other.productivityRating == productivityRating)&&(identical(other.planningAccuracyPct, planningAccuracyPct) || other.planningAccuracyPct == planningAccuracyPct)&&(identical(other.computedAt, computedAt) || other.computedAt == computedAt));
}


@override
int get hashCode => Object.hash(runtimeType,date,totalTasks,completedTasks,plannedTasks,inProgressTasks,missedTasks,skippedTasks,cancelledTasks,rescheduledTasks,plannedDurationMin,actualDurationMin,focusDurationMin,energyLevel,productivityRating,planningAccuracyPct,computedAt);

@override
String toString() {
  return 'DailyStats(date: $date, totalTasks: $totalTasks, completedTasks: $completedTasks, plannedTasks: $plannedTasks, inProgressTasks: $inProgressTasks, missedTasks: $missedTasks, skippedTasks: $skippedTasks, cancelledTasks: $cancelledTasks, rescheduledTasks: $rescheduledTasks, plannedDurationMin: $plannedDurationMin, actualDurationMin: $actualDurationMin, focusDurationMin: $focusDurationMin, energyLevel: $energyLevel, productivityRating: $productivityRating, planningAccuracyPct: $planningAccuracyPct, computedAt: $computedAt)';
}


}

/// @nodoc
abstract mixin class $DailyStatsCopyWith<$Res>  {
  factory $DailyStatsCopyWith(DailyStats value, $Res Function(DailyStats) _then) = _$DailyStatsCopyWithImpl;
@useResult
$Res call({
 DateTime date, int totalTasks, int completedTasks, int plannedTasks, int inProgressTasks, int missedTasks, int skippedTasks, int cancelledTasks, int rescheduledTasks, int plannedDurationMin, int actualDurationMin, int focusDurationMin, int? energyLevel, int? productivityRating, double? planningAccuracyPct, DateTime computedAt
});




}
/// @nodoc
class _$DailyStatsCopyWithImpl<$Res>
    implements $DailyStatsCopyWith<$Res> {
  _$DailyStatsCopyWithImpl(this._self, this._then);

  final DailyStats _self;
  final $Res Function(DailyStats) _then;

/// Create a copy of DailyStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? date = null,Object? totalTasks = null,Object? completedTasks = null,Object? plannedTasks = null,Object? inProgressTasks = null,Object? missedTasks = null,Object? skippedTasks = null,Object? cancelledTasks = null,Object? rescheduledTasks = null,Object? plannedDurationMin = null,Object? actualDurationMin = null,Object? focusDurationMin = null,Object? energyLevel = freezed,Object? productivityRating = freezed,Object? planningAccuracyPct = freezed,Object? computedAt = null,}) {
  return _then(_self.copyWith(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,totalTasks: null == totalTasks ? _self.totalTasks : totalTasks // ignore: cast_nullable_to_non_nullable
as int,completedTasks: null == completedTasks ? _self.completedTasks : completedTasks // ignore: cast_nullable_to_non_nullable
as int,plannedTasks: null == plannedTasks ? _self.plannedTasks : plannedTasks // ignore: cast_nullable_to_non_nullable
as int,inProgressTasks: null == inProgressTasks ? _self.inProgressTasks : inProgressTasks // ignore: cast_nullable_to_non_nullable
as int,missedTasks: null == missedTasks ? _self.missedTasks : missedTasks // ignore: cast_nullable_to_non_nullable
as int,skippedTasks: null == skippedTasks ? _self.skippedTasks : skippedTasks // ignore: cast_nullable_to_non_nullable
as int,cancelledTasks: null == cancelledTasks ? _self.cancelledTasks : cancelledTasks // ignore: cast_nullable_to_non_nullable
as int,rescheduledTasks: null == rescheduledTasks ? _self.rescheduledTasks : rescheduledTasks // ignore: cast_nullable_to_non_nullable
as int,plannedDurationMin: null == plannedDurationMin ? _self.plannedDurationMin : plannedDurationMin // ignore: cast_nullable_to_non_nullable
as int,actualDurationMin: null == actualDurationMin ? _self.actualDurationMin : actualDurationMin // ignore: cast_nullable_to_non_nullable
as int,focusDurationMin: null == focusDurationMin ? _self.focusDurationMin : focusDurationMin // ignore: cast_nullable_to_non_nullable
as int,energyLevel: freezed == energyLevel ? _self.energyLevel : energyLevel // ignore: cast_nullable_to_non_nullable
as int?,productivityRating: freezed == productivityRating ? _self.productivityRating : productivityRating // ignore: cast_nullable_to_non_nullable
as int?,planningAccuracyPct: freezed == planningAccuracyPct ? _self.planningAccuracyPct : planningAccuracyPct // ignore: cast_nullable_to_non_nullable
as double?,computedAt: null == computedAt ? _self.computedAt : computedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [DailyStats].
extension DailyStatsPatterns on DailyStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DailyStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DailyStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DailyStats value)  $default,){
final _that = this;
switch (_that) {
case _DailyStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DailyStats value)?  $default,){
final _that = this;
switch (_that) {
case _DailyStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime date,  int totalTasks,  int completedTasks,  int plannedTasks,  int inProgressTasks,  int missedTasks,  int skippedTasks,  int cancelledTasks,  int rescheduledTasks,  int plannedDurationMin,  int actualDurationMin,  int focusDurationMin,  int? energyLevel,  int? productivityRating,  double? planningAccuracyPct,  DateTime computedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DailyStats() when $default != null:
return $default(_that.date,_that.totalTasks,_that.completedTasks,_that.plannedTasks,_that.inProgressTasks,_that.missedTasks,_that.skippedTasks,_that.cancelledTasks,_that.rescheduledTasks,_that.plannedDurationMin,_that.actualDurationMin,_that.focusDurationMin,_that.energyLevel,_that.productivityRating,_that.planningAccuracyPct,_that.computedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime date,  int totalTasks,  int completedTasks,  int plannedTasks,  int inProgressTasks,  int missedTasks,  int skippedTasks,  int cancelledTasks,  int rescheduledTasks,  int plannedDurationMin,  int actualDurationMin,  int focusDurationMin,  int? energyLevel,  int? productivityRating,  double? planningAccuracyPct,  DateTime computedAt)  $default,) {final _that = this;
switch (_that) {
case _DailyStats():
return $default(_that.date,_that.totalTasks,_that.completedTasks,_that.plannedTasks,_that.inProgressTasks,_that.missedTasks,_that.skippedTasks,_that.cancelledTasks,_that.rescheduledTasks,_that.plannedDurationMin,_that.actualDurationMin,_that.focusDurationMin,_that.energyLevel,_that.productivityRating,_that.planningAccuracyPct,_that.computedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime date,  int totalTasks,  int completedTasks,  int plannedTasks,  int inProgressTasks,  int missedTasks,  int skippedTasks,  int cancelledTasks,  int rescheduledTasks,  int plannedDurationMin,  int actualDurationMin,  int focusDurationMin,  int? energyLevel,  int? productivityRating,  double? planningAccuracyPct,  DateTime computedAt)?  $default,) {final _that = this;
switch (_that) {
case _DailyStats() when $default != null:
return $default(_that.date,_that.totalTasks,_that.completedTasks,_that.plannedTasks,_that.inProgressTasks,_that.missedTasks,_that.skippedTasks,_that.cancelledTasks,_that.rescheduledTasks,_that.plannedDurationMin,_that.actualDurationMin,_that.focusDurationMin,_that.energyLevel,_that.productivityRating,_that.planningAccuracyPct,_that.computedAt);case _:
  return null;

}
}

}

/// @nodoc


class _DailyStats implements DailyStats {
  const _DailyStats({required this.date, this.totalTasks = 0, this.completedTasks = 0, this.plannedTasks = 0, this.inProgressTasks = 0, this.missedTasks = 0, this.skippedTasks = 0, this.cancelledTasks = 0, this.rescheduledTasks = 0, this.plannedDurationMin = 0, this.actualDurationMin = 0, this.focusDurationMin = 0, this.energyLevel, this.productivityRating, this.planningAccuracyPct, required this.computedAt});


@override final  DateTime date;
@override@JsonKey() final  int totalTasks;
@override@JsonKey() final  int completedTasks;
@override@JsonKey() final  int plannedTasks;
@override@JsonKey() final  int inProgressTasks;
@override@JsonKey() final  int missedTasks;
@override@JsonKey() final  int skippedTasks;
@override@JsonKey() final  int cancelledTasks;
@override@JsonKey() final  int rescheduledTasks;
@override@JsonKey() final  int plannedDurationMin;
@override@JsonKey() final  int actualDurationMin;
@override@JsonKey() final  int focusDurationMin;
@override final  int? energyLevel;
@override final  int? productivityRating;
@override final  double? planningAccuracyPct;
@override final  DateTime computedAt;

/// Create a copy of DailyStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DailyStatsCopyWith<_DailyStats> get copyWith => __$DailyStatsCopyWithImpl<_DailyStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DailyStats&&(identical(other.date, date) || other.date == date)&&(identical(other.totalTasks, totalTasks) || other.totalTasks == totalTasks)&&(identical(other.completedTasks, completedTasks) || other.completedTasks == completedTasks)&&(identical(other.plannedTasks, plannedTasks) || other.plannedTasks == plannedTasks)&&(identical(other.inProgressTasks, inProgressTasks) || other.inProgressTasks == inProgressTasks)&&(identical(other.missedTasks, missedTasks) || other.missedTasks == missedTasks)&&(identical(other.skippedTasks, skippedTasks) || other.skippedTasks == skippedTasks)&&(identical(other.cancelledTasks, cancelledTasks) || other.cancelledTasks == cancelledTasks)&&(identical(other.rescheduledTasks, rescheduledTasks) || other.rescheduledTasks == rescheduledTasks)&&(identical(other.plannedDurationMin, plannedDurationMin) || other.plannedDurationMin == plannedDurationMin)&&(identical(other.actualDurationMin, actualDurationMin) || other.actualDurationMin == actualDurationMin)&&(identical(other.focusDurationMin, focusDurationMin) || other.focusDurationMin == focusDurationMin)&&(identical(other.energyLevel, energyLevel) || other.energyLevel == energyLevel)&&(identical(other.productivityRating, productivityRating) || other.productivityRating == productivityRating)&&(identical(other.planningAccuracyPct, planningAccuracyPct) || other.planningAccuracyPct == planningAccuracyPct)&&(identical(other.computedAt, computedAt) || other.computedAt == computedAt));
}


@override
int get hashCode => Object.hash(runtimeType,date,totalTasks,completedTasks,plannedTasks,inProgressTasks,missedTasks,skippedTasks,cancelledTasks,rescheduledTasks,plannedDurationMin,actualDurationMin,focusDurationMin,energyLevel,productivityRating,planningAccuracyPct,computedAt);

@override
String toString() {
  return 'DailyStats(date: $date, totalTasks: $totalTasks, completedTasks: $completedTasks, plannedTasks: $plannedTasks, inProgressTasks: $inProgressTasks, missedTasks: $missedTasks, skippedTasks: $skippedTasks, cancelledTasks: $cancelledTasks, rescheduledTasks: $rescheduledTasks, plannedDurationMin: $plannedDurationMin, actualDurationMin: $actualDurationMin, focusDurationMin: $focusDurationMin, energyLevel: $energyLevel, productivityRating: $productivityRating, planningAccuracyPct: $planningAccuracyPct, computedAt: $computedAt)';
}


}

/// @nodoc
abstract mixin class _$DailyStatsCopyWith<$Res> implements $DailyStatsCopyWith<$Res> {
  factory _$DailyStatsCopyWith(_DailyStats value, $Res Function(_DailyStats) _then) = __$DailyStatsCopyWithImpl;
@override @useResult
$Res call({
 DateTime date, int totalTasks, int completedTasks, int plannedTasks, int inProgressTasks, int missedTasks, int skippedTasks, int cancelledTasks, int rescheduledTasks, int plannedDurationMin, int actualDurationMin, int focusDurationMin, int? energyLevel, int? productivityRating, double? planningAccuracyPct, DateTime computedAt
});




}
/// @nodoc
class __$DailyStatsCopyWithImpl<$Res>
    implements _$DailyStatsCopyWith<$Res> {
  __$DailyStatsCopyWithImpl(this._self, this._then);

  final _DailyStats _self;
  final $Res Function(_DailyStats) _then;

/// Create a copy of DailyStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? date = null,Object? totalTasks = null,Object? completedTasks = null,Object? plannedTasks = null,Object? inProgressTasks = null,Object? missedTasks = null,Object? skippedTasks = null,Object? cancelledTasks = null,Object? rescheduledTasks = null,Object? plannedDurationMin = null,Object? actualDurationMin = null,Object? focusDurationMin = null,Object? energyLevel = freezed,Object? productivityRating = freezed,Object? planningAccuracyPct = freezed,Object? computedAt = null,}) {
  return _then(_DailyStats(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,totalTasks: null == totalTasks ? _self.totalTasks : totalTasks // ignore: cast_nullable_to_non_nullable
as int,completedTasks: null == completedTasks ? _self.completedTasks : completedTasks // ignore: cast_nullable_to_non_nullable
as int,plannedTasks: null == plannedTasks ? _self.plannedTasks : plannedTasks // ignore: cast_nullable_to_non_nullable
as int,inProgressTasks: null == inProgressTasks ? _self.inProgressTasks : inProgressTasks // ignore: cast_nullable_to_non_nullable
as int,missedTasks: null == missedTasks ? _self.missedTasks : missedTasks // ignore: cast_nullable_to_non_nullable
as int,skippedTasks: null == skippedTasks ? _self.skippedTasks : skippedTasks // ignore: cast_nullable_to_non_nullable
as int,cancelledTasks: null == cancelledTasks ? _self.cancelledTasks : cancelledTasks // ignore: cast_nullable_to_non_nullable
as int,rescheduledTasks: null == rescheduledTasks ? _self.rescheduledTasks : rescheduledTasks // ignore: cast_nullable_to_non_nullable
as int,plannedDurationMin: null == plannedDurationMin ? _self.plannedDurationMin : plannedDurationMin // ignore: cast_nullable_to_non_nullable
as int,actualDurationMin: null == actualDurationMin ? _self.actualDurationMin : actualDurationMin // ignore: cast_nullable_to_non_nullable
as int,focusDurationMin: null == focusDurationMin ? _self.focusDurationMin : focusDurationMin // ignore: cast_nullable_to_non_nullable
as int,energyLevel: freezed == energyLevel ? _self.energyLevel : energyLevel // ignore: cast_nullable_to_non_nullable
as int?,productivityRating: freezed == productivityRating ? _self.productivityRating : productivityRating // ignore: cast_nullable_to_non_nullable
as int?,planningAccuracyPct: freezed == planningAccuracyPct ? _self.planningAccuracyPct : planningAccuracyPct // ignore: cast_nullable_to_non_nullable
as double?,computedAt: null == computedAt ? _self.computedAt : computedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
