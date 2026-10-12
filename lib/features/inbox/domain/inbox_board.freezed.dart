// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_board.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InboxSessionView {

 InboxSessionFacts get facts; InboxSessionStatus get status;/// Planner date of the start (`yyyy-MM-dd`); empty without a start.
 String get date;/// The saved Review reason, if any.
 String? get reason;/// The session is on a break day, where Review asks no reason.
 bool get breakDay;/// Same rule as Review's "N without a reason" (`awaitsReason`) plus the
/// break-day rule.
 bool get needsReason;
/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxSessionViewCopyWith<InboxSessionView> get copyWith => _$InboxSessionViewCopyWithImpl<InboxSessionView>(this as InboxSessionView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxSessionView&&(identical(other.facts, facts) || other.facts == facts)&&(identical(other.status, status) || other.status == status)&&(identical(other.date, date) || other.date == date)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.breakDay, breakDay) || other.breakDay == breakDay)&&(identical(other.needsReason, needsReason) || other.needsReason == needsReason));
}


@override
int get hashCode => Object.hash(runtimeType,facts,status,date,reason,breakDay,needsReason);

@override
String toString() {
  return 'InboxSessionView(facts: $facts, status: $status, date: $date, reason: $reason, breakDay: $breakDay, needsReason: $needsReason)';
}


}

/// @nodoc
abstract mixin class $InboxSessionViewCopyWith<$Res>  {
  factory $InboxSessionViewCopyWith(InboxSessionView value, $Res Function(InboxSessionView) _then) = _$InboxSessionViewCopyWithImpl;
@useResult
$Res call({
 InboxSessionFacts facts, InboxSessionStatus status, String date, String? reason, bool breakDay, bool needsReason
});


$InboxSessionFactsCopyWith<$Res> get facts;

}
/// @nodoc
class _$InboxSessionViewCopyWithImpl<$Res>
    implements $InboxSessionViewCopyWith<$Res> {
  _$InboxSessionViewCopyWithImpl(this._self, this._then);

  final InboxSessionView _self;
  final $Res Function(InboxSessionView) _then;

/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? facts = null,Object? status = null,Object? date = null,Object? reason = freezed,Object? breakDay = null,Object? needsReason = null,}) {
  return _then(_self.copyWith(
facts: null == facts ? _self.facts : facts // ignore: cast_nullable_to_non_nullable
as InboxSessionFacts,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InboxSessionStatus,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,breakDay: null == breakDay ? _self.breakDay : breakDay // ignore: cast_nullable_to_non_nullable
as bool,needsReason: null == needsReason ? _self.needsReason : needsReason // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxSessionFactsCopyWith<$Res> get facts {
  
  return $InboxSessionFactsCopyWith<$Res>(_self.facts, (value) {
    return _then(_self.copyWith(facts: value));
  });
}
}


/// Adds pattern-matching-related methods to [InboxSessionView].
extension InboxSessionViewPatterns on InboxSessionView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxSessionView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxSessionView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxSessionView value)  $default,){
final _that = this;
switch (_that) {
case _InboxSessionView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxSessionView value)?  $default,){
final _that = this;
switch (_that) {
case _InboxSessionView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InboxSessionFacts facts,  InboxSessionStatus status,  String date,  String? reason,  bool breakDay,  bool needsReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxSessionView() when $default != null:
return $default(_that.facts,_that.status,_that.date,_that.reason,_that.breakDay,_that.needsReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InboxSessionFacts facts,  InboxSessionStatus status,  String date,  String? reason,  bool breakDay,  bool needsReason)  $default,) {final _that = this;
switch (_that) {
case _InboxSessionView():
return $default(_that.facts,_that.status,_that.date,_that.reason,_that.breakDay,_that.needsReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InboxSessionFacts facts,  InboxSessionStatus status,  String date,  String? reason,  bool breakDay,  bool needsReason)?  $default,) {final _that = this;
switch (_that) {
case _InboxSessionView() when $default != null:
return $default(_that.facts,_that.status,_that.date,_that.reason,_that.breakDay,_that.needsReason);case _:
  return null;

}
}

}

/// @nodoc


class _InboxSessionView implements InboxSessionView {
  const _InboxSessionView({required this.facts, required this.status, required this.date, this.reason, this.breakDay = false, this.needsReason = false});
  

@override final  InboxSessionFacts facts;
@override final  InboxSessionStatus status;
/// Planner date of the start (`yyyy-MM-dd`); empty without a start.
@override final  String date;
/// The saved Review reason, if any.
@override final  String? reason;
/// The session is on a break day, where Review asks no reason.
@override@JsonKey() final  bool breakDay;
/// Same rule as Review's "N without a reason" (`awaitsReason`) plus the
/// break-day rule.
@override@JsonKey() final  bool needsReason;

/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxSessionViewCopyWith<_InboxSessionView> get copyWith => __$InboxSessionViewCopyWithImpl<_InboxSessionView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxSessionView&&(identical(other.facts, facts) || other.facts == facts)&&(identical(other.status, status) || other.status == status)&&(identical(other.date, date) || other.date == date)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.breakDay, breakDay) || other.breakDay == breakDay)&&(identical(other.needsReason, needsReason) || other.needsReason == needsReason));
}


@override
int get hashCode => Object.hash(runtimeType,facts,status,date,reason,breakDay,needsReason);

@override
String toString() {
  return 'InboxSessionView(facts: $facts, status: $status, date: $date, reason: $reason, breakDay: $breakDay, needsReason: $needsReason)';
}


}

/// @nodoc
abstract mixin class _$InboxSessionViewCopyWith<$Res> implements $InboxSessionViewCopyWith<$Res> {
  factory _$InboxSessionViewCopyWith(_InboxSessionView value, $Res Function(_InboxSessionView) _then) = __$InboxSessionViewCopyWithImpl;
@override @useResult
$Res call({
 InboxSessionFacts facts, InboxSessionStatus status, String date, String? reason, bool breakDay, bool needsReason
});


@override $InboxSessionFactsCopyWith<$Res> get facts;

}
/// @nodoc
class __$InboxSessionViewCopyWithImpl<$Res>
    implements _$InboxSessionViewCopyWith<$Res> {
  __$InboxSessionViewCopyWithImpl(this._self, this._then);

  final _InboxSessionView _self;
  final $Res Function(_InboxSessionView) _then;

/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? facts = null,Object? status = null,Object? date = null,Object? reason = freezed,Object? breakDay = null,Object? needsReason = null,}) {
  return _then(_InboxSessionView(
facts: null == facts ? _self.facts : facts // ignore: cast_nullable_to_non_nullable
as InboxSessionFacts,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InboxSessionStatus,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,breakDay: null == breakDay ? _self.breakDay : breakDay // ignore: cast_nullable_to_non_nullable
as bool,needsReason: null == needsReason ? _self.needsReason : needsReason // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of InboxSessionView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxSessionFactsCopyWith<$Res> get facts {
  
  return $InboxSessionFactsCopyWith<$Res>(_self.facts, (value) {
    return _then(_self.copyWith(facts: value));
  });
}
}

/// @nodoc
mixin _$InboxIdeaView {

 InboxItemFacts get item; InboxItemStatus get status;/// Sessions, soonest first, deleted ones included (status dropped).
 List<InboxSessionView> get sessions;/// The event that holds the idea closed now; null unless closed.
 InboxClosure? get closure;/// The Done chip: Finished, Closed, Let go or an Experiment chip.
 String? get chip;/// The experiment named by the open closure, when it is an experiment.
 String? get experimentId;/// True when the open closure names an experiment whose row is gone.
 bool get experimentMissing;/// When the idea reached Done (closure time, or its latest done end).
 DateTime? get resolvedAt;/// Start of the soonest upcoming session.
 DateTime? get nextStart;/// Start of the most recent missed session.
 DateTime? get lastMissedStart;/// End of the most recent missed session; Left over is ordered by it.
 DateTime? get lastMissedEnd; int get upcomingCount; int get needsReasonCount;
/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxIdeaViewCopyWith<InboxIdeaView> get copyWith => _$InboxIdeaViewCopyWithImpl<InboxIdeaView>(this as InboxIdeaView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxIdeaView&&(identical(other.item, item) || other.item == item)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.sessions, sessions)&&(identical(other.closure, closure) || other.closure == closure)&&(identical(other.chip, chip) || other.chip == chip)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.experimentMissing, experimentMissing) || other.experimentMissing == experimentMissing)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.nextStart, nextStart) || other.nextStart == nextStart)&&(identical(other.lastMissedStart, lastMissedStart) || other.lastMissedStart == lastMissedStart)&&(identical(other.lastMissedEnd, lastMissedEnd) || other.lastMissedEnd == lastMissedEnd)&&(identical(other.upcomingCount, upcomingCount) || other.upcomingCount == upcomingCount)&&(identical(other.needsReasonCount, needsReasonCount) || other.needsReasonCount == needsReasonCount));
}


@override
int get hashCode => Object.hash(runtimeType,item,status,const DeepCollectionEquality().hash(sessions),closure,chip,experimentId,experimentMissing,resolvedAt,nextStart,lastMissedStart,lastMissedEnd,upcomingCount,needsReasonCount);

@override
String toString() {
  return 'InboxIdeaView(item: $item, status: $status, sessions: $sessions, closure: $closure, chip: $chip, experimentId: $experimentId, experimentMissing: $experimentMissing, resolvedAt: $resolvedAt, nextStart: $nextStart, lastMissedStart: $lastMissedStart, lastMissedEnd: $lastMissedEnd, upcomingCount: $upcomingCount, needsReasonCount: $needsReasonCount)';
}


}

/// @nodoc
abstract mixin class $InboxIdeaViewCopyWith<$Res>  {
  factory $InboxIdeaViewCopyWith(InboxIdeaView value, $Res Function(InboxIdeaView) _then) = _$InboxIdeaViewCopyWithImpl;
@useResult
$Res call({
 InboxItemFacts item, InboxItemStatus status, List<InboxSessionView> sessions, InboxClosure? closure, String? chip, String? experimentId, bool experimentMissing, DateTime? resolvedAt, DateTime? nextStart, DateTime? lastMissedStart, DateTime? lastMissedEnd, int upcomingCount, int needsReasonCount
});


$InboxItemFactsCopyWith<$Res> get item;$InboxClosureCopyWith<$Res>? get closure;

}
/// @nodoc
class _$InboxIdeaViewCopyWithImpl<$Res>
    implements $InboxIdeaViewCopyWith<$Res> {
  _$InboxIdeaViewCopyWithImpl(this._self, this._then);

  final InboxIdeaView _self;
  final $Res Function(InboxIdeaView) _then;

/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? item = null,Object? status = null,Object? sessions = null,Object? closure = freezed,Object? chip = freezed,Object? experimentId = freezed,Object? experimentMissing = null,Object? resolvedAt = freezed,Object? nextStart = freezed,Object? lastMissedStart = freezed,Object? lastMissedEnd = freezed,Object? upcomingCount = null,Object? needsReasonCount = null,}) {
  return _then(_self.copyWith(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as InboxItemFacts,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InboxItemStatus,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<InboxSessionView>,closure: freezed == closure ? _self.closure : closure // ignore: cast_nullable_to_non_nullable
as InboxClosure?,chip: freezed == chip ? _self.chip : chip // ignore: cast_nullable_to_non_nullable
as String?,experimentId: freezed == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String?,experimentMissing: null == experimentMissing ? _self.experimentMissing : experimentMissing // ignore: cast_nullable_to_non_nullable
as bool,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nextStart: freezed == nextStart ? _self.nextStart : nextStart // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMissedStart: freezed == lastMissedStart ? _self.lastMissedStart : lastMissedStart // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMissedEnd: freezed == lastMissedEnd ? _self.lastMissedEnd : lastMissedEnd // ignore: cast_nullable_to_non_nullable
as DateTime?,upcomingCount: null == upcomingCount ? _self.upcomingCount : upcomingCount // ignore: cast_nullable_to_non_nullable
as int,needsReasonCount: null == needsReasonCount ? _self.needsReasonCount : needsReasonCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxItemFactsCopyWith<$Res> get item {
  
  return $InboxItemFactsCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxClosureCopyWith<$Res>? get closure {
    if (_self.closure == null) {
    return null;
  }

  return $InboxClosureCopyWith<$Res>(_self.closure!, (value) {
    return _then(_self.copyWith(closure: value));
  });
}
}


/// Adds pattern-matching-related methods to [InboxIdeaView].
extension InboxIdeaViewPatterns on InboxIdeaView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxIdeaView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxIdeaView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxIdeaView value)  $default,){
final _that = this;
switch (_that) {
case _InboxIdeaView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxIdeaView value)?  $default,){
final _that = this;
switch (_that) {
case _InboxIdeaView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InboxItemFacts item,  InboxItemStatus status,  List<InboxSessionView> sessions,  InboxClosure? closure,  String? chip,  String? experimentId,  bool experimentMissing,  DateTime? resolvedAt,  DateTime? nextStart,  DateTime? lastMissedStart,  DateTime? lastMissedEnd,  int upcomingCount,  int needsReasonCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxIdeaView() when $default != null:
return $default(_that.item,_that.status,_that.sessions,_that.closure,_that.chip,_that.experimentId,_that.experimentMissing,_that.resolvedAt,_that.nextStart,_that.lastMissedStart,_that.lastMissedEnd,_that.upcomingCount,_that.needsReasonCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InboxItemFacts item,  InboxItemStatus status,  List<InboxSessionView> sessions,  InboxClosure? closure,  String? chip,  String? experimentId,  bool experimentMissing,  DateTime? resolvedAt,  DateTime? nextStart,  DateTime? lastMissedStart,  DateTime? lastMissedEnd,  int upcomingCount,  int needsReasonCount)  $default,) {final _that = this;
switch (_that) {
case _InboxIdeaView():
return $default(_that.item,_that.status,_that.sessions,_that.closure,_that.chip,_that.experimentId,_that.experimentMissing,_that.resolvedAt,_that.nextStart,_that.lastMissedStart,_that.lastMissedEnd,_that.upcomingCount,_that.needsReasonCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InboxItemFacts item,  InboxItemStatus status,  List<InboxSessionView> sessions,  InboxClosure? closure,  String? chip,  String? experimentId,  bool experimentMissing,  DateTime? resolvedAt,  DateTime? nextStart,  DateTime? lastMissedStart,  DateTime? lastMissedEnd,  int upcomingCount,  int needsReasonCount)?  $default,) {final _that = this;
switch (_that) {
case _InboxIdeaView() when $default != null:
return $default(_that.item,_that.status,_that.sessions,_that.closure,_that.chip,_that.experimentId,_that.experimentMissing,_that.resolvedAt,_that.nextStart,_that.lastMissedStart,_that.lastMissedEnd,_that.upcomingCount,_that.needsReasonCount);case _:
  return null;

}
}

}

/// @nodoc


class _InboxIdeaView implements InboxIdeaView {
  const _InboxIdeaView({required this.item, required this.status, this.sessions = const <InboxSessionView>[], this.closure, this.chip, this.experimentId, this.experimentMissing = false, this.resolvedAt, this.nextStart, this.lastMissedStart, this.lastMissedEnd, this.upcomingCount = 0, this.needsReasonCount = 0});
  

@override final  InboxItemFacts item;
@override final  InboxItemStatus status;
/// Sessions, soonest first, deleted ones included (status dropped).
@override@JsonKey() final  List<InboxSessionView> sessions;
/// The event that holds the idea closed now; null unless closed.
@override final  InboxClosure? closure;
/// The Done chip: Finished, Closed, Let go or an Experiment chip.
@override final  String? chip;
/// The experiment named by the open closure, when it is an experiment.
@override final  String? experimentId;
/// True when the open closure names an experiment whose row is gone.
@override@JsonKey() final  bool experimentMissing;
/// When the idea reached Done (closure time, or its latest done end).
@override final  DateTime? resolvedAt;
/// Start of the soonest upcoming session.
@override final  DateTime? nextStart;
/// Start of the most recent missed session.
@override final  DateTime? lastMissedStart;
/// End of the most recent missed session; Left over is ordered by it.
@override final  DateTime? lastMissedEnd;
@override@JsonKey() final  int upcomingCount;
@override@JsonKey() final  int needsReasonCount;

/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxIdeaViewCopyWith<_InboxIdeaView> get copyWith => __$InboxIdeaViewCopyWithImpl<_InboxIdeaView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxIdeaView&&(identical(other.item, item) || other.item == item)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.sessions, sessions)&&(identical(other.closure, closure) || other.closure == closure)&&(identical(other.chip, chip) || other.chip == chip)&&(identical(other.experimentId, experimentId) || other.experimentId == experimentId)&&(identical(other.experimentMissing, experimentMissing) || other.experimentMissing == experimentMissing)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.nextStart, nextStart) || other.nextStart == nextStart)&&(identical(other.lastMissedStart, lastMissedStart) || other.lastMissedStart == lastMissedStart)&&(identical(other.lastMissedEnd, lastMissedEnd) || other.lastMissedEnd == lastMissedEnd)&&(identical(other.upcomingCount, upcomingCount) || other.upcomingCount == upcomingCount)&&(identical(other.needsReasonCount, needsReasonCount) || other.needsReasonCount == needsReasonCount));
}


@override
int get hashCode => Object.hash(runtimeType,item,status,const DeepCollectionEquality().hash(sessions),closure,chip,experimentId,experimentMissing,resolvedAt,nextStart,lastMissedStart,lastMissedEnd,upcomingCount,needsReasonCount);

@override
String toString() {
  return 'InboxIdeaView(item: $item, status: $status, sessions: $sessions, closure: $closure, chip: $chip, experimentId: $experimentId, experimentMissing: $experimentMissing, resolvedAt: $resolvedAt, nextStart: $nextStart, lastMissedStart: $lastMissedStart, lastMissedEnd: $lastMissedEnd, upcomingCount: $upcomingCount, needsReasonCount: $needsReasonCount)';
}


}

/// @nodoc
abstract mixin class _$InboxIdeaViewCopyWith<$Res> implements $InboxIdeaViewCopyWith<$Res> {
  factory _$InboxIdeaViewCopyWith(_InboxIdeaView value, $Res Function(_InboxIdeaView) _then) = __$InboxIdeaViewCopyWithImpl;
@override @useResult
$Res call({
 InboxItemFacts item, InboxItemStatus status, List<InboxSessionView> sessions, InboxClosure? closure, String? chip, String? experimentId, bool experimentMissing, DateTime? resolvedAt, DateTime? nextStart, DateTime? lastMissedStart, DateTime? lastMissedEnd, int upcomingCount, int needsReasonCount
});


@override $InboxItemFactsCopyWith<$Res> get item;@override $InboxClosureCopyWith<$Res>? get closure;

}
/// @nodoc
class __$InboxIdeaViewCopyWithImpl<$Res>
    implements _$InboxIdeaViewCopyWith<$Res> {
  __$InboxIdeaViewCopyWithImpl(this._self, this._then);

  final _InboxIdeaView _self;
  final $Res Function(_InboxIdeaView) _then;

/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? item = null,Object? status = null,Object? sessions = null,Object? closure = freezed,Object? chip = freezed,Object? experimentId = freezed,Object? experimentMissing = null,Object? resolvedAt = freezed,Object? nextStart = freezed,Object? lastMissedStart = freezed,Object? lastMissedEnd = freezed,Object? upcomingCount = null,Object? needsReasonCount = null,}) {
  return _then(_InboxIdeaView(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as InboxItemFacts,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InboxItemStatus,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<InboxSessionView>,closure: freezed == closure ? _self.closure : closure // ignore: cast_nullable_to_non_nullable
as InboxClosure?,chip: freezed == chip ? _self.chip : chip // ignore: cast_nullable_to_non_nullable
as String?,experimentId: freezed == experimentId ? _self.experimentId : experimentId // ignore: cast_nullable_to_non_nullable
as String?,experimentMissing: null == experimentMissing ? _self.experimentMissing : experimentMissing // ignore: cast_nullable_to_non_nullable
as bool,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nextStart: freezed == nextStart ? _self.nextStart : nextStart // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMissedStart: freezed == lastMissedStart ? _self.lastMissedStart : lastMissedStart // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMissedEnd: freezed == lastMissedEnd ? _self.lastMissedEnd : lastMissedEnd // ignore: cast_nullable_to_non_nullable
as DateTime?,upcomingCount: null == upcomingCount ? _self.upcomingCount : upcomingCount // ignore: cast_nullable_to_non_nullable
as int,needsReasonCount: null == needsReasonCount ? _self.needsReasonCount : needsReasonCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxItemFactsCopyWith<$Res> get item {
  
  return $InboxItemFactsCopyWith<$Res>(_self.item, (value) {
    return _then(_self.copyWith(item: value));
  });
}/// Create a copy of InboxIdeaView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxClosureCopyWith<$Res>? get closure {
    if (_self.closure == null) {
    return null;
  }

  return $InboxClosureCopyWith<$Res>(_self.closure!, (value) {
    return _then(_self.copyWith(closure: value));
  });
}
}

/// @nodoc
mixin _$InboxReasonsMissing {

 int get count;/// The most recent planner date among them.
 String? get latestDate;
/// Create a copy of InboxReasonsMissing
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxReasonsMissingCopyWith<InboxReasonsMissing> get copyWith => _$InboxReasonsMissingCopyWithImpl<InboxReasonsMissing>(this as InboxReasonsMissing, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxReasonsMissing&&(identical(other.count, count) || other.count == count)&&(identical(other.latestDate, latestDate) || other.latestDate == latestDate));
}


@override
int get hashCode => Object.hash(runtimeType,count,latestDate);

@override
String toString() {
  return 'InboxReasonsMissing(count: $count, latestDate: $latestDate)';
}


}

/// @nodoc
abstract mixin class $InboxReasonsMissingCopyWith<$Res>  {
  factory $InboxReasonsMissingCopyWith(InboxReasonsMissing value, $Res Function(InboxReasonsMissing) _then) = _$InboxReasonsMissingCopyWithImpl;
@useResult
$Res call({
 int count, String? latestDate
});




}
/// @nodoc
class _$InboxReasonsMissingCopyWithImpl<$Res>
    implements $InboxReasonsMissingCopyWith<$Res> {
  _$InboxReasonsMissingCopyWithImpl(this._self, this._then);

  final InboxReasonsMissing _self;
  final $Res Function(InboxReasonsMissing) _then;

/// Create a copy of InboxReasonsMissing
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? count = null,Object? latestDate = freezed,}) {
  return _then(_self.copyWith(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,latestDate: freezed == latestDate ? _self.latestDate : latestDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxReasonsMissing].
extension InboxReasonsMissingPatterns on InboxReasonsMissing {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxReasonsMissing value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxReasonsMissing() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxReasonsMissing value)  $default,){
final _that = this;
switch (_that) {
case _InboxReasonsMissing():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxReasonsMissing value)?  $default,){
final _that = this;
switch (_that) {
case _InboxReasonsMissing() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int count,  String? latestDate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxReasonsMissing() when $default != null:
return $default(_that.count,_that.latestDate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int count,  String? latestDate)  $default,) {final _that = this;
switch (_that) {
case _InboxReasonsMissing():
return $default(_that.count,_that.latestDate);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int count,  String? latestDate)?  $default,) {final _that = this;
switch (_that) {
case _InboxReasonsMissing() when $default != null:
return $default(_that.count,_that.latestDate);case _:
  return null;

}
}

}

/// @nodoc


class _InboxReasonsMissing implements InboxReasonsMissing {
  const _InboxReasonsMissing({this.count = 0, this.latestDate});
  

@override@JsonKey() final  int count;
/// The most recent planner date among them.
@override final  String? latestDate;

/// Create a copy of InboxReasonsMissing
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxReasonsMissingCopyWith<_InboxReasonsMissing> get copyWith => __$InboxReasonsMissingCopyWithImpl<_InboxReasonsMissing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxReasonsMissing&&(identical(other.count, count) || other.count == count)&&(identical(other.latestDate, latestDate) || other.latestDate == latestDate));
}


@override
int get hashCode => Object.hash(runtimeType,count,latestDate);

@override
String toString() {
  return 'InboxReasonsMissing(count: $count, latestDate: $latestDate)';
}


}

/// @nodoc
abstract mixin class _$InboxReasonsMissingCopyWith<$Res> implements $InboxReasonsMissingCopyWith<$Res> {
  factory _$InboxReasonsMissingCopyWith(_InboxReasonsMissing value, $Res Function(_InboxReasonsMissing) _then) = __$InboxReasonsMissingCopyWithImpl;
@override @useResult
$Res call({
 int count, String? latestDate
});




}
/// @nodoc
class __$InboxReasonsMissingCopyWithImpl<$Res>
    implements _$InboxReasonsMissingCopyWith<$Res> {
  __$InboxReasonsMissingCopyWithImpl(this._self, this._then);

  final _InboxReasonsMissing _self;
  final $Res Function(_InboxReasonsMissing) _then;

/// Create a copy of InboxReasonsMissing
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? count = null,Object? latestDate = freezed,}) {
  return _then(_InboxReasonsMissing(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,latestDate: freezed == latestDate ? _self.latestDate : latestDate // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$InboxBoard {

 List<String> get leftOver; List<String> get ideas; List<String> get comingUp; List<String> get done; int get openCount; int get doneCount; InboxReasonsMissing get reasonsMissing; Map<String, InboxIdeaView> get byId;/// The next moment any status can change.
 DateTime get nextBoundary;
/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxBoardCopyWith<InboxBoard> get copyWith => _$InboxBoardCopyWithImpl<InboxBoard>(this as InboxBoard, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxBoard&&const DeepCollectionEquality().equals(other.leftOver, leftOver)&&const DeepCollectionEquality().equals(other.ideas, ideas)&&const DeepCollectionEquality().equals(other.comingUp, comingUp)&&const DeepCollectionEquality().equals(other.done, done)&&(identical(other.openCount, openCount) || other.openCount == openCount)&&(identical(other.doneCount, doneCount) || other.doneCount == doneCount)&&(identical(other.reasonsMissing, reasonsMissing) || other.reasonsMissing == reasonsMissing)&&const DeepCollectionEquality().equals(other.byId, byId)&&(identical(other.nextBoundary, nextBoundary) || other.nextBoundary == nextBoundary));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(leftOver),const DeepCollectionEquality().hash(ideas),const DeepCollectionEquality().hash(comingUp),const DeepCollectionEquality().hash(done),openCount,doneCount,reasonsMissing,const DeepCollectionEquality().hash(byId),nextBoundary);

@override
String toString() {
  return 'InboxBoard(leftOver: $leftOver, ideas: $ideas, comingUp: $comingUp, done: $done, openCount: $openCount, doneCount: $doneCount, reasonsMissing: $reasonsMissing, byId: $byId, nextBoundary: $nextBoundary)';
}


}

/// @nodoc
abstract mixin class $InboxBoardCopyWith<$Res>  {
  factory $InboxBoardCopyWith(InboxBoard value, $Res Function(InboxBoard) _then) = _$InboxBoardCopyWithImpl;
@useResult
$Res call({
 List<String> leftOver, List<String> ideas, List<String> comingUp, List<String> done, int openCount, int doneCount, InboxReasonsMissing reasonsMissing, Map<String, InboxIdeaView> byId, DateTime nextBoundary
});


$InboxReasonsMissingCopyWith<$Res> get reasonsMissing;

}
/// @nodoc
class _$InboxBoardCopyWithImpl<$Res>
    implements $InboxBoardCopyWith<$Res> {
  _$InboxBoardCopyWithImpl(this._self, this._then);

  final InboxBoard _self;
  final $Res Function(InboxBoard) _then;

/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? leftOver = null,Object? ideas = null,Object? comingUp = null,Object? done = null,Object? openCount = null,Object? doneCount = null,Object? reasonsMissing = null,Object? byId = null,Object? nextBoundary = null,}) {
  return _then(_self.copyWith(
leftOver: null == leftOver ? _self.leftOver : leftOver // ignore: cast_nullable_to_non_nullable
as List<String>,ideas: null == ideas ? _self.ideas : ideas // ignore: cast_nullable_to_non_nullable
as List<String>,comingUp: null == comingUp ? _self.comingUp : comingUp // ignore: cast_nullable_to_non_nullable
as List<String>,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as List<String>,openCount: null == openCount ? _self.openCount : openCount // ignore: cast_nullable_to_non_nullable
as int,doneCount: null == doneCount ? _self.doneCount : doneCount // ignore: cast_nullable_to_non_nullable
as int,reasonsMissing: null == reasonsMissing ? _self.reasonsMissing : reasonsMissing // ignore: cast_nullable_to_non_nullable
as InboxReasonsMissing,byId: null == byId ? _self.byId : byId // ignore: cast_nullable_to_non_nullable
as Map<String, InboxIdeaView>,nextBoundary: null == nextBoundary ? _self.nextBoundary : nextBoundary // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}
/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxReasonsMissingCopyWith<$Res> get reasonsMissing {
  
  return $InboxReasonsMissingCopyWith<$Res>(_self.reasonsMissing, (value) {
    return _then(_self.copyWith(reasonsMissing: value));
  });
}
}


/// Adds pattern-matching-related methods to [InboxBoard].
extension InboxBoardPatterns on InboxBoard {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxBoard value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxBoard() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxBoard value)  $default,){
final _that = this;
switch (_that) {
case _InboxBoard():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxBoard value)?  $default,){
final _that = this;
switch (_that) {
case _InboxBoard() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> leftOver,  List<String> ideas,  List<String> comingUp,  List<String> done,  int openCount,  int doneCount,  InboxReasonsMissing reasonsMissing,  Map<String, InboxIdeaView> byId,  DateTime nextBoundary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxBoard() when $default != null:
return $default(_that.leftOver,_that.ideas,_that.comingUp,_that.done,_that.openCount,_that.doneCount,_that.reasonsMissing,_that.byId,_that.nextBoundary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> leftOver,  List<String> ideas,  List<String> comingUp,  List<String> done,  int openCount,  int doneCount,  InboxReasonsMissing reasonsMissing,  Map<String, InboxIdeaView> byId,  DateTime nextBoundary)  $default,) {final _that = this;
switch (_that) {
case _InboxBoard():
return $default(_that.leftOver,_that.ideas,_that.comingUp,_that.done,_that.openCount,_that.doneCount,_that.reasonsMissing,_that.byId,_that.nextBoundary);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> leftOver,  List<String> ideas,  List<String> comingUp,  List<String> done,  int openCount,  int doneCount,  InboxReasonsMissing reasonsMissing,  Map<String, InboxIdeaView> byId,  DateTime nextBoundary)?  $default,) {final _that = this;
switch (_that) {
case _InboxBoard() when $default != null:
return $default(_that.leftOver,_that.ideas,_that.comingUp,_that.done,_that.openCount,_that.doneCount,_that.reasonsMissing,_that.byId,_that.nextBoundary);case _:
  return null;

}
}

}

/// @nodoc


class _InboxBoard implements InboxBoard {
  const _InboxBoard({this.leftOver = const <String>[], this.ideas = const <String>[], this.comingUp = const <String>[], this.done = const <String>[], this.openCount = 0, this.doneCount = 0, this.reasonsMissing = const InboxReasonsMissing(), this.byId = const <String, InboxIdeaView>{}, required this.nextBoundary});
  

@override@JsonKey() final  List<String> leftOver;
@override@JsonKey() final  List<String> ideas;
@override@JsonKey() final  List<String> comingUp;
@override@JsonKey() final  List<String> done;
@override@JsonKey() final  int openCount;
@override@JsonKey() final  int doneCount;
@override@JsonKey() final  InboxReasonsMissing reasonsMissing;
@override@JsonKey() final  Map<String, InboxIdeaView> byId;
/// The next moment any status can change.
@override final  DateTime nextBoundary;

/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxBoardCopyWith<_InboxBoard> get copyWith => __$InboxBoardCopyWithImpl<_InboxBoard>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxBoard&&const DeepCollectionEquality().equals(other.leftOver, leftOver)&&const DeepCollectionEquality().equals(other.ideas, ideas)&&const DeepCollectionEquality().equals(other.comingUp, comingUp)&&const DeepCollectionEquality().equals(other.done, done)&&(identical(other.openCount, openCount) || other.openCount == openCount)&&(identical(other.doneCount, doneCount) || other.doneCount == doneCount)&&(identical(other.reasonsMissing, reasonsMissing) || other.reasonsMissing == reasonsMissing)&&const DeepCollectionEquality().equals(other.byId, byId)&&(identical(other.nextBoundary, nextBoundary) || other.nextBoundary == nextBoundary));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(leftOver),const DeepCollectionEquality().hash(ideas),const DeepCollectionEquality().hash(comingUp),const DeepCollectionEquality().hash(done),openCount,doneCount,reasonsMissing,const DeepCollectionEquality().hash(byId),nextBoundary);

@override
String toString() {
  return 'InboxBoard(leftOver: $leftOver, ideas: $ideas, comingUp: $comingUp, done: $done, openCount: $openCount, doneCount: $doneCount, reasonsMissing: $reasonsMissing, byId: $byId, nextBoundary: $nextBoundary)';
}


}

/// @nodoc
abstract mixin class _$InboxBoardCopyWith<$Res> implements $InboxBoardCopyWith<$Res> {
  factory _$InboxBoardCopyWith(_InboxBoard value, $Res Function(_InboxBoard) _then) = __$InboxBoardCopyWithImpl;
@override @useResult
$Res call({
 List<String> leftOver, List<String> ideas, List<String> comingUp, List<String> done, int openCount, int doneCount, InboxReasonsMissing reasonsMissing, Map<String, InboxIdeaView> byId, DateTime nextBoundary
});


@override $InboxReasonsMissingCopyWith<$Res> get reasonsMissing;

}
/// @nodoc
class __$InboxBoardCopyWithImpl<$Res>
    implements _$InboxBoardCopyWith<$Res> {
  __$InboxBoardCopyWithImpl(this._self, this._then);

  final _InboxBoard _self;
  final $Res Function(_InboxBoard) _then;

/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? leftOver = null,Object? ideas = null,Object? comingUp = null,Object? done = null,Object? openCount = null,Object? doneCount = null,Object? reasonsMissing = null,Object? byId = null,Object? nextBoundary = null,}) {
  return _then(_InboxBoard(
leftOver: null == leftOver ? _self.leftOver : leftOver // ignore: cast_nullable_to_non_nullable
as List<String>,ideas: null == ideas ? _self.ideas : ideas // ignore: cast_nullable_to_non_nullable
as List<String>,comingUp: null == comingUp ? _self.comingUp : comingUp // ignore: cast_nullable_to_non_nullable
as List<String>,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as List<String>,openCount: null == openCount ? _self.openCount : openCount // ignore: cast_nullable_to_non_nullable
as int,doneCount: null == doneCount ? _self.doneCount : doneCount // ignore: cast_nullable_to_non_nullable
as int,reasonsMissing: null == reasonsMissing ? _self.reasonsMissing : reasonsMissing // ignore: cast_nullable_to_non_nullable
as InboxReasonsMissing,byId: null == byId ? _self.byId : byId // ignore: cast_nullable_to_non_nullable
as Map<String, InboxIdeaView>,nextBoundary: null == nextBoundary ? _self.nextBoundary : nextBoundary // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

/// Create a copy of InboxBoard
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InboxReasonsMissingCopyWith<$Res> get reasonsMissing {
  
  return $InboxReasonsMissingCopyWith<$Res>(_self.reasonsMissing, (value) {
    return _then(_self.copyWith(reasonsMissing: value));
  });
}
}

// dart format on
