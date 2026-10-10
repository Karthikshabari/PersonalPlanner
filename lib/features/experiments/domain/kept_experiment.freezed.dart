// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kept_experiment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$KeptWeekBar {

 String get weekStart; String get label; int get doneMin; int get targetMin; int get heightPercent; int? get percent; bool get isCurrent; int? get targetThenMin; String get semanticsLabel;
/// Create a copy of KeptWeekBar
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeptWeekBarCopyWith<KeptWeekBar> get copyWith => _$KeptWeekBarCopyWithImpl<KeptWeekBar>(this as KeptWeekBar, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeptWeekBar&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.label, label) || other.label == label)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.targetMin, targetMin) || other.targetMin == targetMin)&&(identical(other.heightPercent, heightPercent) || other.heightPercent == heightPercent)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.isCurrent, isCurrent) || other.isCurrent == isCurrent)&&(identical(other.targetThenMin, targetThenMin) || other.targetThenMin == targetThenMin)&&(identical(other.semanticsLabel, semanticsLabel) || other.semanticsLabel == semanticsLabel));
}


@override
int get hashCode => Object.hash(runtimeType,weekStart,label,doneMin,targetMin,heightPercent,percent,isCurrent,targetThenMin,semanticsLabel);

@override
String toString() {
  return 'KeptWeekBar(weekStart: $weekStart, label: $label, doneMin: $doneMin, targetMin: $targetMin, heightPercent: $heightPercent, percent: $percent, isCurrent: $isCurrent, targetThenMin: $targetThenMin, semanticsLabel: $semanticsLabel)';
}


}

/// @nodoc
abstract mixin class $KeptWeekBarCopyWith<$Res>  {
  factory $KeptWeekBarCopyWith(KeptWeekBar value, $Res Function(KeptWeekBar) _then) = _$KeptWeekBarCopyWithImpl;
@useResult
$Res call({
 String weekStart, String label, int doneMin, int targetMin, int heightPercent, int? percent, bool isCurrent, int? targetThenMin, String semanticsLabel
});




}
/// @nodoc
class _$KeptWeekBarCopyWithImpl<$Res>
    implements $KeptWeekBarCopyWith<$Res> {
  _$KeptWeekBarCopyWithImpl(this._self, this._then);

  final KeptWeekBar _self;
  final $Res Function(KeptWeekBar) _then;

/// Create a copy of KeptWeekBar
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? weekStart = null,Object? label = null,Object? doneMin = null,Object? targetMin = null,Object? heightPercent = null,Object? percent = freezed,Object? isCurrent = null,Object? targetThenMin = freezed,Object? semanticsLabel = null,}) {
  return _then(_self.copyWith(
weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,targetMin: null == targetMin ? _self.targetMin : targetMin // ignore: cast_nullable_to_non_nullable
as int,heightPercent: null == heightPercent ? _self.heightPercent : heightPercent // ignore: cast_nullable_to_non_nullable
as int,percent: freezed == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as int?,isCurrent: null == isCurrent ? _self.isCurrent : isCurrent // ignore: cast_nullable_to_non_nullable
as bool,targetThenMin: freezed == targetThenMin ? _self.targetThenMin : targetThenMin // ignore: cast_nullable_to_non_nullable
as int?,semanticsLabel: null == semanticsLabel ? _self.semanticsLabel : semanticsLabel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [KeptWeekBar].
extension KeptWeekBarPatterns on KeptWeekBar {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeptWeekBar value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeptWeekBar() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeptWeekBar value)  $default,){
final _that = this;
switch (_that) {
case _KeptWeekBar():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeptWeekBar value)?  $default,){
final _that = this;
switch (_that) {
case _KeptWeekBar() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String weekStart,  String label,  int doneMin,  int targetMin,  int heightPercent,  int? percent,  bool isCurrent,  int? targetThenMin,  String semanticsLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeptWeekBar() when $default != null:
return $default(_that.weekStart,_that.label,_that.doneMin,_that.targetMin,_that.heightPercent,_that.percent,_that.isCurrent,_that.targetThenMin,_that.semanticsLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String weekStart,  String label,  int doneMin,  int targetMin,  int heightPercent,  int? percent,  bool isCurrent,  int? targetThenMin,  String semanticsLabel)  $default,) {final _that = this;
switch (_that) {
case _KeptWeekBar():
return $default(_that.weekStart,_that.label,_that.doneMin,_that.targetMin,_that.heightPercent,_that.percent,_that.isCurrent,_that.targetThenMin,_that.semanticsLabel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String weekStart,  String label,  int doneMin,  int targetMin,  int heightPercent,  int? percent,  bool isCurrent,  int? targetThenMin,  String semanticsLabel)?  $default,) {final _that = this;
switch (_that) {
case _KeptWeekBar() when $default != null:
return $default(_that.weekStart,_that.label,_that.doneMin,_that.targetMin,_that.heightPercent,_that.percent,_that.isCurrent,_that.targetThenMin,_that.semanticsLabel);case _:
  return null;

}
}

}

/// @nodoc


class _KeptWeekBar implements KeptWeekBar {
  const _KeptWeekBar({required this.weekStart, required this.label, required this.doneMin, required this.targetMin, required this.heightPercent, this.percent, required this.isCurrent, this.targetThenMin, required this.semanticsLabel});
  

@override final  String weekStart;
@override final  String label;
@override final  int doneMin;
@override final  int targetMin;
@override final  int heightPercent;
@override final  int? percent;
@override final  bool isCurrent;
@override final  int? targetThenMin;
@override final  String semanticsLabel;

/// Create a copy of KeptWeekBar
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeptWeekBarCopyWith<_KeptWeekBar> get copyWith => __$KeptWeekBarCopyWithImpl<_KeptWeekBar>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeptWeekBar&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.label, label) || other.label == label)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.targetMin, targetMin) || other.targetMin == targetMin)&&(identical(other.heightPercent, heightPercent) || other.heightPercent == heightPercent)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.isCurrent, isCurrent) || other.isCurrent == isCurrent)&&(identical(other.targetThenMin, targetThenMin) || other.targetThenMin == targetThenMin)&&(identical(other.semanticsLabel, semanticsLabel) || other.semanticsLabel == semanticsLabel));
}


@override
int get hashCode => Object.hash(runtimeType,weekStart,label,doneMin,targetMin,heightPercent,percent,isCurrent,targetThenMin,semanticsLabel);

@override
String toString() {
  return 'KeptWeekBar(weekStart: $weekStart, label: $label, doneMin: $doneMin, targetMin: $targetMin, heightPercent: $heightPercent, percent: $percent, isCurrent: $isCurrent, targetThenMin: $targetThenMin, semanticsLabel: $semanticsLabel)';
}


}

/// @nodoc
abstract mixin class _$KeptWeekBarCopyWith<$Res> implements $KeptWeekBarCopyWith<$Res> {
  factory _$KeptWeekBarCopyWith(_KeptWeekBar value, $Res Function(_KeptWeekBar) _then) = __$KeptWeekBarCopyWithImpl;
@override @useResult
$Res call({
 String weekStart, String label, int doneMin, int targetMin, int heightPercent, int? percent, bool isCurrent, int? targetThenMin, String semanticsLabel
});




}
/// @nodoc
class __$KeptWeekBarCopyWithImpl<$Res>
    implements _$KeptWeekBarCopyWith<$Res> {
  __$KeptWeekBarCopyWithImpl(this._self, this._then);

  final _KeptWeekBar _self;
  final $Res Function(_KeptWeekBar) _then;

/// Create a copy of KeptWeekBar
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? weekStart = null,Object? label = null,Object? doneMin = null,Object? targetMin = null,Object? heightPercent = null,Object? percent = freezed,Object? isCurrent = null,Object? targetThenMin = freezed,Object? semanticsLabel = null,}) {
  return _then(_KeptWeekBar(
weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,targetMin: null == targetMin ? _self.targetMin : targetMin // ignore: cast_nullable_to_non_nullable
as int,heightPercent: null == heightPercent ? _self.heightPercent : heightPercent // ignore: cast_nullable_to_non_nullable
as int,percent: freezed == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as int?,isCurrent: null == isCurrent ? _self.isCurrent : isCurrent // ignore: cast_nullable_to_non_nullable
as bool,targetThenMin: freezed == targetThenMin ? _self.targetThenMin : targetThenMin // ignore: cast_nullable_to_non_nullable
as int?,semanticsLabel: null == semanticsLabel ? _self.semanticsLabel : semanticsLabel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$KeptDayColumn {

 String get date; String get dayName; int get doneMin; double get fillFraction; bool get isToday; String get valueLabel; bool get dim;
/// Create a copy of KeptDayColumn
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeptDayColumnCopyWith<KeptDayColumn> get copyWith => _$KeptDayColumnCopyWithImpl<KeptDayColumn>(this as KeptDayColumn, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeptDayColumn&&(identical(other.date, date) || other.date == date)&&(identical(other.dayName, dayName) || other.dayName == dayName)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.fillFraction, fillFraction) || other.fillFraction == fillFraction)&&(identical(other.isToday, isToday) || other.isToday == isToday)&&(identical(other.valueLabel, valueLabel) || other.valueLabel == valueLabel)&&(identical(other.dim, dim) || other.dim == dim));
}


@override
int get hashCode => Object.hash(runtimeType,date,dayName,doneMin,fillFraction,isToday,valueLabel,dim);

@override
String toString() {
  return 'KeptDayColumn(date: $date, dayName: $dayName, doneMin: $doneMin, fillFraction: $fillFraction, isToday: $isToday, valueLabel: $valueLabel, dim: $dim)';
}


}

/// @nodoc
abstract mixin class $KeptDayColumnCopyWith<$Res>  {
  factory $KeptDayColumnCopyWith(KeptDayColumn value, $Res Function(KeptDayColumn) _then) = _$KeptDayColumnCopyWithImpl;
@useResult
$Res call({
 String date, String dayName, int doneMin, double fillFraction, bool isToday, String valueLabel, bool dim
});




}
/// @nodoc
class _$KeptDayColumnCopyWithImpl<$Res>
    implements $KeptDayColumnCopyWith<$Res> {
  _$KeptDayColumnCopyWithImpl(this._self, this._then);

  final KeptDayColumn _self;
  final $Res Function(KeptDayColumn) _then;

/// Create a copy of KeptDayColumn
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? date = null,Object? dayName = null,Object? doneMin = null,Object? fillFraction = null,Object? isToday = null,Object? valueLabel = null,Object? dim = null,}) {
  return _then(_self.copyWith(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,dayName: null == dayName ? _self.dayName : dayName // ignore: cast_nullable_to_non_nullable
as String,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,fillFraction: null == fillFraction ? _self.fillFraction : fillFraction // ignore: cast_nullable_to_non_nullable
as double,isToday: null == isToday ? _self.isToday : isToday // ignore: cast_nullable_to_non_nullable
as bool,valueLabel: null == valueLabel ? _self.valueLabel : valueLabel // ignore: cast_nullable_to_non_nullable
as String,dim: null == dim ? _self.dim : dim // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [KeptDayColumn].
extension KeptDayColumnPatterns on KeptDayColumn {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeptDayColumn value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeptDayColumn() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeptDayColumn value)  $default,){
final _that = this;
switch (_that) {
case _KeptDayColumn():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeptDayColumn value)?  $default,){
final _that = this;
switch (_that) {
case _KeptDayColumn() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String date,  String dayName,  int doneMin,  double fillFraction,  bool isToday,  String valueLabel,  bool dim)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeptDayColumn() when $default != null:
return $default(_that.date,_that.dayName,_that.doneMin,_that.fillFraction,_that.isToday,_that.valueLabel,_that.dim);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String date,  String dayName,  int doneMin,  double fillFraction,  bool isToday,  String valueLabel,  bool dim)  $default,) {final _that = this;
switch (_that) {
case _KeptDayColumn():
return $default(_that.date,_that.dayName,_that.doneMin,_that.fillFraction,_that.isToday,_that.valueLabel,_that.dim);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String date,  String dayName,  int doneMin,  double fillFraction,  bool isToday,  String valueLabel,  bool dim)?  $default,) {final _that = this;
switch (_that) {
case _KeptDayColumn() when $default != null:
return $default(_that.date,_that.dayName,_that.doneMin,_that.fillFraction,_that.isToday,_that.valueLabel,_that.dim);case _:
  return null;

}
}

}

/// @nodoc


class _KeptDayColumn implements KeptDayColumn {
  const _KeptDayColumn({required this.date, required this.dayName, required this.doneMin, required this.fillFraction, required this.isToday, required this.valueLabel, required this.dim});
  

@override final  String date;
@override final  String dayName;
@override final  int doneMin;
@override final  double fillFraction;
@override final  bool isToday;
@override final  String valueLabel;
@override final  bool dim;

/// Create a copy of KeptDayColumn
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeptDayColumnCopyWith<_KeptDayColumn> get copyWith => __$KeptDayColumnCopyWithImpl<_KeptDayColumn>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeptDayColumn&&(identical(other.date, date) || other.date == date)&&(identical(other.dayName, dayName) || other.dayName == dayName)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.fillFraction, fillFraction) || other.fillFraction == fillFraction)&&(identical(other.isToday, isToday) || other.isToday == isToday)&&(identical(other.valueLabel, valueLabel) || other.valueLabel == valueLabel)&&(identical(other.dim, dim) || other.dim == dim));
}


@override
int get hashCode => Object.hash(runtimeType,date,dayName,doneMin,fillFraction,isToday,valueLabel,dim);

@override
String toString() {
  return 'KeptDayColumn(date: $date, dayName: $dayName, doneMin: $doneMin, fillFraction: $fillFraction, isToday: $isToday, valueLabel: $valueLabel, dim: $dim)';
}


}

/// @nodoc
abstract mixin class _$KeptDayColumnCopyWith<$Res> implements $KeptDayColumnCopyWith<$Res> {
  factory _$KeptDayColumnCopyWith(_KeptDayColumn value, $Res Function(_KeptDayColumn) _then) = __$KeptDayColumnCopyWithImpl;
@override @useResult
$Res call({
 String date, String dayName, int doneMin, double fillFraction, bool isToday, String valueLabel, bool dim
});




}
/// @nodoc
class __$KeptDayColumnCopyWithImpl<$Res>
    implements _$KeptDayColumnCopyWith<$Res> {
  __$KeptDayColumnCopyWithImpl(this._self, this._then);

  final _KeptDayColumn _self;
  final $Res Function(_KeptDayColumn) _then;

/// Create a copy of KeptDayColumn
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? date = null,Object? dayName = null,Object? doneMin = null,Object? fillFraction = null,Object? isToday = null,Object? valueLabel = null,Object? dim = null,}) {
  return _then(_KeptDayColumn(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,dayName: null == dayName ? _self.dayName : dayName // ignore: cast_nullable_to_non_nullable
as String,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,fillFraction: null == fillFraction ? _self.fillFraction : fillFraction // ignore: cast_nullable_to_non_nullable
as double,isToday: null == isToday ? _self.isToday : isToday // ignore: cast_nullable_to_non_nullable
as bool,valueLabel: null == valueLabel ? _self.valueLabel : valueLabel // ignore: cast_nullable_to_non_nullable
as String,dim: null == dim ? _self.dim : dim // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$KeptExperimentView {

 String get experimentId; String get name; int get revision;/// `yyyy-MM-dd`: the day the experiment was concluded with Keep it.
 String get keptSince; String get subtitle; String? get why;/// The planner date the numbers were computed for.
 String get today; String get weekStart; String get nextWeekStart; int get weekdayTargetMin; int get weekendTargetMin; int get weekdayCount; int get weekendCount; int get targetMin; int get doneMin; int get plannedMin; int get expectedMin; int get paceMin; String get chipText; KeptTone get chipTone; KeptPlanState get planState; int get remainingMin; int get shortMin; double get doneFraction; double get plannedEndFraction; double get tickFraction; ExperimentTargetChange? get pendingChange; List<KeptWeekBar> get bars; String get axisStartLabel; List<KeptDayColumn> get days;
/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeptExperimentViewCopyWith<KeptExperimentView> get copyWith => _$KeptExperimentViewCopyWithImpl<KeptExperimentView>(this as KeptExperimentView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeptExperimentView&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.name, name) || other.name == name)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.keptSince, keptSince) || other.keptSince == keptSince)&&(identical(other.subtitle, subtitle) || other.subtitle == subtitle)&&(identical(other.why, why) || other.why == why)&&(identical(other.today, today) || other.today == today)&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.nextWeekStart, nextWeekStart) || other.nextWeekStart == nextWeekStart)&&(identical(other.weekdayTargetMin, weekdayTargetMin) || other.weekdayTargetMin == weekdayTargetMin)&&(identical(other.weekendTargetMin, weekendTargetMin) || other.weekendTargetMin == weekendTargetMin)&&(identical(other.weekdayCount, weekdayCount) || other.weekdayCount == weekdayCount)&&(identical(other.weekendCount, weekendCount) || other.weekendCount == weekendCount)&&(identical(other.targetMin, targetMin) || other.targetMin == targetMin)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.plannedMin, plannedMin) || other.plannedMin == plannedMin)&&(identical(other.expectedMin, expectedMin) || other.expectedMin == expectedMin)&&(identical(other.paceMin, paceMin) || other.paceMin == paceMin)&&(identical(other.chipText, chipText) || other.chipText == chipText)&&(identical(other.chipTone, chipTone) || other.chipTone == chipTone)&&(identical(other.planState, planState) || other.planState == planState)&&(identical(other.remainingMin, remainingMin) || other.remainingMin == remainingMin)&&(identical(other.shortMin, shortMin) || other.shortMin == shortMin)&&(identical(other.doneFraction, doneFraction) || other.doneFraction == doneFraction)&&(identical(other.plannedEndFraction, plannedEndFraction) || other.plannedEndFraction == plannedEndFraction)&&(identical(other.tickFraction, tickFraction) || other.tickFraction == tickFraction)&&(identical(other.pendingChange, pendingChange) || other.pendingChange == pendingChange)&&const DeepCollectionEquality().equals(other.bars, bars)&&(identical(other.axisStartLabel, axisStartLabel) || other.axisStartLabel == axisStartLabel)&&const DeepCollectionEquality().equals(other.days, days));
}


@override
int get hashCode => Object.hashAll([runtimeType,experimentId,name,revision,keptSince,subtitle,why,today,weekStart,nextWeekStart,weekdayTargetMin,weekendTargetMin,weekdayCount,weekendCount,targetMin,doneMin,plannedMin,expectedMin,paceMin,chipText,chipTone,planState,remainingMin,shortMin,doneFraction,plannedEndFraction,tickFraction,pendingChange,const DeepCollectionEquality().hash(bars),axisStartLabel,const DeepCollectionEquality().hash(days)]);

@override
String toString() {
  return 'KeptExperimentView(experimentId: $experimentId, name: $name, revision: $revision, keptSince: $keptSince, subtitle: $subtitle, why: $why, today: $today, weekStart: $weekStart, nextWeekStart: $nextWeekStart, weekdayTargetMin: $weekdayTargetMin, weekendTargetMin: $weekendTargetMin, weekdayCount: $weekdayCount, weekendCount: $weekendCount, targetMin: $targetMin, doneMin: $doneMin, plannedMin: $plannedMin, expectedMin: $expectedMin, paceMin: $paceMin, chipText: $chipText, chipTone: $chipTone, planState: $planState, remainingMin: $remainingMin, shortMin: $shortMin, doneFraction: $doneFraction, plannedEndFraction: $plannedEndFraction, tickFraction: $tickFraction, pendingChange: $pendingChange, bars: $bars, axisStartLabel: $axisStartLabel, days: $days)';
}


}

/// @nodoc
abstract mixin class $KeptExperimentViewCopyWith<$Res>  {
  factory $KeptExperimentViewCopyWith(KeptExperimentView value, $Res Function(KeptExperimentView) _then) = _$KeptExperimentViewCopyWithImpl;
@useResult
$Res call({
 String experimentId, String name, int revision, String keptSince, String subtitle, String? why, String today, String weekStart, String nextWeekStart, int weekdayTargetMin, int weekendTargetMin, int weekdayCount, int weekendCount, int targetMin, int doneMin, int plannedMin, int expectedMin, int paceMin, String chipText, KeptTone chipTone, KeptPlanState planState, int remainingMin, int shortMin, double doneFraction, double plannedEndFraction, double tickFraction, ExperimentTargetChange? pendingChange, List<KeptWeekBar> bars, String axisStartLabel, List<KeptDayColumn> days
});


$ExperimentTargetChangeCopyWith<$Res>? get pendingChange;

}
/// @nodoc
class _$KeptExperimentViewCopyWithImpl<$Res>
    implements $KeptExperimentViewCopyWith<$Res> {
  _$KeptExperimentViewCopyWithImpl(this._self, this._then);

  final KeptExperimentView _self;
  final $Res Function(KeptExperimentView) _then;

/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? experimentId = null,Object? name = null,Object? revision = null,Object? keptSince = null,Object? subtitle = null,Object? why = freezed,Object? today = null,Object? weekStart = null,Object? nextWeekStart = null,Object? weekdayTargetMin = null,Object? weekendTargetMin = null,Object? weekdayCount = null,Object? weekendCount = null,Object? targetMin = null,Object? doneMin = null,Object? plannedMin = null,Object? expectedMin = null,Object? paceMin = null,Object? chipText = null,Object? chipTone = null,Object? planState = null,Object? remainingMin = null,Object? shortMin = null,Object? doneFraction = null,Object? plannedEndFraction = null,Object? tickFraction = null,Object? pendingChange = freezed,Object? bars = null,Object? axisStartLabel = null,Object? days = null,}) {
  return _then(_self.copyWith(
experimentId: null == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,keptSince: null == keptSince ? _self.keptSince : keptSince // ignore: cast_nullable_to_non_nullable
as String,subtitle: null == subtitle ? _self.subtitle : subtitle // ignore: cast_nullable_to_non_nullable
as String,why: freezed == why ? _self.why : why // ignore: cast_nullable_to_non_nullable
as String?,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as String,weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as String,nextWeekStart: null == nextWeekStart ? _self.nextWeekStart : nextWeekStart // ignore: cast_nullable_to_non_nullable
as String,weekdayTargetMin: null == weekdayTargetMin ? _self.weekdayTargetMin : weekdayTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekendTargetMin: null == weekendTargetMin ? _self.weekendTargetMin : weekendTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekdayCount: null == weekdayCount ? _self.weekdayCount : weekdayCount // ignore: cast_nullable_to_non_nullable
as int,weekendCount: null == weekendCount ? _self.weekendCount : weekendCount // ignore: cast_nullable_to_non_nullable
as int,targetMin: null == targetMin ? _self.targetMin : targetMin // ignore: cast_nullable_to_non_nullable
as int,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,plannedMin: null == plannedMin ? _self.plannedMin : plannedMin // ignore: cast_nullable_to_non_nullable
as int,expectedMin: null == expectedMin ? _self.expectedMin : expectedMin // ignore: cast_nullable_to_non_nullable
as int,paceMin: null == paceMin ? _self.paceMin : paceMin // ignore: cast_nullable_to_non_nullable
as int,chipText: null == chipText ? _self.chipText : chipText // ignore: cast_nullable_to_non_nullable
as String,chipTone: null == chipTone ? _self.chipTone : chipTone // ignore: cast_nullable_to_non_nullable
as KeptTone,planState: null == planState ? _self.planState : planState // ignore: cast_nullable_to_non_nullable
as KeptPlanState,remainingMin: null == remainingMin ? _self.remainingMin : remainingMin // ignore: cast_nullable_to_non_nullable
as int,shortMin: null == shortMin ? _self.shortMin : shortMin // ignore: cast_nullable_to_non_nullable
as int,doneFraction: null == doneFraction ? _self.doneFraction : doneFraction // ignore: cast_nullable_to_non_nullable
as double,plannedEndFraction: null == plannedEndFraction ? _self.plannedEndFraction : plannedEndFraction // ignore: cast_nullable_to_non_nullable
as double,tickFraction: null == tickFraction ? _self.tickFraction : tickFraction // ignore: cast_nullable_to_non_nullable
as double,pendingChange: freezed == pendingChange ? _self.pendingChange : pendingChange // ignore: cast_nullable_to_non_nullable
as ExperimentTargetChange?,bars: null == bars ? _self.bars : bars // ignore: cast_nullable_to_non_nullable
as List<KeptWeekBar>,axisStartLabel: null == axisStartLabel ? _self.axisStartLabel : axisStartLabel // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<KeptDayColumn>,
  ));
}
/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExperimentTargetChangeCopyWith<$Res>? get pendingChange {
    if (_self.pendingChange == null) {
    return null;
  }

  return $ExperimentTargetChangeCopyWith<$Res>(_self.pendingChange!, (value) {
    return _then(_self.copyWith(pendingChange: value));
  });
}
}


/// Adds pattern-matching-related methods to [KeptExperimentView].
extension KeptExperimentViewPatterns on KeptExperimentView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeptExperimentView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeptExperimentView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeptExperimentView value)  $default,){
final _that = this;
switch (_that) {
case _KeptExperimentView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeptExperimentView value)?  $default,){
final _that = this;
switch (_that) {
case _KeptExperimentView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String experimentId,  String name,  int revision,  String keptSince,  String subtitle,  String? why,  String today,  String weekStart,  String nextWeekStart,  int weekdayTargetMin,  int weekendTargetMin,  int weekdayCount,  int weekendCount,  int targetMin,  int doneMin,  int plannedMin,  int expectedMin,  int paceMin,  String chipText,  KeptTone chipTone,  KeptPlanState planState,  int remainingMin,  int shortMin,  double doneFraction,  double plannedEndFraction,  double tickFraction,  ExperimentTargetChange? pendingChange,  List<KeptWeekBar> bars,  String axisStartLabel,  List<KeptDayColumn> days)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeptExperimentView() when $default != null:
return $default(_that.experimentId,_that.name,_that.revision,_that.keptSince,_that.subtitle,_that.why,_that.today,_that.weekStart,_that.nextWeekStart,_that.weekdayTargetMin,_that.weekendTargetMin,_that.weekdayCount,_that.weekendCount,_that.targetMin,_that.doneMin,_that.plannedMin,_that.expectedMin,_that.paceMin,_that.chipText,_that.chipTone,_that.planState,_that.remainingMin,_that.shortMin,_that.doneFraction,_that.plannedEndFraction,_that.tickFraction,_that.pendingChange,_that.bars,_that.axisStartLabel,_that.days);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String experimentId,  String name,  int revision,  String keptSince,  String subtitle,  String? why,  String today,  String weekStart,  String nextWeekStart,  int weekdayTargetMin,  int weekendTargetMin,  int weekdayCount,  int weekendCount,  int targetMin,  int doneMin,  int plannedMin,  int expectedMin,  int paceMin,  String chipText,  KeptTone chipTone,  KeptPlanState planState,  int remainingMin,  int shortMin,  double doneFraction,  double plannedEndFraction,  double tickFraction,  ExperimentTargetChange? pendingChange,  List<KeptWeekBar> bars,  String axisStartLabel,  List<KeptDayColumn> days)  $default,) {final _that = this;
switch (_that) {
case _KeptExperimentView():
return $default(_that.experimentId,_that.name,_that.revision,_that.keptSince,_that.subtitle,_that.why,_that.today,_that.weekStart,_that.nextWeekStart,_that.weekdayTargetMin,_that.weekendTargetMin,_that.weekdayCount,_that.weekendCount,_that.targetMin,_that.doneMin,_that.plannedMin,_that.expectedMin,_that.paceMin,_that.chipText,_that.chipTone,_that.planState,_that.remainingMin,_that.shortMin,_that.doneFraction,_that.plannedEndFraction,_that.tickFraction,_that.pendingChange,_that.bars,_that.axisStartLabel,_that.days);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String experimentId,  String name,  int revision,  String keptSince,  String subtitle,  String? why,  String today,  String weekStart,  String nextWeekStart,  int weekdayTargetMin,  int weekendTargetMin,  int weekdayCount,  int weekendCount,  int targetMin,  int doneMin,  int plannedMin,  int expectedMin,  int paceMin,  String chipText,  KeptTone chipTone,  KeptPlanState planState,  int remainingMin,  int shortMin,  double doneFraction,  double plannedEndFraction,  double tickFraction,  ExperimentTargetChange? pendingChange,  List<KeptWeekBar> bars,  String axisStartLabel,  List<KeptDayColumn> days)?  $default,) {final _that = this;
switch (_that) {
case _KeptExperimentView() when $default != null:
return $default(_that.experimentId,_that.name,_that.revision,_that.keptSince,_that.subtitle,_that.why,_that.today,_that.weekStart,_that.nextWeekStart,_that.weekdayTargetMin,_that.weekendTargetMin,_that.weekdayCount,_that.weekendCount,_that.targetMin,_that.doneMin,_that.plannedMin,_that.expectedMin,_that.paceMin,_that.chipText,_that.chipTone,_that.planState,_that.remainingMin,_that.shortMin,_that.doneFraction,_that.plannedEndFraction,_that.tickFraction,_that.pendingChange,_that.bars,_that.axisStartLabel,_that.days);case _:
  return null;

}
}

}

/// @nodoc


class _KeptExperimentView implements KeptExperimentView {
  const _KeptExperimentView({required this.experimentId, required this.name, required this.revision, required this.keptSince, required this.subtitle, this.why, required this.today, required this.weekStart, required this.nextWeekStart, required this.weekdayTargetMin, required this.weekendTargetMin, required this.weekdayCount, required this.weekendCount, required this.targetMin, required this.doneMin, required this.plannedMin, required this.expectedMin, required this.paceMin, required this.chipText, required this.chipTone, required this.planState, required this.remainingMin, required this.shortMin, required this.doneFraction, required this.plannedEndFraction, required this.tickFraction, this.pendingChange, required this.bars, required this.axisStartLabel, required this.days});
  

@override final  String experimentId;
@override final  String name;
@override final  int revision;
/// `yyyy-MM-dd`: the day the experiment was concluded with Keep it.
@override final  String keptSince;
@override final  String subtitle;
@override final  String? why;
/// The planner date the numbers were computed for.
@override final  String today;
@override final  String weekStart;
@override final  String nextWeekStart;
@override final  int weekdayTargetMin;
@override final  int weekendTargetMin;
@override final  int weekdayCount;
@override final  int weekendCount;
@override final  int targetMin;
@override final  int doneMin;
@override final  int plannedMin;
@override final  int expectedMin;
@override final  int paceMin;
@override final  String chipText;
@override final  KeptTone chipTone;
@override final  KeptPlanState planState;
@override final  int remainingMin;
@override final  int shortMin;
@override final  double doneFraction;
@override final  double plannedEndFraction;
@override final  double tickFraction;
@override final  ExperimentTargetChange? pendingChange;
@override final  List<KeptWeekBar> bars;
@override final  String axisStartLabel;
@override final  List<KeptDayColumn> days;

/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeptExperimentViewCopyWith<_KeptExperimentView> get copyWith => __$KeptExperimentViewCopyWithImpl<_KeptExperimentView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeptExperimentView&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.name, name) || other.name == name)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.keptSince, keptSince) || other.keptSince == keptSince)&&(identical(other.subtitle, subtitle) || other.subtitle == subtitle)&&(identical(other.why, why) || other.why == why)&&(identical(other.today, today) || other.today == today)&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.nextWeekStart, nextWeekStart) || other.nextWeekStart == nextWeekStart)&&(identical(other.weekdayTargetMin, weekdayTargetMin) || other.weekdayTargetMin == weekdayTargetMin)&&(identical(other.weekendTargetMin, weekendTargetMin) || other.weekendTargetMin == weekendTargetMin)&&(identical(other.weekdayCount, weekdayCount) || other.weekdayCount == weekdayCount)&&(identical(other.weekendCount, weekendCount) || other.weekendCount == weekendCount)&&(identical(other.targetMin, targetMin) || other.targetMin == targetMin)&&(identical(other.doneMin, doneMin) || other.doneMin == doneMin)&&(identical(other.plannedMin, plannedMin) || other.plannedMin == plannedMin)&&(identical(other.expectedMin, expectedMin) || other.expectedMin == expectedMin)&&(identical(other.paceMin, paceMin) || other.paceMin == paceMin)&&(identical(other.chipText, chipText) || other.chipText == chipText)&&(identical(other.chipTone, chipTone) || other.chipTone == chipTone)&&(identical(other.planState, planState) || other.planState == planState)&&(identical(other.remainingMin, remainingMin) || other.remainingMin == remainingMin)&&(identical(other.shortMin, shortMin) || other.shortMin == shortMin)&&(identical(other.doneFraction, doneFraction) || other.doneFraction == doneFraction)&&(identical(other.plannedEndFraction, plannedEndFraction) || other.plannedEndFraction == plannedEndFraction)&&(identical(other.tickFraction, tickFraction) || other.tickFraction == tickFraction)&&(identical(other.pendingChange, pendingChange) || other.pendingChange == pendingChange)&&const DeepCollectionEquality().equals(other.bars, bars)&&(identical(other.axisStartLabel, axisStartLabel) || other.axisStartLabel == axisStartLabel)&&const DeepCollectionEquality().equals(other.days, days));
}


@override
int get hashCode => Object.hashAll([runtimeType,experimentId,name,revision,keptSince,subtitle,why,today,weekStart,nextWeekStart,weekdayTargetMin,weekendTargetMin,weekdayCount,weekendCount,targetMin,doneMin,plannedMin,expectedMin,paceMin,chipText,chipTone,planState,remainingMin,shortMin,doneFraction,plannedEndFraction,tickFraction,pendingChange,const DeepCollectionEquality().hash(bars),axisStartLabel,const DeepCollectionEquality().hash(days)]);

@override
String toString() {
  return 'KeptExperimentView(experimentId: $experimentId, name: $name, revision: $revision, keptSince: $keptSince, subtitle: $subtitle, why: $why, today: $today, weekStart: $weekStart, nextWeekStart: $nextWeekStart, weekdayTargetMin: $weekdayTargetMin, weekendTargetMin: $weekendTargetMin, weekdayCount: $weekdayCount, weekendCount: $weekendCount, targetMin: $targetMin, doneMin: $doneMin, plannedMin: $plannedMin, expectedMin: $expectedMin, paceMin: $paceMin, chipText: $chipText, chipTone: $chipTone, planState: $planState, remainingMin: $remainingMin, shortMin: $shortMin, doneFraction: $doneFraction, plannedEndFraction: $plannedEndFraction, tickFraction: $tickFraction, pendingChange: $pendingChange, bars: $bars, axisStartLabel: $axisStartLabel, days: $days)';
}


}

/// @nodoc
abstract mixin class _$KeptExperimentViewCopyWith<$Res> implements $KeptExperimentViewCopyWith<$Res> {
  factory _$KeptExperimentViewCopyWith(_KeptExperimentView value, $Res Function(_KeptExperimentView) _then) = __$KeptExperimentViewCopyWithImpl;
@override @useResult
$Res call({
 String experimentId, String name, int revision, String keptSince, String subtitle, String? why, String today, String weekStart, String nextWeekStart, int weekdayTargetMin, int weekendTargetMin, int weekdayCount, int weekendCount, int targetMin, int doneMin, int plannedMin, int expectedMin, int paceMin, String chipText, KeptTone chipTone, KeptPlanState planState, int remainingMin, int shortMin, double doneFraction, double plannedEndFraction, double tickFraction, ExperimentTargetChange? pendingChange, List<KeptWeekBar> bars, String axisStartLabel, List<KeptDayColumn> days
});


@override $ExperimentTargetChangeCopyWith<$Res>? get pendingChange;

}
/// @nodoc
class __$KeptExperimentViewCopyWithImpl<$Res>
    implements _$KeptExperimentViewCopyWith<$Res> {
  __$KeptExperimentViewCopyWithImpl(this._self, this._then);

  final _KeptExperimentView _self;
  final $Res Function(_KeptExperimentView) _then;

/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? experimentId = null,Object? name = null,Object? revision = null,Object? keptSince = null,Object? subtitle = null,Object? why = freezed,Object? today = null,Object? weekStart = null,Object? nextWeekStart = null,Object? weekdayTargetMin = null,Object? weekendTargetMin = null,Object? weekdayCount = null,Object? weekendCount = null,Object? targetMin = null,Object? doneMin = null,Object? plannedMin = null,Object? expectedMin = null,Object? paceMin = null,Object? chipText = null,Object? chipTone = null,Object? planState = null,Object? remainingMin = null,Object? shortMin = null,Object? doneFraction = null,Object? plannedEndFraction = null,Object? tickFraction = null,Object? pendingChange = freezed,Object? bars = null,Object? axisStartLabel = null,Object? days = null,}) {
  return _then(_KeptExperimentView(
experimentId: null == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,keptSince: null == keptSince ? _self.keptSince : keptSince // ignore: cast_nullable_to_non_nullable
as String,subtitle: null == subtitle ? _self.subtitle : subtitle // ignore: cast_nullable_to_non_nullable
as String,why: freezed == why ? _self.why : why // ignore: cast_nullable_to_non_nullable
as String?,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as String,weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as String,nextWeekStart: null == nextWeekStart ? _self.nextWeekStart : nextWeekStart // ignore: cast_nullable_to_non_nullable
as String,weekdayTargetMin: null == weekdayTargetMin ? _self.weekdayTargetMin : weekdayTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekendTargetMin: null == weekendTargetMin ? _self.weekendTargetMin : weekendTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekdayCount: null == weekdayCount ? _self.weekdayCount : weekdayCount // ignore: cast_nullable_to_non_nullable
as int,weekendCount: null == weekendCount ? _self.weekendCount : weekendCount // ignore: cast_nullable_to_non_nullable
as int,targetMin: null == targetMin ? _self.targetMin : targetMin // ignore: cast_nullable_to_non_nullable
as int,doneMin: null == doneMin ? _self.doneMin : doneMin // ignore: cast_nullable_to_non_nullable
as int,plannedMin: null == plannedMin ? _self.plannedMin : plannedMin // ignore: cast_nullable_to_non_nullable
as int,expectedMin: null == expectedMin ? _self.expectedMin : expectedMin // ignore: cast_nullable_to_non_nullable
as int,paceMin: null == paceMin ? _self.paceMin : paceMin // ignore: cast_nullable_to_non_nullable
as int,chipText: null == chipText ? _self.chipText : chipText // ignore: cast_nullable_to_non_nullable
as String,chipTone: null == chipTone ? _self.chipTone : chipTone // ignore: cast_nullable_to_non_nullable
as KeptTone,planState: null == planState ? _self.planState : planState // ignore: cast_nullable_to_non_nullable
as KeptPlanState,remainingMin: null == remainingMin ? _self.remainingMin : remainingMin // ignore: cast_nullable_to_non_nullable
as int,shortMin: null == shortMin ? _self.shortMin : shortMin // ignore: cast_nullable_to_non_nullable
as int,doneFraction: null == doneFraction ? _self.doneFraction : doneFraction // ignore: cast_nullable_to_non_nullable
as double,plannedEndFraction: null == plannedEndFraction ? _self.plannedEndFraction : plannedEndFraction // ignore: cast_nullable_to_non_nullable
as double,tickFraction: null == tickFraction ? _self.tickFraction : tickFraction // ignore: cast_nullable_to_non_nullable
as double,pendingChange: freezed == pendingChange ? _self.pendingChange : pendingChange // ignore: cast_nullable_to_non_nullable
as ExperimentTargetChange?,bars: null == bars ? _self.bars : bars // ignore: cast_nullable_to_non_nullable
as List<KeptWeekBar>,axisStartLabel: null == axisStartLabel ? _self.axisStartLabel : axisStartLabel // ignore: cast_nullable_to_non_nullable
as String,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<KeptDayColumn>,
  ));
}

/// Create a copy of KeptExperimentView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExperimentTargetChangeCopyWith<$Res>? get pendingChange {
    if (_self.pendingChange == null) {
    return null;
  }

  return $ExperimentTargetChangeCopyWith<$Res>(_self.pendingChange!, (value) {
    return _then(_self.copyWith(pendingChange: value));
  });
}
}

/// @nodoc
mixin _$KeptSegment {

 List<KeptExperimentView> get views;
/// Create a copy of KeptSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeptSegmentCopyWith<KeptSegment> get copyWith => _$KeptSegmentCopyWithImpl<KeptSegment>(this as KeptSegment, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeptSegment&&const DeepCollectionEquality().equals(other.views, views));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(views));

@override
String toString() {
  return 'KeptSegment(views: $views)';
}


}

/// @nodoc
abstract mixin class $KeptSegmentCopyWith<$Res>  {
  factory $KeptSegmentCopyWith(KeptSegment value, $Res Function(KeptSegment) _then) = _$KeptSegmentCopyWithImpl;
@useResult
$Res call({
 List<KeptExperimentView> views
});




}
/// @nodoc
class _$KeptSegmentCopyWithImpl<$Res>
    implements $KeptSegmentCopyWith<$Res> {
  _$KeptSegmentCopyWithImpl(this._self, this._then);

  final KeptSegment _self;
  final $Res Function(KeptSegment) _then;

/// Create a copy of KeptSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? views = null,}) {
  return _then(_self.copyWith(
views: null == views ? _self.views : views // ignore: cast_nullable_to_non_nullable
as List<KeptExperimentView>,
  ));
}

}


/// Adds pattern-matching-related methods to [KeptSegment].
extension KeptSegmentPatterns on KeptSegment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _KeptSegment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _KeptSegment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _KeptSegment value)  $default,){
final _that = this;
switch (_that) {
case _KeptSegment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _KeptSegment value)?  $default,){
final _that = this;
switch (_that) {
case _KeptSegment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<KeptExperimentView> views)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _KeptSegment() when $default != null:
return $default(_that.views);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<KeptExperimentView> views)  $default,) {final _that = this;
switch (_that) {
case _KeptSegment():
return $default(_that.views);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<KeptExperimentView> views)?  $default,) {final _that = this;
switch (_that) {
case _KeptSegment() when $default != null:
return $default(_that.views);case _:
  return null;

}
}

}

/// @nodoc


class _KeptSegment implements KeptSegment {
  const _KeptSegment({this.views = const <KeptExperimentView>[]});
  

@override@JsonKey() final  List<KeptExperimentView> views;

/// Create a copy of KeptSegment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$KeptSegmentCopyWith<_KeptSegment> get copyWith => __$KeptSegmentCopyWithImpl<_KeptSegment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _KeptSegment&&const DeepCollectionEquality().equals(other.views, views));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(views));

@override
String toString() {
  return 'KeptSegment(views: $views)';
}


}

/// @nodoc
abstract mixin class _$KeptSegmentCopyWith<$Res> implements $KeptSegmentCopyWith<$Res> {
  factory _$KeptSegmentCopyWith(_KeptSegment value, $Res Function(_KeptSegment) _then) = __$KeptSegmentCopyWithImpl;
@override @useResult
$Res call({
 List<KeptExperimentView> views
});




}
/// @nodoc
class __$KeptSegmentCopyWithImpl<$Res>
    implements _$KeptSegmentCopyWith<$Res> {
  __$KeptSegmentCopyWithImpl(this._self, this._then);

  final _KeptSegment _self;
  final $Res Function(_KeptSegment) _then;

/// Create a copy of KeptSegment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? views = null,}) {
  return _then(_KeptSegment(
views: null == views ? _self.views : views // ignore: cast_nullable_to_non_nullable
as List<KeptExperimentView>,
  ));
}


}

// dart format on
