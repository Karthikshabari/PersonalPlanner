// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_template.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskTemplate {

 String get id; String get name; String? get description; int get durationMin; String? get categoryId; int get priority; List<String> get tags; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of TaskTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskTemplateCopyWith<TaskTemplate> get copyWith => _$TaskTemplateCopyWithImpl<TaskTemplate>(this as TaskTemplate, _$identity);

  /// Serializes this TaskTemplate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,durationMin,categoryId,priority,const DeepCollectionEquality().hash(tags),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'TaskTemplate(id: $id, name: $name, description: $description, durationMin: $durationMin, categoryId: $categoryId, priority: $priority, tags: $tags, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class $TaskTemplateCopyWith<$Res>  {
  factory $TaskTemplateCopyWith(TaskTemplate value, $Res Function(TaskTemplate) _then) = _$TaskTemplateCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, int durationMin, String? categoryId, int priority, List<String> tags, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$TaskTemplateCopyWithImpl<$Res>
    implements $TaskTemplateCopyWith<$Res> {
  _$TaskTemplateCopyWithImpl(this._self, this._then);

  final TaskTemplate _self;
  final $Res Function(TaskTemplate) _then;

/// Create a copy of TaskTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? durationMin = null,Object? categoryId = freezed,Object? priority = null,Object? tags = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskTemplate].
extension TaskTemplatePatterns on TaskTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskTemplate value)  $default,){
final _that = this;
switch (_that) {
case _TaskTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _TaskTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskTemplate() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _TaskTemplate():
return $default(_that.id,_that.name,_that.description,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  int durationMin,  String? categoryId,  int priority,  List<String> tags,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _TaskTemplate() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.durationMin,_that.categoryId,_that.priority,_that.tags,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskTemplate implements TaskTemplate {
  const _TaskTemplate({required this.id, required this.name, this.description, required this.durationMin, this.categoryId, this.priority = 0, this.tags = const [], required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _TaskTemplate.fromJson(Map<String, dynamic> json) => _$TaskTemplateFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  int durationMin;
@override final  String? categoryId;
@override@JsonKey() final  int priority;
@override@JsonKey() final  List<String> tags;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of TaskTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskTemplateCopyWith<_TaskTemplate> get copyWith => __$TaskTemplateCopyWithImpl<_TaskTemplate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskTemplateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.durationMin, durationMin) || other.durationMin == durationMin)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,durationMin,categoryId,priority,const DeepCollectionEquality().hash(tags),createdAt,updatedAt,deletedAt);

@override
String toString() {
  return 'TaskTemplate(id: $id, name: $name, description: $description, durationMin: $durationMin, categoryId: $categoryId, priority: $priority, tags: $tags, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskTemplateCopyWith<$Res> implements $TaskTemplateCopyWith<$Res> {
  factory _$TaskTemplateCopyWith(_TaskTemplate value, $Res Function(_TaskTemplate) _then) = __$TaskTemplateCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, int durationMin, String? categoryId, int priority, List<String> tags, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$TaskTemplateCopyWithImpl<$Res>
    implements _$TaskTemplateCopyWith<$Res> {
  __$TaskTemplateCopyWithImpl(this._self, this._then);

  final _TaskTemplate _self;
  final $Res Function(_TaskTemplate) _then;

/// Create a copy of TaskTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? durationMin = null,Object? categoryId = freezed,Object? priority = null,Object? tags = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_TaskTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,durationMin: null == durationMin ? _self.durationMin : durationMin // ignore: cast_nullable_to_non_nullable
as int,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
