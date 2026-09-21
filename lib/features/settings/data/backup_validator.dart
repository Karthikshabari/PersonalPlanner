import 'dart:convert';

import 'package:personal_planner/features/settings/data/backup_format.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/enums/recurrence_removal_reason.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/core/utils/missed_at.dart';
import 'package:personal_planner/features/task_editor/domain/plan_title_history.dart';

/// Validates the complete portable payload before a write transaction starts.
/// It deliberately does not know about Drift so malformed documents can be
/// rejected without opening a mutation path.
class BackupValidator {
  static const tableNames = [
    'tasks',
    'subtasks',
    'categories',
    'tags',
    'task_tags',
    'recurring_rules',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'timer_sessions',
    'day_contexts',
  ];

  static const dataKeys = {...tableNames, 'settings'};

  static const v1TableNames = [
    'tasks',
    'subtasks',
    'categories',
    'tags',
    'task_tags',
    'recurring_rules',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'timer_sessions',
  ];

  static const rowKeys = <String, Set<String>>{
    'tasks': {
      'id',
      'title',
      'description',
      'start_time',
      'end_time',
      'estimated_duration_min',
      'actual_duration_min',
      'manual_duration_adjustment_min',
      'manual_actual_set',
      'category_id',
      'priority',
      'status',
      'notes',
      'recurring_rule_id',
      'recurrence_removal_reason',
      'rescheduled_from_id',
      'rescheduled_to_id',
      'is_inbox',
      'inbox_content_version',
      'due_date',
      'missed_at',
      'plan_title_history',
      'display_plan_change_id',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'subtasks': {
      'id',
      'task_id',
      'title',
      'is_completed',
      'sort_order',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'categories': {
      'id',
      'name',
      'color_hex',
      'sort_order',
      'is_focus',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'tags': {'id', 'name', 'created_at', 'updated_at', 'deleted_at'},
    'task_tags': {
      'task_id',
      'tag_id',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'recurring_rules': {
      'id',
      'rrule',
      'task_title',
      'task_description',
      'duration_min',
      'category_id',
      'priority',
      'tags',
      'start_time_of_day',
      'start_date',
      'end_date',
      'is_active',
      'exceptions',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'task_templates': {
      'id',
      'name',
      'description',
      'duration_min',
      'category_id',
      'priority',
      'tags',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'daily_reviews': {
      'id',
      'date',
      'reflection',
      'energy_level',
      'productivity_rating',
      'planning_accuracy_rating',
      'wins',
      'improvements',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'weekly_reviews': {
      'id',
      'week_start_date',
      'reflection',
      'overall_rating',
      'goals_met',
      'goals_missed',
      'next_week_focus',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'timer_sessions': {
      'id',
      'task_id',
      'started_at',
      'ended_at',
      'duration_sec',
      'state',
      'running_since',
      'work_intervals',
      'owner_device_id',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    'day_contexts': {
      'id',
      'date',
      'kind',
      'custom_label',
      'created_at',
      'updated_at',
      'deleted_at',
    },
  };

  /// Verifies the historical v1 topology before any compatibility field is
  /// synthesized. Envelope checksum/count validation runs in [BackupCodec]
  /// immediately before this method; full semantic validation runs again on
  /// the resulting canonical v2 data.
  static void validateOriginalV1Structure(Map<String, dynamic> data) {
    _requireKeys(data, {...v1TableNames, 'settings'}, 'v1 backup data');
    for (final table in v1TableNames) {
      final expected = Set<String>.from(rowKeys[table]!);
      if (table == 'tasks') {
        expected.removeAll(const {
          'manual_actual_set',
          'inbox_content_version',
          'due_date',
          'plan_title_history',
          'display_plan_change_id',
        });
      } else if (table == 'timer_sessions') {
        expected.removeAll(const {
          'state',
          'running_since',
          'work_intervals',
          'owner_device_id',
        });
      }
      final rows = _list(data[table], 'v1 $table');
      for (final raw in rows) {
        _requireKeys(_map(raw, 'v1 $table row'), expected, 'v1 $table row');
      }
    }
    _map(data['settings'], 'v1 settings');
  }

  Map<String, Set<String>> validate(Map<String, dynamic> data) {
    _requireKeys(data, dataKeys, 'backup data');
    final ids = <String, Set<String>>{};
    for (final table in tableNames) {
      final rows = _list(data[table], table);
      final seen = <String>{};
      ids[table] = seen;
      for (final raw in rows) {
        final row = _map(raw, '$table row');
        _requireKeys(row, rowKeys[table]!, '$table row');
        final identity = entryId(table, row);
        if (!seen.add(identity)) {
          throw BackupValidationException(
            'Duplicate $table identity: $identity',
          );
        }
        _validateRow(table, row);
      }
    }

    final settings = _map(data['settings'], 'settings');
    for (final entry in settings.entries) {
      if (!acceptedPortableSettingKeys.contains(entry.key)) {
        throw BackupValidationException(
          'Setting is not portable: ${entry.key}',
        );
      }
      _validateSetting(entry.key, entry.value);
    }
    _validateUniqueBusinessDates(data);
    _validateReferences(data, ids);
    return ids;
  }

  static String entryId(String table, Map<String, dynamic> row) =>
      table == 'task_tags'
      ? '${_string(row['task_id'], 'task_tags task_id')}:${_string(row['tag_id'], 'task_tags tag_id')}'
      : _string(row['id'], '$table id');

  static Map<String, dynamic> map(dynamic value, String field) =>
      _map(value, field);

  static List<dynamic> list(dynamic value, String field) => _list(value, field);

  static String string(dynamic value, String field) => _string(value, field);

  static String boundedString(Map<String, dynamic> row, String field, int max) {
    final value = _string(row[field], field);
    if (value.length > max) {
      throw BackupValidationException('$field is too long.');
    }
    return value;
  }

  static String id(Map<String, dynamic> row, String field) {
    final value = _string(row[field], field);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw BackupValidationException('$field must be a UUID.');
    }
    return value;
  }

  static String? nullableId(Map<String, dynamic> row, String field) =>
      row[field] == null ? null : id(row, field);

  static String? nullableString(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value == null) return null;
    if (value is String) return value;
    throw BackupValidationException('$field must be a string or null.');
  }

  static int integer(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is int) return value;
    throw BackupValidationException('$field must be an integer.');
  }

  static int nonNegativeInt(Map<String, dynamic> row, String field) {
    final value = integer(row, field);
    if (value < 0) {
      throw BackupValidationException('$field must not be negative.');
    }
    return value;
  }

  static int positiveInt(Map<String, dynamic> row, String field) {
    final value = integer(row, field);
    if (value <= 0) throw BackupValidationException('$field must be positive.');
    return value;
  }

  static int? nullableNonNegativeInt(Map<String, dynamic> row, String field) =>
      row[field] == null ? null : nonNegativeInt(row, field);

  static int? nullablePositiveInt(Map<String, dynamic> row, String field) =>
      row[field] == null ? null : positiveInt(row, field);

  static bool boolean(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is bool) return value;
    throw BackupValidationException('$field must be boolean.');
  }

  static int priority(Map<String, dynamic> row, String field) {
    final value = integer(row, field);
    if (value < 0 || value > 4) {
      throw BackupValidationException('$field is out of range.');
    }
    return value;
  }

  static String status(Map<String, dynamic> row, String field) {
    const values = {
      'planned',
      'in_progress',
      'completed',
      'skipped',
      'cancelled',
      'rescheduled',
    };
    final value = _string(row[field], field);
    if (!values.contains(value)) {
      throw BackupValidationException('$field is invalid.');
    }
    return value;
  }

  static String color(Map<String, dynamic> row, String field) {
    final value = _string(row[field], field);
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
      throw BackupValidationException('$field is invalid.');
    }
    return value;
  }

  static DateTime dateTime(Map<String, dynamic> row, String field) =>
      _dateTimeValue(row[field], field);

  static DateTime? nullableDateTime(Map<String, dynamic> row, String field) =>
      row[field] == null ? null : dateTime(row, field);

  static String dateOnly(Map<String, dynamic> row, String field) {
    final value = _string(row[field], field);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    final year = int.tryParse(match?.group(1) ?? '');
    final month = int.tryParse(match?.group(2) ?? '');
    final day = int.tryParse(match?.group(3) ?? '');
    final parsed = year == null || month == null || day == null
        ? null
        : DateTime.tryParse(value);
    if (match == null ||
        parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      throw BackupValidationException('$field must be yyyy-MM-dd.');
    }
    return value;
  }

  static String? nullableDateOnly(Map<String, dynamic> row, String field) =>
      row[field] == null ? null : dateOnly(row, field);

  static String? nullableMissedAt(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value == null) return null;
    if (value is! String || MissedAtCodec.parse(value) == null) {
      throw BackupValidationException('$field must be a valid timestamp.');
    }
    final normalized = MissedAtCodec.normalize(value);
    row[field] = normalized;
    return normalized;
  }

  static String timeOfDay(Map<String, dynamic> row, String field) {
    final value = _string(row[field], field);
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    final hour = int.tryParse(match?.group(1) ?? '');
    final minute = int.tryParse(match?.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      throw BackupValidationException('$field must be HH:mm.');
    }
    return value;
  }

  static int? rating(Map<String, dynamic> row, String field) {
    if (row[field] == null) return null;
    final value = integer(row, field);
    if (value < 1 || value > 5) {
      throw BackupValidationException('$field is out of range.');
    }
    return value;
  }

  static List<String> stringList(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is! List || value.any((item) => item is! String)) {
      throw BackupValidationException('$field must be an array of strings.');
    }
    return value.cast<String>();
  }

  static List<PlanTitleChange> planTitleHistory(
    Map<String, dynamic> row,
    String field,
  ) {
    final value = row[field];
    if (value is! List) {
      throw BackupValidationException('$field must be an array.');
    }
    try {
      // Portable backup uses structured JSON while the shared Task contract
      // stores JSON text. Route it through the same strict decoder so extra
      // fields, non-string values and non-UTC timestamps cannot enter from a
      // restore path that sync/local writes would reject.
      return PlanTitleHistory.decodeJson(jsonEncode(value));
    } on FormatException catch (error) {
      throw BackupValidationException(error.message);
    } on Object {
      throw const BackupValidationException('Invalid plan title event.');
    }
  }

  static List<String> idList(Map<String, dynamic> row, String field) {
    final values = stringList(row, field);
    final seen = <String>{};
    for (final value in values) {
      id({field: value}, field);
      if (!seen.add(value)) {
        throw BackupValidationException('$field contains a duplicate UUID.');
      }
    }
    return values;
  }

  static List<String> dateList(Map<String, dynamic> row, String field) {
    final values = stringList(row, field);
    final seen = <String>{};
    for (final value in values) {
      dateOnly({field: value}, field);
      if (!seen.add(value)) {
        throw BackupValidationException('$field contains a duplicate date.');
      }
    }
    return values;
  }

  void _validateRow(String table, Map<String, dynamic> row) {
    switch (table) {
      case 'tasks':
        id(row, 'id');
        boundedString(row, 'title', 500);
        nullableString(row, 'description');
        final start = nullableDateTime(row, 'start_time');
        final end = nullableDateTime(row, 'end_time');
        if ((start == null) != (end == null) ||
            (start != null && !end!.isAfter(start))) {
          throw const BackupValidationException(
            'Task times must be both null or end after start.',
          );
        }
        nullablePositiveInt(row, 'estimated_duration_min');
        nullableNonNegativeInt(row, 'actual_duration_min');
        integer(row, 'manual_duration_adjustment_min');
        boolean(row, 'manual_actual_set');
        nullableId(row, 'category_id');
        priority(row, 'priority');
        status(row, 'status');
        nullableString(row, 'notes');
        nullableId(row, 'recurring_rule_id');
        final recurrenceRemovalReason = nullableString(
          row,
          'recurrence_removal_reason',
        );
        if (recurrenceRemovalReason != null &&
            !RecurrenceRemovalReason.values.contains(recurrenceRemovalReason)) {
          throw const BackupValidationException(
            'Invalid recurrence removal reason.',
          );
        }
        nullableId(row, 'rescheduled_from_id');
        nullableId(row, 'rescheduled_to_id');
        boolean(row, 'is_inbox');
        final marker = integer(row, 'inbox_content_version');
        if (marker != 0 && marker != 1) {
          throw const BackupValidationException(
            'inbox_content_version must be 0 or 1.',
          );
        }
        nullableDateOnly(row, 'due_date');
        final history = planTitleHistory(row, 'plan_title_history');
        final displayPlanChangeId = nullableId(row, 'display_plan_change_id');
        try {
          PlanTitleHistory.validate(
            history,
            displayPlanChangeId: displayPlanChangeId,
            currentTitle: string(row['title'], 'title'),
          );
        } on FormatException catch (error) {
          throw BackupValidationException(error.message);
        }
        if (boolean(row, 'is_inbox') && (start != null || end != null)) {
          throw const BackupValidationException(
            'Inbox tasks must not have a schedule.',
          );
        }
        nullableMissedAt(row, 'missed_at');
        _validateAuditDates(row);
      case 'subtasks':
        id(row, 'id');
        id(row, 'task_id');
        boundedString(row, 'title', 500);
        boolean(row, 'is_completed');
        nonNegativeInt(row, 'sort_order');
        _validateAuditDates(row);
      case 'categories':
        id(row, 'id');
        boundedString(row, 'name', 100);
        color(row, 'color_hex');
        nonNegativeInt(row, 'sort_order');
        boolean(row, 'is_focus');
        _validateAuditDates(row);
      case 'tags':
        id(row, 'id');
        boundedString(row, 'name', 100);
        _validateAuditDates(row);
      case 'task_tags':
        id(row, 'task_id');
        id(row, 'tag_id');
        _validateAuditDates(row);
      case 'recurring_rules':
        id(row, 'id');
        boundedString(row, 'rrule', 500);
        boundedString(row, 'task_title', 500);
        nullableString(row, 'task_description');
        positiveInt(row, 'duration_min');
        nullableId(row, 'category_id');
        priority(row, 'priority');
        idList(row, 'tags');
        timeOfDay(row, 'start_time_of_day');
        final startDate = dateOnly(row, 'start_date');
        final endDate = nullableDateOnly(row, 'end_date');
        if (endDate != null && endDate.compareTo(startDate) < 0) {
          throw const BackupValidationException(
            'Recurring rule end date precedes its start date.',
          );
        }
        boolean(row, 'is_active');
        dateList(row, 'exceptions');
        _validateAuditDates(row);
      case 'task_templates':
        id(row, 'id');
        boundedString(row, 'name', 500);
        nullableString(row, 'description');
        positiveInt(row, 'duration_min');
        nullableId(row, 'category_id');
        priority(row, 'priority');
        idList(row, 'tags');
        _validateAuditDates(row);
      case 'daily_reviews':
        id(row, 'id');
        dateOnly(row, 'date');
        nullableString(row, 'reflection');
        rating(row, 'energy_level');
        rating(row, 'productivity_rating');
        rating(row, 'planning_accuracy_rating');
        stringList(row, 'wins');
        stringList(row, 'improvements');
        _validateAuditDates(row);
      case 'weekly_reviews':
        id(row, 'id');
        dateOnly(row, 'week_start_date');
        nullableString(row, 'reflection');
        rating(row, 'overall_rating');
        stringList(row, 'goals_met');
        stringList(row, 'goals_missed');
        stringList(row, 'next_week_focus');
        _validateAuditDates(row);
      case 'timer_sessions':
        id(row, 'id');
        id(row, 'task_id');
        final started = dateTime(row, 'started_at');
        final ended = nullableDateTime(row, 'ended_at');
        if (ended != null && ended.isBefore(started)) {
          throw const BackupValidationException(
            'Timer session ended before it started.',
          );
        }
        nonNegativeInt(row, 'duration_sec');
        final state = string(row['state'], 'state');
        if (!const {'paused', 'finished'}.contains(state)) {
          throw const BackupValidationException(
            'Portable unfinished timers must be paused.',
          );
        }
        if (row['owner_device_id'] != null) {
          throw const BackupValidationException(
            'Timer owner identity is not portable.',
          );
        }
        final runningSince = nullableDateTime(row, 'running_since');
        if (runningSince != null) {
          throw const BackupValidationException(
            'Portable timers cannot retain a running segment.',
          );
        }
        if ((state == 'finished') != (ended != null)) {
          throw const BackupValidationException(
            'Timer state and end timestamp disagree.',
          );
        }
        final intervals = list(row['work_intervals'], 'work_intervals');
        var total = 0;
        DateTime? priorEnd;
        for (final rawInterval in intervals) {
          final interval = map(rawInterval, 'timer work interval');
          _requireKeys(interval, const {
            'start_at',
            'end_at',
            'duration_sec',
          }, 'timer work interval');
          final intervalStart = dateTime(interval, 'start_at');
          final intervalEnd = dateTime(interval, 'end_at');
          final seconds = nonNegativeInt(interval, 'duration_sec');
          if (intervalEnd.isBefore(intervalStart) ||
              (priorEnd != null && intervalStart.isBefore(priorEnd))) {
            throw const BackupValidationException(
              'Timer work intervals must be chronological.',
            );
          }
          priorEnd = intervalEnd;
          total += seconds;
        }
        if (intervals.isNotEmpty && total != integer(row, 'duration_sec')) {
          throw const BackupValidationException(
            'Timer interval seconds must equal duration_sec.',
          );
        }
        _validateAuditDates(row);
      case 'day_contexts':
        final idValue = id(row, 'id');
        final date = dateOnly(row, 'date');
        final expectedId = generateDeterministicUuid('day-context:$date');
        if (idValue != expectedId) {
          throw const BackupValidationException(
            'Day context ID does not match its calendar date.',
          );
        }
        final kind = _string(row['kind'], 'kind');
        if (!const {
          'office',
          'holiday',
          'leave',
          'travel',
          'custom',
        }.contains(kind)) {
          throw const BackupValidationException('Day context kind is invalid.');
        }
        final label = nullableString(row, 'custom_label');
        if (kind == 'custom') {
          final trimmed = label?.trim() ?? '';
          if (trimmed.isEmpty || trimmed.length > 80 || trimmed != label) {
            throw const BackupValidationException(
              'Custom day context labels must be trimmed and 1–80 characters.',
            );
          }
        } else if (label != null) {
          throw const BackupValidationException(
            'Preset day contexts cannot have a custom label.',
          );
        }
        _validateAuditDates(row);
    }
  }

  void _validateReferences(
    Map<String, dynamic> data,
    Map<String, Set<String>> ids,
  ) {
    bool exists(String table, String? value) =>
        value == null || ids[table]!.contains(value);
    for (final raw in _list(data['tasks'], 'tasks')) {
      final row = _map(raw, 'task');
      for (final field in const [
        'category_id',
        'recurring_rule_id',
        'rescheduled_from_id',
        'rescheduled_to_id',
      ]) {
        final value = nullableId(row, field);
        final table = field == 'category_id'
            ? 'categories'
            : field == 'recurring_rule_id'
            ? 'recurring_rules'
            : 'tasks';
        if (!exists(table, value)) {
          throw BackupValidationException(
            'Task reference $field is missing: $value',
          );
        }
      }
    }
    for (final raw in _list(data['subtasks'], 'subtasks')) {
      if (!exists('tasks', id(_map(raw, 'subtask'), 'task_id'))) {
        throw const BackupValidationException(
          'Subtask references a missing task.',
        );
      }
    }
    for (final raw in _list(data['task_tags'], 'task_tags')) {
      final row = _map(raw, 'task tag');
      if (!exists('tasks', id(row, 'task_id')) ||
          !exists('tags', id(row, 'tag_id'))) {
        throw const BackupValidationException(
          'Task-tag relationship references a missing row.',
        );
      }
    }
    for (final table in const ['recurring_rules', 'task_templates']) {
      for (final raw in _list(data[table], table)) {
        final row = _map(raw, table);
        if (!exists('categories', nullableId(row, 'category_id'))) {
          throw BackupValidationException(
            '$table references a missing category.',
          );
        }
        for (final tagId in idList(row, 'tags')) {
          if (!exists('tags', tagId)) {
            throw BackupValidationException('$table references a missing tag.');
          }
        }
      }
    }
    for (final raw in _list(data['timer_sessions'], 'timer_sessions')) {
      if (!exists('tasks', id(_map(raw, 'timer session'), 'task_id'))) {
        throw const BackupValidationException(
          'Timer session references a missing task.',
        );
      }
    }
  }

  void _validateUniqueBusinessDates(Map<String, dynamic> data) {
    for (final entry in const [
      ('daily_reviews', 'date'),
      ('weekly_reviews', 'week_start_date'),
      ('day_contexts', 'date'),
    ]) {
      final seen = <String>{};
      for (final raw in _list(data[entry.$1], entry.$1)) {
        final value = _string(_map(raw, entry.$1)[entry.$2], entry.$2);
        if (!seen.add(value)) {
          throw BackupValidationException('Duplicate ${entry.$1} date: $value');
        }
      }
    }
  }

  void _validateSetting(String key, dynamic rawValue) {
    final value = _string(rawValue, 'settings[$key]');
    switch (key) {
      case 'grid_interval_minutes':
        if (!const {'15', '30', '60'}.contains(value)) {
          throw const BackupValidationException(
            'grid_interval_minutes must be 15, 30, or 60.',
          );
        }
      case 'theme_mode':
        if (!const {'system', 'light', 'dark'}.contains(value)) {
          throw const BackupValidationException('theme_mode is invalid.');
        }
      case 'review_reminder_enabled':
      case legacyOnboardingCompletedSettingKey:
        if (!const {'true', 'false'}.contains(value)) {
          throw BackupValidationException('$key must be true or false.');
        }
      case 'review_reminder_time':
        final minutes = int.tryParse(value);
        if (minutes == null || minutes < 0 || minutes > 24 * 60 - 1) {
          throw const BackupValidationException(
            'review_reminder_time is out of range.',
          );
        }
    }
  }

  void _validateAuditDates(Map<String, dynamic> row) {
    dateTime(row, 'created_at');
    dateTime(row, 'updated_at');
    nullableDateTime(row, 'deleted_at');
  }

  static DateTime _dateTimeValue(dynamic value, String field) {
    if (value is! String ||
        !value.contains('T') ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw BackupValidationException('$field must be an ISO timestamp.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw BackupValidationException('$field is not a valid timestamp.');
    }
    return parsed.toUtc();
  }

  static Map<String, dynamic> _map(dynamic value, String field) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw BackupValidationException('$field must be an object.');
  }

  static List<dynamic> _list(dynamic value, String field) {
    if (value is List) return value;
    throw BackupValidationException('$field must be an array.');
  }

  static String _string(dynamic value, String field) {
    if (value is String && value.isNotEmpty) return value;
    throw BackupValidationException('$field must be a non-empty string.');
  }

  static void _requireKeys(
    Map<String, dynamic> map,
    Set<String> expected,
    String field,
  ) {
    if (map.length != expected.length ||
        map.keys.any((key) => !expected.contains(key))) {
      throw BackupValidationException(
        '$field has unsupported or missing fields.',
      );
    }
  }
}
