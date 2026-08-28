// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recurring_rule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RecurringRule {

 String get id; String get rrule; String get taskTitle; String? get taskDescription; int get durationMin; String? get categoryId; int get priority; List<String> get tags;/// Local wall-clock time of day as `HH:mm`.
 String get startTimeOfDay;/// First date the rule can occur on (`yyyy-MM-dd`).
 DateTime get startDate; DateTime? get endDate; bool get isActive;/// Excluded dates as `yyyy-MM-dd` strings.
 List<String> get exceptions; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of RecurringRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecurringRuleCopyWith<RecurringRule> get copyWith => _$RecurringRuleCopyWithImpl<RecurringRule>(this as RecurringRule, _$identity);

  /// Serializes this RecurringRule to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecurringRule&&(identical(other.id, id) || other.id == id)&&(identical(other.rrule, rrule) || other.rrule == rrule)&&(identical(other.taskTitle, taskTitle) || other.taskTitle == taskTitle)&&(identical(other.taskDescription, taskDescription) || other.taskDescription == taskDescription)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.startTimeOfDay, startTimeOfDay) || other.startTimeOfDay == startTimeOfDay)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&const DeepCollectionEquality().equals(other.exceptions, exceptions)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,rrule,taskTitle,taskDescription,durationMin,categoryId,priority,const DeepCollectionEquality().hash(tags),startTimeOfDay,startDate,endDate,isActive,const DeepCollectionEquality().hash(exceptions),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'RecurringRule(id: $id, rrule: $rrule, taskTitle: $taskTitle, taskDescription: $taskDescription, durationMin: $durationMin, categoryId: $categoryId, priority: $priority, tags: $tags, startTimeOfDay: $startTimeOfDay, startDate: $startDate, endDate: $endDate, isActive: $isActive, exceptions: $exceptions, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $RecurringRuleCopyWith<$Res>  {
  factory $RecurringRuleCopyWith(RecurringRule value, $Res Function(RecurringRule) _then) = _$RecurringRuleCopyWithImpl;
@useResult
$Res call({
 String id, String rrule, String taskTitle, String? taskDescription, int durationMin, String? categoryId, int priority, List<String> tags, String startTimeOfDay, DateTime startDate, DateTime? endDate, bool isActive, List<String> exceptions, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$RecurringRuleCopyWithImpl<$Res>
    implements $RecurringRuleCopyWith<$Res> {
  _$RecurringRuleCopyWithImpl(this._self, this._then);

  final RecurringRule _self;
  final $Res Function(RecurringRule) _then;

/// Create a copy of RecurringRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? rrule = null,Object? taskTitle = null,Object? taskDescription = freezed,Object? durationMin = null,Object? categoryId = freezed,Object? priority = null,Object? tags = null,Object? startTimeOfDay = null,Object? startDate = null,Object? endDate = freezed,Object? isActive = null,Object? exceptions = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,rrule: null == rrule ? _self.rrule : rrule // ignore: cast_nullable_to_non_nullable
as String,taskTitle: null == taskTitle ? _self.taskTitle : taskTitle // ignore: cast_nullable_to_non_nullable
as String,taskDescription: freezed == taskDescription ? _self.taskDescription : taskDescription // ignore: cast_nullable_to_non_nullable
as String?,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,startTimeOfDay: null == startTimeOfDay ? _self.startTimeOfDay : startTimeOfDay // ignore: cast_nullable_to_non_nullable
as String,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,exceptions: null == exceptions ? _self.exceptions : exceptions // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [RecurringRule].
extension RecurringRulePatterns on RecurringRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecurringRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecurringRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecurringRule value)  $default,){
final _that = this;
switch (_that) {
case _RecurringRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecurringRule value)?  $default,){
final _that = this;
switch (_that) {
case _RecurringRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String rrule,  String taskTitle,  String? taskDescription,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  String startTimeOfDay,  DateTime startDate,  DateTime? endDate,  bool isActive,  List<String> exceptions,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecurringRule() when $default != null:
return $default(_that.id,_that.rrule,_that.taskTitle,_that.taskDescription,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.startTimeOfDay,_that.startDate,_that.endDate,_that.isActive,_that.exceptions,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String rrule,  String taskTitle,  String? taskDescription,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  String startTimeOfDay,  DateTime startDate,  DateTime? endDate,  bool isActive,  List<String> exceptions,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _RecurringRule():
return $default(_that.id,_that.rrule,_that.taskTitle,_that.taskDescription,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.startTimeOfDay,_that.startDate,_that.endDate,_that.isActive,_that.exceptions,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String rrule,  String taskTitle,  String? taskDescription,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  String startTimeOfDay,  DateTime startDate,  DateTime? endDate,  bool isActive,  List<String> exceptions,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _RecurringRule() when $default != null:
return $default(_that.id,_that.rrule,_that.taskTitle,_that.taskDescription,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.startTimeOfDay,_that.startDate,_that.endDate,_that.isActive,_that.exceptions,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecurringRule implements RecurringRule {
  const _RecurringRule({required this.id, required this.rrule, required this.taskTitle, this.taskDescription, required this.durationMin, this.categoryId, this.priority = 0, this.tags = const [], required this.startTimeOfDay, required this.startDate, this.endDate, this.isActive = true, this.exceptions = const [], required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _RecurringRule.fromJson(Map<String, dynamic> json) => _$RecurringRuleFromJson(json);

@override final  String id;
@override final  String rrule;
@override final  String taskTitle;
@override final  String? taskDescription;
@override final  int durationMin;
@override final  String? categoryId;
@override@JsonKey() final  int priority;
@override@JsonKey() final  List<String> tags;
/// Local wall-clock time of day as `HH:mm`.
@override final  String startTimeOfDay;
/// First date the rule can occur on (`yyyy-MM-dd`).
@override final  DateTime startDate;
@override final  DateTime? endDate;
@override@JsonKey() final  bool isActive;
/// Excluded dates as `yyyy-MM-dd` strings.
@override@JsonKey() final  List<String> exceptions;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of RecurringRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecurringRuleCopyWith<_RecurringRule> get copyWith => __$RecurringRuleCopyWithImpl<_RecurringRule>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecurringRuleToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecurringRule&&(identical(other.id, id) || other.id == id)&&(identical(other.rrule, rrule) || other.rrule == rrule)&&(identical(other.taskTitle, taskTitle) || other.taskTitle == taskTitle)&&(identical(other.taskDescription, taskDescription) || other.taskDescription == taskDescription)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.startTimeOfDay, startTimeOfDay) || other.startTimeOfDay == startTimeOfDay)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&const DeepCollectionEquality().equals(other.exceptions, exceptions)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,rrule,taskTitle,taskDescription,durationMin,categoryId,priority,const DeepCollectionEquality().hash(tags),startTimeOfDay,startDate,endDate,isActive,const DeepCollectionEquality().hash(exceptions),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'RecurringRule(id: $id, rrule: $rrule, taskTitle: $taskTitle, taskDescription: $taskDescription, durationMin: $durationMin, categoryId: $categoryId, priority: $priority, tags: $tags, startTimeOfDay: $startTimeOfDay, startDate: $startDate, endDate: $endDate, isActive: $isActive, exceptions: $exceptions, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$RecurringRuleCopyWith<$Res> implements $RecurringRuleCopyWith<$Res> {
  factory _$RecurringRuleCopyWith(_RecurringRule value, $Res Function(_RecurringRule) _then) = __$RecurringRuleCopyWithImpl;
@override @useResult
$Res call({
 String id, String rrule, String taskTitle, String? taskDescription, int durationMin, String? categoryId, int priority, List<String> tags, String startTimeOfDay, DateTime startDate, DateTime? endDate, bool isActive, List<String> exceptions, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$RecurringRuleCopyWithImpl<$Res>
    implements _$RecurringRuleCopyWith<$Res> {
  __$RecurringRuleCopyWithImpl(this._self, this._then);

  final _RecurringRule _self;
  final $Res Function(_RecurringRule) _then;

/// Create a copy of RecurringRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? rrule = null,Object? taskTitle = null,Object? taskDescription = freezed,Object? durationMin = null,Object? categoryId = freezed,Object? priority = null,Object? tags = null,Object? startTimeOfDay = null,Object? startDate = null,Object? endDate = freezed,Object? isActive = null,Object? exceptions = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_RecurringRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,rrule: null == rrule ? _self.rrule : rrule // ignore: cast_nullable_to_non_nullable
as String,taskTitle: null == taskTitle ? _self.taskTitle : taskTitle // ignore: cast_nullable_to_non_nullable
as String,taskDescription: freezed == taskDescription ? _self.taskDescription : taskDescription // ignore: cast_nullable_to_non_nullable
as String?,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,startTimeOfDay: null == startTimeOfDay ? _self.startTimeOfDay : startTimeOfDay // ignore: cast_nullable_to_non_nullable
as String,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,exceptions: null == exceptions ? _self.exceptions : exceptions // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
