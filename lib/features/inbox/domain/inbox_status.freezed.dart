// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InboxSessionFacts {

 String get id; String get itemId; String get title; DateTime? get start; DateTime? get end; TaskStatus get status; DateTime? get deletedAt; DateTime get createdAt;
/// Create a copy of InboxSessionFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxSessionFactsCopyWith<InboxSessionFacts> get copyWith => _$InboxSessionFactsCopyWithImpl<InboxSessionFacts>(this as InboxSessionFacts, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxSessionFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.title, title) || other.title == title)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.status, status) || other.status == status)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,itemId,title,start,end,status,deletedAt,createdAt);

@override
String toString() {
  return 'InboxSessionFacts(id: $id, itemId: $itemId, title: $title, start: $start, end: $end, status: $status, deletedAt: $deletedAt, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $InboxSessionFactsCopyWith<$Res>  {
  factory $InboxSessionFactsCopyWith(InboxSessionFacts value, $Res Function(InboxSessionFacts) _then) = _$InboxSessionFactsCopyWithImpl;
@useResult
$Res call({
 String id, String itemId, String title, DateTime? start, DateTime? end, TaskStatus status, DateTime? deletedAt, DateTime createdAt
});




}
/// @nodoc
class _$InboxSessionFactsCopyWithImpl<$Res>
    implements $InboxSessionFactsCopyWith<$Res> {
  _$InboxSessionFactsCopyWithImpl(this._self, this._then);

  final InboxSessionFacts _self;
  final $Res Function(InboxSessionFacts) _then;

/// Create a copy of InboxSessionFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? itemId = null,Object? title = null,Object? start = freezed,Object? end = freezed,Object? status = null,Object? deletedAt = freezed,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as DateTime?,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxSessionFacts].
extension InboxSessionFactsPatterns on InboxSessionFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxSessionFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxSessionFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxSessionFacts value)  $default,){
final _that = this;
switch (_that) {
case _InboxSessionFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxSessionFacts value)?  $default,){
final _that = this;
switch (_that) {
case _InboxSessionFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String itemId,  String title,  DateTime? start,  DateTime? end,  TaskStatus status,  DateTime? deletedAt,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxSessionFacts() when $default != null:
return $default(_that.id,_that.itemId,_that.title,_that.start,_that.end,_that.status,_that.deletedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String itemId,  String title,  DateTime? start,  DateTime? end,  TaskStatus status,  DateTime? deletedAt,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _InboxSessionFacts():
return $default(_that.id,_that.itemId,_that.title,_that.start,_that.end,_that.status,_that.deletedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String itemId,  String title,  DateTime? start,  DateTime? end,  TaskStatus status,  DateTime? deletedAt,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _InboxSessionFacts() when $default != null:
return $default(_that.id,_that.itemId,_that.title,_that.start,_that.end,_that.status,_that.deletedAt,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _InboxSessionFacts implements InboxSessionFacts {
  const _InboxSessionFacts({required this.id, required this.itemId, required this.title, this.start, this.end, required this.status, this.deletedAt, required this.createdAt});
  

@override final  String id;
@override final  String itemId;
@override final  String title;
@override final  DateTime? start;
@override final  DateTime? end;
@override final  TaskStatus status;
@override final  DateTime? deletedAt;
@override final  DateTime createdAt;

/// Create a copy of InboxSessionFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxSessionFactsCopyWith<_InboxSessionFacts> get copyWith => __$InboxSessionFactsCopyWithImpl<_InboxSessionFacts>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxSessionFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.title, title) || other.title == title)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.status, status) || other.status == status)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,itemId,title,start,end,status,deletedAt,createdAt);

@override
String toString() {
  return 'InboxSessionFacts(id: $id, itemId: $itemId, title: $title, start: $start, end: $end, status: $status, deletedAt: $deletedAt, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$InboxSessionFactsCopyWith<$Res> implements $InboxSessionFactsCopyWith<$Res> {
  factory _$InboxSessionFactsCopyWith(_InboxSessionFacts value, $Res Function(_InboxSessionFacts) _then) = __$InboxSessionFactsCopyWithImpl;
@override @useResult
$Res call({
 String id, String itemId, String title, DateTime? start, DateTime? end, TaskStatus status, DateTime? deletedAt, DateTime createdAt
});




}
/// @nodoc
class __$InboxSessionFactsCopyWithImpl<$Res>
    implements _$InboxSessionFactsCopyWith<$Res> {
  __$InboxSessionFactsCopyWithImpl(this._self, this._then);

  final _InboxSessionFacts _self;
  final $Res Function(_InboxSessionFacts) _then;

/// Create a copy of InboxSessionFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? itemId = null,Object? title = null,Object? start = freezed,Object? end = freezed,Object? status = null,Object? deletedAt = freezed,Object? createdAt = null,}) {
  return _then(_InboxSessionFacts(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as DateTime?,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$InboxItemFacts {

 String get id;/// The raw description.
 String get text; DateTime get createdAt;/// Legacy hint only.
 String? get dueDate; List<InboxClosure> get history;
/// Create a copy of InboxItemFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxItemFactsCopyWith<InboxItemFacts> get copyWith => _$InboxItemFactsCopyWithImpl<InboxItemFacts>(this as InboxItemFacts, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxItemFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&const DeepCollectionEquality().equals(other.history, history));
}


@override
int get hashCode => Object.hash(runtimeType,id,text,createdAt,dueDate,const DeepCollectionEquality().hash(history));

@override
String toString() {
  return 'InboxItemFacts(id: $id, text: $text, createdAt: $createdAt, dueDate: $dueDate, history: $history)';
}


}

/// @nodoc
abstract mixin class $InboxItemFactsCopyWith<$Res>  {
  factory $InboxItemFactsCopyWith(InboxItemFacts value, $Res Function(InboxItemFacts) _then) = _$InboxItemFactsCopyWithImpl;
@useResult
$Res call({
 String id, String text, DateTime createdAt, String? dueDate, List<InboxClosure> history
});




}
/// @nodoc
class _$InboxItemFactsCopyWithImpl<$Res>
    implements $InboxItemFactsCopyWith<$Res> {
  _$InboxItemFactsCopyWithImpl(this._self, this._then);

  final InboxItemFacts _self;
  final $Res Function(InboxItemFacts) _then;

/// Create a copy of InboxItemFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? createdAt = null,Object? dueDate = freezed,Object? history = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as List<InboxClosure>,
  ));
}

}


/// Adds pattern-matching-related methods to [InboxItemFacts].
extension InboxItemFactsPatterns on InboxItemFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InboxItemFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InboxItemFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InboxItemFacts value)  $default,){
final _that = this;
switch (_that) {
case _InboxItemFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InboxItemFacts value)?  $default,){
final _that = this;
switch (_that) {
case _InboxItemFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String text,  DateTime createdAt,  String? dueDate,  List<InboxClosure> history)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InboxItemFacts() when $default != null:
return $default(_that.id,_that.text,_that.createdAt,_that.dueDate,_that.history);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String text,  DateTime createdAt,  String? dueDate,  List<InboxClosure> history)  $default,) {final _that = this;
switch (_that) {
case _InboxItemFacts():
return $default(_that.id,_that.text,_that.createdAt,_that.dueDate,_that.history);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String text,  DateTime createdAt,  String? dueDate,  List<InboxClosure> history)?  $default,) {final _that = this;
switch (_that) {
case _InboxItemFacts() when $default != null:
return $default(_that.id,_that.text,_that.createdAt,_that.dueDate,_that.history);case _:
  return null;

}
}

}

/// @nodoc


class _InboxItemFacts implements InboxItemFacts {
  const _InboxItemFacts({required this.id, required this.text, required this.createdAt, this.dueDate, this.history = const <InboxClosure>[]});
  

@override final  String id;
/// The raw description.
@override final  String text;
@override final  DateTime createdAt;
/// Legacy hint only.
@override final  String? dueDate;
@override@JsonKey() final  List<InboxClosure> history;

/// Create a copy of InboxItemFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InboxItemFactsCopyWith<_InboxItemFacts> get copyWith => __$InboxItemFactsCopyWithImpl<_InboxItemFacts>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InboxItemFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&const DeepCollectionEquality().equals(other.history, history));
}


@override
int get hashCode => Object.hash(runtimeType,id,text,createdAt,dueDate,const DeepCollectionEquality().hash(history));

@override
String toString() {
  return 'InboxItemFacts(id: $id, text: $text, createdAt: $createdAt, dueDate: $dueDate, history: $history)';
}


}

/// @nodoc
abstract mixin class _$InboxItemFactsCopyWith<$Res> implements $InboxItemFactsCopyWith<$Res> {
  factory _$InboxItemFactsCopyWith(_InboxItemFacts value, $Res Function(_InboxItemFacts) _then) = __$InboxItemFactsCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, DateTime createdAt, String? dueDate, List<InboxClosure> history
});




}
/// @nodoc
class __$InboxItemFactsCopyWithImpl<$Res>
    implements _$InboxItemFactsCopyWith<$Res> {
  __$InboxItemFactsCopyWithImpl(this._self, this._then);

  final _InboxItemFacts _self;
  final $Res Function(_InboxItemFacts) _then;

/// Create a copy of InboxItemFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? createdAt = null,Object? dueDate = freezed,Object? history = null,}) {
  return _then(_InboxItemFacts(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String?,history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as List<InboxClosure>,
  ));
}


}

// dart format on
