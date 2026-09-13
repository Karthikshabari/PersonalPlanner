// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inbox_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InboxItem {

 Task get task;
/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InboxItemCopyWith<InboxItem> get copyWith => _$InboxItemCopyWithImpl<InboxItem>(this as InboxItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InboxItem&&(identical(other.task, task) || other.task == task));
}


@override
int get hashCode => Object.hash(runtimeType,task);

@override
String toString() {
  return 'InboxItem(task: $task)';
}


}

/// @nodoc
abstract mixin class $InboxItemCopyWith<$Res>  {
  factory $InboxItemCopyWith(InboxItem value, $Res Function(InboxItem) _then) = _$InboxItemCopyWithImpl;
@useResult
$Res call({
 Task task
});


$TaskCopyWith<$Res> get task;

}
/// @nodoc
class _$InboxItemCopyWithImpl<$Res>
    implements $InboxItemCopyWith<$Res> {
  _$InboxItemCopyWithImpl(this._self, this._then);

  final InboxItem _self;
  final $Res Function(InboxItem) _then;

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? task = null,}) {
  return _then(_self.copyWith(
task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as Task,
  ));
}
/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TaskCopyWith<$Res> get task {
  
  return $TaskCopyWith<$Res>(_self.task, (value) {
    return _then(_self.copyWith(task: value));
  });
}
}


/// Adds pattern-matching-related methods to [InboxItem].
extension InboxItemPatterns on InboxItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExplicitInboxItem value)?  explicit,TResult Function( OverdueInboxItem value)?  overdue,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExplicitInboxItem() when explicit != null:
return explicit(_that);case OverdueInboxItem() when overdue != null:
return overdue(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExplicitInboxItem value)  explicit,required TResult Function( OverdueInboxItem value)  overdue,}){
final _that = this;
switch (_that) {
case ExplicitInboxItem():
return explicit(_that);case OverdueInboxItem():
return overdue(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExplicitInboxItem value)?  explicit,TResult? Function( OverdueInboxItem value)?  overdue,}){
final _that = this;
switch (_that) {
case ExplicitInboxItem() when explicit != null:
return explicit(_that);case OverdueInboxItem() when overdue != null:
return overdue(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Task task)?  explicit,TResult Function( Task task)?  overdue,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExplicitInboxItem() when explicit != null:
return explicit(_that.task);case OverdueInboxItem() when overdue != null:
return overdue(_that.task);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Task task)  explicit,required TResult Function( Task task)  overdue,}) {final _that = this;
switch (_that) {
case ExplicitInboxItem():
return explicit(_that.task);case OverdueInboxItem():
return overdue(_that.task);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Task task)?  explicit,TResult? Function( Task task)?  overdue,}) {final _that = this;
switch (_that) {
case ExplicitInboxItem() when explicit != null:
return explicit(_that.task);case OverdueInboxItem() when overdue != null:
return overdue(_that.task);case _:
  return null;

}
}

}

/// @nodoc


class ExplicitInboxItem extends InboxItem {
  const ExplicitInboxItem(this.task): super._();
  

@override final  Task task;

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExplicitInboxItemCopyWith<ExplicitInboxItem> get copyWith => _$ExplicitInboxItemCopyWithImpl<ExplicitInboxItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExplicitInboxItem&&(identical(other.task, task) || other.task == task));
}


@override
int get hashCode => Object.hash(runtimeType,task);

@override
String toString() {
  return 'InboxItem.explicit(task: $task)';
}


}

/// @nodoc
abstract mixin class $ExplicitInboxItemCopyWith<$Res> implements $InboxItemCopyWith<$Res> {
  factory $ExplicitInboxItemCopyWith(ExplicitInboxItem value, $Res Function(ExplicitInboxItem) _then) = _$ExplicitInboxItemCopyWithImpl;
@override @useResult
$Res call({
 Task task
});


@override $TaskCopyWith<$Res> get task;

}
/// @nodoc
class _$ExplicitInboxItemCopyWithImpl<$Res>
    implements $ExplicitInboxItemCopyWith<$Res> {
  _$ExplicitInboxItemCopyWithImpl(this._self, this._then);

  final ExplicitInboxItem _self;
  final $Res Function(ExplicitInboxItem) _then;

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? task = null,}) {
  return _then(ExplicitInboxItem(
null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as Task,
  ));
}

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TaskCopyWith<$Res> get task {
  
  return $TaskCopyWith<$Res>(_self.task, (value) {
    return _then(_self.copyWith(task: value));
  });
}
}

/// @nodoc


class OverdueInboxItem extends InboxItem {
  const OverdueInboxItem(this.task): super._();
  

@override final  Task task;

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OverdueInboxItemCopyWith<OverdueInboxItem> get copyWith => _$OverdueInboxItemCopyWithImpl<OverdueInboxItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OverdueInboxItem&&(identical(other.task, task) || other.task == task));
}


@override
int get hashCode => Object.hash(runtimeType,task);

@override
String toString() {
  return 'InboxItem.overdue(task: $task)';
}


}

/// @nodoc
abstract mixin class $OverdueInboxItemCopyWith<$Res> implements $InboxItemCopyWith<$Res> {
  factory $OverdueInboxItemCopyWith(OverdueInboxItem value, $Res Function(OverdueInboxItem) _then) = _$OverdueInboxItemCopyWithImpl;
@override @useResult
$Res call({
 Task task
});


@override $TaskCopyWith<$Res> get task;

}
/// @nodoc
class _$OverdueInboxItemCopyWithImpl<$Res>
    implements $OverdueInboxItemCopyWith<$Res> {
  _$OverdueInboxItemCopyWithImpl(this._self, this._then);

  final OverdueInboxItem _self;
  final $Res Function(OverdueInboxItem) _then;

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? task = null,}) {
  return _then(OverdueInboxItem(
null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as Task,
  ));
}

/// Create a copy of InboxItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TaskCopyWith<$Res> get task {
  
  return $TaskCopyWith<$Res>(_self.task, (value) {
    return _then(_self.copyWith(task: value));
  });
}
}

// dart format on
