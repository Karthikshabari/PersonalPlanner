// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InboxExperimentFacts {

 String get id; String get name; String get startDate; String get endDate; ExperimentStatus get status; ExperimentOutcome? get outcome; String? get concludedOn; DateTime? get retiredAt; DateTime? get deletedAt;
/// Create a copy of InboxExperimentFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxExperimentFactsCopyWith<InboxExperimentFacts> get copyWith => _$InboxExperimentFactsCopyWithImpl<InboxExperimentFacts>(this as InboxExperimentFacts, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxExperimentFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.concludedOn, concludedOn) || other.concludedOn == concludedOn)&&(identical(other.retiredAt, retiredAt) || other.retiredAt == retiredAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,startDate,endDate,status,outcome,concludedOn,retiredAt,deletedAt);

@override
String toString() {
  return 'InboxExperimentFacts(id: $id, name: $name, startDate: $startDate, endDate: $endDate, status: $status, outcome: $outcome, concludedOn: $concludedOn, retiredAt: $retiredAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $InboxExperimentFactsCopyWith<$Res>  {
  factory $InboxExperimentFactsCopyWith(InboxExperimentFacts value, $Res Function(InboxExperimentFacts) _then) = _$InboxExperimentFactsCopyWithImpl;
@useResult
$Res call({
 String id, String name, String startDate, String endDate, ExperimentStatus status, ExperimentOutcome? outcome, String? concludedOn, DateTime? retiredAt, DateTime? deletedAt
});




}
/// @nodoc
class _$InboxExperimentFactsCopyWithImpl<$Res>
    implements $InboxExperimentFactsCopyWith<$Res> {
  _$InboxExperimentFactsCopyWithImpl(this._self, this._then);

  final InboxExperimentFacts _self;
  final $Res Function(InboxExperimentFacts) _then;

/// Create a copy of InboxExperimentFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? startDate = null,Object? endDate = null,Object? status = null,Object? outcome = freezed,Object? concludedOn = freezed,Object? retiredAt = freezed,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ExperimentStatus,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ExperimentOutcome?,concludedOn: freezed == concludedOn ? _self.concludedOn : concludedOn // ignore: cast_nullable_to_non_nullable
as String?,retiredAt: freezed == retiredAt ? _self.retiredAt : retiredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxExperimentFacts].
extension InboxExperimentFactsPatterns on InboxExperimentFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxExperimentFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxExperimentFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxExperimentFacts value)  $default,){
final _that = this;
switch (_that) {
case _InboxExperimentFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxExperimentFacts value)?  $default,){
final _that = this;
switch (_that) {
case _InboxExperimentFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String startDate,  String endDate,  ExperimentStatus status,  ExperimentOutcome? outcome,  String? concludedOn,  DateTime? retiredAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxExperimentFacts() when $default != null:
return $default(_that.id,_that.name,_that.startDate,_that.endDate,_that.status,_that.outcome,_that.concludedOn,_that.retiredAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String startDate,  String endDate,  ExperimentStatus status,  ExperimentOutcome? outcome,  String? concludedOn,  DateTime? retiredAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _InboxExperimentFacts():
return $default(_that.id,_that.name,_that.startDate,_that.endDate,_that.status,_that.outcome,_that.concludedOn,_that.retiredAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String startDate,  String endDate,  ExperimentStatus status,  ExperimentOutcome? outcome,  String? concludedOn,  DateTime? retiredAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _InboxExperimentFacts() when $default != null:
return $default(_that.id,_that.name,_that.startDate,_that.endDate,_that.status,_that.outcome,_that.concludedOn,_that.retiredAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _InboxExperimentFacts implements InboxExperimentFacts {
  const _InboxExperimentFacts({required this.id, required this.name, required this.startDate, required this.endDate, required this.status, this.outcome, this.concludedOn, this.retiredAt, this.deletedAt});
  

@override final  String id;
@override final  String name;
@override final  String startDate;
@override final  String endDate;
@override final  ExperimentStatus status;
@override final  ExperimentOutcome? outcome;
@override final  String? concludedOn;
@override final  DateTime? retiredAt;
@override final  DateTime? deletedAt;

/// Create a copy of InboxExperimentFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxExperimentFactsCopyWith<_InboxExperimentFacts> get copyWith => __$InboxExperimentFactsCopyWithImpl<_InboxExperimentFacts>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxExperimentFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.concludedOn, concludedOn) || other.concludedOn == concludedOn)&&(identical(other.retiredAt, retiredAt) || other.retiredAt == retiredAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,startDate,endDate,status,outcome,concludedOn,retiredAt,deletedAt);

@override
String toString() {
  return 'InboxExperimentFacts(id: $id, name: $name, startDate: $startDate, endDate: $endDate, status: $status, outcome: $outcome, concludedOn: $concludedOn, retiredAt: $retiredAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$InboxExperimentFactsCopyWith<$Res> implements $InboxExperimentFactsCopyWith<$Res> {
  factory _$InboxExperimentFactsCopyWith(_InboxExperimentFacts value, $Res Function(_InboxExperimentFacts) _then) = __$InboxExperimentFactsCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String startDate, String endDate, ExperimentStatus status, ExperimentOutcome? outcome, String? concludedOn, DateTime? retiredAt, DateTime? deletedAt
});




}
/// @nodoc
class __$InboxExperimentFactsCopyWithImpl<$Res>
    implements _$InboxExperimentFactsCopyWith<$Res> {
  __$InboxExperimentFactsCopyWithImpl(this._self, this._then);

  final _InboxExperimentFacts _self;
  final $Res Function(_InboxExperimentFacts) _then;

/// Create a copy of InboxExperimentFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? startDate = null,Object? endDate = null,Object? status = null,Object? outcome = freezed,Object? concludedOn = freezed,Object? retiredAt = freezed,Object? deletedAt = freezed,}) {
  return _then(_InboxExperimentFacts(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ExperimentStatus,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ExperimentOutcome?,concludedOn: freezed == concludedOn ? _self.concludedOn : concludedOn // ignore: cast_nullable_to_non_nullable
as String?,retiredAt: freezed == retiredAt ? _self.retiredAt : retiredAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$InboxSource {

/// Open and closed ideas (`is_inbox = 1`, not deleted).
 List<InboxItemFacts> get items;/// Every row with an `inbox_item_id`, deleted ones included.
 List<InboxSessionFacts> get sessions;/// Saved Review reasons (trimmed, non-blank) by session id. Read from
/// `daily_reviews.task_reasons_json` for the planner date of each session
/// that is not done. Unsaved drafts are not here.
 Map<String, String> get reasons;/// Experiments named in an idea's history, by id. A missing key means the
/// experiment row is gone.
 Map<String, InboxExperimentFacts> get experiments;
/// Create a copy of InboxSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxSourceCopyWith<InboxSource> get copyWith => _$InboxSourceCopyWithImpl<InboxSource>(this as InboxSource, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxSource&&const DeepCollectionEquality().equals(other.items, items)&&const DeepCollectionEquality().equals(other.sessions, sessions)&&const DeepCollectionEquality().equals(other.reasons, reasons)&&const DeepCollectionEquality().equals(other.experiments, experiments));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),const DeepCollectionEquality().hash(sessions),const DeepCollectionEquality().hash(reasons),const DeepCollectionEquality().hash(experiments));

@override
String toString() {
  return 'InboxSource(items: $items, sessions: $sessions, reasons: $reasons, experiments: $experiments)';
}


}

/// @nodoc
abstract mixin class $InboxSourceCopyWith<$Res>  {
  factory $InboxSourceCopyWith(InboxSource value, $Res Function(InboxSource) _then) = _$InboxSourceCopyWithImpl;
@useResult
$Res call({
 List<InboxItemFacts> items, List<InboxSessionFacts> sessions, Map<String, String> reasons, Map<String, InboxExperimentFacts> experiments
});




}
/// @nodoc
class _$InboxSourceCopyWithImpl<$Res>
    implements $InboxSourceCopyWith<$Res> {
  _$InboxSourceCopyWithImpl(this._self, this._then);

  final InboxSource _self;
  final $Res Function(InboxSource) _then;

/// Create a copy of InboxSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? sessions = null,Object? reasons = null,Object? experiments = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<InboxItemFacts>,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<InboxSessionFacts>,reasons: null == reasons ? _self.reasons : reasons // ignore: cast_nullable_to_non_nullable
as Map<String, String>,experiments: null == experiments ? _self.experiments : experiments // ignore: cast_nullable_to_non_nullable
as Map<String, InboxExperimentFacts>,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxSource].
extension InboxSourcePatterns on InboxSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxSource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxSource value)  $default,){
final _that = this;
switch (_that) {
case _InboxSource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxSource value)?  $default,){
final _that = this;
switch (_that) {
case _InboxSource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<InboxItemFacts> items,  List<InboxSessionFacts> sessions,  Map<String, String> reasons,  Map<String, InboxExperimentFacts> experiments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxSource() when $default != null:
return $default(_that.items,_that.sessions,_that.reasons,_that.experiments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<InboxItemFacts> items,  List<InboxSessionFacts> sessions,  Map<String, String> reasons,  Map<String, InboxExperimentFacts> experiments)  $default,) {final _that = this;
switch (_that) {
case _InboxSource():
return $default(_that.items,_that.sessions,_that.reasons,_that.experiments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<InboxItemFacts> items,  List<InboxSessionFacts> sessions,  Map<String, String> reasons,  Map<String, InboxExperimentFacts> experiments)?  $default,) {final _that = this;
switch (_that) {
case _InboxSource() when $default != null:
return $default(_that.items,_that.sessions,_that.reasons,_that.experiments);case _:
  return null;

}
}

}

/// @nodoc


class _InboxSource implements InboxSource {
  const _InboxSource({this.items = const <InboxItemFacts>[], this.sessions = const <InboxSessionFacts>[], this.reasons = const <String, String>{}, this.experiments = const <String, InboxExperimentFacts>{}});
  

/// Open and closed ideas (`is_inbox = 1`, not deleted).
@override@JsonKey() final  List<InboxItemFacts> items;
/// Every row with an `inbox_item_id`, deleted ones included.
@override@JsonKey() final  List<InboxSessionFacts> sessions;
/// Saved Review reasons (trimmed, non-blank) by session id. Read from
/// `daily_reviews.task_reasons_json` for the planner date of each session
/// that is not done. Unsaved drafts are not here.
@override@JsonKey() final  Map<String, String> reasons;
/// Experiments named in an idea's history, by id. A missing key means the
/// experiment row is gone.
@override@JsonKey() final  Map<String, InboxExperimentFacts> experiments;

/// Create a copy of InboxSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxSourceCopyWith<_InboxSource> get copyWith => __$InboxSourceCopyWithImpl<_InboxSource>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxSource&&const DeepCollectionEquality().equals(other.items, items)&&const DeepCollectionEquality().equals(other.sessions, sessions)&&const DeepCollectionEquality().equals(other.reasons, reasons)&&const DeepCollectionEquality().equals(other.experiments, experiments));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),const DeepCollectionEquality().hash(sessions),const DeepCollectionEquality().hash(reasons),const DeepCollectionEquality().hash(experiments));

@override
String toString() {
  return 'InboxSource(items: $items, sessions: $sessions, reasons: $reasons, experiments: $experiments)';
}


}

/// @nodoc
abstract mixin class _$InboxSourceCopyWith<$Res> implements $InboxSourceCopyWith<$Res> {
  factory _$InboxSourceCopyWith(_InboxSource value, $Res Function(_InboxSource) _then) = __$InboxSourceCopyWithImpl;
@override @useResult
$Res call({
 List<InboxItemFacts> items, List<InboxSessionFacts> sessions, Map<String, String> reasons, Map<String, InboxExperimentFacts> experiments
});




}
/// @nodoc
class __$InboxSourceCopyWithImpl<$Res>
    implements _$InboxSourceCopyWith<$Res> {
  __$InboxSourceCopyWithImpl(this._self, this._then);

  final _InboxSource _self;
  final $Res Function(_InboxSource) _then;

/// Create a copy of InboxSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? sessions = null,Object? reasons = null,Object? experiments = null,}) {
  return _then(_InboxSource(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<InboxItemFacts>,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<InboxSessionFacts>,reasons: null == reasons ? _self.reasons : reasons // ignore: cast_nullable_to_non_nullable
as Map<String, String>,experiments: null == experiments ? _self.experiments : experiments // ignore: cast_nullable_to_non_nullable
as Map<String, InboxExperimentFacts>,
  ));
}


}

// dart format on
