// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Task {

 String get id; String get title; String? get description; DateTime? get startTime; DateTime? get endTime; int? get estimatedDurationMin; int? get actualDurationMin; int get manualDurationAdjustmentMin;/// Distinguishes an explicit manual zero from no manually recorded work.
 bool get manualActualSet; String? get categoryId; Priority get priority; TaskStatus get status; String? get notes; String? get recurringRuleId; String? get recurrenceRemovalReason; String? get rescheduledFromId; String? get rescheduledToId; bool get isInbox; int get inboxContentVersion; String? get dueDate; String? get missedAt; List<PlanTitleChange> get planTitleHistory; String? get displayPlanChangeId; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskCopyWith<Task> get copyWith => _$TaskCopyWithImpl<Task>(this as Task, _$identity);

  /// Serializes this Task to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Task&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.estimatedDurationMin, estimatedDurationMin) || other.estimatedDurationMin == estimatedDurationMin)&&(identical(other.actualDurationMin, actualDurationMin) || other.actualDurationMin == actualDurationMin)&&(identical(other.manualDurationAdjustmentMin, manualDurationAdjustmentMin) || other.manualDurationAdjustmentMin == manualDurationAdjustmentMin)&&(identical(other.manualActualSet, manualActualSet) || other.manualActualSet == manualActualSet)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.recurringRuleId, recurringRuleId) || other.recurringRuleId == recurringRuleId)&&(identical(other.recurrenceRemovalReason, recurrenceRemovalReason) || other.recurrenceRemovalReason == recurrenceRemovalReason)&&(identical(other.rescheduledFromId, rescheduledFromId) || other.rescheduledFromId == rescheduledFromId)&&(identical(other.rescheduledToId, rescheduledToId) || other.rescheduledToId == rescheduledToId)&&(identical(other.isInbox, isInbox) || other.isInbox == isInbox)&&(identical(other.inboxContentVersion, inboxContentVersion) || other.inboxContentVersion == inboxContentVersion)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.missedAt, missedAt) || other.missedAt == missedAt)&&const DeepCollectionEquality().equals(other.planTitleHistory, planTitleHistory)&&(identical(other.displayPlanChangeId, displayPlanChangeId) || other.displayPlanChangeId == displayPlanChangeId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,description,startTime,endTime,estimatedDurationMin,actualDurationMin,manualDurationAdjustmentMin,manualActualSet,categoryId,priority,status,notes,recurringRuleId,recurrenceRemovalReason,rescheduledFromId,rescheduledToId,isInbox,inboxContentVersion,dueDate,missedAt,const DeepCollectionEquality().hash(planTitleHistory),displayPlanChangeId,createdAt,updatedAt,deletedAt]);

@override
String toString() {
  return 'Task(id: $id, title: $title, description: $description, startTime: $startTime, endTime: $endTime, estimatedDurationMin: $estimatedDurationMin, actualDurationMin: $actualDurationMin, manualDurationAdjustmentMin: $manualDurationAdjustmentMin, manualActualSet: $manualActualSet, categoryId: $categoryId, priority: $priority, status: $status, notes: $notes, recurringRuleId: $recurringRuleId, recurrenceRemovalReason: $recurrenceRemovalReason, rescheduledFromId: $rescheduledFromId, rescheduledToId: $rescheduledToId, isInbox: $isInbox, inboxContentVersion: $inboxContentVersion, dueDate: $dueDate, missedAt: $missedAt, planTitleHistory: $planTitleHistory, displayPlanChangeId: $displayPlanChangeId, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $TaskCopyWith<$Res>  {
  factory $TaskCopyWith(Task value, $Res Function(Task) _then) = _$TaskCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? description, DateTime? startTime, DateTime? endTime, int? estimatedDurationMin, int? actualDurationMin, int manualDurationAdjustmentMin, bool manualActualSet, String? categoryId, Priority priority, TaskStatus status, String? notes, String? recurringRuleId, String? recurrenceRemovalReason, String? rescheduledFromId, String? rescheduledToId, bool isInbox, int inboxContentVersion, String? dueDate, String? missedAt, List<PlanTitleChange> planTitleHistory, String? displayPlanChangeId, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$TaskCopyWithImpl<$Res>
    implements $TaskCopyWith<$Res> {
  _$TaskCopyWithImpl(this._self, this._then);

  final Task _self;
  final $Res Function(Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? description = freezed,Object? startTime = freezed,Object? endTime = freezed,Object? estimatedDurationMin = freezed,Object? actualDurationMin = freezed,Object? manualDurationAdjustmentMin = null,Object? manualActualSet = null,Object? categoryId = freezed,Object? priority = null,Object? status = null,Object? notes = freezed,Object? recurringRuleId = freezed,Object? recurrenceRemovalReason = freezed,Object? rescheduledFromId = freezed,Object? rescheduledToId = freezed,Object? isInbox = null,Object? inboxContentVersion = null,Object? dueDate = freezed,Object? missedAt = freezed,Object? planTitleHistory = null,Object? displayPlanChangeId = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,startTime: freezed == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime?,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,estimatedDurationMin: freezed == estimatedDurationMin ? _self.estimatedDurationMin : estimatedDurationMin // ignore: cast_nullable_to_non_nullable
as int?,actualDurationMin: freezed == actualDurationMin ? _self.actualDurationMin : actualDurationMin // ignore: cast_nullable_to_non_nullable
as int?,manualDurationAdjustmentMin: null == manualDurationAdjustmentMin ? _self.manualDurationAdjustmentMin : manualDurationAdjustmentMin // ignore: cast_nullable_to_non_nullable
as int,manualActualSet: null == manualActualSet ? _self.manualActualSet : manualActualSet // ignore: cast_nullable_to_non_nullable
as bool,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as Priority,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,recurringRuleId: freezed == recurringRuleId ? _self.recurringRuleId : recurringRuleId // ignore: cast_nullable_to_non_nullable
as String?,recurrenceRemovalReason: freezed == recurrenceRemovalReason ? _self.recurrenceRemovalReason : recurrenceRemovalReason // ignore: cast_nullable_to_non_nullable
as String?,rescheduledFromId: freezed == rescheduledFromId ? _self.rescheduledFromId : rescheduledFromId // ignore: cast_nullable_to_non_nullable
as String?,rescheduledToId: freezed == rescheduledToId ? _self.rescheduledToId : rescheduledToId // ignore: cast_nullable_to_non_nullable
as String?,isInbox: null == isInbox ? _self.isInbox : isInbox // ignore: cast_nullable_to_non_nullable
as bool,inboxContentVersion: null == inboxContentVersion ? _self.inboxContentVersion : inboxContentVersion // ignore: cast_nullable_to_non_nullable
as int,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,missedAt: freezed == missedAt ? _self.missedAt : missedAt // ignore: cast_nullable_to_non_nullable
as String?,planTitleHistory: null == planTitleHistory ? _self.planTitleHistory : planTitleHistory // ignore: cast_nullable_to_non_nullable
as List<PlanTitleChange>,displayPlanChangeId: freezed == displayPlanChangeId ? _self.displayPlanChangeId : displayPlanChangeId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Task].
extension TaskPatterns on Task {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Task value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Task() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Task value)  $default,){
final _that = this;
switch (_that) {
case _Task():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Task value)?  $default,){
final _that = this;
switch (_that) {
case _Task() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? description,  DateTime? startTime,  DateTime? endTime,  int? estimatedDurationMin,  int? actualDurationMin,  int manualDurationAdjustmentMin,  bool manualActualSet,  String? categoryId,  Priority priority,  TaskStatus status,  String? notes,  String? recurringRuleId,  String? recurrenceRemovalReason,  String? rescheduledFromId,  String? rescheduledToId,  bool isInbox,  int inboxContentVersion,  String? dueDate,  String? missedAt,  List<PlanTitleChange> planTitleHistory,  String? displayPlanChangeId,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.startTime,_that.endTime,_that.estimatedDurationMin,_that.actualDurationMin,_that.manualDurationAdjustmentMin,_that.manualActualSet,_that.categoryId,_that.priority,_that.status,_that.notes,_that.recurringRuleId,_that.recurrenceRemovalReason,_that.rescheduledFromId,_that.rescheduledToId,_that.isInbox,_that.inboxContentVersion,_that.dueDate,_that.missedAt,_that.planTitleHistory,_that.displayPlanChangeId,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? description,  DateTime? startTime,  DateTime? endTime,  int? estimatedDurationMin,  int? actualDurationMin,  int manualDurationAdjustmentMin,  bool manualActualSet,  String? categoryId,  Priority priority,  TaskStatus status,  String? notes,  String? recurringRuleId,  String? recurrenceRemovalReason,  String? rescheduledFromId,  String? rescheduledToId,  bool isInbox,  int inboxContentVersion,  String? dueDate,  String? missedAt,  List<PlanTitleChange> planTitleHistory,  String? displayPlanChangeId,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Task():
return $default(_that.id,_that.title,_that.description,_that.startTime,_that.endTime,_that.estimatedDurationMin,_that.actualDurationMin,_that.manualDurationAdjustmentMin,_that.manualActualSet,_that.categoryId,_that.priority,_that.status,_that.notes,_that.recurringRuleId,_that.recurrenceRemovalReason,_that.rescheduledFromId,_that.rescheduledToId,_that.isInbox,_that.inboxContentVersion,_that.dueDate,_that.missedAt,_that.planTitleHistory,_that.displayPlanChangeId,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? description,  DateTime? startTime,  DateTime? endTime,  int? estimatedDurationMin,  int? actualDurationMin,  int manualDurationAdjustmentMin,  bool manualActualSet,  String? categoryId,  Priority priority,  TaskStatus status,  String? notes,  String? recurringRuleId,  String? recurrenceRemovalReason,  String? rescheduledFromId,  String? rescheduledToId,  bool isInbox,  int inboxContentVersion,  String? dueDate,  String? missedAt,  List<PlanTitleChange> planTitleHistory,  String? displayPlanChangeId,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.startTime,_that.endTime,_that.estimatedDurationMin,_that.actualDurationMin,_that.manualDurationAdjustmentMin,_that.manualActualSet,_that.categoryId,_that.priority,_that.status,_that.notes,_that.recurringRuleId,_that.recurrenceRemovalReason,_that.rescheduledFromId,_that.rescheduledToId,_that.isInbox,_that.inboxContentVersion,_that.dueDate,_that.missedAt,_that.planTitleHistory,_that.displayPlanChangeId,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Task implements Task {
  const _Task({required this.id, required this.title, this.description, this.startTime, this.endTime, this.estimatedDurationMin, this.actualDurationMin, this.manualDurationAdjustmentMin = 0, this.manualActualSet = false, this.categoryId, this.priority = Priority.none, this.status = TaskStatus.planned, this.notes, this.recurringRuleId, this.recurrenceRemovalReason, this.rescheduledFromId, this.rescheduledToId, this.isInbox = false, this.inboxContentVersion = 0, this.dueDate, this.missedAt, this.planTitleHistory = const <PlanTitleChange>[], this.displayPlanChangeId, required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

@override final  String id;
@override final  String title;
@override final  String? description;
@override final  DateTime? startTime;
@override final  DateTime? endTime;
@override final  int? estimatedDurationMin;
@override final  int? actualDurationMin;
@override@JsonKey() final  int manualDurationAdjustmentMin;
/// Distinguishes an explicit manual zero from no manually recorded work.
@override@JsonKey() final  bool manualActualSet;
@override final  String? categoryId;
@override@JsonKey() final  Priority priority;
@override@JsonKey() final  TaskStatus status;
@override final  String? notes;
@override final  String? recurringRuleId;
@override final  String? recurrenceRemovalReason;
@override final  String? rescheduledFromId;
@override final  String? rescheduledToId;
@override@JsonKey() final  bool isInbox;
@override@JsonKey() final  int inboxContentVersion;
@override final  String? dueDate;
@override final  String? missedAt;
@override@JsonKey() final  List<PlanTitleChange> planTitleHistory;
@override final  String? displayPlanChangeId;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskCopyWith<_Task> get copyWith => __$TaskCopyWithImpl<_Task>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Task&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.startTime, startTime) || other.startTime == startTime)&&(identical(other.endTime, endTime) || other.endTime == endTime)&&(identical(other.estimatedDurationMin, estimatedDurationMin) || other.estimatedDurationMin == estimatedDurationMin)&&(identical(other.actualDurationMin, actualDurationMin) || other.actualDurationMin == actualDurationMin)&&(identical(other.manualDurationAdjustmentMin, manualDurationAdjustmentMin) || other.manualDurationAdjustmentMin == manualDurationAdjustmentMin)&&(identical(other.manualActualSet, manualActualSet) || other.manualActualSet == manualActualSet)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.recurringRuleId, recurringRuleId) || other.recurringRuleId == recurringRuleId)&&(identical(other.recurrenceRemovalReason, recurrenceRemovalReason) || other.recurrenceRemovalReason == recurrenceRemovalReason)&&(identical(other.rescheduledFromId, rescheduledFromId) || other.rescheduledFromId == rescheduledFromId)&&(identical(other.rescheduledToId, rescheduledToId) || other.rescheduledToId == rescheduledToId)&&(identical(other.isInbox, isInbox) || other.isInbox == isInbox)&&(identical(other.inboxContentVersion, inboxContentVersion) || other.inboxContentVersion == inboxContentVersion)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.missedAt, missedAt) || other.missedAt == missedAt)&&const DeepCollectionEquality().equals(other.planTitleHistory, planTitleHistory)&&(identical(other.displayPlanChangeId, displayPlanChangeId) || other.displayPlanChangeId == displayPlanChangeId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,description,startTime,endTime,estimatedDurationMin,actualDurationMin,manualDurationAdjustmentMin,manualActualSet,categoryId,priority,status,notes,recurringRuleId,recurrenceRemovalReason,rescheduledFromId,rescheduledToId,isInbox,inboxContentVersion,dueDate,missedAt,const DeepCollectionEquality().hash(planTitleHistory),displayPlanChangeId,createdAt,updatedAt,deletedAt]);

@override
String toString() {
  return 'Task(id: $id, title: $title, description: $description, startTime: $startTime, endTime: $endTime, estimatedDurationMin: $estimatedDurationMin, actualDurationMin: $actualDurationMin, manualDurationAdjustmentMin: $manualDurationAdjustmentMin, manualActualSet: $manualActualSet, categoryId: $categoryId, priority: $priority, status: $status, notes: $notes, recurringRuleId: $recurringRuleId, recurrenceRemovalReason: $recurrenceRemovalReason, rescheduledFromId: $rescheduledFromId, rescheduledToId: $rescheduledToId, isInbox: $isInbox, inboxContentVersion: $inboxContentVersion, dueDate: $dueDate, missedAt: $missedAt, planTitleHistory: $planTitleHistory, displayPlanChangeId: $displayPlanChangeId, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskCopyWith<$Res> implements $TaskCopyWith<$Res> {
  factory _$TaskCopyWith(_Task value, $Res Function(_Task) _then) = __$TaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? description, DateTime? startTime, DateTime? endTime, int? estimatedDurationMin, int? actualDurationMin, int manualDurationAdjustmentMin, bool manualActualSet, String? categoryId, Priority priority, TaskStatus status, String? notes, String? recurringRuleId, String? recurrenceRemovalReason, String? rescheduledFromId, String? rescheduledToId, bool isInbox, int inboxContentVersion, String? dueDate, String? missedAt, List<PlanTitleChange> planTitleHistory, String? displayPlanChangeId, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$TaskCopyWithImpl<$Res>
    implements _$TaskCopyWith<$Res> {
  __$TaskCopyWithImpl(this._self, this._then);

  final _Task _self;
  final $Res Function(_Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? description = freezed,Object? startTime = freezed,Object? endTime = freezed,Object? estimatedDurationMin = freezed,Object? actualDurationMin = freezed,Object? manualDurationAdjustmentMin = null,Object? manualActualSet = null,Object? categoryId = freezed,Object? priority = null,Object? status = null,Object? notes = freezed,Object? recurringRuleId = freezed,Object? recurrenceRemovalReason = freezed,Object? rescheduledFromId = freezed,Object? rescheduledToId = freezed,Object? isInbox = null,Object? inboxContentVersion = null,Object? dueDate = freezed,Object? missedAt = freezed,Object? planTitleHistory = null,Object? displayPlanChangeId = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_Task(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,startTime: freezed == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as DateTime?,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as DateTime?,estimatedDurationMin: freezed == estimatedDurationMin ? _self.estimatedDurationMin : estimatedDurationMin // ignore: cast_nullable_to_non_nullable
as int?,actualDurationMin: freezed == actualDurationMin ? _self.actualDurationMin : actualDurationMin // ignore: cast_nullable_to_non_nullable
as int?,manualDurationAdjustmentMin: null == manualDurationAdjustmentMin ? _self.manualDurationAdjustmentMin : manualDurationAdjustmentMin // ignore: cast_nullable_to_non_nullable
as int,manualActualSet: null == manualActualSet ? _self.manualActualSet : manualActualSet // ignore: cast_nullable_to_non_nullable
as bool,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as Priority,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,recurringRuleId: freezed == recurringRuleId ? _self.recurringRuleId : recurringRuleId // ignore: cast_nullable_to_non_nullable
as String?,recurrenceRemovalReason: freezed == recurrenceRemovalReason ? _self.recurrenceRemovalReason : recurrenceRemovalReason // ignore: cast_nullable_to_non_nullable
as String?,rescheduledFromId: freezed == rescheduledFromId ? _self.rescheduledFromId : rescheduledFromId // ignore: cast_nullable_to_non_nullable
as String?,rescheduledToId: freezed == rescheduledToId ? _self.rescheduledToId : rescheduledToId // ignore: cast_nullable_to_non_nullable
as String?,isInbox: null == isInbox ? _self.isInbox : isInbox // ignore: cast_nullable_to_non_nullable
as bool,inboxContentVersion: null == inboxContentVersion ? _self.inboxContentVersion : inboxContentVersion // ignore: cast_nullable_to_non_nullable
as int,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,missedAt: freezed == missedAt ? _self.missedAt : missedAt // ignore: cast_nullable_to_non_nullable
as String?,planTitleHistory: null == planTitleHistory ? _self.planTitleHistory : planTitleHistory // ignore: cast_nullable_to_non_nullable
as List<PlanTitleChange>,displayPlanChangeId: freezed == displayPlanChangeId ? _self.displayPlanChangeId : displayPlanChangeId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
