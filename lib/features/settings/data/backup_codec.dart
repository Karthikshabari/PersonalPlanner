import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/timer_session.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../task_editor/domain/plan_title_history.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import 'backup_format.dart';
import 'backup_validator.dart';

/// Owns the portable document envelope, canonical JSON, checksum, and the
/// conversion between Drift rows and portable domain maps.
class BackupCodec {
  static Future<Map<String, dynamic>> exportData(AppDatabase db) async {
    // All table reads share one SQLite snapshot. Encoding and checksum
    // generation happen after this transaction so serialization never holds
    // the database lock while doing CPU work.
    return db.transaction(() async {
      final exportedAt = DateTime.now();
      final data = <String, dynamic>{
        'tasks': (await db.select(db.tasks).get()).map(_taskToJson).toList(),
        'subtasks': (await db.select(db.subtasks).get())
            .map(_subtaskToJson)
            .toList(),
        'categories': (await db.select(db.categories).get())
            .map(_categoryToJson)
            .toList(),
        'tags': (await db.select(db.tags).get()).map(_tagToJson).toList(),
        'task_tags': (await db.select(db.taskTags).get())
            .map(_taskTagToJson)
            .toList(),
        'recurring_rules': (await db.select(db.recurringRules).get())
            .map(_recurringRuleToJson)
            .toList(),
        'task_templates': (await db.select(db.taskTemplates).get())
            .map(_templateToJson)
            .toList(),
        'daily_reviews': (await db.select(db.dailyReviews).get())
            .map(_dailyReviewToJson)
            .toList(),
        'weekly_reviews': (await db.select(db.weeklyReviews).get())
            .map(_weeklyReviewToJson)
            .toList(),
        'timer_sessions': (await db.select(db.timerSessions).get())
            .map((row) => _timerSessionToJson(row, exportedAt))
            .toList(),
        'day_contexts': (await db.select(db.dayContexts).get())
            .map(_dayContextToJson)
            .toList(),
        'settings': await _exportSettings(db),
      };
      return _sortedData(data);
    });
  }

  static String encodeData(Map<String, dynamic> data) {
    final canonicalData = _sortedData(data);
    final content = <String, dynamic>{
      'schema_version': plannerBackupSchemaVersion,
      'data': canonicalData,
    };
    final document = <String, dynamic>{
      'format': 'personal_planner_backup',
      'schema_version': plannerBackupSchemaVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'content': content,
      'content_checksum': checksum(content),
      'validation': <String, dynamic>{
        'algorithm': 'SHA-256',
        'record_counts': recordCounts(canonicalData),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Decodes the envelope and verifies all structural/checksum metadata. The
  /// field-level and graph-level checks belong to [BackupValidator].
  static Map<String, dynamic> decodeData(String source) {
    if (utf8.encode(source).length > plannerBackupMaxBytes) {
      throw const BackupValidationException('Backup file is too large.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const BackupValidationException('Backup is not valid JSON.');
    }
    final root = _asMap(decoded, 'backup document');
    _requireKeys(root, const {
      'format',
      'schema_version',
      'exported_at',
      'content',
      'content_checksum',
      'validation',
    }, 'backup document');
    if (root['format'] != 'personal_planner_backup') {
      throw const BackupValidationException('Unsupported backup format.');
    }
    final documentVersion = root['schema_version'];
    if (documentVersion != 1 && documentVersion != plannerBackupSchemaVersion) {
      throw const BackupValidationException(
        'Unsupported backup schema version.',
      );
    }
    final content = _asMap(root['content'], 'backup content');
    _requireKeys(content, const {'schema_version', 'data'}, 'backup content');
    if (content['schema_version'] != documentVersion) {
      throw const BackupValidationException('Backup content version mismatch.');
    }
    final checksum = _string(root['content_checksum'], 'content checksum');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        checksum != checksumForContent(content)) {
      throw const BackupValidationException(
        'Backup checksum does not match its content.',
      );
    }
    final validation = _asMap(root['validation'], 'validation metadata');
    _requireKeys(validation, const {
      'algorithm',
      'record_counts',
    }, 'validation metadata');
    if (validation['algorithm'] != 'SHA-256') {
      throw const BackupValidationException(
        'Unsupported backup checksum algorithm.',
      );
    }
    _dateTimeValue(root['exported_at'], 'exported_at');
    final data = _asMap(content['data'], 'backup data');
    final counts = _asMap(validation['record_counts'], 'record_counts');
    final expectedCounts = recordCounts(data);
    if (counts.length != expectedCounts.length ||
        counts.keys.any((key) => !expectedCounts.containsKey(key)) ||
        expectedCounts.entries.any(
          (entry) => counts[entry.key] != entry.value,
        )) {
      throw const BackupValidationException(
        'Backup validation record counts do not match its data.',
      );
    }
    if (documentVersion == 1) {
      BackupValidator.validateOriginalV1Structure(data);
    }
    return _adaptImportedData(data, documentVersion as int);
  }

  /// v1 was checksum-verified above before this adapter changes anything.
  /// Its task estimate is treated as a stale compatibility cache and is
  /// projected from the source interval for both v1 and v2 imports.
  static Map<String, dynamic> _adaptImportedData(
    Map<String, dynamic> data,
    int version,
  ) {
    final result = <String, dynamic>{
      for (final entry in data.entries)
        entry.key: entry.value is List
            ? (entry.value as List)
                  .map(
                    (row) => row is Map ? Map<String, dynamic>.from(row) : row,
                  )
                  .toList()
            : entry.value,
    };
    // Backups produced before R3 have no context table. They remain valid and
    // import with an empty context collection after checksum verification.
    result['day_contexts'] ??= <dynamic>[];
    final timerRows = result['timer_sessions'];
    if (timerRows is List) {
      for (final raw in timerRows) {
        if (raw is! Map<String, dynamic>) continue;
        final ended = raw['ended_at'];
        final state = raw['state']?.toString();
        // Old portable data has no persisted state. Imported unfinished work
        // is always paused and unclaimed; it never auto-runs on this device.
        raw['state'] = ended == null && state != 'finished'
            ? 'paused'
            : 'finished';
        raw['running_since'] = null;
        raw['work_intervals'] = raw['work_intervals'] is List
            ? raw['work_intervals']
            : <dynamic>[];
        raw['owner_device_id'] = null;
      }
    }
    final tasks = result['tasks'];
    if (tasks is List) {
      for (final raw in tasks) {
        if (raw is! Map<String, dynamic>) continue;
        final isInbox =
            raw['is_inbox'] == true ||
            raw['is_inbox'] == 1 ||
            raw['is_inbox'] == '1';
        final marker = raw['inbox_content_version'];
        final markerValue = marker is int
            ? marker
            : int.tryParse('$marker') ?? 0;
        if (isInbox && markerValue == 0) {
          final title = raw['title']?.toString() ?? '';
          final description = raw['description'];
          if (description == null || description == '') {
            raw['description'] = title;
          } else if (description != title) {
            raw['description'] = '$title\n\n$description';
          }
          raw['inbox_content_version'] = 1;
        } else {
          raw['inbox_content_version'] = markerValue;
        }
        raw['due_date'] = raw.containsKey('due_date') ? raw['due_date'] : null;
        final portableHistory = raw['plan_title_history'];
        if (portableHistory is! List) {
          final legacyJson = raw['plan_title_history_json'];
          raw['plan_title_history'] = legacyJson is String
              ? PlanTitleHistory.decodeJson(legacyJson)
                    .map((event) => event.toJson())
                    .toList(growable: false)
              : <dynamic>[];
        }
        raw['display_plan_change_id'] =
            raw.containsKey('display_plan_change_id')
            ? raw['display_plan_change_id']
            : null;
        final manualSet = raw['manual_actual_set'];
        final hasManualSet = manualSet == true || manualSet == false;
        final previousActual = raw['actual_duration_min'];
        final previousAdjustment = raw['manual_duration_adjustment_min'];
        final adjustment = previousAdjustment is int
            ? previousAdjustment
            : int.tryParse('$previousAdjustment') ?? 0;
        if (!hasManualSet) {
          var finishedSeconds = 0;
          if (timerRows is List) {
            for (final session in timerRows) {
              if (session is Map<String, dynamic> &&
                  session['task_id'] == raw['id'] &&
                  session['state'] == 'finished') {
                final seconds = session['duration_sec'];
                finishedSeconds += seconds is int
                    ? seconds
                    : int.tryParse('$seconds') ?? 0;
              }
            }
          }
          final actual = previousActual is int
              ? previousActual
              : int.tryParse('$previousActual');
          raw['manual_duration_adjustment_min'] =
              adjustment == 0 && actual != null
              ? actual - (finishedSeconds ~/ 60)
              : adjustment;
          raw['manual_actual_set'] = actual != null || adjustment != 0;
        }
        if (isInbox) {
          raw['start_time'] = null;
          raw['end_time'] = null;
        }
        final start = DateTime.tryParse(raw['start_time']?.toString() ?? '');
        final end = DateTime.tryParse(raw['end_time']?.toString() ?? '');
        raw['estimated_duration_min'] = isInbox
            ? null
            : TaskTimeMetrics.plannedMinutes(start, end);
      }
    }
    // Keep the parameter explicit so a future v3 adapter cannot accidentally
    // be treated as a v1 document by this path.
    if (version != 1 && version != plannerBackupSchemaVersion) {
      throw const BackupValidationException(
        'Unsupported backup schema version.',
      );
    }
    return result;
  }

  static String checksum(Map<String, dynamic> content) =>
      sha256.convert(utf8.encode(canonicalJson(content))).toString();

  static String checksumForContent(Map<String, dynamic> content) =>
      checksum(content);

  static Map<String, int> recordCounts(Map<String, dynamic> data) => {
    for (final entry in data.entries)
      entry.key: entry.value is List
          ? (entry.value as List).length
          : entry.value is Map
          ? (entry.value as Map).length
          : -1,
  };

  static String canonicalJson(dynamic value) =>
      jsonEncode(_canonicalize(value));

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static Map<String, dynamic> _sortedData(Map<String, dynamic> data) {
    final result = <String, dynamic>{
      for (final entry in data.entries)
        entry.key: entry.value is List
            ? List<dynamic>.from(entry.value as List)
            : entry.value,
    };
    for (final key in result.keys) {
      final rows = result[key];
      if (rows is List) {
        rows.sort((a, b) {
          final left = _asMap(a, '$key row');
          final right = _asMap(b, '$key row');
          return _identity(key, left).compareTo(_identity(key, right));
        });
      }
    }
    return result;
  }

  static String _identity(String table, Map<String, dynamic> row) =>
      table == 'task_tags'
      ? '${row['task_id']}:${row['tag_id']}'
      : '${row['id']}';

  static Future<Map<String, String>> _exportSettings(AppDatabase db) async {
    final rows = await (db.select(
      db.appSettings,
    )..where((setting) => setting.key.isIn(portableSettingKeys))).get();
    final values = <String, String>{for (final row in rows) row.key: row.value};
    final sorted = values.keys.toList()..sort();
    return <String, String>{for (final key in sorted) key: values[key]!};
  }

  static Map<String, dynamic> _taskToJson(TaskRow row) => {
    'id': row.id,
    'title': row.title,
    'description': row.description,
    'start_time': row.isInbox ? null : _iso(row.startTime),
    'end_time': row.isInbox ? null : _iso(row.endTime),
    // The estimate is a compatibility projection. Never export a stale
    // value as the authoritative planned-duration source.
    'estimated_duration_min': row.isInbox
        ? null
        : TaskTimeMetrics.plannedMinutes(row.startTime, row.endTime),
    'actual_duration_min': row.actualDurationMin,
    'manual_duration_adjustment_min': row.manualDurationAdjustmentMin,
    'manual_actual_set': row.manualActualSet,
    'category_id': row.categoryId,
    'priority': row.priority,
    'status': row.status,
    'notes': row.notes,
    'recurring_rule_id': row.recurringRuleId,
    'rescheduled_from_id': row.rescheduledFromId,
    'rescheduled_to_id': row.rescheduledToId,
    'is_inbox': row.isInbox,
    'inbox_content_version': row.inboxContentVersion,
    'due_date': row.dueDate,
    'missed_at': row.missedAt,
    'plan_title_history': PlanTitleHistory.decodeJson(row.planTitleHistoryJson)
        .map((event) => event.toJson())
        .toList(growable: false),
    'display_plan_change_id': row.displayPlanChangeId,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _subtaskToJson(SubtaskRow row) => {
    'id': row.id,
    'task_id': row.taskId,
    'title': row.title,
    'is_completed': row.isCompleted,
    'sort_order': row.sortOrder,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _categoryToJson(CategoryRow row) => {
    'id': row.id,
    'name': row.name,
    'color_hex': row.colorHex,
    'sort_order': row.sortOrder,
    'is_focus': row.isFocus,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _tagToJson(TagRow row) => {
    'id': row.id,
    'name': row.name,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _taskTagToJson(TaskTagRow row) => {
    'task_id': row.taskId,
    'tag_id': row.tagId,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _recurringRuleToJson(RecurringRuleRow row) => {
    'id': row.id,
    'rrule': row.rrule,
    'task_title': row.taskTitle,
    'task_description': row.taskDescription,
    'duration_min': row.durationMin,
    'category_id': row.categoryId,
    'priority': row.priority,
    'tags': JsonListUtils.decode(row.tagsJson),
    'start_time_of_day': row.startTimeOfDay,
    'start_date': row.startDate,
    'end_date': row.endDate,
    'is_active': row.isActive,
    'exceptions': JsonListUtils.decode(row.exceptionsJson),
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _templateToJson(TaskTemplateRow row) => {
    'id': row.id,
    'name': row.name,
    'description': row.description,
    'duration_min': row.durationMin,
    'category_id': row.categoryId,
    'priority': row.priority,
    'tags': JsonListUtils.decode(row.tagsJson),
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _dailyReviewToJson(DailyReviewRow row) => {
    'id': row.id,
    'date': row.date,
    'reflection': row.reflection,
    'energy_level': row.energyLevel,
    'productivity_rating': row.productivityRating,
    'planning_accuracy_rating': row.planningAccuracyRating,
    'wins': JsonListUtils.decode(row.winsJson),
    'improvements': JsonListUtils.decode(row.improvementsJson),
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _weeklyReviewToJson(WeeklyReviewRow row) => {
    'id': row.id,
    'week_start_date': row.weekStartDate,
    'reflection': row.reflection,
    'overall_rating': row.overallRating,
    'goals_met': JsonListUtils.decode(row.goalsMetJson),
    'goals_missed': JsonListUtils.decode(row.goalsMissedJson),
    'next_week_focus': JsonListUtils.decode(row.nextWeekFocusJson),
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static Map<String, dynamic> _timerSessionToJson(
    TimerSessionRow row,
    DateTime exportedAt,
  ) {
    var state = row.state;
    var duration = row.durationSec;
    var intervals = TaskActualDurationService.decodeIntervals(
      row.workIntervalsJson,
    );
    var runningSince = row.runningSince;
    var updatedAt = row.updatedAt;
    if (state == 'running') {
      final began = runningSince ?? row.startedAt;
      var end = exportedAt.toUtc();
      if (end.isBefore(began)) end = began;
      final seconds = end.difference(began).inSeconds.clamp(0, 1 << 31).toInt();
      if (seconds > 0) {
        intervals = [
          ...intervals,
          TimerWorkInterval(startAt: began, endAt: end, durationSec: seconds),
        ];
      }
      duration = intervals.fold(
        0,
        (sum, interval) => sum + interval.durationSec,
      );
      state = 'paused';
      runningSince = null;
      updatedAt = end;
    }
    return {
      'id': row.id,
      'task_id': row.taskId,
      'started_at': _iso(row.startedAt),
      'ended_at': _iso(row.endedAt),
      'duration_sec': duration,
      'state': state,
      'running_since': null,
      'work_intervals': [
        for (final interval in intervals)
          TaskActualDurationService.intervalToJson(interval),
      ],
      'owner_device_id': null,
      'created_at': _iso(row.createdAt),
      'updated_at': _iso(updatedAt),
      'deleted_at': _iso(row.deletedAt),
    };
  }

  static Map<String, dynamic> _dayContextToJson(DayContextRow row) => {
    'id': row.id,
    'date': row.date,
    'kind': row.kind,
    'custom_label': row.customLabel,
    'created_at': _iso(row.createdAt),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': _iso(row.deletedAt),
  };

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

  static Map<String, dynamic> _asMap(dynamic value, String field) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw BackupValidationException('$field must be an object.');
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
}
