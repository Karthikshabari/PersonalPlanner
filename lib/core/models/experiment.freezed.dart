// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'experiment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExperimentExtension {

 String get reason;@JsonKey(name: 'previous_end_date') String get previousEndDate;@JsonKey(name: 'new_end_date') String get newEndDate;@JsonKey(name: 'made_on') String get madeOn;
/// Create a copy of ExperimentExtension
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExperimentExtensionCopyWith<ExperimentExtension> get copyWith => _$ExperimentExtensionCopyWithImpl<ExperimentExtension>(this as ExperimentExtension, _$identity);

  /// Serializes this ExperimentExtension to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExperimentExtension&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.previousEndDate, previousEndDate) || other.previousEndDate == previousEndDate)&&(identical(other.newEndDate, newEndDate) || other.newEndDate == newEndDate)&&(identical(other.madeOn, madeOn) || other.madeOn == madeOn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,reason,previousEndDate,newEndDate,madeOn);

@override
String toString() {
  return 'ExperimentExtension(reason: $reason, previousEndDate: $previousEndDate, newEndDate: $newEndDate, madeOn: $madeOn)';
}


}

/// @nodoc
abstract mixin class $ExperimentExtensionCopyWith<$Res>  {
  factory $ExperimentExtensionCopyWith(ExperimentExtension value, $Res Function(ExperimentExtension) _then) = _$ExperimentExtensionCopyWithImpl;
@useResult
$Res call({
 String reason,@JsonKey(name: 'previous_end_date') String previousEndDate,@JsonKey(name: 'new_end_date') String newEndDate,@JsonKey(name: 'made_on') String madeOn
});




}
/// @nodoc
class _$ExperimentExtensionCopyWithImpl<$Res>
    implements $ExperimentExtensionCopyWith<$Res> {
  _$ExperimentExtensionCopyWithImpl(this._self, this._then);

  final ExperimentExtension _self;
  final $Res Function(ExperimentExtension) _then;

/// Create a copy of ExperimentExtension
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reason = null,Object? previousEndDate = null,Object? newEndDate = null,Object? madeOn = null,}) {
  return _then(_self.copyWith(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,previousEndDate: null == previousEndDate ? _self.previousEndDate : previousEndDate // ignore: cast_nullable_to_non_nullable
as String,newEndDate: null == newEndDate ? _self.newEndDate : newEndDate // ignore: cast_nullable_to_non_nullable
as String,madeOn: null == madeOn ? _self.madeOn : madeOn // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ExperimentExtension].
extension ExperimentExtensionPatterns on ExperimentExtension {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExperimentExtension value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExperimentExtension() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExperimentExtension value)  $default,){
final _that = this;
switch (_that) {
case _ExperimentExtension():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExperimentExtension value)?  $default,){
final _that = this;
switch (_that) {
case _ExperimentExtension() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String reason, @JsonKey(name: 'previous_end_date')  String previousEndDate, @JsonKey(name: 'new_end_date')  String newEndDate, @JsonKey(name: 'made_on')  String madeOn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExperimentExtension() when $default != null:
return $default(_that.reason,_that.previousEndDate,_that.newEndDate,_that.madeOn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String reason, @JsonKey(name: 'previous_end_date')  String previousEndDate, @JsonKey(name: 'new_end_date')  String newEndDate, @JsonKey(name: 'made_on')  String madeOn)  $default,) {final _that = this;
switch (_that) {
case _ExperimentExtension():
return $default(_that.reason,_that.previousEndDate,_that.newEndDate,_that.madeOn);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String reason, @JsonKey(name: 'previous_end_date')  String previousEndDate, @JsonKey(name: 'new_end_date')  String newEndDate, @JsonKey(name: 'made_on')  String madeOn)?  $default,) {final _that = this;
switch (_that) {
case _ExperimentExtension() when $default != null:
return $default(_that.reason,_that.previousEndDate,_that.newEndDate,_that.madeOn);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExperimentExtension implements ExperimentExtension {
  const _ExperimentExtension({required this.reason, @JsonKey(name: 'previous_end_date') required this.previousEndDate, @JsonKey(name: 'new_end_date') required this.newEndDate, @JsonKey(name: 'made_on') required this.madeOn});
  factory _ExperimentExtension.fromJson(Map<String, dynamic> json) => _$ExperimentExtensionFromJson(json);

@override final  String reason;
@override@JsonKey(name: 'previous_end_date') final  String previousEndDate;
@override@JsonKey(name: 'new_end_date') final  String newEndDate;
@override@JsonKey(name: 'made_on') final  String madeOn;

/// Create a copy of ExperimentExtension
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExperimentExtensionCopyWith<_ExperimentExtension> get copyWith => __$ExperimentExtensionCopyWithImpl<_ExperimentExtension>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExperimentExtensionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExperimentExtension&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.previousEndDate, previousEndDate) || other.previousEndDate == previousEndDate)&&(identical(other.newEndDate, newEndDate) || other.newEndDate == newEndDate)&&(identical(other.madeOn, madeOn) || other.madeOn == madeOn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,reason,previousEndDate,newEndDate,madeOn);

@override
String toString() {
  return 'ExperimentExtension(reason: $reason, previousEndDate: $previousEndDate, newEndDate: $newEndDate, madeOn: $madeOn)';
}


}

/// @nodoc
abstract mixin class _$ExperimentExtensionCopyWith<$Res> implements $ExperimentExtensionCopyWith<$Res> {
  factory _$ExperimentExtensionCopyWith(_ExperimentExtension value, $Res Function(_ExperimentExtension) _then) = __$ExperimentExtensionCopyWithImpl;
@override @useResult
$Res call({
 String reason,@JsonKey(name: 'previous_end_date') String previousEndDate,@JsonKey(name: 'new_end_date') String newEndDate,@JsonKey(name: 'made_on') String madeOn
});




}
/// @nodoc
class __$ExperimentExtensionCopyWithImpl<$Res>
    implements _$ExperimentExtensionCopyWith<$Res> {
  __$ExperimentExtensionCopyWithImpl(this._self, this._then);

  final _ExperimentExtension _self;
  final $Res Function(_ExperimentExtension) _then;

/// Create a copy of ExperimentExtension
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? previousEndDate = null,Object? newEndDate = null,Object? madeOn = null,}) {
  return _then(_ExperimentExtension(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,previousEndDate: null == previousEndDate ? _self.previousEndDate : previousEndDate // ignore: cast_nullable_to_non_nullable
as String,newEndDate: null == newEndDate ? _self.newEndDate : newEndDate // ignore: cast_nullable_to_non_nullable
as String,madeOn: null == madeOn ? _self.madeOn : madeOn // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$Experiment {

 String get id; String get tagId; String get tagName; String? get purpose; String get startDate; String get endDate; int get weekdayTargetMin; int get weekendTargetMin; int get checkInEveryDays; ExperimentStatus get status; List<ExperimentExtension> get extensions; ExperimentOutcome? get outcome; String? get conclusionNote; String? get concludedOn; DateTime get createdAt; DateTime get updatedAt; int get revision;
/// Create a copy of Experiment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExperimentCopyWith<Experiment> get copyWith => _$ExperimentCopyWithImpl<Experiment>(this as Experiment, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Experiment&&(identical(other.id, id) || other.id == id)&&(identical(other.tagId, tagId) || other.tagId == tagId)&&(identical(other.tagName, tagName) || other.tagName == tagName)&&(identical(other.purpose, purpose) || other.purpose == purpose)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.weekdayTargetMin, weekdayTargetMin) || other.weekdayTargetMin == weekdayTargetMin)&&(identical(other.weekendTargetMin, weekendTargetMin) || other.weekendTargetMin == weekendTargetMin)&&(identical(other.checkInEveryDays, checkInEveryDays) || other.checkInEveryDays == checkInEveryDays)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.extensions, extensions)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.conclusionNote, conclusionNote) || other.conclusionNote == conclusionNote)&&(identical(other.concludedOn, concludedOn) || other.concludedOn == concludedOn)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode => Object.hash(runtimeType,id,tagId,tagName,purpose,startDate,endDate,weekdayTargetMin,weekendTargetMin,checkInEveryDays,status,const DeepCollectionEquality().hash(extensions),outcome,conclusionNote,concludedOn,createdAt,updatedAt,revision);

@override
String toString() {
  return 'Experiment(id: $id, tagId: $tagId, tagName: $tagName, purpose: $purpose, startDate: $startDate, endDate: $endDate, weekdayTargetMin: $weekdayTargetMin, weekendTargetMin: $weekendTargetMin, checkInEveryDays: $checkInEveryDays, status: $status, extensions: $extensions, outcome: $outcome, conclusionNote: $conclusionNote, concludedOn: $concludedOn, createdAt: $createdAt, updatedAt: $updatedAt, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $ExperimentCopyWith<$Res>  {
  factory $ExperimentCopyWith(Experiment value, $Res Function(Experiment) _then) = _$ExperimentCopyWithImpl;
@useResult
$Res call({
 String id, String tagId, String tagName, String? purpose, String startDate, String endDate, int weekdayTargetMin, int weekendTargetMin, int checkInEveryDays, ExperimentStatus status, List<ExperimentExtension> extensions, ExperimentOutcome? outcome, String? conclusionNote, String? concludedOn, DateTime createdAt, DateTime updatedAt, int revision
});




}
/// @nodoc
class _$ExperimentCopyWithImpl<$Res>
    implements $ExperimentCopyWith<$Res> {
  _$ExperimentCopyWithImpl(this._self, this._then);

  final Experiment _self;
  final $Res Function(Experiment) _then;

/// Create a copy of Experiment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? tagId = null,Object? tagName = null,Object? purpose = freezed,Object? startDate = null,Object? endDate = null,Object? weekdayTargetMin = null,Object? weekendTargetMin = null,Object? checkInEveryDays = null,Object? status = null,Object? extensions = null,Object? outcome = freezed,Object? conclusionNote = freezed,Object? concludedOn = freezed,Object? createdAt = null,Object? updatedAt = null,Object? revision = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,tagId: null == tagId ? _self.tagId : tagId // ignore: cast_nullable_to_non_nullable
as String,tagName: null == tagName ? _self.tagName : tagName // ignore: cast_nullable_to_non_nullable
as String,purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as String?,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as String,weekdayTargetMin: null == weekdayTargetMin ? _self.weekdayTargetMin : weekdayTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekendTargetMin: null == weekendTargetMin ? _self.weekendTargetMin : weekendTargetMin // ignore: cast_nullable_to_non_nullable
as int,checkInEveryDays: null == checkInEveryDays ? _self.checkInEveryDays : checkInEveryDays // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ExperimentStatus,extensions: null == extensions ? _self.extensions : extensions // ignore: cast_nullable_to_non_nullable
as List<ExperimentExtension>,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ExperimentOutcome?,conclusionNote: freezed == conclusionNote ? _self.conclusionNote : conclusionNote // ignore: cast_nullable_to_non_nullable
as String?,concludedOn: freezed == concludedOn ? _self.concludedOn : concludedOn // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Experiment].
extension ExperimentPatterns on Experiment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Experiment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Experiment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Experiment value)  $default,){
final _that = this;
switch (_that) {
case _Experiment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Experiment value)?  $default,){
final _that = this;
switch (_that) {
case _Experiment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String tagId,  String tagName,  String? purpose,  String startDate,  String endDate,  int weekdayTargetMin,  int weekendTargetMin,  int checkInEveryDays,  ExperimentStatus status,  List<ExperimentExtension> extensions,  ExperimentOutcome? outcome,  String? conclusionNote,  String? concludedOn,  DateTime createdAt,  DateTime updatedAt,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Experiment() when $default != null:
return $default(_that.id,_that.tagId,_that.tagName,_that.purpose,_that.startDate,_that.endDate,_that.weekdayTargetMin,_that.weekendTargetMin,_that.checkInEveryDays,_that.status,_that.extensions,_that.outcome,_that.conclusionNote,_that.concludedOn,_that.createdAt,_that.updatedAt,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String tagId,  String tagName,  String? purpose,  String startDate,  String endDate,  int weekdayTargetMin,  int weekendTargetMin,  int checkInEveryDays,  ExperimentStatus status,  List<ExperimentExtension> extensions,  ExperimentOutcome? outcome,  String? conclusionNote,  String? concludedOn,  DateTime createdAt,  DateTime updatedAt,  int revision)  $default,) {final _that = this;
switch (_that) {
case _Experiment():
return $default(_that.id,_that.tagId,_that.tagName,_that.purpose,_that.startDate,_that.endDate,_that.weekdayTargetMin,_that.weekendTargetMin,_that.checkInEveryDays,_that.status,_that.extensions,_that.outcome,_that.conclusionNote,_that.concludedOn,_that.createdAt,_that.updatedAt,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String tagId,  String tagName,  String? purpose,  String startDate,  String endDate,  int weekdayTargetMin,  int weekendTargetMin,  int checkInEveryDays,  ExperimentStatus status,  List<ExperimentExtension> extensions,  ExperimentOutcome? outcome,  String? conclusionNote,  String? concludedOn,  DateTime createdAt,  DateTime updatedAt,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _Experiment() when $default != null:
return $default(_that.id,_that.tagId,_that.tagName,_that.purpose,_that.startDate,_that.endDate,_that.weekdayTargetMin,_that.weekendTargetMin,_that.checkInEveryDays,_that.status,_that.extensions,_that.outcome,_that.conclusionNote,_that.concludedOn,_that.createdAt,_that.updatedAt,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _Experiment implements Experiment {
  const _Experiment({required this.id, required this.tagId, required this.tagName, this.purpose, required this.startDate, required this.endDate, required this.weekdayTargetMin, required this.weekendTargetMin, required this.checkInEveryDays, required this.status, this.extensions = const <ExperimentExtension>[], this.outcome, this.conclusionNote, this.concludedOn, required this.createdAt, required this.updatedAt, this.revision = 1});
  

@override final  String id;
@override final  String tagId;
@override final  String tagName;
@override final  String? purpose;
@override final  String startDate;
@override final  String endDate;
@override final  int weekdayTargetMin;
@override final  int weekendTargetMin;
@override final  int checkInEveryDays;
@override final  ExperimentStatus status;
@override@JsonKey() final  List<ExperimentExtension> extensions;
@override final  ExperimentOutcome? outcome;
@override final  String? conclusionNote;
@override final  String? concludedOn;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  int revision;

/// Create a copy of Experiment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExperimentCopyWith<_Experiment> get copyWith => __$ExperimentCopyWithImpl<_Experiment>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Experiment&&(identical(other.id, id) || other.id == id)&&(identical(other.tagId, tagId) || other.tagId == tagId)&&(identical(other.tagName, tagName) || other.tagName == tagName)&&(identical(other.purpose, purpose) || other.purpose == purpose)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.weekdayTargetMin, weekdayTargetMin) || other.weekdayTargetMin == weekdayTargetMin)&&(identical(other.weekendTargetMin, weekendTargetMin) || other.weekendTargetMin == weekendTargetMin)&&(identical(other.checkInEveryDays, checkInEveryDays) || other.checkInEveryDays == checkInEveryDays)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.extensions, extensions)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.conclusionNote, conclusionNote) || other.conclusionNote == conclusionNote)&&(identical(other.concludedOn, concludedOn) || other.concludedOn == concludedOn)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode => Object.hash(runtimeType,id,tagId,tagName,purpose,startDate,endDate,weekdayTargetMin,weekendTargetMin,checkInEveryDays,status,const DeepCollectionEquality().hash(extensions),outcome,conclusionNote,concludedOn,createdAt,updatedAt,revision);

@override
String toString() {
  return 'Experiment(id: $id, tagId: $tagId, tagName: $tagName, purpose: $purpose, startDate: $startDate, endDate: $endDate, weekdayTargetMin: $weekdayTargetMin, weekendTargetMin: $weekendTargetMin, checkInEveryDays: $checkInEveryDays, status: $status, extensions: $extensions, outcome: $outcome, conclusionNote: $conclusionNote, concludedOn: $concludedOn, createdAt: $createdAt, updatedAt: $updatedAt, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ExperimentCopyWith<$Res> implements $ExperimentCopyWith<$Res> {
  factory _$ExperimentCopyWith(_Experiment value, $Res Function(_Experiment) _then) = __$ExperimentCopyWithImpl;
@override @useResult
$Res call({
 String id, String tagId, String tagName, String? purpose, String startDate, String endDate, int weekdayTargetMin, int weekendTargetMin, int checkInEveryDays, ExperimentStatus status, List<ExperimentExtension> extensions, ExperimentOutcome? outcome, String? conclusionNote, String? concludedOn, DateTime createdAt, DateTime updatedAt, int revision
});




}
/// @nodoc
class __$ExperimentCopyWithImpl<$Res>
    implements _$ExperimentCopyWith<$Res> {
  __$ExperimentCopyWithImpl(this._self, this._then);

  final _Experiment _self;
  final $Res Function(_Experiment) _then;

/// Create a copy of Experiment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? tagId = null,Object? tagName = null,Object? purpose = freezed,Object? startDate = null,Object? endDate = null,Object? weekdayTargetMin = null,Object? weekendTargetMin = null,Object? checkInEveryDays = null,Object? status = null,Object? extensions = null,Object? outcome = freezed,Object? conclusionNote = freezed,Object? concludedOn = freezed,Object? createdAt = null,Object? updatedAt = null,Object? revision = null,}) {
  return _then(_Experiment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,tagId: null == tagId ? _self.tagId : tagId // ignore: cast_nullable_to_non_nullable
as String,tagName: null == tagName ? _self.tagName : tagName // ignore: cast_nullable_to_non_nullable
as String,purpose: freezed == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as String?,startDate: null == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as String,endDate: null == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as String,weekdayTargetMin: null == weekdayTargetMin ? _self.weekdayTargetMin : weekdayTargetMin // ignore: cast_nullable_to_non_nullable
as int,weekendTargetMin: null == weekendTargetMin ? _self.weekendTargetMin : weekendTargetMin // ignore: cast_nullable_to_non_nullable
as int,checkInEveryDays: null == checkInEveryDays ? _self.checkInEveryDays : checkInEveryDays // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ExperimentStatus,extensions: null == extensions ? _self.extensions : extensions // ignore: cast_nullable_to_non_nullable
as List<ExperimentExtension>,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ExperimentOutcome?,conclusionNote: freezed == conclusionNote ? _self.conclusionNote : conclusionNote // ignore: cast_nullable_to_non_nullable
as String?,concludedOn: freezed == concludedOn ? _self.concludedOn : concludedOn // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
