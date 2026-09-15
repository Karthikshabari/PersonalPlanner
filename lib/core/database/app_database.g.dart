// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 7,
      maxTextLength: 7,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isFocusMeta = const VerificationMeta(
    'isFocus',
  );
  @override
  late final GeneratedColumn<bool> isFocus = GeneratedColumn<bool>(
    'is_focus',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_focus" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CategoriesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CategoriesTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($CategoriesTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    colorHex,
    sortOrder,
    isFocus,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    } else if (isInserting) {
      context.missing(_colorHexMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_focus')) {
      context.handle(
        _isFocusMeta,
        isFocus.isAcceptableOrUnknown(data['is_focus']!, _isFocusMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isFocus: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_focus'],
      )!,
      createdAt: $CategoriesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $CategoriesTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $CategoriesTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String id;
  final String name;
  final String colorHex;
  final int sortOrder;
  final bool isFocus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const CategoryRow({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.sortOrder,
    required this.isFocus,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color_hex'] = Variable<String>(colorHex);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_focus'] = Variable<bool>(isFocus);
    {
      map['created_at'] = Variable<String>(
        $CategoriesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $CategoriesTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $CategoriesTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: Value(colorHex),
      sortOrder: Value(sortOrder),
      isFocus: Value(isFocus),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isFocus: serializer.fromJson<bool>(json['isFocus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String>(colorHex),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isFocus': serializer.toJson<bool>(isFocus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  CategoryRow copyWith({
    String? id,
    String? name,
    String? colorHex,
    int? sortOrder,
    bool? isFocus,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorHex: colorHex ?? this.colorHex,
    sortOrder: sortOrder ?? this.sortOrder,
    isFocus: isFocus ?? this.isFocus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isFocus: data.isFocus.present ? data.isFocus.value : this.isFocus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isFocus: $isFocus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorHex,
    sortOrder,
    isFocus,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.sortOrder == this.sortOrder &&
          other.isFocus == this.isFocus &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> colorHex;
  final Value<int> sortOrder;
  final Value<bool> isFocus;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isFocus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    required String colorHex,
    this.sortOrder = const Value.absent(),
    this.isFocus = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       colorHex = Value(colorHex),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<int>? sortOrder,
    Expression<bool>? isFocus,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isFocus != null) 'is_focus': isFocus,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? colorHex,
    Value<int>? sortOrder,
    Value<bool>? isFocus,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
      isFocus: isFocus ?? this.isFocus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isFocus.present) {
      map['is_focus'] = Variable<bool>(isFocus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $CategoriesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $CategoriesTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $CategoriesTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isFocus: $isFocus, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecurringRulesTable extends RecurringRules
    with TableInfo<$RecurringRulesTable, RecurringRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rruleMeta = const VerificationMeta('rrule');
  @override
  late final GeneratedColumn<String> rrule = GeneratedColumn<String>(
    'rrule',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskTitleMeta = const VerificationMeta(
    'taskTitle',
  );
  @override
  late final GeneratedColumn<String> taskTitle = GeneratedColumn<String>(
    'task_title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskDescriptionMeta = const VerificationMeta(
    'taskDescription',
  );
  @override
  late final GeneratedColumn<String> taskDescription = GeneratedColumn<String>(
    'task_description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMinMeta = const VerificationMeta(
    'durationMin',
  );
  @override
  late final GeneratedColumn<int> durationMin = GeneratedColumn<int>(
    'duration_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeOfDayMeta = const VerificationMeta(
    'startTimeOfDay',
  );
  @override
  late final GeneratedColumn<String> startTimeOfDay = GeneratedColumn<String>(
    'start_time_of_day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _exceptionsJsonMeta = const VerificationMeta(
    'exceptionsJson',
  );
  @override
  late final GeneratedColumn<String> exceptionsJson = GeneratedColumn<String>(
    'exceptions_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($RecurringRulesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($RecurringRulesTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($RecurringRulesTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rrule,
    taskTitle,
    taskDescription,
    durationMin,
    categoryId,
    priority,
    tagsJson,
    startTimeOfDay,
    startDate,
    endDate,
    isActive,
    exceptionsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecurringRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('rrule')) {
      context.handle(
        _rruleMeta,
        rrule.isAcceptableOrUnknown(data['rrule']!, _rruleMeta),
      );
    } else if (isInserting) {
      context.missing(_rruleMeta);
    }
    if (data.containsKey('task_title')) {
      context.handle(
        _taskTitleMeta,
        taskTitle.isAcceptableOrUnknown(data['task_title']!, _taskTitleMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTitleMeta);
    }
    if (data.containsKey('task_description')) {
      context.handle(
        _taskDescriptionMeta,
        taskDescription.isAcceptableOrUnknown(
          data['task_description']!,
          _taskDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('duration_min')) {
      context.handle(
        _durationMinMeta,
        durationMin.isAcceptableOrUnknown(
          data['duration_min']!,
          _durationMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationMinMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('start_time_of_day')) {
      context.handle(
        _startTimeOfDayMeta,
        startTimeOfDay.isAcceptableOrUnknown(
          data['start_time_of_day']!,
          _startTimeOfDayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startTimeOfDayMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('exceptions_json')) {
      context.handle(
        _exceptionsJsonMeta,
        exceptionsJson.isAcceptableOrUnknown(
          data['exceptions_json']!,
          _exceptionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecurringRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      rrule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rrule'],
      )!,
      taskTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_title'],
      )!,
      taskDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_description'],
      ),
      durationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_min'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      ),
      startTimeOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_time_of_day'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      exceptionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exceptions_json'],
      ),
      createdAt: $RecurringRulesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $RecurringRulesTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $RecurringRulesTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $RecurringRulesTable createAlias(String alias) {
    return $RecurringRulesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class RecurringRuleRow extends DataClass
    implements Insertable<RecurringRuleRow> {
  final String id;
  final String rrule;
  final String taskTitle;
  final String? taskDescription;
  final int durationMin;
  final String? categoryId;
  final int priority;
  final String? tagsJson;
  final String startTimeOfDay;
  final String startDate;
  final String? endDate;
  final bool isActive;
  final String? exceptionsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const RecurringRuleRow({
    required this.id,
    required this.rrule,
    required this.taskTitle,
    this.taskDescription,
    required this.durationMin,
    this.categoryId,
    required this.priority,
    this.tagsJson,
    required this.startTimeOfDay,
    required this.startDate,
    this.endDate,
    required this.isActive,
    this.exceptionsJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['rrule'] = Variable<String>(rrule);
    map['task_title'] = Variable<String>(taskTitle);
    if (!nullToAbsent || taskDescription != null) {
      map['task_description'] = Variable<String>(taskDescription);
    }
    map['duration_min'] = Variable<int>(durationMin);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || tagsJson != null) {
      map['tags_json'] = Variable<String>(tagsJson);
    }
    map['start_time_of_day'] = Variable<String>(startTimeOfDay);
    map['start_date'] = Variable<String>(startDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<String>(endDate);
    }
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || exceptionsJson != null) {
      map['exceptions_json'] = Variable<String>(exceptionsJson);
    }
    {
      map['created_at'] = Variable<String>(
        $RecurringRulesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $RecurringRulesTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $RecurringRulesTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  RecurringRulesCompanion toCompanion(bool nullToAbsent) {
    return RecurringRulesCompanion(
      id: Value(id),
      rrule: Value(rrule),
      taskTitle: Value(taskTitle),
      taskDescription: taskDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(taskDescription),
      durationMin: Value(durationMin),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      priority: Value(priority),
      tagsJson: tagsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsJson),
      startTimeOfDay: Value(startTimeOfDay),
      startDate: Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      isActive: Value(isActive),
      exceptionsJson: exceptionsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(exceptionsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory RecurringRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringRuleRow(
      id: serializer.fromJson<String>(json['id']),
      rrule: serializer.fromJson<String>(json['rrule']),
      taskTitle: serializer.fromJson<String>(json['taskTitle']),
      taskDescription: serializer.fromJson<String?>(json['taskDescription']),
      durationMin: serializer.fromJson<int>(json['durationMin']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      priority: serializer.fromJson<int>(json['priority']),
      tagsJson: serializer.fromJson<String?>(json['tagsJson']),
      startTimeOfDay: serializer.fromJson<String>(json['startTimeOfDay']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String?>(json['endDate']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      exceptionsJson: serializer.fromJson<String?>(json['exceptionsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rrule': serializer.toJson<String>(rrule),
      'taskTitle': serializer.toJson<String>(taskTitle),
      'taskDescription': serializer.toJson<String?>(taskDescription),
      'durationMin': serializer.toJson<int>(durationMin),
      'categoryId': serializer.toJson<String?>(categoryId),
      'priority': serializer.toJson<int>(priority),
      'tagsJson': serializer.toJson<String?>(tagsJson),
      'startTimeOfDay': serializer.toJson<String>(startTimeOfDay),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String?>(endDate),
      'isActive': serializer.toJson<bool>(isActive),
      'exceptionsJson': serializer.toJson<String?>(exceptionsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  RecurringRuleRow copyWith({
    String? id,
    String? rrule,
    String? taskTitle,
    Value<String?> taskDescription = const Value.absent(),
    int? durationMin,
    Value<String?> categoryId = const Value.absent(),
    int? priority,
    Value<String?> tagsJson = const Value.absent(),
    String? startTimeOfDay,
    String? startDate,
    Value<String?> endDate = const Value.absent(),
    bool? isActive,
    Value<String?> exceptionsJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => RecurringRuleRow(
    id: id ?? this.id,
    rrule: rrule ?? this.rrule,
    taskTitle: taskTitle ?? this.taskTitle,
    taskDescription: taskDescription.present
        ? taskDescription.value
        : this.taskDescription,
    durationMin: durationMin ?? this.durationMin,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    priority: priority ?? this.priority,
    tagsJson: tagsJson.present ? tagsJson.value : this.tagsJson,
    startTimeOfDay: startTimeOfDay ?? this.startTimeOfDay,
    startDate: startDate ?? this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    isActive: isActive ?? this.isActive,
    exceptionsJson: exceptionsJson.present
        ? exceptionsJson.value
        : this.exceptionsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  RecurringRuleRow copyWithCompanion(RecurringRulesCompanion data) {
    return RecurringRuleRow(
      id: data.id.present ? data.id.value : this.id,
      rrule: data.rrule.present ? data.rrule.value : this.rrule,
      taskTitle: data.taskTitle.present ? data.taskTitle.value : this.taskTitle,
      taskDescription: data.taskDescription.present
          ? data.taskDescription.value
          : this.taskDescription,
      durationMin: data.durationMin.present
          ? data.durationMin.value
          : this.durationMin,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      priority: data.priority.present ? data.priority.value : this.priority,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      startTimeOfDay: data.startTimeOfDay.present
          ? data.startTimeOfDay.value
          : this.startTimeOfDay,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      exceptionsJson: data.exceptionsJson.present
          ? data.exceptionsJson.value
          : this.exceptionsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecurringRuleRow(')
          ..write('id: $id, ')
          ..write('rrule: $rrule, ')
          ..write('taskTitle: $taskTitle, ')
          ..write('taskDescription: $taskDescription, ')
          ..write('durationMin: $durationMin, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('startTimeOfDay: $startTimeOfDay, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('isActive: $isActive, ')
          ..write('exceptionsJson: $exceptionsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rrule,
    taskTitle,
    taskDescription,
    durationMin,
    categoryId,
    priority,
    tagsJson,
    startTimeOfDay,
    startDate,
    endDate,
    isActive,
    exceptionsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringRuleRow &&
          other.id == this.id &&
          other.rrule == this.rrule &&
          other.taskTitle == this.taskTitle &&
          other.taskDescription == this.taskDescription &&
          other.durationMin == this.durationMin &&
          other.categoryId == this.categoryId &&
          other.priority == this.priority &&
          other.tagsJson == this.tagsJson &&
          other.startTimeOfDay == this.startTimeOfDay &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.isActive == this.isActive &&
          other.exceptionsJson == this.exceptionsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class RecurringRulesCompanion extends UpdateCompanion<RecurringRuleRow> {
  final Value<String> id;
  final Value<String> rrule;
  final Value<String> taskTitle;
  final Value<String?> taskDescription;
  final Value<int> durationMin;
  final Value<String?> categoryId;
  final Value<int> priority;
  final Value<String?> tagsJson;
  final Value<String> startTimeOfDay;
  final Value<String> startDate;
  final Value<String?> endDate;
  final Value<bool> isActive;
  final Value<String?> exceptionsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const RecurringRulesCompanion({
    this.id = const Value.absent(),
    this.rrule = const Value.absent(),
    this.taskTitle = const Value.absent(),
    this.taskDescription = const Value.absent(),
    this.durationMin = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.startTimeOfDay = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.isActive = const Value.absent(),
    this.exceptionsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecurringRulesCompanion.insert({
    required String id,
    required String rrule,
    required String taskTitle,
    this.taskDescription = const Value.absent(),
    required int durationMin,
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.tagsJson = const Value.absent(),
    required String startTimeOfDay,
    required String startDate,
    this.endDate = const Value.absent(),
    this.isActive = const Value.absent(),
    this.exceptionsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       rrule = Value(rrule),
       taskTitle = Value(taskTitle),
       durationMin = Value(durationMin),
       startTimeOfDay = Value(startTimeOfDay),
       startDate = Value(startDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RecurringRuleRow> custom({
    Expression<String>? id,
    Expression<String>? rrule,
    Expression<String>? taskTitle,
    Expression<String>? taskDescription,
    Expression<int>? durationMin,
    Expression<String>? categoryId,
    Expression<int>? priority,
    Expression<String>? tagsJson,
    Expression<String>? startTimeOfDay,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<bool>? isActive,
    Expression<String>? exceptionsJson,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rrule != null) 'rrule': rrule,
      if (taskTitle != null) 'task_title': taskTitle,
      if (taskDescription != null) 'task_description': taskDescription,
      if (durationMin != null) 'duration_min': durationMin,
      if (categoryId != null) 'category_id': categoryId,
      if (priority != null) 'priority': priority,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (startTimeOfDay != null) 'start_time_of_day': startTimeOfDay,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (isActive != null) 'is_active': isActive,
      if (exceptionsJson != null) 'exceptions_json': exceptionsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecurringRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? rrule,
    Value<String>? taskTitle,
    Value<String?>? taskDescription,
    Value<int>? durationMin,
    Value<String?>? categoryId,
    Value<int>? priority,
    Value<String?>? tagsJson,
    Value<String>? startTimeOfDay,
    Value<String>? startDate,
    Value<String?>? endDate,
    Value<bool>? isActive,
    Value<String?>? exceptionsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return RecurringRulesCompanion(
      id: id ?? this.id,
      rrule: rrule ?? this.rrule,
      taskTitle: taskTitle ?? this.taskTitle,
      taskDescription: taskDescription ?? this.taskDescription,
      durationMin: durationMin ?? this.durationMin,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      tagsJson: tagsJson ?? this.tagsJson,
      startTimeOfDay: startTimeOfDay ?? this.startTimeOfDay,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      exceptionsJson: exceptionsJson ?? this.exceptionsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rrule.present) {
      map['rrule'] = Variable<String>(rrule.value);
    }
    if (taskTitle.present) {
      map['task_title'] = Variable<String>(taskTitle.value);
    }
    if (taskDescription.present) {
      map['task_description'] = Variable<String>(taskDescription.value);
    }
    if (durationMin.present) {
      map['duration_min'] = Variable<int>(durationMin.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (startTimeOfDay.present) {
      map['start_time_of_day'] = Variable<String>(startTimeOfDay.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (exceptionsJson.present) {
      map['exceptions_json'] = Variable<String>(exceptionsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $RecurringRulesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $RecurringRulesTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $RecurringRulesTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringRulesCompanion(')
          ..write('id: $id, ')
          ..write('rrule: $rrule, ')
          ..write('taskTitle: $taskTitle, ')
          ..write('taskDescription: $taskDescription, ')
          ..write('durationMin: $durationMin, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('startTimeOfDay: $startTimeOfDay, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('isActive: $isActive, ')
          ..write('exceptionsJson: $exceptionsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> startTime =
      GeneratedColumn<String>(
        'start_time',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TasksTable.$converterstartTime);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> endTime =
      GeneratedColumn<String>(
        'end_time',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TasksTable.$converterendTime);
  static const VerificationMeta _estimatedDurationMinMeta =
      const VerificationMeta('estimatedDurationMin');
  @override
  late final GeneratedColumn<int> estimatedDurationMin = GeneratedColumn<int>(
    'estimated_duration_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualDurationMinMeta = const VerificationMeta(
    'actualDurationMin',
  );
  @override
  late final GeneratedColumn<int> actualDurationMin = GeneratedColumn<int>(
    'actual_duration_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manualDurationAdjustmentMinMeta =
      const VerificationMeta('manualDurationAdjustmentMin');
  @override
  late final GeneratedColumn<int> manualDurationAdjustmentMin =
      GeneratedColumn<int>(
        'manual_duration_adjustment_min',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _manualActualSetMeta = const VerificationMeta(
    'manualActualSet',
  );
  @override
  late final GeneratedColumn<bool> manualActualSet = GeneratedColumn<bool>(
    'manual_actual_set',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("manual_actual_set" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('planned'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recurringRuleIdMeta = const VerificationMeta(
    'recurringRuleId',
  );
  @override
  late final GeneratedColumn<String> recurringRuleId = GeneratedColumn<String>(
    'recurring_rule_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recurring_rules (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _recurrenceRemovalReasonMeta =
      const VerificationMeta('recurrenceRemovalReason');
  @override
  late final GeneratedColumn<String>
  recurrenceRemovalReason = GeneratedColumn<String>(
    'recurrence_removal_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (recurrence_removal_reason IS NULL OR recurrence_removal_reason = \'rule_excluded\')',
  );
  static const VerificationMeta _rescheduledFromIdMeta = const VerificationMeta(
    'rescheduledFromId',
  );
  @override
  late final GeneratedColumn<String> rescheduledFromId =
      GeneratedColumn<String>(
        'rescheduled_from_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES tasks (id) ON DELETE SET NULL',
        ),
      );
  static const VerificationMeta _rescheduledToIdMeta = const VerificationMeta(
    'rescheduledToId',
  );
  @override
  late final GeneratedColumn<String> rescheduledToId = GeneratedColumn<String>(
    'rescheduled_to_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _isInboxMeta = const VerificationMeta(
    'isInbox',
  );
  @override
  late final GeneratedColumn<bool> isInbox = GeneratedColumn<bool>(
    'is_inbox',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_inbox" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _inboxContentVersionMeta =
      const VerificationMeta('inboxContentVersion');
  @override
  late final GeneratedColumn<int> inboxContentVersion = GeneratedColumn<int>(
    'inbox_content_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _missedAtMeta = const VerificationMeta(
    'missedAt',
  );
  @override
  late final GeneratedColumn<String> missedAt = GeneratedColumn<String>(
    'missed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planTitleHistoryJsonMeta =
      const VerificationMeta('planTitleHistoryJson');
  @override
  late final GeneratedColumn<String> planTitleHistoryJson =
      GeneratedColumn<String>(
        'plan_title_history_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _displayPlanChangeIdMeta =
      const VerificationMeta('displayPlanChangeId');
  @override
  late final GeneratedColumn<String> displayPlanChangeId =
      GeneratedColumn<String>(
        'display_plan_change_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TasksTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TasksTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TasksTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    startTime,
    endTime,
    estimatedDurationMin,
    actualDurationMin,
    manualDurationAdjustmentMin,
    manualActualSet,
    categoryId,
    priority,
    status,
    notes,
    recurringRuleId,
    recurrenceRemovalReason,
    rescheduledFromId,
    rescheduledToId,
    isInbox,
    inboxContentVersion,
    dueDate,
    missedAt,
    planTitleHistoryJson,
    displayPlanChangeId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('estimated_duration_min')) {
      context.handle(
        _estimatedDurationMinMeta,
        estimatedDurationMin.isAcceptableOrUnknown(
          data['estimated_duration_min']!,
          _estimatedDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('actual_duration_min')) {
      context.handle(
        _actualDurationMinMeta,
        actualDurationMin.isAcceptableOrUnknown(
          data['actual_duration_min']!,
          _actualDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('manual_duration_adjustment_min')) {
      context.handle(
        _manualDurationAdjustmentMinMeta,
        manualDurationAdjustmentMin.isAcceptableOrUnknown(
          data['manual_duration_adjustment_min']!,
          _manualDurationAdjustmentMinMeta,
        ),
      );
    }
    if (data.containsKey('manual_actual_set')) {
      context.handle(
        _manualActualSetMeta,
        manualActualSet.isAcceptableOrUnknown(
          data['manual_actual_set']!,
          _manualActualSetMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('recurring_rule_id')) {
      context.handle(
        _recurringRuleIdMeta,
        recurringRuleId.isAcceptableOrUnknown(
          data['recurring_rule_id']!,
          _recurringRuleIdMeta,
        ),
      );
    }
    if (data.containsKey('recurrence_removal_reason')) {
      context.handle(
        _recurrenceRemovalReasonMeta,
        recurrenceRemovalReason.isAcceptableOrUnknown(
          data['recurrence_removal_reason']!,
          _recurrenceRemovalReasonMeta,
        ),
      );
    }
    if (data.containsKey('rescheduled_from_id')) {
      context.handle(
        _rescheduledFromIdMeta,
        rescheduledFromId.isAcceptableOrUnknown(
          data['rescheduled_from_id']!,
          _rescheduledFromIdMeta,
        ),
      );
    }
    if (data.containsKey('rescheduled_to_id')) {
      context.handle(
        _rescheduledToIdMeta,
        rescheduledToId.isAcceptableOrUnknown(
          data['rescheduled_to_id']!,
          _rescheduledToIdMeta,
        ),
      );
    }
    if (data.containsKey('is_inbox')) {
      context.handle(
        _isInboxMeta,
        isInbox.isAcceptableOrUnknown(data['is_inbox']!, _isInboxMeta),
      );
    }
    if (data.containsKey('inbox_content_version')) {
      context.handle(
        _inboxContentVersionMeta,
        inboxContentVersion.isAcceptableOrUnknown(
          data['inbox_content_version']!,
          _inboxContentVersionMeta,
        ),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('missed_at')) {
      context.handle(
        _missedAtMeta,
        missedAt.isAcceptableOrUnknown(data['missed_at']!, _missedAtMeta),
      );
    }
    if (data.containsKey('plan_title_history_json')) {
      context.handle(
        _planTitleHistoryJsonMeta,
        planTitleHistoryJson.isAcceptableOrUnknown(
          data['plan_title_history_json']!,
          _planTitleHistoryJsonMeta,
        ),
      );
    }
    if (data.containsKey('display_plan_change_id')) {
      context.handle(
        _displayPlanChangeIdMeta,
        displayPlanChangeId.isAcceptableOrUnknown(
          data['display_plan_change_id']!,
          _displayPlanChangeIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      startTime: $TasksTable.$converterstartTime.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}start_time'],
        ),
      ),
      endTime: $TasksTable.$converterendTime.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_time'],
        ),
      ),
      estimatedDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_duration_min'],
      ),
      actualDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_duration_min'],
      ),
      manualDurationAdjustmentMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}manual_duration_adjustment_min'],
      )!,
      manualActualSet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}manual_actual_set'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      recurringRuleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurring_rule_id'],
      ),
      recurrenceRemovalReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_removal_reason'],
      ),
      rescheduledFromId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rescheduled_from_id'],
      ),
      rescheduledToId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rescheduled_to_id'],
      ),
      isInbox: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_inbox'],
      )!,
      inboxContentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}inbox_content_version'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      ),
      missedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}missed_at'],
      ),
      planTitleHistoryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_title_history_json'],
      )!,
      displayPlanChangeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_plan_change_id'],
      ),
      createdAt: $TasksTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $TasksTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $TasksTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime?, String?> $converterstartTime =
      const NullableDateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterendTime =
      const NullableDateTimeUtcConverter();
  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final String id;
  final String title;
  final String? description;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? estimatedDurationMin;
  final int? actualDurationMin;
  final int manualDurationAdjustmentMin;
  final bool manualActualSet;
  final String? categoryId;
  final int priority;
  final String status;
  final String? notes;
  final String? recurringRuleId;

  /// Set only while an unfinished deterministic occurrence is tombstoned
  /// because its rule temporarily stopped producing the original slot.
  /// Ordinary user deletion deliberately leaves this null.
  final String? recurrenceRemovalReason;
  final String? rescheduledFromId;
  final String? rescheduledToId;
  final bool isInbox;
  final int inboxContentVersion;
  final String? dueDate;
  final String? missedAt;
  final String planTitleHistoryJson;
  final String? displayPlanChangeId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;

  /// Nullable until the row is acknowledged by Supabase.
  final int? serverVersion;
  const TaskRow({
    required this.id,
    required this.title,
    this.description,
    this.startTime,
    this.endTime,
    this.estimatedDurationMin,
    this.actualDurationMin,
    required this.manualDurationAdjustmentMin,
    required this.manualActualSet,
    this.categoryId,
    required this.priority,
    required this.status,
    this.notes,
    this.recurringRuleId,
    this.recurrenceRemovalReason,
    this.rescheduledFromId,
    this.rescheduledToId,
    required this.isInbox,
    required this.inboxContentVersion,
    this.dueDate,
    this.missedAt,
    required this.planTitleHistoryJson,
    this.displayPlanChangeId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || startTime != null) {
      map['start_time'] = Variable<String>(
        $TasksTable.$converterstartTime.toSql(startTime),
      );
    }
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<String>(
        $TasksTable.$converterendTime.toSql(endTime),
      );
    }
    if (!nullToAbsent || estimatedDurationMin != null) {
      map['estimated_duration_min'] = Variable<int>(estimatedDurationMin);
    }
    if (!nullToAbsent || actualDurationMin != null) {
      map['actual_duration_min'] = Variable<int>(actualDurationMin);
    }
    map['manual_duration_adjustment_min'] = Variable<int>(
      manualDurationAdjustmentMin,
    );
    map['manual_actual_set'] = Variable<bool>(manualActualSet);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['priority'] = Variable<int>(priority);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || recurringRuleId != null) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId);
    }
    if (!nullToAbsent || recurrenceRemovalReason != null) {
      map['recurrence_removal_reason'] = Variable<String>(
        recurrenceRemovalReason,
      );
    }
    if (!nullToAbsent || rescheduledFromId != null) {
      map['rescheduled_from_id'] = Variable<String>(rescheduledFromId);
    }
    if (!nullToAbsent || rescheduledToId != null) {
      map['rescheduled_to_id'] = Variable<String>(rescheduledToId);
    }
    map['is_inbox'] = Variable<bool>(isInbox);
    map['inbox_content_version'] = Variable<int>(inboxContentVersion);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    if (!nullToAbsent || missedAt != null) {
      map['missed_at'] = Variable<String>(missedAt);
    }
    map['plan_title_history_json'] = Variable<String>(planTitleHistoryJson);
    if (!nullToAbsent || displayPlanChangeId != null) {
      map['display_plan_change_id'] = Variable<String>(displayPlanChangeId);
    }
    {
      map['created_at'] = Variable<String>(
        $TasksTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $TasksTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $TasksTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      startTime: startTime == null && nullToAbsent
          ? const Value.absent()
          : Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      estimatedDurationMin: estimatedDurationMin == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedDurationMin),
      actualDurationMin: actualDurationMin == null && nullToAbsent
          ? const Value.absent()
          : Value(actualDurationMin),
      manualDurationAdjustmentMin: Value(manualDurationAdjustmentMin),
      manualActualSet: Value(manualActualSet),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      priority: Value(priority),
      status: Value(status),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      recurringRuleId: recurringRuleId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringRuleId),
      recurrenceRemovalReason: recurrenceRemovalReason == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceRemovalReason),
      rescheduledFromId: rescheduledFromId == null && nullToAbsent
          ? const Value.absent()
          : Value(rescheduledFromId),
      rescheduledToId: rescheduledToId == null && nullToAbsent
          ? const Value.absent()
          : Value(rescheduledToId),
      isInbox: Value(isInbox),
      inboxContentVersion: Value(inboxContentVersion),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      missedAt: missedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(missedAt),
      planTitleHistoryJson: Value(planTitleHistoryJson),
      displayPlanChangeId: displayPlanChangeId == null && nullToAbsent
          ? const Value.absent()
          : Value(displayPlanChangeId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      startTime: serializer.fromJson<DateTime?>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      estimatedDurationMin: serializer.fromJson<int?>(
        json['estimatedDurationMin'],
      ),
      actualDurationMin: serializer.fromJson<int?>(json['actualDurationMin']),
      manualDurationAdjustmentMin: serializer.fromJson<int>(
        json['manualDurationAdjustmentMin'],
      ),
      manualActualSet: serializer.fromJson<bool>(json['manualActualSet']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      priority: serializer.fromJson<int>(json['priority']),
      status: serializer.fromJson<String>(json['status']),
      notes: serializer.fromJson<String?>(json['notes']),
      recurringRuleId: serializer.fromJson<String?>(json['recurringRuleId']),
      recurrenceRemovalReason: serializer.fromJson<String?>(
        json['recurrenceRemovalReason'],
      ),
      rescheduledFromId: serializer.fromJson<String?>(
        json['rescheduledFromId'],
      ),
      rescheduledToId: serializer.fromJson<String?>(json['rescheduledToId']),
      isInbox: serializer.fromJson<bool>(json['isInbox']),
      inboxContentVersion: serializer.fromJson<int>(
        json['inboxContentVersion'],
      ),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      missedAt: serializer.fromJson<String?>(json['missedAt']),
      planTitleHistoryJson: serializer.fromJson<String>(
        json['planTitleHistoryJson'],
      ),
      displayPlanChangeId: serializer.fromJson<String?>(
        json['displayPlanChangeId'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'startTime': serializer.toJson<DateTime?>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'estimatedDurationMin': serializer.toJson<int?>(estimatedDurationMin),
      'actualDurationMin': serializer.toJson<int?>(actualDurationMin),
      'manualDurationAdjustmentMin': serializer.toJson<int>(
        manualDurationAdjustmentMin,
      ),
      'manualActualSet': serializer.toJson<bool>(manualActualSet),
      'categoryId': serializer.toJson<String?>(categoryId),
      'priority': serializer.toJson<int>(priority),
      'status': serializer.toJson<String>(status),
      'notes': serializer.toJson<String?>(notes),
      'recurringRuleId': serializer.toJson<String?>(recurringRuleId),
      'recurrenceRemovalReason': serializer.toJson<String?>(
        recurrenceRemovalReason,
      ),
      'rescheduledFromId': serializer.toJson<String?>(rescheduledFromId),
      'rescheduledToId': serializer.toJson<String?>(rescheduledToId),
      'isInbox': serializer.toJson<bool>(isInbox),
      'inboxContentVersion': serializer.toJson<int>(inboxContentVersion),
      'dueDate': serializer.toJson<String?>(dueDate),
      'missedAt': serializer.toJson<String?>(missedAt),
      'planTitleHistoryJson': serializer.toJson<String>(planTitleHistoryJson),
      'displayPlanChangeId': serializer.toJson<String?>(displayPlanChangeId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  TaskRow copyWith({
    String? id,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<DateTime?> startTime = const Value.absent(),
    Value<DateTime?> endTime = const Value.absent(),
    Value<int?> estimatedDurationMin = const Value.absent(),
    Value<int?> actualDurationMin = const Value.absent(),
    int? manualDurationAdjustmentMin,
    bool? manualActualSet,
    Value<String?> categoryId = const Value.absent(),
    int? priority,
    String? status,
    Value<String?> notes = const Value.absent(),
    Value<String?> recurringRuleId = const Value.absent(),
    Value<String?> recurrenceRemovalReason = const Value.absent(),
    Value<String?> rescheduledFromId = const Value.absent(),
    Value<String?> rescheduledToId = const Value.absent(),
    bool? isInbox,
    int? inboxContentVersion,
    Value<String?> dueDate = const Value.absent(),
    Value<String?> missedAt = const Value.absent(),
    String? planTitleHistoryJson,
    Value<String?> displayPlanChangeId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => TaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    startTime: startTime.present ? startTime.value : this.startTime,
    endTime: endTime.present ? endTime.value : this.endTime,
    estimatedDurationMin: estimatedDurationMin.present
        ? estimatedDurationMin.value
        : this.estimatedDurationMin,
    actualDurationMin: actualDurationMin.present
        ? actualDurationMin.value
        : this.actualDurationMin,
    manualDurationAdjustmentMin:
        manualDurationAdjustmentMin ?? this.manualDurationAdjustmentMin,
    manualActualSet: manualActualSet ?? this.manualActualSet,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    notes: notes.present ? notes.value : this.notes,
    recurringRuleId: recurringRuleId.present
        ? recurringRuleId.value
        : this.recurringRuleId,
    recurrenceRemovalReason: recurrenceRemovalReason.present
        ? recurrenceRemovalReason.value
        : this.recurrenceRemovalReason,
    rescheduledFromId: rescheduledFromId.present
        ? rescheduledFromId.value
        : this.rescheduledFromId,
    rescheduledToId: rescheduledToId.present
        ? rescheduledToId.value
        : this.rescheduledToId,
    isInbox: isInbox ?? this.isInbox,
    inboxContentVersion: inboxContentVersion ?? this.inboxContentVersion,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    missedAt: missedAt.present ? missedAt.value : this.missedAt,
    planTitleHistoryJson: planTitleHistoryJson ?? this.planTitleHistoryJson,
    displayPlanChangeId: displayPlanChangeId.present
        ? displayPlanChangeId.value
        : this.displayPlanChangeId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      estimatedDurationMin: data.estimatedDurationMin.present
          ? data.estimatedDurationMin.value
          : this.estimatedDurationMin,
      actualDurationMin: data.actualDurationMin.present
          ? data.actualDurationMin.value
          : this.actualDurationMin,
      manualDurationAdjustmentMin: data.manualDurationAdjustmentMin.present
          ? data.manualDurationAdjustmentMin.value
          : this.manualDurationAdjustmentMin,
      manualActualSet: data.manualActualSet.present
          ? data.manualActualSet.value
          : this.manualActualSet,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      priority: data.priority.present ? data.priority.value : this.priority,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      recurringRuleId: data.recurringRuleId.present
          ? data.recurringRuleId.value
          : this.recurringRuleId,
      recurrenceRemovalReason: data.recurrenceRemovalReason.present
          ? data.recurrenceRemovalReason.value
          : this.recurrenceRemovalReason,
      rescheduledFromId: data.rescheduledFromId.present
          ? data.rescheduledFromId.value
          : this.rescheduledFromId,
      rescheduledToId: data.rescheduledToId.present
          ? data.rescheduledToId.value
          : this.rescheduledToId,
      isInbox: data.isInbox.present ? data.isInbox.value : this.isInbox,
      inboxContentVersion: data.inboxContentVersion.present
          ? data.inboxContentVersion.value
          : this.inboxContentVersion,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      missedAt: data.missedAt.present ? data.missedAt.value : this.missedAt,
      planTitleHistoryJson: data.planTitleHistoryJson.present
          ? data.planTitleHistoryJson.value
          : this.planTitleHistoryJson,
      displayPlanChangeId: data.displayPlanChangeId.present
          ? data.displayPlanChangeId.value
          : this.displayPlanChangeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('estimatedDurationMin: $estimatedDurationMin, ')
          ..write('actualDurationMin: $actualDurationMin, ')
          ..write('manualDurationAdjustmentMin: $manualDurationAdjustmentMin, ')
          ..write('manualActualSet: $manualActualSet, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write('recurrenceRemovalReason: $recurrenceRemovalReason, ')
          ..write('rescheduledFromId: $rescheduledFromId, ')
          ..write('rescheduledToId: $rescheduledToId, ')
          ..write('isInbox: $isInbox, ')
          ..write('inboxContentVersion: $inboxContentVersion, ')
          ..write('dueDate: $dueDate, ')
          ..write('missedAt: $missedAt, ')
          ..write('planTitleHistoryJson: $planTitleHistoryJson, ')
          ..write('displayPlanChangeId: $displayPlanChangeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    description,
    startTime,
    endTime,
    estimatedDurationMin,
    actualDurationMin,
    manualDurationAdjustmentMin,
    manualActualSet,
    categoryId,
    priority,
    status,
    notes,
    recurringRuleId,
    recurrenceRemovalReason,
    rescheduledFromId,
    rescheduledToId,
    isInbox,
    inboxContentVersion,
    dueDate,
    missedAt,
    planTitleHistoryJson,
    displayPlanChangeId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.estimatedDurationMin == this.estimatedDurationMin &&
          other.actualDurationMin == this.actualDurationMin &&
          other.manualDurationAdjustmentMin ==
              this.manualDurationAdjustmentMin &&
          other.manualActualSet == this.manualActualSet &&
          other.categoryId == this.categoryId &&
          other.priority == this.priority &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.recurringRuleId == this.recurringRuleId &&
          other.recurrenceRemovalReason == this.recurrenceRemovalReason &&
          other.rescheduledFromId == this.rescheduledFromId &&
          other.rescheduledToId == this.rescheduledToId &&
          other.isInbox == this.isInbox &&
          other.inboxContentVersion == this.inboxContentVersion &&
          other.dueDate == this.dueDate &&
          other.missedAt == this.missedAt &&
          other.planTitleHistoryJson == this.planTitleHistoryJson &&
          other.displayPlanChangeId == this.displayPlanChangeId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime?> startTime;
  final Value<DateTime?> endTime;
  final Value<int?> estimatedDurationMin;
  final Value<int?> actualDurationMin;
  final Value<int> manualDurationAdjustmentMin;
  final Value<bool> manualActualSet;
  final Value<String?> categoryId;
  final Value<int> priority;
  final Value<String> status;
  final Value<String?> notes;
  final Value<String?> recurringRuleId;
  final Value<String?> recurrenceRemovalReason;
  final Value<String?> rescheduledFromId;
  final Value<String?> rescheduledToId;
  final Value<bool> isInbox;
  final Value<int> inboxContentVersion;
  final Value<String?> dueDate;
  final Value<String?> missedAt;
  final Value<String> planTitleHistoryJson;
  final Value<String?> displayPlanChangeId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.estimatedDurationMin = const Value.absent(),
    this.actualDurationMin = const Value.absent(),
    this.manualDurationAdjustmentMin = const Value.absent(),
    this.manualActualSet = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    this.recurrenceRemovalReason = const Value.absent(),
    this.rescheduledFromId = const Value.absent(),
    this.rescheduledToId = const Value.absent(),
    this.isInbox = const Value.absent(),
    this.inboxContentVersion = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.missedAt = const Value.absent(),
    this.planTitleHistoryJson = const Value.absent(),
    this.displayPlanChangeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.estimatedDurationMin = const Value.absent(),
    this.actualDurationMin = const Value.absent(),
    this.manualDurationAdjustmentMin = const Value.absent(),
    this.manualActualSet = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    this.recurrenceRemovalReason = const Value.absent(),
    this.rescheduledFromId = const Value.absent(),
    this.rescheduledToId = const Value.absent(),
    this.isInbox = const Value.absent(),
    this.inboxContentVersion = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.missedAt = const Value.absent(),
    this.planTitleHistoryJson = const Value.absent(),
    this.displayPlanChangeId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<int>? estimatedDurationMin,
    Expression<int>? actualDurationMin,
    Expression<int>? manualDurationAdjustmentMin,
    Expression<bool>? manualActualSet,
    Expression<String>? categoryId,
    Expression<int>? priority,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<String>? recurringRuleId,
    Expression<String>? recurrenceRemovalReason,
    Expression<String>? rescheduledFromId,
    Expression<String>? rescheduledToId,
    Expression<bool>? isInbox,
    Expression<int>? inboxContentVersion,
    Expression<String>? dueDate,
    Expression<String>? missedAt,
    Expression<String>? planTitleHistoryJson,
    Expression<String>? displayPlanChangeId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (estimatedDurationMin != null)
        'estimated_duration_min': estimatedDurationMin,
      if (actualDurationMin != null) 'actual_duration_min': actualDurationMin,
      if (manualDurationAdjustmentMin != null)
        'manual_duration_adjustment_min': manualDurationAdjustmentMin,
      if (manualActualSet != null) 'manual_actual_set': manualActualSet,
      if (categoryId != null) 'category_id': categoryId,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (recurringRuleId != null) 'recurring_rule_id': recurringRuleId,
      if (recurrenceRemovalReason != null)
        'recurrence_removal_reason': recurrenceRemovalReason,
      if (rescheduledFromId != null) 'rescheduled_from_id': rescheduledFromId,
      if (rescheduledToId != null) 'rescheduled_to_id': rescheduledToId,
      if (isInbox != null) 'is_inbox': isInbox,
      if (inboxContentVersion != null)
        'inbox_content_version': inboxContentVersion,
      if (dueDate != null) 'due_date': dueDate,
      if (missedAt != null) 'missed_at': missedAt,
      if (planTitleHistoryJson != null)
        'plan_title_history_json': planTitleHistoryJson,
      if (displayPlanChangeId != null)
        'display_plan_change_id': displayPlanChangeId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime?>? startTime,
    Value<DateTime?>? endTime,
    Value<int?>? estimatedDurationMin,
    Value<int?>? actualDurationMin,
    Value<int>? manualDurationAdjustmentMin,
    Value<bool>? manualActualSet,
    Value<String?>? categoryId,
    Value<int>? priority,
    Value<String>? status,
    Value<String?>? notes,
    Value<String?>? recurringRuleId,
    Value<String?>? recurrenceRemovalReason,
    Value<String?>? rescheduledFromId,
    Value<String?>? rescheduledToId,
    Value<bool>? isInbox,
    Value<int>? inboxContentVersion,
    Value<String?>? dueDate,
    Value<String?>? missedAt,
    Value<String>? planTitleHistoryJson,
    Value<String?>? displayPlanChangeId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
      actualDurationMin: actualDurationMin ?? this.actualDurationMin,
      manualDurationAdjustmentMin:
          manualDurationAdjustmentMin ?? this.manualDurationAdjustmentMin,
      manualActualSet: manualActualSet ?? this.manualActualSet,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
      recurrenceRemovalReason:
          recurrenceRemovalReason ?? this.recurrenceRemovalReason,
      rescheduledFromId: rescheduledFromId ?? this.rescheduledFromId,
      rescheduledToId: rescheduledToId ?? this.rescheduledToId,
      isInbox: isInbox ?? this.isInbox,
      inboxContentVersion: inboxContentVersion ?? this.inboxContentVersion,
      dueDate: dueDate ?? this.dueDate,
      missedAt: missedAt ?? this.missedAt,
      planTitleHistoryJson: planTitleHistoryJson ?? this.planTitleHistoryJson,
      displayPlanChangeId: displayPlanChangeId ?? this.displayPlanChangeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(
        $TasksTable.$converterstartTime.toSql(startTime.value),
      );
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(
        $TasksTable.$converterendTime.toSql(endTime.value),
      );
    }
    if (estimatedDurationMin.present) {
      map['estimated_duration_min'] = Variable<int>(estimatedDurationMin.value);
    }
    if (actualDurationMin.present) {
      map['actual_duration_min'] = Variable<int>(actualDurationMin.value);
    }
    if (manualDurationAdjustmentMin.present) {
      map['manual_duration_adjustment_min'] = Variable<int>(
        manualDurationAdjustmentMin.value,
      );
    }
    if (manualActualSet.present) {
      map['manual_actual_set'] = Variable<bool>(manualActualSet.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (recurringRuleId.present) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId.value);
    }
    if (recurrenceRemovalReason.present) {
      map['recurrence_removal_reason'] = Variable<String>(
        recurrenceRemovalReason.value,
      );
    }
    if (rescheduledFromId.present) {
      map['rescheduled_from_id'] = Variable<String>(rescheduledFromId.value);
    }
    if (rescheduledToId.present) {
      map['rescheduled_to_id'] = Variable<String>(rescheduledToId.value);
    }
    if (isInbox.present) {
      map['is_inbox'] = Variable<bool>(isInbox.value);
    }
    if (inboxContentVersion.present) {
      map['inbox_content_version'] = Variable<int>(inboxContentVersion.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (missedAt.present) {
      map['missed_at'] = Variable<String>(missedAt.value);
    }
    if (planTitleHistoryJson.present) {
      map['plan_title_history_json'] = Variable<String>(
        planTitleHistoryJson.value,
      );
    }
    if (displayPlanChangeId.present) {
      map['display_plan_change_id'] = Variable<String>(
        displayPlanChangeId.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $TasksTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $TasksTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $TasksTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('estimatedDurationMin: $estimatedDurationMin, ')
          ..write('actualDurationMin: $actualDurationMin, ')
          ..write('manualDurationAdjustmentMin: $manualDurationAdjustmentMin, ')
          ..write('manualActualSet: $manualActualSet, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write('recurrenceRemovalReason: $recurrenceRemovalReason, ')
          ..write('rescheduledFromId: $rescheduledFromId, ')
          ..write('rescheduledToId: $rescheduledToId, ')
          ..write('isInbox: $isInbox, ')
          ..write('inboxContentVersion: $inboxContentVersion, ')
          ..write('dueDate: $dueDate, ')
          ..write('missedAt: $missedAt, ')
          ..write('planTitleHistoryJson: $planTitleHistoryJson, ')
          ..write('displayPlanChangeId: $displayPlanChangeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DayContextsTable extends DayContexts
    with TableInfo<$DayContextsTable, DayContextRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayContextsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customLabelMeta = const VerificationMeta(
    'customLabel',
  );
  @override
  late final GeneratedColumn<String> customLabel = GeneratedColumn<String>(
    'custom_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DayContextsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DayContextsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($DayContextsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    kind,
    customLabel,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_contexts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DayContextRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('custom_label')) {
      context.handle(
        _customLabelMeta,
        customLabel.isAcceptableOrUnknown(
          data['custom_label']!,
          _customLabelMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {date},
  ];
  @override
  DayContextRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DayContextRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      customLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_label'],
      ),
      createdAt: $DayContextsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $DayContextsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $DayContextsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $DayContextsTable createAlias(String alias) {
    return $DayContextsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class DayContextRow extends DataClass implements Insertable<DayContextRow> {
  final String id;
  final String date;
  final String kind;
  final String? customLabel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const DayContextRow({
    required this.id,
    required this.date,
    required this.kind,
    this.customLabel,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || customLabel != null) {
      map['custom_label'] = Variable<String>(customLabel);
    }
    {
      map['created_at'] = Variable<String>(
        $DayContextsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $DayContextsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $DayContextsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  DayContextsCompanion toCompanion(bool nullToAbsent) {
    return DayContextsCompanion(
      id: Value(id),
      date: Value(date),
      kind: Value(kind),
      customLabel: customLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(customLabel),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory DayContextRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DayContextRow(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      kind: serializer.fromJson<String>(json['kind']),
      customLabel: serializer.fromJson<String?>(json['customLabel']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'kind': serializer.toJson<String>(kind),
      'customLabel': serializer.toJson<String?>(customLabel),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  DayContextRow copyWith({
    String? id,
    String? date,
    String? kind,
    Value<String?> customLabel = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => DayContextRow(
    id: id ?? this.id,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    customLabel: customLabel.present ? customLabel.value : this.customLabel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  DayContextRow copyWithCompanion(DayContextsCompanion data) {
    return DayContextRow(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      kind: data.kind.present ? data.kind.value : this.kind,
      customLabel: data.customLabel.present
          ? data.customLabel.value
          : this.customLabel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayContextRow(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('customLabel: $customLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    kind,
    customLabel,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayContextRow &&
          other.id == this.id &&
          other.date == this.date &&
          other.kind == this.kind &&
          other.customLabel == this.customLabel &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class DayContextsCompanion extends UpdateCompanion<DayContextRow> {
  final Value<String> id;
  final Value<String> date;
  final Value<String> kind;
  final Value<String?> customLabel;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const DayContextsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.kind = const Value.absent(),
    this.customLabel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DayContextsCompanion.insert({
    required String id,
    required String date,
    required String kind,
    this.customLabel = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       kind = Value(kind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DayContextRow> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? kind,
    Expression<String>? customLabel,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (kind != null) 'kind': kind,
      if (customLabel != null) 'custom_label': customLabel,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DayContextsCompanion copyWith({
    Value<String>? id,
    Value<String>? date,
    Value<String>? kind,
    Value<String?>? customLabel,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return DayContextsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      kind: kind ?? this.kind,
      customLabel: customLabel ?? this.customLabel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (customLabel.present) {
      map['custom_label'] = Variable<String>(customLabel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $DayContextsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $DayContextsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $DayContextsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayContextsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('kind: $kind, ')
          ..write('customLabel: $customLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubtasksTable extends Subtasks
    with TableInfo<$SubtasksTable, SubtaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubtasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SubtasksTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SubtasksTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SubtasksTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    title,
    isCompleted,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subtasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubtaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubtaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubtaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: $SubtasksTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $SubtasksTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $SubtasksTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $SubtasksTable createAlias(String alias) {
    return $SubtasksTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class SubtaskRow extends DataClass implements Insertable<SubtaskRow> {
  final String id;
  final String taskId;
  final String title;
  final bool isCompleted;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const SubtaskRow({
    required this.id,
    required this.taskId,
    required this.title,
    required this.isCompleted,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['title'] = Variable<String>(title);
    map['is_completed'] = Variable<bool>(isCompleted);
    map['sort_order'] = Variable<int>(sortOrder);
    {
      map['created_at'] = Variable<String>(
        $SubtasksTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $SubtasksTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $SubtasksTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  SubtasksCompanion toCompanion(bool nullToAbsent) {
    return SubtasksCompanion(
      id: Value(id),
      taskId: Value(taskId),
      title: Value(title),
      isCompleted: Value(isCompleted),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory SubtaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubtaskRow(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      title: serializer.fromJson<String>(json['title']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'title': serializer.toJson<String>(title),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  SubtaskRow copyWith({
    String? id,
    String? taskId,
    String? title,
    bool? isCompleted,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => SubtaskRow(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    title: title ?? this.title,
    isCompleted: isCompleted ?? this.isCompleted,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  SubtaskRow copyWithCompanion(SubtasksCompanion data) {
    return SubtaskRow(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      title: data.title.present ? data.title.value : this.title,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubtaskRow(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    title,
    isCompleted,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubtaskRow &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.title == this.title &&
          other.isCompleted == this.isCompleted &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class SubtasksCompanion extends UpdateCompanion<SubtaskRow> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> title;
  final Value<bool> isCompleted;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const SubtasksCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.title = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubtasksCompanion.insert({
    required String id,
    required String taskId,
    required String title,
    this.isCompleted = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SubtaskRow> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? title,
    Expression<bool>? isCompleted,
    Expression<int>? sortOrder,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (title != null) 'title': title,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubtasksCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? title,
    Value<bool>? isCompleted,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return SubtasksCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $SubtasksTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $SubtasksTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $SubtasksTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubtasksCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 100,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TagsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TagsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TagsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: $TagsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $TagsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $TagsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class TagRow extends DataClass implements Insertable<TagRow> {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const TagRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    {
      map['created_at'] = Variable<String>(
        $TagsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $TagsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $TagsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  TagRow copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $TagsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $TagsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $TagsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskTagsTable extends TaskTags
    with TableInfo<$TaskTagsTable, TaskTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TaskTagsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TaskTagsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TaskTagsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    tagId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId, tagId};
  @override
  TaskTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskTagRow(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      createdAt: $TaskTagsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $TaskTagsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $TaskTagsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $TaskTagsTable createAlias(String alias) {
    return $TaskTagsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class TaskTagRow extends DataClass implements Insertable<TaskTagRow> {
  final String taskId;
  final String tagId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const TaskTagRow({
    required this.taskId,
    required this.tagId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['tag_id'] = Variable<String>(tagId);
    {
      map['created_at'] = Variable<String>(
        $TaskTagsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $TaskTagsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $TaskTagsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  TaskTagsCompanion toCompanion(bool nullToAbsent) {
    return TaskTagsCompanion(
      taskId: Value(taskId),
      tagId: Value(tagId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory TaskTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskTagRow(
      taskId: serializer.fromJson<String>(json['taskId']),
      tagId: serializer.fromJson<String>(json['tagId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'tagId': serializer.toJson<String>(tagId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  TaskTagRow copyWith({
    String? taskId,
    String? tagId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => TaskTagRow(
    taskId: taskId ?? this.taskId,
    tagId: tagId ?? this.tagId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  TaskTagRow copyWithCompanion(TaskTagsCompanion data) {
    return TaskTagRow(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskTagRow(')
          ..write('taskId: $taskId, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    tagId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskTagRow &&
          other.taskId == this.taskId &&
          other.tagId == this.tagId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class TaskTagsCompanion extends UpdateCompanion<TaskTagRow> {
  final Value<String> taskId;
  final Value<String> tagId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const TaskTagsCompanion({
    this.taskId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskTagsCompanion.insert({
    required String taskId,
    required String tagId,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       tagId = Value(tagId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskTagRow> custom({
    Expression<String>? taskId,
    Expression<String>? tagId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (tagId != null) 'tag_id': tagId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskTagsCompanion copyWith({
    Value<String>? taskId,
    Value<String>? tagId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return TaskTagsCompanion(
      taskId: taskId ?? this.taskId,
      tagId: tagId ?? this.tagId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $TaskTagsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $TaskTagsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $TaskTagsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskTagsCompanion(')
          ..write('taskId: $taskId, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskTemplatesTable extends TaskTemplates
    with TableInfo<$TaskTemplatesTable, TaskTemplateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMinMeta = const VerificationMeta(
    'durationMin',
  );
  @override
  late final GeneratedColumn<int> durationMin = GeneratedColumn<int>(
    'duration_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TaskTemplatesTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TaskTemplatesTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TaskTemplatesTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    durationMin,
    categoryId,
    priority,
    tagsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskTemplateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('duration_min')) {
      context.handle(
        _durationMinMeta,
        durationMin.isAcceptableOrUnknown(
          data['duration_min']!,
          _durationMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationMinMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskTemplateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskTemplateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      durationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_min'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      ),
      createdAt: $TaskTemplatesTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $TaskTemplatesTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $TaskTemplatesTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $TaskTemplatesTable createAlias(String alias) {
    return $TaskTemplatesTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class TaskTemplateRow extends DataClass implements Insertable<TaskTemplateRow> {
  final String id;
  final String name;
  final String? description;
  final int durationMin;
  final String? categoryId;
  final int priority;
  final String? tagsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const TaskTemplateRow({
    required this.id,
    required this.name,
    this.description,
    required this.durationMin,
    this.categoryId,
    required this.priority,
    this.tagsJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['duration_min'] = Variable<int>(durationMin);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || tagsJson != null) {
      map['tags_json'] = Variable<String>(tagsJson);
    }
    {
      map['created_at'] = Variable<String>(
        $TaskTemplatesTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $TaskTemplatesTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $TaskTemplatesTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  TaskTemplatesCompanion toCompanion(bool nullToAbsent) {
    return TaskTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      durationMin: Value(durationMin),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      priority: Value(priority),
      tagsJson: tagsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tagsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory TaskTemplateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskTemplateRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      durationMin: serializer.fromJson<int>(json['durationMin']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      priority: serializer.fromJson<int>(json['priority']),
      tagsJson: serializer.fromJson<String?>(json['tagsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'durationMin': serializer.toJson<int>(durationMin),
      'categoryId': serializer.toJson<String?>(categoryId),
      'priority': serializer.toJson<int>(priority),
      'tagsJson': serializer.toJson<String?>(tagsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  TaskTemplateRow copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    int? durationMin,
    Value<String?> categoryId = const Value.absent(),
    int? priority,
    Value<String?> tagsJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => TaskTemplateRow(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    durationMin: durationMin ?? this.durationMin,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    priority: priority ?? this.priority,
    tagsJson: tagsJson.present ? tagsJson.value : this.tagsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  TaskTemplateRow copyWithCompanion(TaskTemplatesCompanion data) {
    return TaskTemplateRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      durationMin: data.durationMin.present
          ? data.durationMin.value
          : this.durationMin,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      priority: data.priority.present ? data.priority.value : this.priority,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskTemplateRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('durationMin: $durationMin, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    durationMin,
    categoryId,
    priority,
    tagsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskTemplateRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.durationMin == this.durationMin &&
          other.categoryId == this.categoryId &&
          other.priority == this.priority &&
          other.tagsJson == this.tagsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class TaskTemplatesCompanion extends UpdateCompanion<TaskTemplateRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> durationMin;
  final Value<String?> categoryId;
  final Value<int> priority;
  final Value<String?> tagsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const TaskTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.durationMin = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskTemplatesCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    required int durationMin,
    this.categoryId = const Value.absent(),
    this.priority = const Value.absent(),
    this.tagsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       durationMin = Value(durationMin),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskTemplateRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? durationMin,
    Expression<String>? categoryId,
    Expression<int>? priority,
    Expression<String>? tagsJson,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (durationMin != null) 'duration_min': durationMin,
      if (categoryId != null) 'category_id': categoryId,
      if (priority != null) 'priority': priority,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskTemplatesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? durationMin,
    Value<String?>? categoryId,
    Value<int>? priority,
    Value<String?>? tagsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return TaskTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      durationMin: durationMin ?? this.durationMin,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      tagsJson: tagsJson ?? this.tagsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (durationMin.present) {
      map['duration_min'] = Variable<int>(durationMin.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $TaskTemplatesTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $TaskTemplatesTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $TaskTemplatesTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('durationMin: $durationMin, ')
          ..write('categoryId: $categoryId, ')
          ..write('priority: $priority, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyReviewsTable extends DailyReviews
    with TableInfo<$DailyReviewsTable, DailyReviewRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyReviewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reflectionMeta = const VerificationMeta(
    'reflection',
  );
  @override
  late final GeneratedColumn<String> reflection = GeneratedColumn<String>(
    'reflection',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _energyLevelMeta = const VerificationMeta(
    'energyLevel',
  );
  @override
  late final GeneratedColumn<int> energyLevel = GeneratedColumn<int>(
    'energy_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productivityRatingMeta =
      const VerificationMeta('productivityRating');
  @override
  late final GeneratedColumn<int> productivityRating = GeneratedColumn<int>(
    'productivity_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planningAccuracyRatingMeta =
      const VerificationMeta('planningAccuracyRating');
  @override
  late final GeneratedColumn<int> planningAccuracyRating = GeneratedColumn<int>(
    'planning_accuracy_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _winsJsonMeta = const VerificationMeta(
    'winsJson',
  );
  @override
  late final GeneratedColumn<String> winsJson = GeneratedColumn<String>(
    'wins_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _improvementsJsonMeta = const VerificationMeta(
    'improvementsJson',
  );
  @override
  late final GeneratedColumn<String> improvementsJson = GeneratedColumn<String>(
    'improvements_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DailyReviewsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DailyReviewsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($DailyReviewsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    reflection,
    energyLevel,
    productivityRating,
    planningAccuracyRating,
    winsJson,
    improvementsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyReviewRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('reflection')) {
      context.handle(
        _reflectionMeta,
        reflection.isAcceptableOrUnknown(data['reflection']!, _reflectionMeta),
      );
    }
    if (data.containsKey('energy_level')) {
      context.handle(
        _energyLevelMeta,
        energyLevel.isAcceptableOrUnknown(
          data['energy_level']!,
          _energyLevelMeta,
        ),
      );
    }
    if (data.containsKey('productivity_rating')) {
      context.handle(
        _productivityRatingMeta,
        productivityRating.isAcceptableOrUnknown(
          data['productivity_rating']!,
          _productivityRatingMeta,
        ),
      );
    }
    if (data.containsKey('planning_accuracy_rating')) {
      context.handle(
        _planningAccuracyRatingMeta,
        planningAccuracyRating.isAcceptableOrUnknown(
          data['planning_accuracy_rating']!,
          _planningAccuracyRatingMeta,
        ),
      );
    }
    if (data.containsKey('wins_json')) {
      context.handle(
        _winsJsonMeta,
        winsJson.isAcceptableOrUnknown(data['wins_json']!, _winsJsonMeta),
      );
    }
    if (data.containsKey('improvements_json')) {
      context.handle(
        _improvementsJsonMeta,
        improvementsJson.isAcceptableOrUnknown(
          data['improvements_json']!,
          _improvementsJsonMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyReviewRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyReviewRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      reflection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reflection'],
      ),
      energyLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}energy_level'],
      ),
      productivityRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}productivity_rating'],
      ),
      planningAccuracyRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planning_accuracy_rating'],
      ),
      winsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wins_json'],
      ),
      improvementsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}improvements_json'],
      ),
      createdAt: $DailyReviewsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $DailyReviewsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $DailyReviewsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $DailyReviewsTable createAlias(String alias) {
    return $DailyReviewsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class DailyReviewRow extends DataClass implements Insertable<DailyReviewRow> {
  final String id;

  /// Local calendar day as `yyyy-MM-dd`; unique so a date has at most one
  /// review (architecture.md §3 DAILY_REVIEWS).
  final String date;
  final String? reflection;
  final int? energyLevel;
  final int? productivityRating;
  final int? planningAccuracyRating;
  final String? winsJson;
  final String? improvementsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const DailyReviewRow({
    required this.id,
    required this.date,
    this.reflection,
    this.energyLevel,
    this.productivityRating,
    this.planningAccuracyRating,
    this.winsJson,
    this.improvementsJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || reflection != null) {
      map['reflection'] = Variable<String>(reflection);
    }
    if (!nullToAbsent || energyLevel != null) {
      map['energy_level'] = Variable<int>(energyLevel);
    }
    if (!nullToAbsent || productivityRating != null) {
      map['productivity_rating'] = Variable<int>(productivityRating);
    }
    if (!nullToAbsent || planningAccuracyRating != null) {
      map['planning_accuracy_rating'] = Variable<int>(planningAccuracyRating);
    }
    if (!nullToAbsent || winsJson != null) {
      map['wins_json'] = Variable<String>(winsJson);
    }
    if (!nullToAbsent || improvementsJson != null) {
      map['improvements_json'] = Variable<String>(improvementsJson);
    }
    {
      map['created_at'] = Variable<String>(
        $DailyReviewsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $DailyReviewsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $DailyReviewsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  DailyReviewsCompanion toCompanion(bool nullToAbsent) {
    return DailyReviewsCompanion(
      id: Value(id),
      date: Value(date),
      reflection: reflection == null && nullToAbsent
          ? const Value.absent()
          : Value(reflection),
      energyLevel: energyLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(energyLevel),
      productivityRating: productivityRating == null && nullToAbsent
          ? const Value.absent()
          : Value(productivityRating),
      planningAccuracyRating: planningAccuracyRating == null && nullToAbsent
          ? const Value.absent()
          : Value(planningAccuracyRating),
      winsJson: winsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(winsJson),
      improvementsJson: improvementsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(improvementsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory DailyReviewRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyReviewRow(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      reflection: serializer.fromJson<String?>(json['reflection']),
      energyLevel: serializer.fromJson<int?>(json['energyLevel']),
      productivityRating: serializer.fromJson<int?>(json['productivityRating']),
      planningAccuracyRating: serializer.fromJson<int?>(
        json['planningAccuracyRating'],
      ),
      winsJson: serializer.fromJson<String?>(json['winsJson']),
      improvementsJson: serializer.fromJson<String?>(json['improvementsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'reflection': serializer.toJson<String?>(reflection),
      'energyLevel': serializer.toJson<int?>(energyLevel),
      'productivityRating': serializer.toJson<int?>(productivityRating),
      'planningAccuracyRating': serializer.toJson<int?>(planningAccuracyRating),
      'winsJson': serializer.toJson<String?>(winsJson),
      'improvementsJson': serializer.toJson<String?>(improvementsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  DailyReviewRow copyWith({
    String? id,
    String? date,
    Value<String?> reflection = const Value.absent(),
    Value<int?> energyLevel = const Value.absent(),
    Value<int?> productivityRating = const Value.absent(),
    Value<int?> planningAccuracyRating = const Value.absent(),
    Value<String?> winsJson = const Value.absent(),
    Value<String?> improvementsJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => DailyReviewRow(
    id: id ?? this.id,
    date: date ?? this.date,
    reflection: reflection.present ? reflection.value : this.reflection,
    energyLevel: energyLevel.present ? energyLevel.value : this.energyLevel,
    productivityRating: productivityRating.present
        ? productivityRating.value
        : this.productivityRating,
    planningAccuracyRating: planningAccuracyRating.present
        ? planningAccuracyRating.value
        : this.planningAccuracyRating,
    winsJson: winsJson.present ? winsJson.value : this.winsJson,
    improvementsJson: improvementsJson.present
        ? improvementsJson.value
        : this.improvementsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  DailyReviewRow copyWithCompanion(DailyReviewsCompanion data) {
    return DailyReviewRow(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      reflection: data.reflection.present
          ? data.reflection.value
          : this.reflection,
      energyLevel: data.energyLevel.present
          ? data.energyLevel.value
          : this.energyLevel,
      productivityRating: data.productivityRating.present
          ? data.productivityRating.value
          : this.productivityRating,
      planningAccuracyRating: data.planningAccuracyRating.present
          ? data.planningAccuracyRating.value
          : this.planningAccuracyRating,
      winsJson: data.winsJson.present ? data.winsJson.value : this.winsJson,
      improvementsJson: data.improvementsJson.present
          ? data.improvementsJson.value
          : this.improvementsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyReviewRow(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('reflection: $reflection, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('productivityRating: $productivityRating, ')
          ..write('planningAccuracyRating: $planningAccuracyRating, ')
          ..write('winsJson: $winsJson, ')
          ..write('improvementsJson: $improvementsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    reflection,
    energyLevel,
    productivityRating,
    planningAccuracyRating,
    winsJson,
    improvementsJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyReviewRow &&
          other.id == this.id &&
          other.date == this.date &&
          other.reflection == this.reflection &&
          other.energyLevel == this.energyLevel &&
          other.productivityRating == this.productivityRating &&
          other.planningAccuracyRating == this.planningAccuracyRating &&
          other.winsJson == this.winsJson &&
          other.improvementsJson == this.improvementsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class DailyReviewsCompanion extends UpdateCompanion<DailyReviewRow> {
  final Value<String> id;
  final Value<String> date;
  final Value<String?> reflection;
  final Value<int?> energyLevel;
  final Value<int?> productivityRating;
  final Value<int?> planningAccuracyRating;
  final Value<String?> winsJson;
  final Value<String?> improvementsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const DailyReviewsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.reflection = const Value.absent(),
    this.energyLevel = const Value.absent(),
    this.productivityRating = const Value.absent(),
    this.planningAccuracyRating = const Value.absent(),
    this.winsJson = const Value.absent(),
    this.improvementsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyReviewsCompanion.insert({
    required String id,
    required String date,
    this.reflection = const Value.absent(),
    this.energyLevel = const Value.absent(),
    this.productivityRating = const Value.absent(),
    this.planningAccuracyRating = const Value.absent(),
    this.winsJson = const Value.absent(),
    this.improvementsJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DailyReviewRow> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? reflection,
    Expression<int>? energyLevel,
    Expression<int>? productivityRating,
    Expression<int>? planningAccuracyRating,
    Expression<String>? winsJson,
    Expression<String>? improvementsJson,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (reflection != null) 'reflection': reflection,
      if (energyLevel != null) 'energy_level': energyLevel,
      if (productivityRating != null) 'productivity_rating': productivityRating,
      if (planningAccuracyRating != null)
        'planning_accuracy_rating': planningAccuracyRating,
      if (winsJson != null) 'wins_json': winsJson,
      if (improvementsJson != null) 'improvements_json': improvementsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyReviewsCompanion copyWith({
    Value<String>? id,
    Value<String>? date,
    Value<String?>? reflection,
    Value<int?>? energyLevel,
    Value<int?>? productivityRating,
    Value<int?>? planningAccuracyRating,
    Value<String?>? winsJson,
    Value<String?>? improvementsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return DailyReviewsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      reflection: reflection ?? this.reflection,
      energyLevel: energyLevel ?? this.energyLevel,
      productivityRating: productivityRating ?? this.productivityRating,
      planningAccuracyRating:
          planningAccuracyRating ?? this.planningAccuracyRating,
      winsJson: winsJson ?? this.winsJson,
      improvementsJson: improvementsJson ?? this.improvementsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (reflection.present) {
      map['reflection'] = Variable<String>(reflection.value);
    }
    if (energyLevel.present) {
      map['energy_level'] = Variable<int>(energyLevel.value);
    }
    if (productivityRating.present) {
      map['productivity_rating'] = Variable<int>(productivityRating.value);
    }
    if (planningAccuracyRating.present) {
      map['planning_accuracy_rating'] = Variable<int>(
        planningAccuracyRating.value,
      );
    }
    if (winsJson.present) {
      map['wins_json'] = Variable<String>(winsJson.value);
    }
    if (improvementsJson.present) {
      map['improvements_json'] = Variable<String>(improvementsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $DailyReviewsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $DailyReviewsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $DailyReviewsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyReviewsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('reflection: $reflection, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('productivityRating: $productivityRating, ')
          ..write('planningAccuracyRating: $planningAccuracyRating, ')
          ..write('winsJson: $winsJson, ')
          ..write('improvementsJson: $improvementsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WeeklyReviewsTable extends WeeklyReviews
    with TableInfo<$WeeklyReviewsTable, WeeklyReviewRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeeklyReviewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekStartDateMeta = const VerificationMeta(
    'weekStartDate',
  );
  @override
  late final GeneratedColumn<String> weekStartDate = GeneratedColumn<String>(
    'week_start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reflectionMeta = const VerificationMeta(
    'reflection',
  );
  @override
  late final GeneratedColumn<String> reflection = GeneratedColumn<String>(
    'reflection',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _overallRatingMeta = const VerificationMeta(
    'overallRating',
  );
  @override
  late final GeneratedColumn<int> overallRating = GeneratedColumn<int>(
    'overall_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _goalsMetJsonMeta = const VerificationMeta(
    'goalsMetJson',
  );
  @override
  late final GeneratedColumn<String> goalsMetJson = GeneratedColumn<String>(
    'goals_met_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _goalsMissedJsonMeta = const VerificationMeta(
    'goalsMissedJson',
  );
  @override
  late final GeneratedColumn<String> goalsMissedJson = GeneratedColumn<String>(
    'goals_missed_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextWeekFocusJsonMeta = const VerificationMeta(
    'nextWeekFocusJson',
  );
  @override
  late final GeneratedColumn<String> nextWeekFocusJson =
      GeneratedColumn<String>(
        'next_week_focus_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($WeeklyReviewsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($WeeklyReviewsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($WeeklyReviewsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    weekStartDate,
    reflection,
    overallRating,
    goalsMetJson,
    goalsMissedJson,
    nextWeekFocusJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weekly_reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<WeeklyReviewRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('week_start_date')) {
      context.handle(
        _weekStartDateMeta,
        weekStartDate.isAcceptableOrUnknown(
          data['week_start_date']!,
          _weekStartDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekStartDateMeta);
    }
    if (data.containsKey('reflection')) {
      context.handle(
        _reflectionMeta,
        reflection.isAcceptableOrUnknown(data['reflection']!, _reflectionMeta),
      );
    }
    if (data.containsKey('overall_rating')) {
      context.handle(
        _overallRatingMeta,
        overallRating.isAcceptableOrUnknown(
          data['overall_rating']!,
          _overallRatingMeta,
        ),
      );
    }
    if (data.containsKey('goals_met_json')) {
      context.handle(
        _goalsMetJsonMeta,
        goalsMetJson.isAcceptableOrUnknown(
          data['goals_met_json']!,
          _goalsMetJsonMeta,
        ),
      );
    }
    if (data.containsKey('goals_missed_json')) {
      context.handle(
        _goalsMissedJsonMeta,
        goalsMissedJson.isAcceptableOrUnknown(
          data['goals_missed_json']!,
          _goalsMissedJsonMeta,
        ),
      );
    }
    if (data.containsKey('next_week_focus_json')) {
      context.handle(
        _nextWeekFocusJsonMeta,
        nextWeekFocusJson.isAcceptableOrUnknown(
          data['next_week_focus_json']!,
          _nextWeekFocusJsonMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeeklyReviewRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeeklyReviewRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      weekStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_start_date'],
      )!,
      reflection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reflection'],
      ),
      overallRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}overall_rating'],
      ),
      goalsMetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goals_met_json'],
      ),
      goalsMissedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goals_missed_json'],
      ),
      nextWeekFocusJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_week_focus_json'],
      ),
      createdAt: $WeeklyReviewsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $WeeklyReviewsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $WeeklyReviewsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $WeeklyReviewsTable createAlias(String alias) {
    return $WeeklyReviewsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class WeeklyReviewRow extends DataClass implements Insertable<WeeklyReviewRow> {
  final String id;

  /// Monday of the reviewed week as `yyyy-MM-dd`; unique per week
  /// (architecture.md §3 WEEKLY_REVIEWS).
  final String weekStartDate;
  final String? reflection;
  final int? overallRating;
  final String? goalsMetJson;
  final String? goalsMissedJson;
  final String? nextWeekFocusJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const WeeklyReviewRow({
    required this.id,
    required this.weekStartDate,
    this.reflection,
    this.overallRating,
    this.goalsMetJson,
    this.goalsMissedJson,
    this.nextWeekFocusJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['week_start_date'] = Variable<String>(weekStartDate);
    if (!nullToAbsent || reflection != null) {
      map['reflection'] = Variable<String>(reflection);
    }
    if (!nullToAbsent || overallRating != null) {
      map['overall_rating'] = Variable<int>(overallRating);
    }
    if (!nullToAbsent || goalsMetJson != null) {
      map['goals_met_json'] = Variable<String>(goalsMetJson);
    }
    if (!nullToAbsent || goalsMissedJson != null) {
      map['goals_missed_json'] = Variable<String>(goalsMissedJson);
    }
    if (!nullToAbsent || nextWeekFocusJson != null) {
      map['next_week_focus_json'] = Variable<String>(nextWeekFocusJson);
    }
    {
      map['created_at'] = Variable<String>(
        $WeeklyReviewsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $WeeklyReviewsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $WeeklyReviewsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  WeeklyReviewsCompanion toCompanion(bool nullToAbsent) {
    return WeeklyReviewsCompanion(
      id: Value(id),
      weekStartDate: Value(weekStartDate),
      reflection: reflection == null && nullToAbsent
          ? const Value.absent()
          : Value(reflection),
      overallRating: overallRating == null && nullToAbsent
          ? const Value.absent()
          : Value(overallRating),
      goalsMetJson: goalsMetJson == null && nullToAbsent
          ? const Value.absent()
          : Value(goalsMetJson),
      goalsMissedJson: goalsMissedJson == null && nullToAbsent
          ? const Value.absent()
          : Value(goalsMissedJson),
      nextWeekFocusJson: nextWeekFocusJson == null && nullToAbsent
          ? const Value.absent()
          : Value(nextWeekFocusJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory WeeklyReviewRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeeklyReviewRow(
      id: serializer.fromJson<String>(json['id']),
      weekStartDate: serializer.fromJson<String>(json['weekStartDate']),
      reflection: serializer.fromJson<String?>(json['reflection']),
      overallRating: serializer.fromJson<int?>(json['overallRating']),
      goalsMetJson: serializer.fromJson<String?>(json['goalsMetJson']),
      goalsMissedJson: serializer.fromJson<String?>(json['goalsMissedJson']),
      nextWeekFocusJson: serializer.fromJson<String?>(
        json['nextWeekFocusJson'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'weekStartDate': serializer.toJson<String>(weekStartDate),
      'reflection': serializer.toJson<String?>(reflection),
      'overallRating': serializer.toJson<int?>(overallRating),
      'goalsMetJson': serializer.toJson<String?>(goalsMetJson),
      'goalsMissedJson': serializer.toJson<String?>(goalsMissedJson),
      'nextWeekFocusJson': serializer.toJson<String?>(nextWeekFocusJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  WeeklyReviewRow copyWith({
    String? id,
    String? weekStartDate,
    Value<String?> reflection = const Value.absent(),
    Value<int?> overallRating = const Value.absent(),
    Value<String?> goalsMetJson = const Value.absent(),
    Value<String?> goalsMissedJson = const Value.absent(),
    Value<String?> nextWeekFocusJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => WeeklyReviewRow(
    id: id ?? this.id,
    weekStartDate: weekStartDate ?? this.weekStartDate,
    reflection: reflection.present ? reflection.value : this.reflection,
    overallRating: overallRating.present
        ? overallRating.value
        : this.overallRating,
    goalsMetJson: goalsMetJson.present ? goalsMetJson.value : this.goalsMetJson,
    goalsMissedJson: goalsMissedJson.present
        ? goalsMissedJson.value
        : this.goalsMissedJson,
    nextWeekFocusJson: nextWeekFocusJson.present
        ? nextWeekFocusJson.value
        : this.nextWeekFocusJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  WeeklyReviewRow copyWithCompanion(WeeklyReviewsCompanion data) {
    return WeeklyReviewRow(
      id: data.id.present ? data.id.value : this.id,
      weekStartDate: data.weekStartDate.present
          ? data.weekStartDate.value
          : this.weekStartDate,
      reflection: data.reflection.present
          ? data.reflection.value
          : this.reflection,
      overallRating: data.overallRating.present
          ? data.overallRating.value
          : this.overallRating,
      goalsMetJson: data.goalsMetJson.present
          ? data.goalsMetJson.value
          : this.goalsMetJson,
      goalsMissedJson: data.goalsMissedJson.present
          ? data.goalsMissedJson.value
          : this.goalsMissedJson,
      nextWeekFocusJson: data.nextWeekFocusJson.present
          ? data.nextWeekFocusJson.value
          : this.nextWeekFocusJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeeklyReviewRow(')
          ..write('id: $id, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('reflection: $reflection, ')
          ..write('overallRating: $overallRating, ')
          ..write('goalsMetJson: $goalsMetJson, ')
          ..write('goalsMissedJson: $goalsMissedJson, ')
          ..write('nextWeekFocusJson: $nextWeekFocusJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    weekStartDate,
    reflection,
    overallRating,
    goalsMetJson,
    goalsMissedJson,
    nextWeekFocusJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeeklyReviewRow &&
          other.id == this.id &&
          other.weekStartDate == this.weekStartDate &&
          other.reflection == this.reflection &&
          other.overallRating == this.overallRating &&
          other.goalsMetJson == this.goalsMetJson &&
          other.goalsMissedJson == this.goalsMissedJson &&
          other.nextWeekFocusJson == this.nextWeekFocusJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class WeeklyReviewsCompanion extends UpdateCompanion<WeeklyReviewRow> {
  final Value<String> id;
  final Value<String> weekStartDate;
  final Value<String?> reflection;
  final Value<int?> overallRating;
  final Value<String?> goalsMetJson;
  final Value<String?> goalsMissedJson;
  final Value<String?> nextWeekFocusJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const WeeklyReviewsCompanion({
    this.id = const Value.absent(),
    this.weekStartDate = const Value.absent(),
    this.reflection = const Value.absent(),
    this.overallRating = const Value.absent(),
    this.goalsMetJson = const Value.absent(),
    this.goalsMissedJson = const Value.absent(),
    this.nextWeekFocusJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WeeklyReviewsCompanion.insert({
    required String id,
    required String weekStartDate,
    this.reflection = const Value.absent(),
    this.overallRating = const Value.absent(),
    this.goalsMetJson = const Value.absent(),
    this.goalsMissedJson = const Value.absent(),
    this.nextWeekFocusJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       weekStartDate = Value(weekStartDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WeeklyReviewRow> custom({
    Expression<String>? id,
    Expression<String>? weekStartDate,
    Expression<String>? reflection,
    Expression<int>? overallRating,
    Expression<String>? goalsMetJson,
    Expression<String>? goalsMissedJson,
    Expression<String>? nextWeekFocusJson,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (weekStartDate != null) 'week_start_date': weekStartDate,
      if (reflection != null) 'reflection': reflection,
      if (overallRating != null) 'overall_rating': overallRating,
      if (goalsMetJson != null) 'goals_met_json': goalsMetJson,
      if (goalsMissedJson != null) 'goals_missed_json': goalsMissedJson,
      if (nextWeekFocusJson != null) 'next_week_focus_json': nextWeekFocusJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WeeklyReviewsCompanion copyWith({
    Value<String>? id,
    Value<String>? weekStartDate,
    Value<String?>? reflection,
    Value<int?>? overallRating,
    Value<String?>? goalsMetJson,
    Value<String?>? goalsMissedJson,
    Value<String?>? nextWeekFocusJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return WeeklyReviewsCompanion(
      id: id ?? this.id,
      weekStartDate: weekStartDate ?? this.weekStartDate,
      reflection: reflection ?? this.reflection,
      overallRating: overallRating ?? this.overallRating,
      goalsMetJson: goalsMetJson ?? this.goalsMetJson,
      goalsMissedJson: goalsMissedJson ?? this.goalsMissedJson,
      nextWeekFocusJson: nextWeekFocusJson ?? this.nextWeekFocusJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (weekStartDate.present) {
      map['week_start_date'] = Variable<String>(weekStartDate.value);
    }
    if (reflection.present) {
      map['reflection'] = Variable<String>(reflection.value);
    }
    if (overallRating.present) {
      map['overall_rating'] = Variable<int>(overallRating.value);
    }
    if (goalsMetJson.present) {
      map['goals_met_json'] = Variable<String>(goalsMetJson.value);
    }
    if (goalsMissedJson.present) {
      map['goals_missed_json'] = Variable<String>(goalsMissedJson.value);
    }
    if (nextWeekFocusJson.present) {
      map['next_week_focus_json'] = Variable<String>(nextWeekFocusJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $WeeklyReviewsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $WeeklyReviewsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $WeeklyReviewsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeeklyReviewsCompanion(')
          ..write('id: $id, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('reflection: $reflection, ')
          ..write('overallRating: $overallRating, ')
          ..write('goalsMetJson: $goalsMetJson, ')
          ..write('goalsMissedJson: $goalsMissedJson, ')
          ..write('nextWeekFocusJson: $nextWeekFocusJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyStatsCacheTable extends DailyStatsCache
    with TableInfo<$DailyStatsCacheTable, DailyStatsCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyStatsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalTasksMeta = const VerificationMeta(
    'totalTasks',
  );
  @override
  late final GeneratedColumn<int> totalTasks = GeneratedColumn<int>(
    'total_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedTasksMeta = const VerificationMeta(
    'completedTasks',
  );
  @override
  late final GeneratedColumn<int> completedTasks = GeneratedColumn<int>(
    'completed_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _plannedTasksMeta = const VerificationMeta(
    'plannedTasks',
  );
  @override
  late final GeneratedColumn<int> plannedTasks = GeneratedColumn<int>(
    'planned_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _inProgressTasksMeta = const VerificationMeta(
    'inProgressTasks',
  );
  @override
  late final GeneratedColumn<int> inProgressTasks = GeneratedColumn<int>(
    'in_progress_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _missedTasksMeta = const VerificationMeta(
    'missedTasks',
  );
  @override
  late final GeneratedColumn<int> missedTasks = GeneratedColumn<int>(
    'missed_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skippedTasksMeta = const VerificationMeta(
    'skippedTasks',
  );
  @override
  late final GeneratedColumn<int> skippedTasks = GeneratedColumn<int>(
    'skipped_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cancelledTasksMeta = const VerificationMeta(
    'cancelledTasks',
  );
  @override
  late final GeneratedColumn<int> cancelledTasks = GeneratedColumn<int>(
    'cancelled_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rescheduledTasksMeta = const VerificationMeta(
    'rescheduledTasks',
  );
  @override
  late final GeneratedColumn<int> rescheduledTasks = GeneratedColumn<int>(
    'rescheduled_tasks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _plannedDurationMinMeta =
      const VerificationMeta('plannedDurationMin');
  @override
  late final GeneratedColumn<int> plannedDurationMin = GeneratedColumn<int>(
    'planned_duration_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _actualDurationMinMeta = const VerificationMeta(
    'actualDurationMin',
  );
  @override
  late final GeneratedColumn<int> actualDurationMin = GeneratedColumn<int>(
    'actual_duration_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _focusDurationMinMeta = const VerificationMeta(
    'focusDurationMin',
  );
  @override
  late final GeneratedColumn<int> focusDurationMin = GeneratedColumn<int>(
    'focus_duration_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _energyLevelMeta = const VerificationMeta(
    'energyLevel',
  );
  @override
  late final GeneratedColumn<int> energyLevel = GeneratedColumn<int>(
    'energy_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productivityRatingMeta =
      const VerificationMeta('productivityRating');
  @override
  late final GeneratedColumn<int> productivityRating = GeneratedColumn<int>(
    'productivity_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planningAccuracyPctMeta =
      const VerificationMeta('planningAccuracyPct');
  @override
  late final GeneratedColumn<double> planningAccuracyPct =
      GeneratedColumn<double>(
        'planning_accuracy_pct',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> computedAt =
      GeneratedColumn<String>(
        'computed_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($DailyStatsCacheTable.$convertercomputedAt);
  @override
  List<GeneratedColumn> get $columns => [
    date,
    totalTasks,
    completedTasks,
    plannedTasks,
    inProgressTasks,
    missedTasks,
    skippedTasks,
    cancelledTasks,
    rescheduledTasks,
    plannedDurationMin,
    actualDurationMin,
    focusDurationMin,
    energyLevel,
    productivityRating,
    planningAccuracyPct,
    computedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_stats_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyStatsCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('total_tasks')) {
      context.handle(
        _totalTasksMeta,
        totalTasks.isAcceptableOrUnknown(data['total_tasks']!, _totalTasksMeta),
      );
    }
    if (data.containsKey('completed_tasks')) {
      context.handle(
        _completedTasksMeta,
        completedTasks.isAcceptableOrUnknown(
          data['completed_tasks']!,
          _completedTasksMeta,
        ),
      );
    }
    if (data.containsKey('planned_tasks')) {
      context.handle(
        _plannedTasksMeta,
        plannedTasks.isAcceptableOrUnknown(
          data['planned_tasks']!,
          _plannedTasksMeta,
        ),
      );
    }
    if (data.containsKey('in_progress_tasks')) {
      context.handle(
        _inProgressTasksMeta,
        inProgressTasks.isAcceptableOrUnknown(
          data['in_progress_tasks']!,
          _inProgressTasksMeta,
        ),
      );
    }
    if (data.containsKey('missed_tasks')) {
      context.handle(
        _missedTasksMeta,
        missedTasks.isAcceptableOrUnknown(
          data['missed_tasks']!,
          _missedTasksMeta,
        ),
      );
    }
    if (data.containsKey('skipped_tasks')) {
      context.handle(
        _skippedTasksMeta,
        skippedTasks.isAcceptableOrUnknown(
          data['skipped_tasks']!,
          _skippedTasksMeta,
        ),
      );
    }
    if (data.containsKey('cancelled_tasks')) {
      context.handle(
        _cancelledTasksMeta,
        cancelledTasks.isAcceptableOrUnknown(
          data['cancelled_tasks']!,
          _cancelledTasksMeta,
        ),
      );
    }
    if (data.containsKey('rescheduled_tasks')) {
      context.handle(
        _rescheduledTasksMeta,
        rescheduledTasks.isAcceptableOrUnknown(
          data['rescheduled_tasks']!,
          _rescheduledTasksMeta,
        ),
      );
    }
    if (data.containsKey('planned_duration_min')) {
      context.handle(
        _plannedDurationMinMeta,
        plannedDurationMin.isAcceptableOrUnknown(
          data['planned_duration_min']!,
          _plannedDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('actual_duration_min')) {
      context.handle(
        _actualDurationMinMeta,
        actualDurationMin.isAcceptableOrUnknown(
          data['actual_duration_min']!,
          _actualDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('focus_duration_min')) {
      context.handle(
        _focusDurationMinMeta,
        focusDurationMin.isAcceptableOrUnknown(
          data['focus_duration_min']!,
          _focusDurationMinMeta,
        ),
      );
    }
    if (data.containsKey('energy_level')) {
      context.handle(
        _energyLevelMeta,
        energyLevel.isAcceptableOrUnknown(
          data['energy_level']!,
          _energyLevelMeta,
        ),
      );
    }
    if (data.containsKey('productivity_rating')) {
      context.handle(
        _productivityRatingMeta,
        productivityRating.isAcceptableOrUnknown(
          data['productivity_rating']!,
          _productivityRatingMeta,
        ),
      );
    }
    if (data.containsKey('planning_accuracy_pct')) {
      context.handle(
        _planningAccuracyPctMeta,
        planningAccuracyPct.isAcceptableOrUnknown(
          data['planning_accuracy_pct']!,
          _planningAccuracyPctMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailyStatsCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyStatsCacheRow(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      totalTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_tasks'],
      )!,
      completedTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_tasks'],
      )!,
      plannedTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_tasks'],
      )!,
      inProgressTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}in_progress_tasks'],
      )!,
      missedTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}missed_tasks'],
      )!,
      skippedTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skipped_tasks'],
      )!,
      cancelledTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cancelled_tasks'],
      )!,
      rescheduledTasks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rescheduled_tasks'],
      )!,
      plannedDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_duration_min'],
      )!,
      actualDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_duration_min'],
      )!,
      focusDurationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}focus_duration_min'],
      )!,
      energyLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}energy_level'],
      ),
      productivityRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}productivity_rating'],
      ),
      planningAccuracyPct: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}planning_accuracy_pct'],
      ),
      computedAt: $DailyStatsCacheTable.$convertercomputedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}computed_at'],
        )!,
      ),
    );
  }

  @override
  $DailyStatsCacheTable createAlias(String alias) {
    return $DailyStatsCacheTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercomputedAt =
      const DateTimeUtcConverter();
}

class DailyStatsCacheRow extends DataClass
    implements Insertable<DailyStatsCacheRow> {
  /// Local calendar day as `yyyy-MM-dd` (primary key).
  final String date;
  final int totalTasks;
  final int completedTasks;
  final int plannedTasks;
  final int inProgressTasks;
  final int missedTasks;
  final int skippedTasks;
  final int cancelledTasks;
  final int rescheduledTasks;
  final int plannedDurationMin;
  final int actualDurationMin;
  final int focusDurationMin;
  final int? energyLevel;
  final int? productivityRating;
  final double? planningAccuracyPct;
  final DateTime computedAt;
  const DailyStatsCacheRow({
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    required this.plannedTasks,
    required this.inProgressTasks,
    required this.missedTasks,
    required this.skippedTasks,
    required this.cancelledTasks,
    required this.rescheduledTasks,
    required this.plannedDurationMin,
    required this.actualDurationMin,
    required this.focusDurationMin,
    this.energyLevel,
    this.productivityRating,
    this.planningAccuracyPct,
    required this.computedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['total_tasks'] = Variable<int>(totalTasks);
    map['completed_tasks'] = Variable<int>(completedTasks);
    map['planned_tasks'] = Variable<int>(plannedTasks);
    map['in_progress_tasks'] = Variable<int>(inProgressTasks);
    map['missed_tasks'] = Variable<int>(missedTasks);
    map['skipped_tasks'] = Variable<int>(skippedTasks);
    map['cancelled_tasks'] = Variable<int>(cancelledTasks);
    map['rescheduled_tasks'] = Variable<int>(rescheduledTasks);
    map['planned_duration_min'] = Variable<int>(plannedDurationMin);
    map['actual_duration_min'] = Variable<int>(actualDurationMin);
    map['focus_duration_min'] = Variable<int>(focusDurationMin);
    if (!nullToAbsent || energyLevel != null) {
      map['energy_level'] = Variable<int>(energyLevel);
    }
    if (!nullToAbsent || productivityRating != null) {
      map['productivity_rating'] = Variable<int>(productivityRating);
    }
    if (!nullToAbsent || planningAccuracyPct != null) {
      map['planning_accuracy_pct'] = Variable<double>(planningAccuracyPct);
    }
    {
      map['computed_at'] = Variable<String>(
        $DailyStatsCacheTable.$convertercomputedAt.toSql(computedAt),
      );
    }
    return map;
  }

  DailyStatsCacheCompanion toCompanion(bool nullToAbsent) {
    return DailyStatsCacheCompanion(
      date: Value(date),
      totalTasks: Value(totalTasks),
      completedTasks: Value(completedTasks),
      plannedTasks: Value(plannedTasks),
      inProgressTasks: Value(inProgressTasks),
      missedTasks: Value(missedTasks),
      skippedTasks: Value(skippedTasks),
      cancelledTasks: Value(cancelledTasks),
      rescheduledTasks: Value(rescheduledTasks),
      plannedDurationMin: Value(plannedDurationMin),
      actualDurationMin: Value(actualDurationMin),
      focusDurationMin: Value(focusDurationMin),
      energyLevel: energyLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(energyLevel),
      productivityRating: productivityRating == null && nullToAbsent
          ? const Value.absent()
          : Value(productivityRating),
      planningAccuracyPct: planningAccuracyPct == null && nullToAbsent
          ? const Value.absent()
          : Value(planningAccuracyPct),
      computedAt: Value(computedAt),
    );
  }

  factory DailyStatsCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyStatsCacheRow(
      date: serializer.fromJson<String>(json['date']),
      totalTasks: serializer.fromJson<int>(json['totalTasks']),
      completedTasks: serializer.fromJson<int>(json['completedTasks']),
      plannedTasks: serializer.fromJson<int>(json['plannedTasks']),
      inProgressTasks: serializer.fromJson<int>(json['inProgressTasks']),
      missedTasks: serializer.fromJson<int>(json['missedTasks']),
      skippedTasks: serializer.fromJson<int>(json['skippedTasks']),
      cancelledTasks: serializer.fromJson<int>(json['cancelledTasks']),
      rescheduledTasks: serializer.fromJson<int>(json['rescheduledTasks']),
      plannedDurationMin: serializer.fromJson<int>(json['plannedDurationMin']),
      actualDurationMin: serializer.fromJson<int>(json['actualDurationMin']),
      focusDurationMin: serializer.fromJson<int>(json['focusDurationMin']),
      energyLevel: serializer.fromJson<int?>(json['energyLevel']),
      productivityRating: serializer.fromJson<int?>(json['productivityRating']),
      planningAccuracyPct: serializer.fromJson<double?>(
        json['planningAccuracyPct'],
      ),
      computedAt: serializer.fromJson<DateTime>(json['computedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'totalTasks': serializer.toJson<int>(totalTasks),
      'completedTasks': serializer.toJson<int>(completedTasks),
      'plannedTasks': serializer.toJson<int>(plannedTasks),
      'inProgressTasks': serializer.toJson<int>(inProgressTasks),
      'missedTasks': serializer.toJson<int>(missedTasks),
      'skippedTasks': serializer.toJson<int>(skippedTasks),
      'cancelledTasks': serializer.toJson<int>(cancelledTasks),
      'rescheduledTasks': serializer.toJson<int>(rescheduledTasks),
      'plannedDurationMin': serializer.toJson<int>(plannedDurationMin),
      'actualDurationMin': serializer.toJson<int>(actualDurationMin),
      'focusDurationMin': serializer.toJson<int>(focusDurationMin),
      'energyLevel': serializer.toJson<int?>(energyLevel),
      'productivityRating': serializer.toJson<int?>(productivityRating),
      'planningAccuracyPct': serializer.toJson<double?>(planningAccuracyPct),
      'computedAt': serializer.toJson<DateTime>(computedAt),
    };
  }

  DailyStatsCacheRow copyWith({
    String? date,
    int? totalTasks,
    int? completedTasks,
    int? plannedTasks,
    int? inProgressTasks,
    int? missedTasks,
    int? skippedTasks,
    int? cancelledTasks,
    int? rescheduledTasks,
    int? plannedDurationMin,
    int? actualDurationMin,
    int? focusDurationMin,
    Value<int?> energyLevel = const Value.absent(),
    Value<int?> productivityRating = const Value.absent(),
    Value<double?> planningAccuracyPct = const Value.absent(),
    DateTime? computedAt,
  }) => DailyStatsCacheRow(
    date: date ?? this.date,
    totalTasks: totalTasks ?? this.totalTasks,
    completedTasks: completedTasks ?? this.completedTasks,
    plannedTasks: plannedTasks ?? this.plannedTasks,
    inProgressTasks: inProgressTasks ?? this.inProgressTasks,
    missedTasks: missedTasks ?? this.missedTasks,
    skippedTasks: skippedTasks ?? this.skippedTasks,
    cancelledTasks: cancelledTasks ?? this.cancelledTasks,
    rescheduledTasks: rescheduledTasks ?? this.rescheduledTasks,
    plannedDurationMin: plannedDurationMin ?? this.plannedDurationMin,
    actualDurationMin: actualDurationMin ?? this.actualDurationMin,
    focusDurationMin: focusDurationMin ?? this.focusDurationMin,
    energyLevel: energyLevel.present ? energyLevel.value : this.energyLevel,
    productivityRating: productivityRating.present
        ? productivityRating.value
        : this.productivityRating,
    planningAccuracyPct: planningAccuracyPct.present
        ? planningAccuracyPct.value
        : this.planningAccuracyPct,
    computedAt: computedAt ?? this.computedAt,
  );
  DailyStatsCacheRow copyWithCompanion(DailyStatsCacheCompanion data) {
    return DailyStatsCacheRow(
      date: data.date.present ? data.date.value : this.date,
      totalTasks: data.totalTasks.present
          ? data.totalTasks.value
          : this.totalTasks,
      completedTasks: data.completedTasks.present
          ? data.completedTasks.value
          : this.completedTasks,
      plannedTasks: data.plannedTasks.present
          ? data.plannedTasks.value
          : this.plannedTasks,
      inProgressTasks: data.inProgressTasks.present
          ? data.inProgressTasks.value
          : this.inProgressTasks,
      missedTasks: data.missedTasks.present
          ? data.missedTasks.value
          : this.missedTasks,
      skippedTasks: data.skippedTasks.present
          ? data.skippedTasks.value
          : this.skippedTasks,
      cancelledTasks: data.cancelledTasks.present
          ? data.cancelledTasks.value
          : this.cancelledTasks,
      rescheduledTasks: data.rescheduledTasks.present
          ? data.rescheduledTasks.value
          : this.rescheduledTasks,
      plannedDurationMin: data.plannedDurationMin.present
          ? data.plannedDurationMin.value
          : this.plannedDurationMin,
      actualDurationMin: data.actualDurationMin.present
          ? data.actualDurationMin.value
          : this.actualDurationMin,
      focusDurationMin: data.focusDurationMin.present
          ? data.focusDurationMin.value
          : this.focusDurationMin,
      energyLevel: data.energyLevel.present
          ? data.energyLevel.value
          : this.energyLevel,
      productivityRating: data.productivityRating.present
          ? data.productivityRating.value
          : this.productivityRating,
      planningAccuracyPct: data.planningAccuracyPct.present
          ? data.planningAccuracyPct.value
          : this.planningAccuracyPct,
      computedAt: data.computedAt.present
          ? data.computedAt.value
          : this.computedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStatsCacheRow(')
          ..write('date: $date, ')
          ..write('totalTasks: $totalTasks, ')
          ..write('completedTasks: $completedTasks, ')
          ..write('plannedTasks: $plannedTasks, ')
          ..write('inProgressTasks: $inProgressTasks, ')
          ..write('missedTasks: $missedTasks, ')
          ..write('skippedTasks: $skippedTasks, ')
          ..write('cancelledTasks: $cancelledTasks, ')
          ..write('rescheduledTasks: $rescheduledTasks, ')
          ..write('plannedDurationMin: $plannedDurationMin, ')
          ..write('actualDurationMin: $actualDurationMin, ')
          ..write('focusDurationMin: $focusDurationMin, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('productivityRating: $productivityRating, ')
          ..write('planningAccuracyPct: $planningAccuracyPct, ')
          ..write('computedAt: $computedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    totalTasks,
    completedTasks,
    plannedTasks,
    inProgressTasks,
    missedTasks,
    skippedTasks,
    cancelledTasks,
    rescheduledTasks,
    plannedDurationMin,
    actualDurationMin,
    focusDurationMin,
    energyLevel,
    productivityRating,
    planningAccuracyPct,
    computedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStatsCacheRow &&
          other.date == this.date &&
          other.totalTasks == this.totalTasks &&
          other.completedTasks == this.completedTasks &&
          other.plannedTasks == this.plannedTasks &&
          other.inProgressTasks == this.inProgressTasks &&
          other.missedTasks == this.missedTasks &&
          other.skippedTasks == this.skippedTasks &&
          other.cancelledTasks == this.cancelledTasks &&
          other.rescheduledTasks == this.rescheduledTasks &&
          other.plannedDurationMin == this.plannedDurationMin &&
          other.actualDurationMin == this.actualDurationMin &&
          other.focusDurationMin == this.focusDurationMin &&
          other.energyLevel == this.energyLevel &&
          other.productivityRating == this.productivityRating &&
          other.planningAccuracyPct == this.planningAccuracyPct &&
          other.computedAt == this.computedAt);
}

class DailyStatsCacheCompanion extends UpdateCompanion<DailyStatsCacheRow> {
  final Value<String> date;
  final Value<int> totalTasks;
  final Value<int> completedTasks;
  final Value<int> plannedTasks;
  final Value<int> inProgressTasks;
  final Value<int> missedTasks;
  final Value<int> skippedTasks;
  final Value<int> cancelledTasks;
  final Value<int> rescheduledTasks;
  final Value<int> plannedDurationMin;
  final Value<int> actualDurationMin;
  final Value<int> focusDurationMin;
  final Value<int?> energyLevel;
  final Value<int?> productivityRating;
  final Value<double?> planningAccuracyPct;
  final Value<DateTime> computedAt;
  final Value<int> rowid;
  const DailyStatsCacheCompanion({
    this.date = const Value.absent(),
    this.totalTasks = const Value.absent(),
    this.completedTasks = const Value.absent(),
    this.plannedTasks = const Value.absent(),
    this.inProgressTasks = const Value.absent(),
    this.missedTasks = const Value.absent(),
    this.skippedTasks = const Value.absent(),
    this.cancelledTasks = const Value.absent(),
    this.rescheduledTasks = const Value.absent(),
    this.plannedDurationMin = const Value.absent(),
    this.actualDurationMin = const Value.absent(),
    this.focusDurationMin = const Value.absent(),
    this.energyLevel = const Value.absent(),
    this.productivityRating = const Value.absent(),
    this.planningAccuracyPct = const Value.absent(),
    this.computedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyStatsCacheCompanion.insert({
    required String date,
    this.totalTasks = const Value.absent(),
    this.completedTasks = const Value.absent(),
    this.plannedTasks = const Value.absent(),
    this.inProgressTasks = const Value.absent(),
    this.missedTasks = const Value.absent(),
    this.skippedTasks = const Value.absent(),
    this.cancelledTasks = const Value.absent(),
    this.rescheduledTasks = const Value.absent(),
    this.plannedDurationMin = const Value.absent(),
    this.actualDurationMin = const Value.absent(),
    this.focusDurationMin = const Value.absent(),
    this.energyLevel = const Value.absent(),
    this.productivityRating = const Value.absent(),
    this.planningAccuracyPct = const Value.absent(),
    required DateTime computedAt,
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       computedAt = Value(computedAt);
  static Insertable<DailyStatsCacheRow> custom({
    Expression<String>? date,
    Expression<int>? totalTasks,
    Expression<int>? completedTasks,
    Expression<int>? plannedTasks,
    Expression<int>? inProgressTasks,
    Expression<int>? missedTasks,
    Expression<int>? skippedTasks,
    Expression<int>? cancelledTasks,
    Expression<int>? rescheduledTasks,
    Expression<int>? plannedDurationMin,
    Expression<int>? actualDurationMin,
    Expression<int>? focusDurationMin,
    Expression<int>? energyLevel,
    Expression<int>? productivityRating,
    Expression<double>? planningAccuracyPct,
    Expression<String>? computedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (totalTasks != null) 'total_tasks': totalTasks,
      if (completedTasks != null) 'completed_tasks': completedTasks,
      if (plannedTasks != null) 'planned_tasks': plannedTasks,
      if (inProgressTasks != null) 'in_progress_tasks': inProgressTasks,
      if (missedTasks != null) 'missed_tasks': missedTasks,
      if (skippedTasks != null) 'skipped_tasks': skippedTasks,
      if (cancelledTasks != null) 'cancelled_tasks': cancelledTasks,
      if (rescheduledTasks != null) 'rescheduled_tasks': rescheduledTasks,
      if (plannedDurationMin != null)
        'planned_duration_min': plannedDurationMin,
      if (actualDurationMin != null) 'actual_duration_min': actualDurationMin,
      if (focusDurationMin != null) 'focus_duration_min': focusDurationMin,
      if (energyLevel != null) 'energy_level': energyLevel,
      if (productivityRating != null) 'productivity_rating': productivityRating,
      if (planningAccuracyPct != null)
        'planning_accuracy_pct': planningAccuracyPct,
      if (computedAt != null) 'computed_at': computedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyStatsCacheCompanion copyWith({
    Value<String>? date,
    Value<int>? totalTasks,
    Value<int>? completedTasks,
    Value<int>? plannedTasks,
    Value<int>? inProgressTasks,
    Value<int>? missedTasks,
    Value<int>? skippedTasks,
    Value<int>? cancelledTasks,
    Value<int>? rescheduledTasks,
    Value<int>? plannedDurationMin,
    Value<int>? actualDurationMin,
    Value<int>? focusDurationMin,
    Value<int?>? energyLevel,
    Value<int?>? productivityRating,
    Value<double?>? planningAccuracyPct,
    Value<DateTime>? computedAt,
    Value<int>? rowid,
  }) {
    return DailyStatsCacheCompanion(
      date: date ?? this.date,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      plannedTasks: plannedTasks ?? this.plannedTasks,
      inProgressTasks: inProgressTasks ?? this.inProgressTasks,
      missedTasks: missedTasks ?? this.missedTasks,
      skippedTasks: skippedTasks ?? this.skippedTasks,
      cancelledTasks: cancelledTasks ?? this.cancelledTasks,
      rescheduledTasks: rescheduledTasks ?? this.rescheduledTasks,
      plannedDurationMin: plannedDurationMin ?? this.plannedDurationMin,
      actualDurationMin: actualDurationMin ?? this.actualDurationMin,
      focusDurationMin: focusDurationMin ?? this.focusDurationMin,
      energyLevel: energyLevel ?? this.energyLevel,
      productivityRating: productivityRating ?? this.productivityRating,
      planningAccuracyPct: planningAccuracyPct ?? this.planningAccuracyPct,
      computedAt: computedAt ?? this.computedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (totalTasks.present) {
      map['total_tasks'] = Variable<int>(totalTasks.value);
    }
    if (completedTasks.present) {
      map['completed_tasks'] = Variable<int>(completedTasks.value);
    }
    if (plannedTasks.present) {
      map['planned_tasks'] = Variable<int>(plannedTasks.value);
    }
    if (inProgressTasks.present) {
      map['in_progress_tasks'] = Variable<int>(inProgressTasks.value);
    }
    if (missedTasks.present) {
      map['missed_tasks'] = Variable<int>(missedTasks.value);
    }
    if (skippedTasks.present) {
      map['skipped_tasks'] = Variable<int>(skippedTasks.value);
    }
    if (cancelledTasks.present) {
      map['cancelled_tasks'] = Variable<int>(cancelledTasks.value);
    }
    if (rescheduledTasks.present) {
      map['rescheduled_tasks'] = Variable<int>(rescheduledTasks.value);
    }
    if (plannedDurationMin.present) {
      map['planned_duration_min'] = Variable<int>(plannedDurationMin.value);
    }
    if (actualDurationMin.present) {
      map['actual_duration_min'] = Variable<int>(actualDurationMin.value);
    }
    if (focusDurationMin.present) {
      map['focus_duration_min'] = Variable<int>(focusDurationMin.value);
    }
    if (energyLevel.present) {
      map['energy_level'] = Variable<int>(energyLevel.value);
    }
    if (productivityRating.present) {
      map['productivity_rating'] = Variable<int>(productivityRating.value);
    }
    if (planningAccuracyPct.present) {
      map['planning_accuracy_pct'] = Variable<double>(
        planningAccuracyPct.value,
      );
    }
    if (computedAt.present) {
      map['computed_at'] = Variable<String>(
        $DailyStatsCacheTable.$convertercomputedAt.toSql(computedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyStatsCacheCompanion(')
          ..write('date: $date, ')
          ..write('totalTasks: $totalTasks, ')
          ..write('completedTasks: $completedTasks, ')
          ..write('plannedTasks: $plannedTasks, ')
          ..write('inProgressTasks: $inProgressTasks, ')
          ..write('missedTasks: $missedTasks, ')
          ..write('skippedTasks: $skippedTasks, ')
          ..write('cancelledTasks: $cancelledTasks, ')
          ..write('rescheduledTasks: $rescheduledTasks, ')
          ..write('plannedDurationMin: $plannedDurationMin, ')
          ..write('actualDurationMin: $actualDurationMin, ')
          ..write('focusDurationMin: $focusDurationMin, ')
          ..write('energyLevel: $energyLevel, ')
          ..write('productivityRating: $productivityRating, ')
          ..write('planningAccuracyPct: $planningAccuracyPct, ')
          ..write('computedAt: $computedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimerSessionsTable extends TimerSessions
    with TableInfo<$TimerSessionsTable, TimerSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimerSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> startedAt =
      GeneratedColumn<String>(
        'started_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TimerSessionsTable.$converterstartedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> endedAt =
      GeneratedColumn<String>(
        'ended_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TimerSessionsTable.$converterendedAt);
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('finished'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> runningSince =
      GeneratedColumn<String>(
        'running_since',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TimerSessionsTable.$converterrunningSince);
  static const VerificationMeta _workIntervalsJsonMeta = const VerificationMeta(
    'workIntervalsJson',
  );
  @override
  late final GeneratedColumn<String> workIntervalsJson =
      GeneratedColumn<String>(
        'work_intervals_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _ownerDeviceIdMeta = const VerificationMeta(
    'ownerDeviceId',
  );
  @override
  late final GeneratedColumn<String> ownerDeviceId = GeneratedColumn<String>(
    'owner_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TimerSessionsTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TimerSessionsTable.$converterupdatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> deletedAt =
      GeneratedColumn<String>(
        'deleted_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($TimerSessionsTable.$converterdeletedAt);
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<int> syncStatus = GeneratedColumn<int>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    startedAt,
    endedAt,
    durationSec,
    state,
    runningSince,
    workIntervalsJson,
    ownerDeviceId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'timer_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TimerSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('work_intervals_json')) {
      context.handle(
        _workIntervalsJsonMeta,
        workIntervalsJson.isAcceptableOrUnknown(
          data['work_intervals_json']!,
          _workIntervalsJsonMeta,
        ),
      );
    }
    if (data.containsKey('owner_device_id')) {
      context.handle(
        _ownerDeviceIdMeta,
        ownerDeviceId.isAcceptableOrUnknown(
          data['owner_device_id']!,
          _ownerDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimerSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimerSessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      startedAt: $TimerSessionsTable.$converterstartedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}started_at'],
        )!,
      ),
      endedAt: $TimerSessionsTable.$converterendedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}ended_at'],
        ),
      ),
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      runningSince: $TimerSessionsTable.$converterrunningSince.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}running_since'],
        ),
      ),
      workIntervalsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_intervals_json'],
      )!,
      ownerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_device_id'],
      ),
      createdAt: $TimerSessionsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $TimerSessionsTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      deletedAt: $TimerSessionsTable.$converterdeletedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}deleted_at'],
        ),
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_status'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
    );
  }

  @override
  $TimerSessionsTable createAlias(String alias) {
    return $TimerSessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $converterstartedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterendedAt =
      const NullableDateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterrunningSince =
      const NullableDateTimeUtcConverter();
  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime?, String?> $converterdeletedAt =
      const NullableDateTimeUtcConverter();
}

class TimerSessionRow extends DataClass implements Insertable<TimerSessionRow> {
  final String id;
  final String taskId;
  final DateTime startedAt;

  /// Null while the timer is running (architecture.md §3 TIMER_SESSIONS).
  final DateTime? endedAt;
  final int durationSec;
  final String state;
  final DateTime? runningSince;
  final String workIntervalsJson;
  final String? ownerDeviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int syncStatus;
  final int revision;
  final int? serverVersion;
  const TimerSessionRow({
    required this.id,
    required this.taskId,
    required this.startedAt,
    this.endedAt,
    required this.durationSec,
    required this.state,
    this.runningSince,
    required this.workIntervalsJson,
    this.ownerDeviceId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.revision,
    this.serverVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    {
      map['started_at'] = Variable<String>(
        $TimerSessionsTable.$converterstartedAt.toSql(startedAt),
      );
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<String>(
        $TimerSessionsTable.$converterendedAt.toSql(endedAt),
      );
    }
    map['duration_sec'] = Variable<int>(durationSec);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || runningSince != null) {
      map['running_since'] = Variable<String>(
        $TimerSessionsTable.$converterrunningSince.toSql(runningSince),
      );
    }
    map['work_intervals_json'] = Variable<String>(workIntervalsJson);
    if (!nullToAbsent || ownerDeviceId != null) {
      map['owner_device_id'] = Variable<String>(ownerDeviceId);
    }
    {
      map['created_at'] = Variable<String>(
        $TimerSessionsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $TimerSessionsTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(
        $TimerSessionsTable.$converterdeletedAt.toSql(deletedAt),
      );
    }
    map['sync_status'] = Variable<int>(syncStatus);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    return map;
  }

  TimerSessionsCompanion toCompanion(bool nullToAbsent) {
    return TimerSessionsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationSec: Value(durationSec),
      state: Value(state),
      runningSince: runningSince == null && nullToAbsent
          ? const Value.absent()
          : Value(runningSince),
      workIntervalsJson: Value(workIntervalsJson),
      ownerDeviceId: ownerDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerDeviceId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      revision: Value(revision),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
    );
  }

  factory TimerSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimerSessionRow(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationSec: serializer.fromJson<int>(json['durationSec']),
      state: serializer.fromJson<String>(json['state']),
      runningSince: serializer.fromJson<DateTime?>(json['runningSince']),
      workIntervalsJson: serializer.fromJson<String>(json['workIntervalsJson']),
      ownerDeviceId: serializer.fromJson<String?>(json['ownerDeviceId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<int>(json['syncStatus']),
      revision: serializer.fromJson<int>(json['revision']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationSec': serializer.toJson<int>(durationSec),
      'state': serializer.toJson<String>(state),
      'runningSince': serializer.toJson<DateTime?>(runningSince),
      'workIntervalsJson': serializer.toJson<String>(workIntervalsJson),
      'ownerDeviceId': serializer.toJson<String?>(ownerDeviceId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<int>(syncStatus),
      'revision': serializer.toJson<int>(revision),
      'serverVersion': serializer.toJson<int?>(serverVersion),
    };
  }

  TimerSessionRow copyWith({
    String? id,
    String? taskId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    int? durationSec,
    String? state,
    Value<DateTime?> runningSince = const Value.absent(),
    String? workIntervalsJson,
    Value<String?> ownerDeviceId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? syncStatus,
    int? revision,
    Value<int?> serverVersion = const Value.absent(),
  }) => TimerSessionRow(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationSec: durationSec ?? this.durationSec,
    state: state ?? this.state,
    runningSince: runningSince.present ? runningSince.value : this.runningSince,
    workIntervalsJson: workIntervalsJson ?? this.workIntervalsJson,
    ownerDeviceId: ownerDeviceId.present
        ? ownerDeviceId.value
        : this.ownerDeviceId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    revision: revision ?? this.revision,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
  );
  TimerSessionRow copyWithCompanion(TimerSessionsCompanion data) {
    return TimerSessionRow(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      state: data.state.present ? data.state.value : this.state,
      runningSince: data.runningSince.present
          ? data.runningSince.value
          : this.runningSince,
      workIntervalsJson: data.workIntervalsJson.present
          ? data.workIntervalsJson.value
          : this.workIntervalsJson,
      ownerDeviceId: data.ownerDeviceId.present
          ? data.ownerDeviceId.value
          : this.ownerDeviceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      revision: data.revision.present ? data.revision.value : this.revision,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimerSessionRow(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSec: $durationSec, ')
          ..write('state: $state, ')
          ..write('runningSince: $runningSince, ')
          ..write('workIntervalsJson: $workIntervalsJson, ')
          ..write('ownerDeviceId: $ownerDeviceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    startedAt,
    endedAt,
    durationSec,
    state,
    runningSince,
    workIntervalsJson,
    ownerDeviceId,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    revision,
    serverVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimerSessionRow &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationSec == this.durationSec &&
          other.state == this.state &&
          other.runningSince == this.runningSince &&
          other.workIntervalsJson == this.workIntervalsJson &&
          other.ownerDeviceId == this.ownerDeviceId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.revision == this.revision &&
          other.serverVersion == this.serverVersion);
}

class TimerSessionsCompanion extends UpdateCompanion<TimerSessionRow> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> durationSec;
  final Value<String> state;
  final Value<DateTime?> runningSince;
  final Value<String> workIntervalsJson;
  final Value<String?> ownerDeviceId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> syncStatus;
  final Value<int> revision;
  final Value<int?> serverVersion;
  final Value<int> rowid;
  const TimerSessionsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.state = const Value.absent(),
    this.runningSince = const Value.absent(),
    this.workIntervalsJson = const Value.absent(),
    this.ownerDeviceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimerSessionsCompanion.insert({
    required String id,
    required String taskId,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.state = const Value.absent(),
    this.runningSince = const Value.absent(),
    this.workIntervalsJson = const Value.absent(),
    this.ownerDeviceId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.revision = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       startedAt = Value(startedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TimerSessionRow> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? startedAt,
    Expression<String>? endedAt,
    Expression<int>? durationSec,
    Expression<String>? state,
    Expression<String>? runningSince,
    Expression<String>? workIntervalsJson,
    Expression<String>? ownerDeviceId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? syncStatus,
    Expression<int>? revision,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationSec != null) 'duration_sec': durationSec,
      if (state != null) 'state': state,
      if (runningSince != null) 'running_since': runningSince,
      if (workIntervalsJson != null) 'work_intervals_json': workIntervalsJson,
      if (ownerDeviceId != null) 'owner_device_id': ownerDeviceId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (revision != null) 'revision': revision,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimerSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? durationSec,
    Value<String>? state,
    Value<DateTime?>? runningSince,
    Value<String>? workIntervalsJson,
    Value<String?>? ownerDeviceId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? syncStatus,
    Value<int>? revision,
    Value<int?>? serverVersion,
    Value<int>? rowid,
  }) {
    return TimerSessionsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSec: durationSec ?? this.durationSec,
      state: state ?? this.state,
      runningSince: runningSince ?? this.runningSince,
      workIntervalsJson: workIntervalsJson ?? this.workIntervalsJson,
      ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(
        $TimerSessionsTable.$converterstartedAt.toSql(startedAt.value),
      );
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<String>(
        $TimerSessionsTable.$converterendedAt.toSql(endedAt.value),
      );
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (runningSince.present) {
      map['running_since'] = Variable<String>(
        $TimerSessionsTable.$converterrunningSince.toSql(runningSince.value),
      );
    }
    if (workIntervalsJson.present) {
      map['work_intervals_json'] = Variable<String>(workIntervalsJson.value);
    }
    if (ownerDeviceId.present) {
      map['owner_device_id'] = Variable<String>(ownerDeviceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $TimerSessionsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $TimerSessionsTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(
        $TimerSessionsTable.$converterdeletedAt.toSql(deletedAt.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<int>(syncStatus.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimerSessionsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSec: $durationSec, ')
          ..write('state: $state, ')
          ..write('runningSince: $runningSince, ')
          ..write('workIntervalsJson: $workIntervalsJson, ')
          ..write('ownerDeviceId: $ownerDeviceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('revision: $revision, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncLogTable extends SyncLog with TableInfo<$SyncLogTable, SyncLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTableNameMeta = const VerificationMeta(
    'entityTableName',
  );
  @override
  late final GeneratedColumn<String> entityTableName = GeneratedColumn<String>(
    'table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedServerVersionMeta =
      const VerificationMeta('expectedServerVersion');
  @override
  late final GeneratedColumn<int> expectedServerVersion = GeneratedColumn<int>(
    'expected_server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, String> nextAttemptAt =
      GeneratedColumn<String>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($SyncLogTable.$converternextAttemptAt);
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncLogTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncLogTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    entityTableName,
    recordId,
    operation,
    expectedServerVersion,
    payload,
    state,
    attemptCount,
    nextAttemptAt,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('table_name')) {
      context.handle(
        _entityTableNameMeta,
        entityTableName.isAcceptableOrUnknown(
          data['table_name']!,
          _entityTableNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableNameMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('expected_server_version')) {
      context.handle(
        _expectedServerVersionMeta,
        expectedServerVersion.isAcceptableOrUnknown(
          data['expected_server_version']!,
          _expectedServerVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  SyncLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLogRow(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      entityTableName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      expectedServerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_server_version'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: $SyncLogTable.$converternextAttemptAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}next_attempt_at'],
        ),
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: $SyncLogTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $SyncLogTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $SyncLogTable createAlias(String alias) {
    return $SyncLogTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime?, String?> $converternextAttemptAt =
      const NullableDateTimeUtcConverter();
  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
}

class SyncLogRow extends DataClass implements Insertable<SyncLogRow> {
  final String operationId;
  final String entityTableName;
  final String recordId;
  final String operation;
  final int? expectedServerVersion;
  final String payload;
  final String state;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SyncLogRow({
    required this.operationId,
    required this.entityTableName,
    required this.recordId,
    required this.operation,
    this.expectedServerVersion,
    required this.payload,
    required this.state,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['table_name'] = Variable<String>(entityTableName);
    map['record_id'] = Variable<String>(recordId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || expectedServerVersion != null) {
      map['expected_server_version'] = Variable<int>(expectedServerVersion);
    }
    map['payload'] = Variable<String>(payload);
    map['state'] = Variable<String>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<String>(
        $SyncLogTable.$converternextAttemptAt.toSql(nextAttemptAt),
      );
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    {
      map['created_at'] = Variable<String>(
        $SyncLogTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<String>(
        $SyncLogTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  SyncLogCompanion toCompanion(bool nullToAbsent) {
    return SyncLogCompanion(
      operationId: Value(operationId),
      entityTableName: Value(entityTableName),
      recordId: Value(recordId),
      operation: Value(operation),
      expectedServerVersion: expectedServerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedServerVersion),
      payload: Value(payload),
      state: Value(state),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLogRow(
      operationId: serializer.fromJson<String>(json['operationId']),
      entityTableName: serializer.fromJson<String>(json['entityTableName']),
      recordId: serializer.fromJson<String>(json['recordId']),
      operation: serializer.fromJson<String>(json['operation']),
      expectedServerVersion: serializer.fromJson<int?>(
        json['expectedServerVersion'],
      ),
      payload: serializer.fromJson<String>(json['payload']),
      state: serializer.fromJson<String>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'entityTableName': serializer.toJson<String>(entityTableName),
      'recordId': serializer.toJson<String>(recordId),
      'operation': serializer.toJson<String>(operation),
      'expectedServerVersion': serializer.toJson<int?>(expectedServerVersion),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<String>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncLogRow copyWith({
    String? operationId,
    String? entityTableName,
    String? recordId,
    String? operation,
    Value<int?> expectedServerVersion = const Value.absent(),
    String? payload,
    String? state,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SyncLogRow(
    operationId: operationId ?? this.operationId,
    entityTableName: entityTableName ?? this.entityTableName,
    recordId: recordId ?? this.recordId,
    operation: operation ?? this.operation,
    expectedServerVersion: expectedServerVersion.present
        ? expectedServerVersion.value
        : this.expectedServerVersion,
    payload: payload ?? this.payload,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncLogRow copyWithCompanion(SyncLogCompanion data) {
    return SyncLogRow(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      entityTableName: data.entityTableName.present
          ? data.entityTableName.value
          : this.entityTableName,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      operation: data.operation.present ? data.operation.value : this.operation,
      expectedServerVersion: data.expectedServerVersion.present
          ? data.expectedServerVersion.value
          : this.expectedServerVersion,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogRow(')
          ..write('operationId: $operationId, ')
          ..write('entityTableName: $entityTableName, ')
          ..write('recordId: $recordId, ')
          ..write('operation: $operation, ')
          ..write('expectedServerVersion: $expectedServerVersion, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    entityTableName,
    recordId,
    operation,
    expectedServerVersion,
    payload,
    state,
    attemptCount,
    nextAttemptAt,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLogRow &&
          other.operationId == this.operationId &&
          other.entityTableName == this.entityTableName &&
          other.recordId == this.recordId &&
          other.operation == this.operation &&
          other.expectedServerVersion == this.expectedServerVersion &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SyncLogCompanion extends UpdateCompanion<SyncLogRow> {
  final Value<String> operationId;
  final Value<String> entityTableName;
  final Value<String> recordId;
  final Value<String> operation;
  final Value<int?> expectedServerVersion;
  final Value<String> payload;
  final Value<String> state;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncLogCompanion({
    this.operationId = const Value.absent(),
    this.entityTableName = const Value.absent(),
    this.recordId = const Value.absent(),
    this.operation = const Value.absent(),
    this.expectedServerVersion = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncLogCompanion.insert({
    required String operationId,
    required String entityTableName,
    required String recordId,
    required String operation,
    this.expectedServerVersion = const Value.absent(),
    required String payload,
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       entityTableName = Value(entityTableName),
       recordId = Value(recordId),
       operation = Value(operation),
       payload = Value(payload),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SyncLogRow> custom({
    Expression<String>? operationId,
    Expression<String>? entityTableName,
    Expression<String>? recordId,
    Expression<String>? operation,
    Expression<int>? expectedServerVersion,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<int>? attemptCount,
    Expression<String>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (entityTableName != null) 'table_name': entityTableName,
      if (recordId != null) 'record_id': recordId,
      if (operation != null) 'operation': operation,
      if (expectedServerVersion != null)
        'expected_server_version': expectedServerVersion,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncLogCompanion copyWith({
    Value<String>? operationId,
    Value<String>? entityTableName,
    Value<String>? recordId,
    Value<String>? operation,
    Value<int?>? expectedServerVersion,
    Value<String>? payload,
    Value<String>? state,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncLogCompanion(
      operationId: operationId ?? this.operationId,
      entityTableName: entityTableName ?? this.entityTableName,
      recordId: recordId ?? this.recordId,
      operation: operation ?? this.operation,
      expectedServerVersion:
          expectedServerVersion ?? this.expectedServerVersion,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (entityTableName.present) {
      map['table_name'] = Variable<String>(entityTableName.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (expectedServerVersion.present) {
      map['expected_server_version'] = Variable<int>(
        expectedServerVersion.value,
      );
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<String>(
        $SyncLogTable.$converternextAttemptAt.toSql(nextAttemptAt.value),
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $SyncLogTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $SyncLogTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLogCompanion(')
          ..write('operationId: $operationId, ')
          ..write('entityTableName: $entityTableName, ')
          ..write('recordId: $recordId, ')
          ..write('operation: $operation, ')
          ..write('expectedServerVersion: $expectedServerVersion, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictsTable extends SyncConflicts
    with TableInfo<$SyncConflictsTable, SyncConflictRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTableNameMeta = const VerificationMeta(
    'entityTableName',
  );
  @override
  late final GeneratedColumn<String> entityTableName = GeneratedColumn<String>(
    'table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedServerVersionMeta =
      const VerificationMeta('expectedServerVersion');
  @override
  late final GeneratedColumn<int> expectedServerVersion = GeneratedColumn<int>(
    'expected_server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualServerVersionMeta =
      const VerificationMeta('actualServerVersion');
  @override
  late final GeneratedColumn<int> actualServerVersion = GeneratedColumn<int>(
    'actual_server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localSnapshotMeta = const VerificationMeta(
    'localSnapshot',
  );
  @override
  late final GeneratedColumn<String> localSnapshot = GeneratedColumn<String>(
    'local_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteSnapshotMeta = const VerificationMeta(
    'remoteSnapshot',
  );
  @override
  late final GeneratedColumn<String> remoteSnapshot = GeneratedColumn<String>(
    'remote_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> createdAt =
      GeneratedColumn<String>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncConflictsTable.$convertercreatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    operationId,
    entityTableName,
    recordId,
    expectedServerVersion,
    actualServerVersion,
    localSnapshot,
    remoteSnapshot,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflictRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('table_name')) {
      context.handle(
        _entityTableNameMeta,
        entityTableName.isAcceptableOrUnknown(
          data['table_name']!,
          _entityTableNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableNameMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('expected_server_version')) {
      context.handle(
        _expectedServerVersionMeta,
        expectedServerVersion.isAcceptableOrUnknown(
          data['expected_server_version']!,
          _expectedServerVersionMeta,
        ),
      );
    }
    if (data.containsKey('actual_server_version')) {
      context.handle(
        _actualServerVersionMeta,
        actualServerVersion.isAcceptableOrUnknown(
          data['actual_server_version']!,
          _actualServerVersionMeta,
        ),
      );
    }
    if (data.containsKey('local_snapshot')) {
      context.handle(
        _localSnapshotMeta,
        localSnapshot.isAcceptableOrUnknown(
          data['local_snapshot']!,
          _localSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localSnapshotMeta);
    }
    if (data.containsKey('remote_snapshot')) {
      context.handle(
        _remoteSnapshotMeta,
        remoteSnapshot.isAcceptableOrUnknown(
          data['remote_snapshot']!,
          _remoteSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteSnapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflictRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflictRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      entityTableName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      expectedServerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_server_version'],
      ),
      actualServerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_server_version'],
      ),
      localSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_snapshot'],
      )!,
      remoteSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_snapshot'],
      )!,
      createdAt: $SyncConflictsTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}created_at'],
        )!,
      ),
    );
  }

  @override
  $SyncConflictsTable createAlias(String alias) {
    return $SyncConflictsTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $convertercreatedAt =
      const DateTimeUtcConverter();
}

class SyncConflictRow extends DataClass implements Insertable<SyncConflictRow> {
  final String id;
  final String operationId;
  final String entityTableName;
  final String recordId;
  final int? expectedServerVersion;
  final int? actualServerVersion;
  final String localSnapshot;
  final String remoteSnapshot;
  final DateTime createdAt;
  const SyncConflictRow({
    required this.id,
    required this.operationId,
    required this.entityTableName,
    required this.recordId,
    this.expectedServerVersion,
    this.actualServerVersion,
    required this.localSnapshot,
    required this.remoteSnapshot,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['operation_id'] = Variable<String>(operationId);
    map['table_name'] = Variable<String>(entityTableName);
    map['record_id'] = Variable<String>(recordId);
    if (!nullToAbsent || expectedServerVersion != null) {
      map['expected_server_version'] = Variable<int>(expectedServerVersion);
    }
    if (!nullToAbsent || actualServerVersion != null) {
      map['actual_server_version'] = Variable<int>(actualServerVersion);
    }
    map['local_snapshot'] = Variable<String>(localSnapshot);
    map['remote_snapshot'] = Variable<String>(remoteSnapshot);
    {
      map['created_at'] = Variable<String>(
        $SyncConflictsTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    return map;
  }

  SyncConflictsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictsCompanion(
      id: Value(id),
      operationId: Value(operationId),
      entityTableName: Value(entityTableName),
      recordId: Value(recordId),
      expectedServerVersion: expectedServerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedServerVersion),
      actualServerVersion: actualServerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(actualServerVersion),
      localSnapshot: Value(localSnapshot),
      remoteSnapshot: Value(remoteSnapshot),
      createdAt: Value(createdAt),
    );
  }

  factory SyncConflictRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflictRow(
      id: serializer.fromJson<String>(json['id']),
      operationId: serializer.fromJson<String>(json['operationId']),
      entityTableName: serializer.fromJson<String>(json['entityTableName']),
      recordId: serializer.fromJson<String>(json['recordId']),
      expectedServerVersion: serializer.fromJson<int?>(
        json['expectedServerVersion'],
      ),
      actualServerVersion: serializer.fromJson<int?>(
        json['actualServerVersion'],
      ),
      localSnapshot: serializer.fromJson<String>(json['localSnapshot']),
      remoteSnapshot: serializer.fromJson<String>(json['remoteSnapshot']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'operationId': serializer.toJson<String>(operationId),
      'entityTableName': serializer.toJson<String>(entityTableName),
      'recordId': serializer.toJson<String>(recordId),
      'expectedServerVersion': serializer.toJson<int?>(expectedServerVersion),
      'actualServerVersion': serializer.toJson<int?>(actualServerVersion),
      'localSnapshot': serializer.toJson<String>(localSnapshot),
      'remoteSnapshot': serializer.toJson<String>(remoteSnapshot),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncConflictRow copyWith({
    String? id,
    String? operationId,
    String? entityTableName,
    String? recordId,
    Value<int?> expectedServerVersion = const Value.absent(),
    Value<int?> actualServerVersion = const Value.absent(),
    String? localSnapshot,
    String? remoteSnapshot,
    DateTime? createdAt,
  }) => SyncConflictRow(
    id: id ?? this.id,
    operationId: operationId ?? this.operationId,
    entityTableName: entityTableName ?? this.entityTableName,
    recordId: recordId ?? this.recordId,
    expectedServerVersion: expectedServerVersion.present
        ? expectedServerVersion.value
        : this.expectedServerVersion,
    actualServerVersion: actualServerVersion.present
        ? actualServerVersion.value
        : this.actualServerVersion,
    localSnapshot: localSnapshot ?? this.localSnapshot,
    remoteSnapshot: remoteSnapshot ?? this.remoteSnapshot,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncConflictRow copyWithCompanion(SyncConflictsCompanion data) {
    return SyncConflictRow(
      id: data.id.present ? data.id.value : this.id,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      entityTableName: data.entityTableName.present
          ? data.entityTableName.value
          : this.entityTableName,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      expectedServerVersion: data.expectedServerVersion.present
          ? data.expectedServerVersion.value
          : this.expectedServerVersion,
      actualServerVersion: data.actualServerVersion.present
          ? data.actualServerVersion.value
          : this.actualServerVersion,
      localSnapshot: data.localSnapshot.present
          ? data.localSnapshot.value
          : this.localSnapshot,
      remoteSnapshot: data.remoteSnapshot.present
          ? data.remoteSnapshot.value
          : this.remoteSnapshot,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictRow(')
          ..write('id: $id, ')
          ..write('operationId: $operationId, ')
          ..write('entityTableName: $entityTableName, ')
          ..write('recordId: $recordId, ')
          ..write('expectedServerVersion: $expectedServerVersion, ')
          ..write('actualServerVersion: $actualServerVersion, ')
          ..write('localSnapshot: $localSnapshot, ')
          ..write('remoteSnapshot: $remoteSnapshot, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    operationId,
    entityTableName,
    recordId,
    expectedServerVersion,
    actualServerVersion,
    localSnapshot,
    remoteSnapshot,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflictRow &&
          other.id == this.id &&
          other.operationId == this.operationId &&
          other.entityTableName == this.entityTableName &&
          other.recordId == this.recordId &&
          other.expectedServerVersion == this.expectedServerVersion &&
          other.actualServerVersion == this.actualServerVersion &&
          other.localSnapshot == this.localSnapshot &&
          other.remoteSnapshot == this.remoteSnapshot &&
          other.createdAt == this.createdAt);
}

class SyncConflictsCompanion extends UpdateCompanion<SyncConflictRow> {
  final Value<String> id;
  final Value<String> operationId;
  final Value<String> entityTableName;
  final Value<String> recordId;
  final Value<int?> expectedServerVersion;
  final Value<int?> actualServerVersion;
  final Value<String> localSnapshot;
  final Value<String> remoteSnapshot;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncConflictsCompanion({
    this.id = const Value.absent(),
    this.operationId = const Value.absent(),
    this.entityTableName = const Value.absent(),
    this.recordId = const Value.absent(),
    this.expectedServerVersion = const Value.absent(),
    this.actualServerVersion = const Value.absent(),
    this.localSnapshot = const Value.absent(),
    this.remoteSnapshot = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsCompanion.insert({
    required String id,
    required String operationId,
    required String entityTableName,
    required String recordId,
    this.expectedServerVersion = const Value.absent(),
    this.actualServerVersion = const Value.absent(),
    required String localSnapshot,
    required String remoteSnapshot,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       operationId = Value(operationId),
       entityTableName = Value(entityTableName),
       recordId = Value(recordId),
       localSnapshot = Value(localSnapshot),
       remoteSnapshot = Value(remoteSnapshot),
       createdAt = Value(createdAt);
  static Insertable<SyncConflictRow> custom({
    Expression<String>? id,
    Expression<String>? operationId,
    Expression<String>? entityTableName,
    Expression<String>? recordId,
    Expression<int>? expectedServerVersion,
    Expression<int>? actualServerVersion,
    Expression<String>? localSnapshot,
    Expression<String>? remoteSnapshot,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (operationId != null) 'operation_id': operationId,
      if (entityTableName != null) 'table_name': entityTableName,
      if (recordId != null) 'record_id': recordId,
      if (expectedServerVersion != null)
        'expected_server_version': expectedServerVersion,
      if (actualServerVersion != null)
        'actual_server_version': actualServerVersion,
      if (localSnapshot != null) 'local_snapshot': localSnapshot,
      if (remoteSnapshot != null) 'remote_snapshot': remoteSnapshot,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsCompanion copyWith({
    Value<String>? id,
    Value<String>? operationId,
    Value<String>? entityTableName,
    Value<String>? recordId,
    Value<int?>? expectedServerVersion,
    Value<int?>? actualServerVersion,
    Value<String>? localSnapshot,
    Value<String>? remoteSnapshot,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncConflictsCompanion(
      id: id ?? this.id,
      operationId: operationId ?? this.operationId,
      entityTableName: entityTableName ?? this.entityTableName,
      recordId: recordId ?? this.recordId,
      expectedServerVersion:
          expectedServerVersion ?? this.expectedServerVersion,
      actualServerVersion: actualServerVersion ?? this.actualServerVersion,
      localSnapshot: localSnapshot ?? this.localSnapshot,
      remoteSnapshot: remoteSnapshot ?? this.remoteSnapshot,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (entityTableName.present) {
      map['table_name'] = Variable<String>(entityTableName.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (expectedServerVersion.present) {
      map['expected_server_version'] = Variable<int>(
        expectedServerVersion.value,
      );
    }
    if (actualServerVersion.present) {
      map['actual_server_version'] = Variable<int>(actualServerVersion.value);
    }
    if (localSnapshot.present) {
      map['local_snapshot'] = Variable<String>(localSnapshot.value);
    }
    if (remoteSnapshot.present) {
      map['remote_snapshot'] = Variable<String>(remoteSnapshot.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(
        $SyncConflictsTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsCompanion(')
          ..write('id: $id, ')
          ..write('operationId: $operationId, ')
          ..write('entityTableName: $entityTableName, ')
          ..write('recordId: $recordId, ')
          ..write('expectedServerVersion: $expectedServerVersion, ')
          ..write('actualServerVersion: $actualServerVersion, ')
          ..write('localSnapshot: $localSnapshot, ')
          ..write('remoteSnapshot: $remoteSnapshot, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastChangeIdMeta = const VerificationMeta(
    'lastChangeId',
  );
  @override
  late final GeneratedColumn<int> lastChangeId = GeneratedColumn<int>(
    'last_change_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, String> updatedAt =
      GeneratedColumn<String>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($SyncStateTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [accountId, lastChangeId, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('last_change_id')) {
      context.handle(
        _lastChangeIdMeta,
        lastChangeId.isAcceptableOrUnknown(
          data['last_change_id']!,
          _lastChangeIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      lastChangeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_change_id'],
      )!,
      updatedAt: $SyncStateTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, String> $converterupdatedAt =
      const DateTimeUtcConverter();
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final String accountId;
  final int lastChangeId;
  final DateTime updatedAt;
  const SyncStateRow({
    required this.accountId,
    required this.lastChangeId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['last_change_id'] = Variable<int>(lastChangeId);
    {
      map['updated_at'] = Variable<String>(
        $SyncStateTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      accountId: Value(accountId),
      lastChangeId: Value(lastChangeId),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      lastChangeId: serializer.fromJson<int>(json['lastChangeId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'lastChangeId': serializer.toJson<int>(lastChangeId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncStateRow copyWith({
    String? accountId,
    int? lastChangeId,
    DateTime? updatedAt,
  }) => SyncStateRow(
    accountId: accountId ?? this.accountId,
    lastChangeId: lastChangeId ?? this.lastChangeId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncStateRow copyWithCompanion(SyncStateCompanion data) {
    return SyncStateRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      lastChangeId: data.lastChangeId.present
          ? data.lastChangeId.value
          : this.lastChangeId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('accountId: $accountId, ')
          ..write('lastChangeId: $lastChangeId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, lastChangeId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.accountId == this.accountId &&
          other.lastChangeId == this.lastChangeId &&
          other.updatedAt == this.updatedAt);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<String> accountId;
  final Value<int> lastChangeId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.accountId = const Value.absent(),
    this.lastChangeId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String accountId,
    this.lastChangeId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       updatedAt = Value(updatedAt);
  static Insertable<SyncStateRow> custom({
    Expression<String>? accountId,
    Expression<int>? lastChangeId,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (lastChangeId != null) 'last_change_id': lastChangeId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? accountId,
    Value<int>? lastChangeId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      accountId: accountId ?? this.accountId,
      lastChangeId: lastChangeId ?? this.lastChangeId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (lastChangeId.present) {
      map['last_change_id'] = Variable<int>(lastChangeId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(
        $SyncStateTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('accountId: $accountId, ')
          ..write('lastChangeId: $lastChangeId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $RecurringRulesTable recurringRules = $RecurringRulesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $DayContextsTable dayContexts = $DayContextsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SubtasksTable subtasks = $SubtasksTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $TaskTagsTable taskTags = $TaskTagsTable(this);
  late final $TaskTemplatesTable taskTemplates = $TaskTemplatesTable(this);
  late final $DailyReviewsTable dailyReviews = $DailyReviewsTable(this);
  late final $WeeklyReviewsTable weeklyReviews = $WeeklyReviewsTable(this);
  late final $DailyStatsCacheTable dailyStatsCache = $DailyStatsCacheTable(
    this,
  );
  late final $TimerSessionsTable timerSessions = $TimerSessionsTable(this);
  late final $SyncLogTable syncLog = $SyncLogTable(this);
  late final $SyncConflictsTable syncConflicts = $SyncConflictsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final TaskDao taskDao = TaskDao(this as AppDatabase);
  late final CategoryDao categoryDao = CategoryDao(this as AppDatabase);
  late final SubtaskDao subtaskDao = SubtaskDao(this as AppDatabase);
  late final TagDao tagDao = TagDao(this as AppDatabase);
  late final RecurringRuleDao recurringRuleDao = RecurringRuleDao(
    this as AppDatabase,
  );
  late final TemplateDao templateDao = TemplateDao(this as AppDatabase);
  late final ReviewDao reviewDao = ReviewDao(this as AppDatabase);
  late final StatsDao statsDao = StatsDao(this as AppDatabase);
  late final TimerDao timerDao = TimerDao(this as AppDatabase);
  late final SyncDao syncDao = SyncDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    recurringRules,
    tasks,
    dayContexts,
    appSettings,
    subtasks,
    tags,
    taskTags,
    taskTemplates,
    dailyReviews,
    weeklyReviews,
    dailyStatsCache,
    timerSessions,
    syncLog,
    syncConflicts,
    syncState,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('recurring_rules', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'recurring_rules',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subtasks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_templates', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('timer_sessions', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String id,
      required String name,
      required String colorHex,
      Value<int> sortOrder,
      Value<bool> isFocus,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> colorHex,
      Value<int> sortOrder,
      Value<bool> isFocus,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecurringRulesTable, List<RecurringRuleRow>>
  _recurringRulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.recurringRules,
    aliasName: $_aliasNameGenerator(
      db.categories.id,
      db.recurringRules.categoryId,
    ),
  );

  $$RecurringRulesTableProcessedTableManager get recurringRulesRefs {
    final manager = $$RecurringRulesTableTableManager(
      $_db,
      $_db.recurringRules,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recurringRulesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<TaskRow>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: $_aliasNameGenerator(db.categories.id, db.tasks.categoryId),
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TaskTemplatesTable, List<TaskTemplateRow>>
  _taskTemplatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskTemplates,
    aliasName: $_aliasNameGenerator(
      db.categories.id,
      db.taskTemplates.categoryId,
    ),
  );

  $$TaskTemplatesTableProcessedTableManager get taskTemplatesRefs {
    final manager = $$TaskTemplatesTableTableManager(
      $_db,
      $_db.taskTemplates,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskTemplatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFocus => $composableBuilder(
    column: $table.isFocus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> recurringRulesRefs(
    Expression<bool> Function($$RecurringRulesTableFilterComposer f) f,
  ) {
    final $$RecurringRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurringRules,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringRulesTableFilterComposer(
            $db: $db,
            $table: $db.recurringRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskTemplatesRefs(
    Expression<bool> Function($$TaskTemplatesTableFilterComposer f) f,
  ) {
    final $$TaskTemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTemplates,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTemplatesTableFilterComposer(
            $db: $db,
            $table: $db.taskTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFocus => $composableBuilder(
    column: $table.isFocus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isFocus =>
      $composableBuilder(column: $table.isFocus, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  Expression<T> recurringRulesRefs<T extends Object>(
    Expression<T> Function($$RecurringRulesTableAnnotationComposer a) f,
  ) {
    final $$RecurringRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recurringRules,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.recurringRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> taskTemplatesRefs<T extends Object>(
    Expression<T> Function($$TaskTemplatesTableAnnotationComposer a) f,
  ) {
    final $$TaskTemplatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTemplates,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTemplatesTableAnnotationComposer(
            $db: $db,
            $table: $db.taskTemplates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({
            bool recurringRulesRefs,
            bool tasksRefs,
            bool taskTemplatesRefs,
          })
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> colorHex = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isFocus = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                colorHex: colorHex,
                sortOrder: sortOrder,
                isFocus: isFocus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String colorHex,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isFocus = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                colorHex: colorHex,
                sortOrder: sortOrder,
                isFocus: isFocus,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                recurringRulesRefs = false,
                tasksRefs = false,
                taskTemplatesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recurringRulesRefs) db.recurringRules,
                    if (tasksRefs) db.tasks,
                    if (taskTemplatesRefs) db.taskTemplates,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recurringRulesRefs)
                        await $_getPrefetchedData<
                          CategoryRow,
                          $CategoriesTable,
                          RecurringRuleRow
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._recurringRulesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).recurringRulesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedData<
                          CategoryRow,
                          $CategoriesTable,
                          TaskRow
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).tasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskTemplatesRefs)
                        await $_getPrefetchedData<
                          CategoryRow,
                          $CategoriesTable,
                          TaskTemplateRow
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._taskTemplatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).taskTemplatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({
        bool recurringRulesRefs,
        bool tasksRefs,
        bool taskTemplatesRefs,
      })
    >;
typedef $$RecurringRulesTableCreateCompanionBuilder =
    RecurringRulesCompanion Function({
      required String id,
      required String rrule,
      required String taskTitle,
      Value<String?> taskDescription,
      required int durationMin,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String?> tagsJson,
      required String startTimeOfDay,
      required String startDate,
      Value<String?> endDate,
      Value<bool> isActive,
      Value<String?> exceptionsJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$RecurringRulesTableUpdateCompanionBuilder =
    RecurringRulesCompanion Function({
      Value<String> id,
      Value<String> rrule,
      Value<String> taskTitle,
      Value<String?> taskDescription,
      Value<int> durationMin,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String?> tagsJson,
      Value<String> startTimeOfDay,
      Value<String> startDate,
      Value<String?> endDate,
      Value<bool> isActive,
      Value<String?> exceptionsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$RecurringRulesTableReferences
    extends
        BaseReferences<_$AppDatabase, $RecurringRulesTable, RecurringRuleRow> {
  $$RecurringRulesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias(
        $_aliasNameGenerator(db.recurringRules.categoryId, db.categories.id),
      );

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<TaskRow>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: $_aliasNameGenerator(
      db.recurringRules.id,
      db.tasks.recurringRuleId,
    ),
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager($_db, $_db.tasks).filter(
      (f) => f.recurringRuleId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecurringRulesTableFilterComposer
    extends Composer<_$AppDatabase, $RecurringRulesTable> {
  $$RecurringRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskTitle => $composableBuilder(
    column: $table.taskTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTimeOfDay => $composableBuilder(
    column: $table.startTimeOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exceptionsJson => $composableBuilder(
    column: $table.exceptionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.recurringRuleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecurringRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecurringRulesTable> {
  $$RecurringRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskTitle => $composableBuilder(
    column: $table.taskTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTimeOfDay => $composableBuilder(
    column: $table.startTimeOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exceptionsJson => $composableBuilder(
    column: $table.exceptionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecurringRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecurringRulesTable> {
  $$RecurringRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rrule =>
      $composableBuilder(column: $table.rrule, builder: (column) => column);

  GeneratedColumn<String> get taskTitle =>
      $composableBuilder(column: $table.taskTitle, builder: (column) => column);

  GeneratedColumn<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get startTimeOfDay => $composableBuilder(
    column: $table.startTimeOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get exceptionsJson => $composableBuilder(
    column: $table.exceptionsJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.recurringRuleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecurringRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecurringRulesTable,
          RecurringRuleRow,
          $$RecurringRulesTableFilterComposer,
          $$RecurringRulesTableOrderingComposer,
          $$RecurringRulesTableAnnotationComposer,
          $$RecurringRulesTableCreateCompanionBuilder,
          $$RecurringRulesTableUpdateCompanionBuilder,
          (RecurringRuleRow, $$RecurringRulesTableReferences),
          RecurringRuleRow,
          PrefetchHooks Function({bool categoryId, bool tasksRefs})
        > {
  $$RecurringRulesTableTableManager(
    _$AppDatabase db,
    $RecurringRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecurringRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecurringRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecurringRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> rrule = const Value.absent(),
                Value<String> taskTitle = const Value.absent(),
                Value<String?> taskDescription = const Value.absent(),
                Value<int> durationMin = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<String> startTimeOfDay = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String?> endDate = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String?> exceptionsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecurringRulesCompanion(
                id: id,
                rrule: rrule,
                taskTitle: taskTitle,
                taskDescription: taskDescription,
                durationMin: durationMin,
                categoryId: categoryId,
                priority: priority,
                tagsJson: tagsJson,
                startTimeOfDay: startTimeOfDay,
                startDate: startDate,
                endDate: endDate,
                isActive: isActive,
                exceptionsJson: exceptionsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String rrule,
                required String taskTitle,
                Value<String?> taskDescription = const Value.absent(),
                required int durationMin,
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                required String startTimeOfDay,
                required String startDate,
                Value<String?> endDate = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String?> exceptionsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecurringRulesCompanion.insert(
                id: id,
                rrule: rrule,
                taskTitle: taskTitle,
                taskDescription: taskDescription,
                durationMin: durationMin,
                categoryId: categoryId,
                priority: priority,
                tagsJson: tagsJson,
                startTimeOfDay: startTimeOfDay,
                startDate: startDate,
                endDate: endDate,
                isActive: isActive,
                exceptionsJson: exceptionsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecurringRulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false, tasksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (tasksRefs) db.tasks],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.categoryId,
                                referencedTable: $$RecurringRulesTableReferences
                                    ._categoryIdTable(db),
                                referencedColumn:
                                    $$RecurringRulesTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tasksRefs)
                    await $_getPrefetchedData<
                      RecurringRuleRow,
                      $RecurringRulesTable,
                      TaskRow
                    >(
                      currentTable: table,
                      referencedTable: $$RecurringRulesTableReferences
                          ._tasksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RecurringRulesTableReferences(
                            db,
                            table,
                            p0,
                          ).tasksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.recurringRuleId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RecurringRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecurringRulesTable,
      RecurringRuleRow,
      $$RecurringRulesTableFilterComposer,
      $$RecurringRulesTableOrderingComposer,
      $$RecurringRulesTableAnnotationComposer,
      $$RecurringRulesTableCreateCompanionBuilder,
      $$RecurringRulesTableUpdateCompanionBuilder,
      (RecurringRuleRow, $$RecurringRulesTableReferences),
      RecurringRuleRow,
      PrefetchHooks Function({bool categoryId, bool tasksRefs})
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String title,
      Value<String?> description,
      Value<DateTime?> startTime,
      Value<DateTime?> endTime,
      Value<int?> estimatedDurationMin,
      Value<int?> actualDurationMin,
      Value<int> manualDurationAdjustmentMin,
      Value<bool> manualActualSet,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String> status,
      Value<String?> notes,
      Value<String?> recurringRuleId,
      Value<String?> recurrenceRemovalReason,
      Value<String?> rescheduledFromId,
      Value<String?> rescheduledToId,
      Value<bool> isInbox,
      Value<int> inboxContentVersion,
      Value<String?> dueDate,
      Value<String?> missedAt,
      Value<String> planTitleHistoryJson,
      Value<String?> displayPlanChangeId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> description,
      Value<DateTime?> startTime,
      Value<DateTime?> endTime,
      Value<int?> estimatedDurationMin,
      Value<int?> actualDurationMin,
      Value<int> manualDurationAdjustmentMin,
      Value<bool> manualActualSet,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String> status,
      Value<String?> notes,
      Value<String?> recurringRuleId,
      Value<String?> recurrenceRemovalReason,
      Value<String?> rescheduledFromId,
      Value<String?> rescheduledToId,
      Value<bool> isInbox,
      Value<int> inboxContentVersion,
      Value<String?> dueDate,
      Value<String?> missedAt,
      Value<String> planTitleHistoryJson,
      Value<String?> displayPlanChangeId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, TaskRow> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) => db.categories
      .createAlias($_aliasNameGenerator(db.tasks.categoryId, db.categories.id));

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $RecurringRulesTable _recurringRuleIdTable(_$AppDatabase db) =>
      db.recurringRules.createAlias(
        $_aliasNameGenerator(db.tasks.recurringRuleId, db.recurringRules.id),
      );

  $$RecurringRulesTableProcessedTableManager? get recurringRuleId {
    final $_column = $_itemColumn<String>('recurring_rule_id');
    if ($_column == null) return null;
    final manager = $$RecurringRulesTableTableManager(
      $_db,
      $_db.recurringRules,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recurringRuleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _rescheduledFromIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(db.tasks.rescheduledFromId, db.tasks.id),
      );

  $$TasksTableProcessedTableManager? get rescheduledFromId {
    final $_column = $_itemColumn<String>('rescheduled_from_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rescheduledFromIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _rescheduledToIdTable(_$AppDatabase db) => db.tasks
      .createAlias($_aliasNameGenerator(db.tasks.rescheduledToId, db.tasks.id));

  $$TasksTableProcessedTableManager? get rescheduledToId {
    final $_column = $_itemColumn<String>('rescheduled_to_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rescheduledToIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SubtasksTable, List<SubtaskRow>>
  _subtasksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subtasks,
    aliasName: $_aliasNameGenerator(db.tasks.id, db.subtasks.taskId),
  );

  $$SubtasksTableProcessedTableManager get subtasksRefs {
    final manager = $$SubtasksTableTableManager(
      $_db,
      $_db.subtasks,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_subtasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TaskTagsTable, List<TaskTagRow>>
  _taskTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskTags,
    aliasName: $_aliasNameGenerator(db.tasks.id, db.taskTags.taskId),
  );

  $$TaskTagsTableProcessedTableManager get taskTagsRefs {
    final manager = $$TaskTagsTableTableManager(
      $_db,
      $_db.taskTags,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TimerSessionsTable, List<TimerSessionRow>>
  _timerSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.timerSessions,
    aliasName: $_aliasNameGenerator(db.tasks.id, db.timerSessions.taskId),
  );

  $$TimerSessionsTableProcessedTableManager get timerSessionsRefs {
    final manager = $$TimerSessionsTableTableManager(
      $_db,
      $_db.timerSessions,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_timerSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get startTime =>
      $composableBuilder(
        column: $table.startTime,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get endTime =>
      $composableBuilder(
        column: $table.endTime,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get estimatedDurationMin => $composableBuilder(
    column: $table.estimatedDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get manualDurationAdjustmentMin => $composableBuilder(
    column: $table.manualDurationAdjustmentMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get manualActualSet => $composableBuilder(
    column: $table.manualActualSet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceRemovalReason => $composableBuilder(
    column: $table.recurrenceRemovalReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isInbox => $composableBuilder(
    column: $table.isInbox,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inboxContentVersion => $composableBuilder(
    column: $table.inboxContentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get missedAt => $composableBuilder(
    column: $table.missedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planTitleHistoryJson => $composableBuilder(
    column: $table.planTitleHistoryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayPlanChangeId => $composableBuilder(
    column: $table.displayPlanChangeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringRulesTableFilterComposer get recurringRuleId {
    final $$RecurringRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringRuleId,
      referencedTable: $db.recurringRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringRulesTableFilterComposer(
            $db: $db,
            $table: $db.recurringRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get rescheduledFromId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledFromId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get rescheduledToId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledToId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> subtasksRefs(
    Expression<bool> Function($$SubtasksTableFilterComposer f) f,
  ) {
    final $$SubtasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subtasks,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubtasksTableFilterComposer(
            $db: $db,
            $table: $db.subtasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskTagsRefs(
    Expression<bool> Function($$TaskTagsTableFilterComposer f) f,
  ) {
    final $$TaskTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTags,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTagsTableFilterComposer(
            $db: $db,
            $table: $db.taskTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> timerSessionsRefs(
    Expression<bool> Function($$TimerSessionsTableFilterComposer f) f,
  ) {
    final $$TimerSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timerSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimerSessionsTableFilterComposer(
            $db: $db,
            $table: $db.timerSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedDurationMin => $composableBuilder(
    column: $table.estimatedDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get manualDurationAdjustmentMin => $composableBuilder(
    column: $table.manualDurationAdjustmentMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get manualActualSet => $composableBuilder(
    column: $table.manualActualSet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceRemovalReason => $composableBuilder(
    column: $table.recurrenceRemovalReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isInbox => $composableBuilder(
    column: $table.isInbox,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inboxContentVersion => $composableBuilder(
    column: $table.inboxContentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get missedAt => $composableBuilder(
    column: $table.missedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planTitleHistoryJson => $composableBuilder(
    column: $table.planTitleHistoryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayPlanChangeId => $composableBuilder(
    column: $table.displayPlanChangeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringRulesTableOrderingComposer get recurringRuleId {
    final $$RecurringRulesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringRuleId,
      referencedTable: $db.recurringRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringRulesTableOrderingComposer(
            $db: $db,
            $table: $db.recurringRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get rescheduledFromId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledFromId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get rescheduledToId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledToId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get estimatedDurationMin => $composableBuilder(
    column: $table.estimatedDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get manualDurationAdjustmentMin => $composableBuilder(
    column: $table.manualDurationAdjustmentMin,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get manualActualSet => $composableBuilder(
    column: $table.manualActualSet,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get recurrenceRemovalReason => $composableBuilder(
    column: $table.recurrenceRemovalReason,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isInbox =>
      $composableBuilder(column: $table.isInbox, builder: (column) => column);

  GeneratedColumn<int> get inboxContentVersion => $composableBuilder(
    column: $table.inboxContentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get missedAt =>
      $composableBuilder(column: $table.missedAt, builder: (column) => column);

  GeneratedColumn<String> get planTitleHistoryJson => $composableBuilder(
    column: $table.planTitleHistoryJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayPlanChangeId => $composableBuilder(
    column: $table.displayPlanChangeId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecurringRulesTableAnnotationComposer get recurringRuleId {
    final $$RecurringRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recurringRuleId,
      referencedTable: $db.recurringRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecurringRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.recurringRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get rescheduledFromId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledFromId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get rescheduledToId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.rescheduledToId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> subtasksRefs<T extends Object>(
    Expression<T> Function($$SubtasksTableAnnotationComposer a) f,
  ) {
    final $$SubtasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subtasks,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubtasksTableAnnotationComposer(
            $db: $db,
            $table: $db.subtasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> taskTagsRefs<T extends Object>(
    Expression<T> Function($$TaskTagsTableAnnotationComposer a) f,
  ) {
    final $$TaskTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTags,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> timerSessionsRefs<T extends Object>(
    Expression<T> Function($$TimerSessionsTableAnnotationComposer a) f,
  ) {
    final $$TimerSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timerSessions,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimerSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.timerSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, $$TasksTableReferences),
          TaskRow,
          PrefetchHooks Function({
            bool categoryId,
            bool recurringRuleId,
            bool rescheduledFromId,
            bool rescheduledToId,
            bool subtasksRefs,
            bool taskTagsRefs,
            bool timerSessionsRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime?> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<int?> estimatedDurationMin = const Value.absent(),
                Value<int?> actualDurationMin = const Value.absent(),
                Value<int> manualDurationAdjustmentMin = const Value.absent(),
                Value<bool> manualActualSet = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> recurringRuleId = const Value.absent(),
                Value<String?> recurrenceRemovalReason = const Value.absent(),
                Value<String?> rescheduledFromId = const Value.absent(),
                Value<String?> rescheduledToId = const Value.absent(),
                Value<bool> isInbox = const Value.absent(),
                Value<int> inboxContentVersion = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> missedAt = const Value.absent(),
                Value<String> planTitleHistoryJson = const Value.absent(),
                Value<String?> displayPlanChangeId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                title: title,
                description: description,
                startTime: startTime,
                endTime: endTime,
                estimatedDurationMin: estimatedDurationMin,
                actualDurationMin: actualDurationMin,
                manualDurationAdjustmentMin: manualDurationAdjustmentMin,
                manualActualSet: manualActualSet,
                categoryId: categoryId,
                priority: priority,
                status: status,
                notes: notes,
                recurringRuleId: recurringRuleId,
                recurrenceRemovalReason: recurrenceRemovalReason,
                rescheduledFromId: rescheduledFromId,
                rescheduledToId: rescheduledToId,
                isInbox: isInbox,
                inboxContentVersion: inboxContentVersion,
                dueDate: dueDate,
                missedAt: missedAt,
                planTitleHistoryJson: planTitleHistoryJson,
                displayPlanChangeId: displayPlanChangeId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<DateTime?> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<int?> estimatedDurationMin = const Value.absent(),
                Value<int?> actualDurationMin = const Value.absent(),
                Value<int> manualDurationAdjustmentMin = const Value.absent(),
                Value<bool> manualActualSet = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> recurringRuleId = const Value.absent(),
                Value<String?> recurrenceRemovalReason = const Value.absent(),
                Value<String?> rescheduledFromId = const Value.absent(),
                Value<String?> rescheduledToId = const Value.absent(),
                Value<bool> isInbox = const Value.absent(),
                Value<int> inboxContentVersion = const Value.absent(),
                Value<String?> dueDate = const Value.absent(),
                Value<String?> missedAt = const Value.absent(),
                Value<String> planTitleHistoryJson = const Value.absent(),
                Value<String?> displayPlanChangeId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                title: title,
                description: description,
                startTime: startTime,
                endTime: endTime,
                estimatedDurationMin: estimatedDurationMin,
                actualDurationMin: actualDurationMin,
                manualDurationAdjustmentMin: manualDurationAdjustmentMin,
                manualActualSet: manualActualSet,
                categoryId: categoryId,
                priority: priority,
                status: status,
                notes: notes,
                recurringRuleId: recurringRuleId,
                recurrenceRemovalReason: recurrenceRemovalReason,
                rescheduledFromId: rescheduledFromId,
                rescheduledToId: rescheduledToId,
                isInbox: isInbox,
                inboxContentVersion: inboxContentVersion,
                dueDate: dueDate,
                missedAt: missedAt,
                planTitleHistoryJson: planTitleHistoryJson,
                displayPlanChangeId: displayPlanChangeId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TasksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                categoryId = false,
                recurringRuleId = false,
                rescheduledFromId = false,
                rescheduledToId = false,
                subtasksRefs = false,
                taskTagsRefs = false,
                timerSessionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (subtasksRefs) db.subtasks,
                    if (taskTagsRefs) db.taskTags,
                    if (timerSessionsRefs) db.timerSessions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$TasksTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (recurringRuleId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.recurringRuleId,
                                    referencedTable: $$TasksTableReferences
                                        ._recurringRuleIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._recurringRuleIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (rescheduledFromId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.rescheduledFromId,
                                    referencedTable: $$TasksTableReferences
                                        ._rescheduledFromIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._rescheduledFromIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (rescheduledToId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.rescheduledToId,
                                    referencedTable: $$TasksTableReferences
                                        ._rescheduledToIdTable(db),
                                    referencedColumn: $$TasksTableReferences
                                        ._rescheduledToIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (subtasksRefs)
                        await $_getPrefetchedData<
                          TaskRow,
                          $TasksTable,
                          SubtaskRow
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._subtasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).subtasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskTagsRefs)
                        await $_getPrefetchedData<
                          TaskRow,
                          $TasksTable,
                          TaskTagRow
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._taskTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (timerSessionsRefs)
                        await $_getPrefetchedData<
                          TaskRow,
                          $TasksTable,
                          TimerSessionRow
                        >(
                          currentTable: table,
                          referencedTable: $$TasksTableReferences
                              ._timerSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).timerSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, $$TasksTableReferences),
      TaskRow,
      PrefetchHooks Function({
        bool categoryId,
        bool recurringRuleId,
        bool rescheduledFromId,
        bool rescheduledToId,
        bool subtasksRefs,
        bool taskTagsRefs,
        bool timerSessionsRefs,
      })
    >;
typedef $$DayContextsTableCreateCompanionBuilder =
    DayContextsCompanion Function({
      required String id,
      required String date,
      required String kind,
      Value<String?> customLabel,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$DayContextsTableUpdateCompanionBuilder =
    DayContextsCompanion Function({
      Value<String> id,
      Value<String> date,
      Value<String> kind,
      Value<String?> customLabel,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

class $$DayContextsTableFilterComposer
    extends Composer<_$AppDatabase, $DayContextsTable> {
  $$DayContextsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DayContextsTableOrderingComposer
    extends Composer<_$AppDatabase, $DayContextsTable> {
  $$DayContextsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DayContextsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DayContextsTable> {
  $$DayContextsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get customLabel => $composableBuilder(
    column: $table.customLabel,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );
}

class $$DayContextsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DayContextsTable,
          DayContextRow,
          $$DayContextsTableFilterComposer,
          $$DayContextsTableOrderingComposer,
          $$DayContextsTableAnnotationComposer,
          $$DayContextsTableCreateCompanionBuilder,
          $$DayContextsTableUpdateCompanionBuilder,
          (
            DayContextRow,
            BaseReferences<_$AppDatabase, $DayContextsTable, DayContextRow>,
          ),
          DayContextRow,
          PrefetchHooks Function()
        > {
  $$DayContextsTableTableManager(_$AppDatabase db, $DayContextsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DayContextsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DayContextsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DayContextsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> customLabel = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayContextsCompanion(
                id: id,
                date: date,
                kind: kind,
                customLabel: customLabel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String date,
                required String kind,
                Value<String?> customLabel = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DayContextsCompanion.insert(
                id: id,
                date: date,
                kind: kind,
                customLabel: customLabel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DayContextsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DayContextsTable,
      DayContextRow,
      $$DayContextsTableFilterComposer,
      $$DayContextsTableOrderingComposer,
      $$DayContextsTableAnnotationComposer,
      $$DayContextsTableCreateCompanionBuilder,
      $$DayContextsTableUpdateCompanionBuilder,
      (
        DayContextRow,
        BaseReferences<_$AppDatabase, $DayContextsTable, DayContextRow>,
      ),
      DayContextRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$SubtasksTableCreateCompanionBuilder =
    SubtasksCompanion Function({
      required String id,
      required String taskId,
      required String title,
      Value<bool> isCompleted,
      Value<int> sortOrder,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$SubtasksTableUpdateCompanionBuilder =
    SubtasksCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> title,
      Value<bool> isCompleted,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$SubtasksTableReferences
    extends BaseReferences<_$AppDatabase, $SubtasksTable, SubtaskRow> {
  $$SubtasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) => db.tasks.createAlias(
    $_aliasNameGenerator(db.subtasks.taskId, db.tasks.id),
  );

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubtasksTableFilterComposer
    extends Composer<_$AppDatabase, $SubtasksTable> {
  $$SubtasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubtasksTableOrderingComposer
    extends Composer<_$AppDatabase, $SubtasksTable> {
  $$SubtasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubtasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubtasksTable> {
  $$SubtasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubtasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubtasksTable,
          SubtaskRow,
          $$SubtasksTableFilterComposer,
          $$SubtasksTableOrderingComposer,
          $$SubtasksTableAnnotationComposer,
          $$SubtasksTableCreateCompanionBuilder,
          $$SubtasksTableUpdateCompanionBuilder,
          (SubtaskRow, $$SubtasksTableReferences),
          SubtaskRow,
          PrefetchHooks Function({bool taskId})
        > {
  $$SubtasksTableTableManager(_$AppDatabase db, $SubtasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubtasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubtasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubtasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubtasksCompanion(
                id: id,
                taskId: taskId,
                title: title,
                isCompleted: isCompleted,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String title,
                Value<bool> isCompleted = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubtasksCompanion.insert(
                id: id,
                taskId: taskId,
                title: title,
                isCompleted: isCompleted,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SubtasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$SubtasksTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$SubtasksTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SubtasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubtasksTable,
      SubtaskRow,
      $$SubtasksTableFilterComposer,
      $$SubtasksTableOrderingComposer,
      $$SubtasksTableAnnotationComposer,
      $$SubtasksTableCreateCompanionBuilder,
      $$SubtasksTableUpdateCompanionBuilder,
      (SubtaskRow, $$SubtasksTableReferences),
      SubtaskRow,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, TagRow> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TaskTagsTable, List<TaskTagRow>>
  _taskTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskTags,
    aliasName: $_aliasNameGenerator(db.tags.id, db.taskTags.tagId),
  );

  $$TaskTagsTableProcessedTableManager get taskTagsRefs {
    final manager = $$TaskTagsTableTableManager(
      $_db,
      $_db.taskTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> taskTagsRefs(
    Expression<bool> Function($$TaskTagsTableFilterComposer f) f,
  ) {
    final $$TaskTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTagsTableFilterComposer(
            $db: $db,
            $table: $db.taskTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  Expression<T> taskTagsRefs<T extends Object>(
    Expression<T> Function($$TaskTagsTableAnnotationComposer a) f,
  ) {
    final $$TaskTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, $$TagsTableReferences),
          TagRow,
          PrefetchHooks Function({bool taskTagsRefs})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({taskTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (taskTagsRefs) db.taskTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (taskTagsRefs)
                    await $_getPrefetchedData<TagRow, $TagsTable, TaskTagRow>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences._taskTagsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).taskTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, $$TagsTableReferences),
      TagRow,
      PrefetchHooks Function({bool taskTagsRefs})
    >;
typedef $$TaskTagsTableCreateCompanionBuilder =
    TaskTagsCompanion Function({
      required String taskId,
      required String tagId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$TaskTagsTableUpdateCompanionBuilder =
    TaskTagsCompanion Function({
      Value<String> taskId,
      Value<String> tagId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$TaskTagsTableReferences
    extends BaseReferences<_$AppDatabase, $TaskTagsTable, TaskTagRow> {
  $$TaskTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TasksTable _taskIdTable(_$AppDatabase db) => db.tasks.createAlias(
    $_aliasNameGenerator(db.taskTags.taskId, db.tasks.id),
  );

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias($_aliasNameGenerator(db.taskTags.tagId, db.tags.id));

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskTagsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskTagsTable> {
  $$TaskTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskTagsTable> {
  $$TaskTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskTagsTable> {
  $$TaskTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskTagsTable,
          TaskTagRow,
          $$TaskTagsTableFilterComposer,
          $$TaskTagsTableOrderingComposer,
          $$TaskTagsTableAnnotationComposer,
          $$TaskTagsTableCreateCompanionBuilder,
          $$TaskTagsTableUpdateCompanionBuilder,
          (TaskTagRow, $$TaskTagsTableReferences),
          TaskTagRow,
          PrefetchHooks Function({bool taskId, bool tagId})
        > {
  $$TaskTagsTableTableManager(_$AppDatabase db, $TaskTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskTagsCompanion(
                taskId: taskId,
                tagId: tagId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String tagId,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskTagsCompanion.insert(
                taskId: taskId,
                tagId: tagId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$TaskTagsTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$TaskTagsTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable: $$TaskTagsTableReferences
                                    ._tagIdTable(db),
                                referencedColumn: $$TaskTagsTableReferences
                                    ._tagIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskTagsTable,
      TaskTagRow,
      $$TaskTagsTableFilterComposer,
      $$TaskTagsTableOrderingComposer,
      $$TaskTagsTableAnnotationComposer,
      $$TaskTagsTableCreateCompanionBuilder,
      $$TaskTagsTableUpdateCompanionBuilder,
      (TaskTagRow, $$TaskTagsTableReferences),
      TaskTagRow,
      PrefetchHooks Function({bool taskId, bool tagId})
    >;
typedef $$TaskTemplatesTableCreateCompanionBuilder =
    TaskTemplatesCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      required int durationMin,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String?> tagsJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$TaskTemplatesTableUpdateCompanionBuilder =
    TaskTemplatesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<int> durationMin,
      Value<String?> categoryId,
      Value<int> priority,
      Value<String?> tagsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$TaskTemplatesTableReferences
    extends
        BaseReferences<_$AppDatabase, $TaskTemplatesTable, TaskTemplateRow> {
  $$TaskTemplatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias(
        $_aliasNameGenerator(db.taskTemplates.categoryId, db.categories.id),
      );

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskTemplatesTable> {
  $$TaskTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskTemplatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskTemplatesTable,
          TaskTemplateRow,
          $$TaskTemplatesTableFilterComposer,
          $$TaskTemplatesTableOrderingComposer,
          $$TaskTemplatesTableAnnotationComposer,
          $$TaskTemplatesTableCreateCompanionBuilder,
          $$TaskTemplatesTableUpdateCompanionBuilder,
          (TaskTemplateRow, $$TaskTemplatesTableReferences),
          TaskTemplateRow,
          PrefetchHooks Function({bool categoryId})
        > {
  $$TaskTemplatesTableTableManager(_$AppDatabase db, $TaskTemplatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> durationMin = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskTemplatesCompanion(
                id: id,
                name: name,
                description: description,
                durationMin: durationMin,
                categoryId: categoryId,
                priority: priority,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                required int durationMin,
                Value<String?> categoryId = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> tagsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskTemplatesCompanion.insert(
                id: id,
                name: name,
                description: description,
                durationMin: durationMin,
                categoryId: categoryId,
                priority: priority,
                tagsJson: tagsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskTemplatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (categoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.categoryId,
                                referencedTable: $$TaskTemplatesTableReferences
                                    ._categoryIdTable(db),
                                referencedColumn: $$TaskTemplatesTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskTemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskTemplatesTable,
      TaskTemplateRow,
      $$TaskTemplatesTableFilterComposer,
      $$TaskTemplatesTableOrderingComposer,
      $$TaskTemplatesTableAnnotationComposer,
      $$TaskTemplatesTableCreateCompanionBuilder,
      $$TaskTemplatesTableUpdateCompanionBuilder,
      (TaskTemplateRow, $$TaskTemplatesTableReferences),
      TaskTemplateRow,
      PrefetchHooks Function({bool categoryId})
    >;
typedef $$DailyReviewsTableCreateCompanionBuilder =
    DailyReviewsCompanion Function({
      required String id,
      required String date,
      Value<String?> reflection,
      Value<int?> energyLevel,
      Value<int?> productivityRating,
      Value<int?> planningAccuracyRating,
      Value<String?> winsJson,
      Value<String?> improvementsJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$DailyReviewsTableUpdateCompanionBuilder =
    DailyReviewsCompanion Function({
      Value<String> id,
      Value<String> date,
      Value<String?> reflection,
      Value<int?> energyLevel,
      Value<int?> productivityRating,
      Value<int?> planningAccuracyRating,
      Value<String?> winsJson,
      Value<String?> improvementsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

class $$DailyReviewsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyReviewsTable> {
  $$DailyReviewsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get planningAccuracyRating => $composableBuilder(
    column: $table.planningAccuracyRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get winsJson => $composableBuilder(
    column: $table.winsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get improvementsJson => $composableBuilder(
    column: $table.improvementsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyReviewsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyReviewsTable> {
  $$DailyReviewsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get planningAccuracyRating => $composableBuilder(
    column: $table.planningAccuracyRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get winsJson => $composableBuilder(
    column: $table.winsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get improvementsJson => $composableBuilder(
    column: $table.improvementsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyReviewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyReviewsTable> {
  $$DailyReviewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => column,
  );

  GeneratedColumn<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => column,
  );

  GeneratedColumn<int> get planningAccuracyRating => $composableBuilder(
    column: $table.planningAccuracyRating,
    builder: (column) => column,
  );

  GeneratedColumn<String> get winsJson =>
      $composableBuilder(column: $table.winsJson, builder: (column) => column);

  GeneratedColumn<String> get improvementsJson => $composableBuilder(
    column: $table.improvementsJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );
}

class $$DailyReviewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyReviewsTable,
          DailyReviewRow,
          $$DailyReviewsTableFilterComposer,
          $$DailyReviewsTableOrderingComposer,
          $$DailyReviewsTableAnnotationComposer,
          $$DailyReviewsTableCreateCompanionBuilder,
          $$DailyReviewsTableUpdateCompanionBuilder,
          (
            DailyReviewRow,
            BaseReferences<_$AppDatabase, $DailyReviewsTable, DailyReviewRow>,
          ),
          DailyReviewRow,
          PrefetchHooks Function()
        > {
  $$DailyReviewsTableTableManager(_$AppDatabase db, $DailyReviewsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyReviewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyReviewsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyReviewsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String?> reflection = const Value.absent(),
                Value<int?> energyLevel = const Value.absent(),
                Value<int?> productivityRating = const Value.absent(),
                Value<int?> planningAccuracyRating = const Value.absent(),
                Value<String?> winsJson = const Value.absent(),
                Value<String?> improvementsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyReviewsCompanion(
                id: id,
                date: date,
                reflection: reflection,
                energyLevel: energyLevel,
                productivityRating: productivityRating,
                planningAccuracyRating: planningAccuracyRating,
                winsJson: winsJson,
                improvementsJson: improvementsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String date,
                Value<String?> reflection = const Value.absent(),
                Value<int?> energyLevel = const Value.absent(),
                Value<int?> productivityRating = const Value.absent(),
                Value<int?> planningAccuracyRating = const Value.absent(),
                Value<String?> winsJson = const Value.absent(),
                Value<String?> improvementsJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyReviewsCompanion.insert(
                id: id,
                date: date,
                reflection: reflection,
                energyLevel: energyLevel,
                productivityRating: productivityRating,
                planningAccuracyRating: planningAccuracyRating,
                winsJson: winsJson,
                improvementsJson: improvementsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyReviewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyReviewsTable,
      DailyReviewRow,
      $$DailyReviewsTableFilterComposer,
      $$DailyReviewsTableOrderingComposer,
      $$DailyReviewsTableAnnotationComposer,
      $$DailyReviewsTableCreateCompanionBuilder,
      $$DailyReviewsTableUpdateCompanionBuilder,
      (
        DailyReviewRow,
        BaseReferences<_$AppDatabase, $DailyReviewsTable, DailyReviewRow>,
      ),
      DailyReviewRow,
      PrefetchHooks Function()
    >;
typedef $$WeeklyReviewsTableCreateCompanionBuilder =
    WeeklyReviewsCompanion Function({
      required String id,
      required String weekStartDate,
      Value<String?> reflection,
      Value<int?> overallRating,
      Value<String?> goalsMetJson,
      Value<String?> goalsMissedJson,
      Value<String?> nextWeekFocusJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$WeeklyReviewsTableUpdateCompanionBuilder =
    WeeklyReviewsCompanion Function({
      Value<String> id,
      Value<String> weekStartDate,
      Value<String?> reflection,
      Value<int?> overallRating,
      Value<String?> goalsMetJson,
      Value<String?> goalsMissedJson,
      Value<String?> nextWeekFocusJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

class $$WeeklyReviewsTableFilterComposer
    extends Composer<_$AppDatabase, $WeeklyReviewsTable> {
  $$WeeklyReviewsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get overallRating => $composableBuilder(
    column: $table.overallRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalsMetJson => $composableBuilder(
    column: $table.goalsMetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalsMissedJson => $composableBuilder(
    column: $table.goalsMissedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextWeekFocusJson => $composableBuilder(
    column: $table.nextWeekFocusJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WeeklyReviewsTableOrderingComposer
    extends Composer<_$AppDatabase, $WeeklyReviewsTable> {
  $$WeeklyReviewsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get overallRating => $composableBuilder(
    column: $table.overallRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalsMetJson => $composableBuilder(
    column: $table.goalsMetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalsMissedJson => $composableBuilder(
    column: $table.goalsMissedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextWeekFocusJson => $composableBuilder(
    column: $table.nextWeekFocusJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WeeklyReviewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WeeklyReviewsTable> {
  $$WeeklyReviewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reflection => $composableBuilder(
    column: $table.reflection,
    builder: (column) => column,
  );

  GeneratedColumn<int> get overallRating => $composableBuilder(
    column: $table.overallRating,
    builder: (column) => column,
  );

  GeneratedColumn<String> get goalsMetJson => $composableBuilder(
    column: $table.goalsMetJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get goalsMissedJson => $composableBuilder(
    column: $table.goalsMissedJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextWeekFocusJson => $composableBuilder(
    column: $table.nextWeekFocusJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );
}

class $$WeeklyReviewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WeeklyReviewsTable,
          WeeklyReviewRow,
          $$WeeklyReviewsTableFilterComposer,
          $$WeeklyReviewsTableOrderingComposer,
          $$WeeklyReviewsTableAnnotationComposer,
          $$WeeklyReviewsTableCreateCompanionBuilder,
          $$WeeklyReviewsTableUpdateCompanionBuilder,
          (
            WeeklyReviewRow,
            BaseReferences<_$AppDatabase, $WeeklyReviewsTable, WeeklyReviewRow>,
          ),
          WeeklyReviewRow,
          PrefetchHooks Function()
        > {
  $$WeeklyReviewsTableTableManager(_$AppDatabase db, $WeeklyReviewsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeeklyReviewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeeklyReviewsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeeklyReviewsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> weekStartDate = const Value.absent(),
                Value<String?> reflection = const Value.absent(),
                Value<int?> overallRating = const Value.absent(),
                Value<String?> goalsMetJson = const Value.absent(),
                Value<String?> goalsMissedJson = const Value.absent(),
                Value<String?> nextWeekFocusJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WeeklyReviewsCompanion(
                id: id,
                weekStartDate: weekStartDate,
                reflection: reflection,
                overallRating: overallRating,
                goalsMetJson: goalsMetJson,
                goalsMissedJson: goalsMissedJson,
                nextWeekFocusJson: nextWeekFocusJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String weekStartDate,
                Value<String?> reflection = const Value.absent(),
                Value<int?> overallRating = const Value.absent(),
                Value<String?> goalsMetJson = const Value.absent(),
                Value<String?> goalsMissedJson = const Value.absent(),
                Value<String?> nextWeekFocusJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WeeklyReviewsCompanion.insert(
                id: id,
                weekStartDate: weekStartDate,
                reflection: reflection,
                overallRating: overallRating,
                goalsMetJson: goalsMetJson,
                goalsMissedJson: goalsMissedJson,
                nextWeekFocusJson: nextWeekFocusJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WeeklyReviewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WeeklyReviewsTable,
      WeeklyReviewRow,
      $$WeeklyReviewsTableFilterComposer,
      $$WeeklyReviewsTableOrderingComposer,
      $$WeeklyReviewsTableAnnotationComposer,
      $$WeeklyReviewsTableCreateCompanionBuilder,
      $$WeeklyReviewsTableUpdateCompanionBuilder,
      (
        WeeklyReviewRow,
        BaseReferences<_$AppDatabase, $WeeklyReviewsTable, WeeklyReviewRow>,
      ),
      WeeklyReviewRow,
      PrefetchHooks Function()
    >;
typedef $$DailyStatsCacheTableCreateCompanionBuilder =
    DailyStatsCacheCompanion Function({
      required String date,
      Value<int> totalTasks,
      Value<int> completedTasks,
      Value<int> plannedTasks,
      Value<int> inProgressTasks,
      Value<int> missedTasks,
      Value<int> skippedTasks,
      Value<int> cancelledTasks,
      Value<int> rescheduledTasks,
      Value<int> plannedDurationMin,
      Value<int> actualDurationMin,
      Value<int> focusDurationMin,
      Value<int?> energyLevel,
      Value<int?> productivityRating,
      Value<double?> planningAccuracyPct,
      required DateTime computedAt,
      Value<int> rowid,
    });
typedef $$DailyStatsCacheTableUpdateCompanionBuilder =
    DailyStatsCacheCompanion Function({
      Value<String> date,
      Value<int> totalTasks,
      Value<int> completedTasks,
      Value<int> plannedTasks,
      Value<int> inProgressTasks,
      Value<int> missedTasks,
      Value<int> skippedTasks,
      Value<int> cancelledTasks,
      Value<int> rescheduledTasks,
      Value<int> plannedDurationMin,
      Value<int> actualDurationMin,
      Value<int> focusDurationMin,
      Value<int?> energyLevel,
      Value<int?> productivityRating,
      Value<double?> planningAccuracyPct,
      Value<DateTime> computedAt,
      Value<int> rowid,
    });

class $$DailyStatsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $DailyStatsCacheTable> {
  $$DailyStatsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalTasks => $composableBuilder(
    column: $table.totalTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedTasks => $composableBuilder(
    column: $table.plannedTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inProgressTasks => $composableBuilder(
    column: $table.inProgressTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get missedTasks => $composableBuilder(
    column: $table.missedTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skippedTasks => $composableBuilder(
    column: $table.skippedTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cancelledTasks => $composableBuilder(
    column: $table.cancelledTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rescheduledTasks => $composableBuilder(
    column: $table.rescheduledTasks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedDurationMin => $composableBuilder(
    column: $table.plannedDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get focusDurationMin => $composableBuilder(
    column: $table.focusDurationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get planningAccuracyPct => $composableBuilder(
    column: $table.planningAccuracyPct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get computedAt =>
      $composableBuilder(
        column: $table.computedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$DailyStatsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyStatsCacheTable> {
  $$DailyStatsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalTasks => $composableBuilder(
    column: $table.totalTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedTasks => $composableBuilder(
    column: $table.plannedTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inProgressTasks => $composableBuilder(
    column: $table.inProgressTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get missedTasks => $composableBuilder(
    column: $table.missedTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skippedTasks => $composableBuilder(
    column: $table.skippedTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cancelledTasks => $composableBuilder(
    column: $table.cancelledTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rescheduledTasks => $composableBuilder(
    column: $table.rescheduledTasks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedDurationMin => $composableBuilder(
    column: $table.plannedDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get focusDurationMin => $composableBuilder(
    column: $table.focusDurationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get planningAccuracyPct => $composableBuilder(
    column: $table.planningAccuracyPct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get computedAt => $composableBuilder(
    column: $table.computedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyStatsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyStatsCacheTable> {
  $$DailyStatsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get totalTasks => $composableBuilder(
    column: $table.totalTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedTasks => $composableBuilder(
    column: $table.completedTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedTasks => $composableBuilder(
    column: $table.plannedTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get inProgressTasks => $composableBuilder(
    column: $table.inProgressTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get missedTasks => $composableBuilder(
    column: $table.missedTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get skippedTasks => $composableBuilder(
    column: $table.skippedTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cancelledTasks => $composableBuilder(
    column: $table.cancelledTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rescheduledTasks => $composableBuilder(
    column: $table.rescheduledTasks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedDurationMin => $composableBuilder(
    column: $table.plannedDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualDurationMin => $composableBuilder(
    column: $table.actualDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get focusDurationMin => $composableBuilder(
    column: $table.focusDurationMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get energyLevel => $composableBuilder(
    column: $table.energyLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get productivityRating => $composableBuilder(
    column: $table.productivityRating,
    builder: (column) => column,
  );

  GeneratedColumn<double> get planningAccuracyPct => $composableBuilder(
    column: $table.planningAccuracyPct,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get computedAt =>
      $composableBuilder(
        column: $table.computedAt,
        builder: (column) => column,
      );
}

class $$DailyStatsCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyStatsCacheTable,
          DailyStatsCacheRow,
          $$DailyStatsCacheTableFilterComposer,
          $$DailyStatsCacheTableOrderingComposer,
          $$DailyStatsCacheTableAnnotationComposer,
          $$DailyStatsCacheTableCreateCompanionBuilder,
          $$DailyStatsCacheTableUpdateCompanionBuilder,
          (
            DailyStatsCacheRow,
            BaseReferences<
              _$AppDatabase,
              $DailyStatsCacheTable,
              DailyStatsCacheRow
            >,
          ),
          DailyStatsCacheRow,
          PrefetchHooks Function()
        > {
  $$DailyStatsCacheTableTableManager(
    _$AppDatabase db,
    $DailyStatsCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyStatsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyStatsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyStatsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<int> totalTasks = const Value.absent(),
                Value<int> completedTasks = const Value.absent(),
                Value<int> plannedTasks = const Value.absent(),
                Value<int> inProgressTasks = const Value.absent(),
                Value<int> missedTasks = const Value.absent(),
                Value<int> skippedTasks = const Value.absent(),
                Value<int> cancelledTasks = const Value.absent(),
                Value<int> rescheduledTasks = const Value.absent(),
                Value<int> plannedDurationMin = const Value.absent(),
                Value<int> actualDurationMin = const Value.absent(),
                Value<int> focusDurationMin = const Value.absent(),
                Value<int?> energyLevel = const Value.absent(),
                Value<int?> productivityRating = const Value.absent(),
                Value<double?> planningAccuracyPct = const Value.absent(),
                Value<DateTime> computedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCacheCompanion(
                date: date,
                totalTasks: totalTasks,
                completedTasks: completedTasks,
                plannedTasks: plannedTasks,
                inProgressTasks: inProgressTasks,
                missedTasks: missedTasks,
                skippedTasks: skippedTasks,
                cancelledTasks: cancelledTasks,
                rescheduledTasks: rescheduledTasks,
                plannedDurationMin: plannedDurationMin,
                actualDurationMin: actualDurationMin,
                focusDurationMin: focusDurationMin,
                energyLevel: energyLevel,
                productivityRating: productivityRating,
                planningAccuracyPct: planningAccuracyPct,
                computedAt: computedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                Value<int> totalTasks = const Value.absent(),
                Value<int> completedTasks = const Value.absent(),
                Value<int> plannedTasks = const Value.absent(),
                Value<int> inProgressTasks = const Value.absent(),
                Value<int> missedTasks = const Value.absent(),
                Value<int> skippedTasks = const Value.absent(),
                Value<int> cancelledTasks = const Value.absent(),
                Value<int> rescheduledTasks = const Value.absent(),
                Value<int> plannedDurationMin = const Value.absent(),
                Value<int> actualDurationMin = const Value.absent(),
                Value<int> focusDurationMin = const Value.absent(),
                Value<int?> energyLevel = const Value.absent(),
                Value<int?> productivityRating = const Value.absent(),
                Value<double?> planningAccuracyPct = const Value.absent(),
                required DateTime computedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyStatsCacheCompanion.insert(
                date: date,
                totalTasks: totalTasks,
                completedTasks: completedTasks,
                plannedTasks: plannedTasks,
                inProgressTasks: inProgressTasks,
                missedTasks: missedTasks,
                skippedTasks: skippedTasks,
                cancelledTasks: cancelledTasks,
                rescheduledTasks: rescheduledTasks,
                plannedDurationMin: plannedDurationMin,
                actualDurationMin: actualDurationMin,
                focusDurationMin: focusDurationMin,
                energyLevel: energyLevel,
                productivityRating: productivityRating,
                planningAccuracyPct: planningAccuracyPct,
                computedAt: computedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyStatsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyStatsCacheTable,
      DailyStatsCacheRow,
      $$DailyStatsCacheTableFilterComposer,
      $$DailyStatsCacheTableOrderingComposer,
      $$DailyStatsCacheTableAnnotationComposer,
      $$DailyStatsCacheTableCreateCompanionBuilder,
      $$DailyStatsCacheTableUpdateCompanionBuilder,
      (
        DailyStatsCacheRow,
        BaseReferences<
          _$AppDatabase,
          $DailyStatsCacheTable,
          DailyStatsCacheRow
        >,
      ),
      DailyStatsCacheRow,
      PrefetchHooks Function()
    >;
typedef $$TimerSessionsTableCreateCompanionBuilder =
    TimerSessionsCompanion Function({
      required String id,
      required String taskId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int> durationSec,
      Value<String> state,
      Value<DateTime?> runningSince,
      Value<String> workIntervalsJson,
      Value<String?> ownerDeviceId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });
typedef $$TimerSessionsTableUpdateCompanionBuilder =
    TimerSessionsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> durationSec,
      Value<String> state,
      Value<DateTime?> runningSince,
      Value<String> workIntervalsJson,
      Value<String?> ownerDeviceId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> syncStatus,
      Value<int> revision,
      Value<int?> serverVersion,
      Value<int> rowid,
    });

final class $$TimerSessionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $TimerSessionsTable, TimerSessionRow> {
  $$TimerSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TasksTable _taskIdTable(_$AppDatabase db) => db.tasks.createAlias(
    $_aliasNameGenerator(db.timerSessions.taskId, db.tasks.id),
  );

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TimerSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $TimerSessionsTable> {
  $$TimerSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get startedAt =>
      $composableBuilder(
        column: $table.startedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get endedAt =>
      $composableBuilder(
        column: $table.endedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String>
  get runningSince => $composableBuilder(
    column: $table.runningSince,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get workIntervalsJson => $composableBuilder(
    column: $table.workIntervalsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String> get deletedAt =>
      $composableBuilder(
        column: $table.deletedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TimerSessionsTable> {
  $$TimerSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runningSince => $composableBuilder(
    column: $table.runningSince,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workIntervalsJson => $composableBuilder(
    column: $table.workIntervalsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimerSessionsTable> {
  $$TimerSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get runningSince =>
      $composableBuilder(
        column: $table.runningSince,
        builder: (column) => column,
      );

  GeneratedColumn<String> get workIntervalsJson => $composableBuilder(
    column: $table.workIntervalsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerDeviceId => $composableBuilder(
    column: $table.ownerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TimerSessionsTable,
          TimerSessionRow,
          $$TimerSessionsTableFilterComposer,
          $$TimerSessionsTableOrderingComposer,
          $$TimerSessionsTableAnnotationComposer,
          $$TimerSessionsTableCreateCompanionBuilder,
          $$TimerSessionsTableUpdateCompanionBuilder,
          (TimerSessionRow, $$TimerSessionsTableReferences),
          TimerSessionRow,
          PrefetchHooks Function({bool taskId})
        > {
  $$TimerSessionsTableTableManager(_$AppDatabase db, $TimerSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimerSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimerSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimerSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime?> runningSince = const Value.absent(),
                Value<String> workIntervalsJson = const Value.absent(),
                Value<String?> ownerDeviceId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimerSessionsCompanion(
                id: id,
                taskId: taskId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSec: durationSec,
                state: state,
                runningSince: runningSince,
                workIntervalsJson: workIntervalsJson,
                ownerDeviceId: ownerDeviceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime?> runningSince = const Value.absent(),
                Value<String> workIntervalsJson = const Value.absent(),
                Value<String?> ownerDeviceId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> syncStatus = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimerSessionsCompanion.insert(
                id: id,
                taskId: taskId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSec: durationSec,
                state: state,
                runningSince: runningSince,
                workIntervalsJson: workIntervalsJson,
                ownerDeviceId: ownerDeviceId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                revision: revision,
                serverVersion: serverVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TimerSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable: $$TimerSessionsTableReferences
                                    ._taskIdTable(db),
                                referencedColumn: $$TimerSessionsTableReferences
                                    ._taskIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TimerSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TimerSessionsTable,
      TimerSessionRow,
      $$TimerSessionsTableFilterComposer,
      $$TimerSessionsTableOrderingComposer,
      $$TimerSessionsTableAnnotationComposer,
      $$TimerSessionsTableCreateCompanionBuilder,
      $$TimerSessionsTableUpdateCompanionBuilder,
      (TimerSessionRow, $$TimerSessionsTableReferences),
      TimerSessionRow,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$SyncLogTableCreateCompanionBuilder =
    SyncLogCompanion Function({
      required String operationId,
      required String entityTableName,
      required String recordId,
      required String operation,
      Value<int?> expectedServerVersion,
      required String payload,
      Value<String> state,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncLogTableUpdateCompanionBuilder =
    SyncLogCompanion Function({
      Value<String> operationId,
      Value<String> entityTableName,
      Value<String> recordId,
      Value<String> operation,
      Value<int?> expectedServerVersion,
      Value<String> payload,
      Value<String> state,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncLogTableFilterComposer
    extends Composer<_$AppDatabase, $SyncLogTable> {
  $$SyncLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, String>
  get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SyncLogTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncLogTable> {
  $$SyncLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncLogTable> {
  $$SyncLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, String> get nextAttemptAt =>
      $composableBuilder(
        column: $table.nextAttemptAt,
        builder: (column) => column,
      );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncLogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncLogTable,
          SyncLogRow,
          $$SyncLogTableFilterComposer,
          $$SyncLogTableOrderingComposer,
          $$SyncLogTableAnnotationComposer,
          $$SyncLogTableCreateCompanionBuilder,
          $$SyncLogTableUpdateCompanionBuilder,
          (
            SyncLogRow,
            BaseReferences<_$AppDatabase, $SyncLogTable, SyncLogRow>,
          ),
          SyncLogRow,
          PrefetchHooks Function()
        > {
  $$SyncLogTableTableManager(_$AppDatabase db, $SyncLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> entityTableName = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<int?> expectedServerVersion = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncLogCompanion(
                operationId: operationId,
                entityTableName: entityTableName,
                recordId: recordId,
                operation: operation,
                expectedServerVersion: expectedServerVersion,
                payload: payload,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String entityTableName,
                required String recordId,
                required String operation,
                Value<int?> expectedServerVersion = const Value.absent(),
                required String payload,
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncLogCompanion.insert(
                operationId: operationId,
                entityTableName: entityTableName,
                recordId: recordId,
                operation: operation,
                expectedServerVersion: expectedServerVersion,
                payload: payload,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncLogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncLogTable,
      SyncLogRow,
      $$SyncLogTableFilterComposer,
      $$SyncLogTableOrderingComposer,
      $$SyncLogTableAnnotationComposer,
      $$SyncLogTableCreateCompanionBuilder,
      $$SyncLogTableUpdateCompanionBuilder,
      (SyncLogRow, BaseReferences<_$AppDatabase, $SyncLogTable, SyncLogRow>),
      SyncLogRow,
      PrefetchHooks Function()
    >;
typedef $$SyncConflictsTableCreateCompanionBuilder =
    SyncConflictsCompanion Function({
      required String id,
      required String operationId,
      required String entityTableName,
      required String recordId,
      Value<int?> expectedServerVersion,
      Value<int?> actualServerVersion,
      required String localSnapshot,
      required String remoteSnapshot,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SyncConflictsTableUpdateCompanionBuilder =
    SyncConflictsCompanion Function({
      Value<String> id,
      Value<String> operationId,
      Value<String> entityTableName,
      Value<String> recordId,
      Value<int?> expectedServerVersion,
      Value<int?> actualServerVersion,
      Value<String> localSnapshot,
      Value<String> remoteSnapshot,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SyncConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualServerVersion => $composableBuilder(
    column: $table.actualServerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localSnapshot => $composableBuilder(
    column: $table.localSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteSnapshot => $composableBuilder(
    column: $table.remoteSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SyncConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualServerVersion => $composableBuilder(
    column: $table.actualServerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localSnapshot => $composableBuilder(
    column: $table.localSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteSnapshot => $composableBuilder(
    column: $table.remoteSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityTableName => $composableBuilder(
    column: $table.entityTableName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get expectedServerVersion => $composableBuilder(
    column: $table.expectedServerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualServerVersion => $composableBuilder(
    column: $table.actualServerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localSnapshot => $composableBuilder(
    column: $table.localSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteSnapshot => $composableBuilder(
    column: $table.remoteSnapshot,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncConflictsTable,
          SyncConflictRow,
          $$SyncConflictsTableFilterComposer,
          $$SyncConflictsTableOrderingComposer,
          $$SyncConflictsTableAnnotationComposer,
          $$SyncConflictsTableCreateCompanionBuilder,
          $$SyncConflictsTableUpdateCompanionBuilder,
          (
            SyncConflictRow,
            BaseReferences<_$AppDatabase, $SyncConflictsTable, SyncConflictRow>,
          ),
          SyncConflictRow,
          PrefetchHooks Function()
        > {
  $$SyncConflictsTableTableManager(_$AppDatabase db, $SyncConflictsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> entityTableName = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int?> expectedServerVersion = const Value.absent(),
                Value<int?> actualServerVersion = const Value.absent(),
                Value<String> localSnapshot = const Value.absent(),
                Value<String> remoteSnapshot = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion(
                id: id,
                operationId: operationId,
                entityTableName: entityTableName,
                recordId: recordId,
                expectedServerVersion: expectedServerVersion,
                actualServerVersion: actualServerVersion,
                localSnapshot: localSnapshot,
                remoteSnapshot: remoteSnapshot,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String operationId,
                required String entityTableName,
                required String recordId,
                Value<int?> expectedServerVersion = const Value.absent(),
                Value<int?> actualServerVersion = const Value.absent(),
                required String localSnapshot,
                required String remoteSnapshot,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion.insert(
                id: id,
                operationId: operationId,
                entityTableName: entityTableName,
                recordId: recordId,
                expectedServerVersion: expectedServerVersion,
                actualServerVersion: actualServerVersion,
                localSnapshot: localSnapshot,
                remoteSnapshot: remoteSnapshot,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncConflictsTable,
      SyncConflictRow,
      $$SyncConflictsTableFilterComposer,
      $$SyncConflictsTableOrderingComposer,
      $$SyncConflictsTableAnnotationComposer,
      $$SyncConflictsTableCreateCompanionBuilder,
      $$SyncConflictsTableUpdateCompanionBuilder,
      (
        SyncConflictRow,
        BaseReferences<_$AppDatabase, $SyncConflictsTable, SyncConflictRow>,
      ),
      SyncConflictRow,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String accountId,
      Value<int> lastChangeId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> accountId,
      Value<int> lastChangeId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastChangeId => $composableBuilder(
    column: $table.lastChangeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, String> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastChangeId => $composableBuilder(
    column: $table.lastChangeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get lastChangeId => $composableBuilder(
    column: $table.lastChangeId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateRow,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateRow,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateRow>,
          ),
          SyncStateRow,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<int> lastChangeId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                accountId: accountId,
                lastChangeId: lastChangeId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                Value<int> lastChangeId = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                accountId: accountId,
                lastChangeId: lastChangeId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateRow,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateRow,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateRow>,
      ),
      SyncStateRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$RecurringRulesTableTableManager get recurringRules =>
      $$RecurringRulesTableTableManager(_db, _db.recurringRules);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$DayContextsTableTableManager get dayContexts =>
      $$DayContextsTableTableManager(_db, _db.dayContexts);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SubtasksTableTableManager get subtasks =>
      $$SubtasksTableTableManager(_db, _db.subtasks);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$TaskTagsTableTableManager get taskTags =>
      $$TaskTagsTableTableManager(_db, _db.taskTags);
  $$TaskTemplatesTableTableManager get taskTemplates =>
      $$TaskTemplatesTableTableManager(_db, _db.taskTemplates);
  $$DailyReviewsTableTableManager get dailyReviews =>
      $$DailyReviewsTableTableManager(_db, _db.dailyReviews);
  $$WeeklyReviewsTableTableManager get weeklyReviews =>
      $$WeeklyReviewsTableTableManager(_db, _db.weeklyReviews);
  $$DailyStatsCacheTableTableManager get dailyStatsCache =>
      $$DailyStatsCacheTableTableManager(_db, _db.dailyStatsCache);
  $$TimerSessionsTableTableManager get timerSessions =>
      $$TimerSessionsTableTableManager(_db, _db.timerSessions);
  $$SyncLogTableTableManager get syncLog =>
      $$SyncLogTableTableManager(_db, _db.syncLog);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db, _db.syncConflicts);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
