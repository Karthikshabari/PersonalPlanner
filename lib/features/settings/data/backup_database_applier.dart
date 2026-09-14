import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/task_time_metrics.dart';
import '../../timer/domain/task_actual_duration_service.dart';
import '../../task_editor/domain/plan_title_history.dart';
import 'backup_format.dart';
import 'backup_merge_planner.dart';
import 'backup_validator.dart';

/// Owns the only write side of the backup boundary. It is called from a
/// recoverable Drift transaction after codec, validation, and merge planning
/// have completed.
class BackupDatabaseApplier {
  BackupDatabaseApplier(this._db);

  final AppDatabase _db;

  Future<void> applyMerge(BackupMergePlan plan) async {
    for (final entry in _orderedEntries(plan.rowsToInsert)) {
      for (final row in entry.value) {
        await insertRow(entry.key, row);
      }
    }
    for (final entry in plan.settingsToInsert.entries) {
      await _db.syncDao.setSetting(entry.key, entry.value);
    }
    await rebuildDerivedState();
  }

  Future<void> applyReplace(Map<String, dynamic> data) async {
    await _db.syncDao.runWithoutOutbound(() async {
      await _deleteUserRows();
      await _deletePortableSettings();
      // A replacement is a complete local snapshot. Any old outbox,
      // conflict, or cursor state describes rows that no longer exist in the
      // restored database and must not survive to a later sync attempt.
      await _db.delete(_db.syncLog).go();
      await _db.delete(_db.syncConflicts).go();
      await _db.delete(_db.syncState).go();
      for (final entry in _orderedDataEntries(data)) {
        if (entry.key == 'settings') {
          final settings = BackupValidator.map(entry.value, 'settings');
          for (final setting in settings.entries) {
            await _db.syncDao.setSetting(
              BackupValidator.string(setting.key, 'settings key'),
              BackupValidator.string(setting.value, 'settings value'),
            );
          }
        } else {
          for (final raw in BackupValidator.list(entry.value, entry.key)) {
            await insertRow(
              entry.key,
              BackupValidator.map(raw, '${entry.key} row'),
            );
          }
        }
      }
      await rebuildDerivedState();
    });
  }

  Future<void> insertRow(String table, Map<String, dynamic> row) async {
    switch (table) {
      case 'categories':
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                name: BackupValidator.boundedString(row, 'name', 100),
                colorHex: BackupValidator.color(row, 'color_hex'),
                sortOrder: Value(
                  BackupValidator.nonNegativeInt(row, 'sort_order'),
                ),
                isFocus: Value(BackupValidator.boolean(row, 'is_focus')),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'tasks':
        await _db
            .into(_db.tasks)
            .insert(
              TasksCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                title: BackupValidator.boundedString(row, 'title', 500),
                description: Value(
                  BackupValidator.nullableString(row, 'description'),
                ),
                startTime: Value(
                  BackupValidator.boolean(row, 'is_inbox')
                      ? null
                      : BackupValidator.nullableDateTime(row, 'start_time'),
                ),
                endTime: Value(
                  BackupValidator.boolean(row, 'is_inbox')
                      ? null
                      : BackupValidator.nullableDateTime(row, 'end_time'),
                ),
                estimatedDurationMin: Value(
                  BackupValidator.boolean(row, 'is_inbox')
                      ? null
                      : TaskTimeMetrics.plannedMinutes(
                          BackupValidator.nullableDateTime(row, 'start_time'),
                          BackupValidator.nullableDateTime(row, 'end_time'),
                        ),
                ),
                actualDurationMin: Value(
                  BackupValidator.nullableNonNegativeInt(
                    row,
                    'actual_duration_min',
                  ),
                ),
                manualDurationAdjustmentMin: Value(
                  BackupValidator.integer(
                    row,
                    'manual_duration_adjustment_min',
                  ),
                ),
                manualActualSet: Value(
                  BackupValidator.boolean(row, 'manual_actual_set'),
                ),
                categoryId: Value(
                  BackupValidator.nullableId(row, 'category_id'),
                ),
                priority: Value(BackupValidator.priority(row, 'priority')),
                status: Value(BackupValidator.status(row, 'status')),
                notes: Value(BackupValidator.nullableString(row, 'notes')),
                recurringRuleId: Value(
                  BackupValidator.nullableId(row, 'recurring_rule_id'),
                ),
                rescheduledFromId: Value(
                  BackupValidator.nullableId(row, 'rescheduled_from_id'),
                ),
                rescheduledToId: Value(
                  BackupValidator.nullableId(row, 'rescheduled_to_id'),
                ),
                isInbox: Value(BackupValidator.boolean(row, 'is_inbox')),
                inboxContentVersion: Value(
                  BackupValidator.integer(row, 'inbox_content_version'),
                ),
                dueDate: Value(
                  BackupValidator.nullableDateOnly(row, 'due_date'),
                ),
                missedAt: Value(
                  BackupValidator.nullableString(row, 'missed_at'),
                ),
                planTitleHistoryJson: Value(
                  PlanTitleHistory.encodeJson(
                    BackupValidator.planTitleHistory(row, 'plan_title_history'),
                  ),
                ),
                displayPlanChangeId: Value(
                  BackupValidator.nullableId(row, 'display_plan_change_id'),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'subtasks':
        await _db
            .into(_db.subtasks)
            .insert(
              SubtasksCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                taskId: BackupValidator.id(row, 'task_id'),
                title: BackupValidator.boundedString(row, 'title', 500),
                isCompleted: Value(
                  BackupValidator.boolean(row, 'is_completed'),
                ),
                sortOrder: Value(
                  BackupValidator.nonNegativeInt(row, 'sort_order'),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'tags':
        await _db
            .into(_db.tags)
            .insert(
              TagsCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                name: BackupValidator.boundedString(row, 'name', 100),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'task_tags':
        await _db
            .into(_db.taskTags)
            .insert(
              TaskTagsCompanion.insert(
                taskId: BackupValidator.id(row, 'task_id'),
                tagId: BackupValidator.id(row, 'tag_id'),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'recurring_rules':
        await _db
            .into(_db.recurringRules)
            .insert(
              RecurringRulesCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                rrule: BackupValidator.boundedString(row, 'rrule', 500),
                taskTitle: BackupValidator.boundedString(
                  row,
                  'task_title',
                  500,
                ),
                taskDescription: Value(
                  BackupValidator.nullableString(row, 'task_description'),
                ),
                durationMin: BackupValidator.positiveInt(row, 'duration_min'),
                categoryId: Value(
                  BackupValidator.nullableId(row, 'category_id'),
                ),
                priority: Value(BackupValidator.priority(row, 'priority')),
                tagsJson: Value(
                  JsonListUtils.encode(BackupValidator.idList(row, 'tags')),
                ),
                startTimeOfDay: BackupValidator.timeOfDay(
                  row,
                  'start_time_of_day',
                ),
                startDate: BackupValidator.dateOnly(row, 'start_date'),
                endDate: Value(
                  BackupValidator.nullableDateOnly(row, 'end_date'),
                ),
                isActive: Value(BackupValidator.boolean(row, 'is_active')),
                exceptionsJson: Value(
                  JsonListUtils.encode(
                    BackupValidator.dateList(row, 'exceptions'),
                  ),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'task_templates':
        await _db
            .into(_db.taskTemplates)
            .insert(
              TaskTemplatesCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                name: BackupValidator.boundedString(row, 'name', 500),
                description: Value(
                  BackupValidator.nullableString(row, 'description'),
                ),
                durationMin: BackupValidator.positiveInt(row, 'duration_min'),
                categoryId: Value(
                  BackupValidator.nullableId(row, 'category_id'),
                ),
                priority: Value(BackupValidator.priority(row, 'priority')),
                tagsJson: Value(
                  JsonListUtils.encode(BackupValidator.idList(row, 'tags')),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'daily_reviews':
        await _db
            .into(_db.dailyReviews)
            .insert(
              DailyReviewsCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                date: BackupValidator.dateOnly(row, 'date'),
                reflection: Value(
                  BackupValidator.nullableString(row, 'reflection'),
                ),
                energyLevel: Value(BackupValidator.rating(row, 'energy_level')),
                productivityRating: Value(
                  BackupValidator.rating(row, 'productivity_rating'),
                ),
                planningAccuracyRating: Value(
                  BackupValidator.rating(row, 'planning_accuracy_rating'),
                ),
                winsJson: Value(_stringListJson(row, 'wins')),
                improvementsJson: Value(_stringListJson(row, 'improvements')),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'weekly_reviews':
        await _db
            .into(_db.weeklyReviews)
            .insert(
              WeeklyReviewsCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                weekStartDate: BackupValidator.dateOnly(row, 'week_start_date'),
                reflection: Value(
                  BackupValidator.nullableString(row, 'reflection'),
                ),
                overallRating: Value(
                  BackupValidator.rating(row, 'overall_rating'),
                ),
                goalsMetJson: Value(_stringListJson(row, 'goals_met')),
                goalsMissedJson: Value(_stringListJson(row, 'goals_missed')),
                nextWeekFocusJson: Value(
                  _stringListJson(row, 'next_week_focus'),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'timer_sessions':
        await _db
            .into(_db.timerSessions)
            .insert(
              TimerSessionsCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                taskId: BackupValidator.id(row, 'task_id'),
                startedAt: BackupValidator.dateTime(row, 'started_at'),
                endedAt: Value(
                  BackupValidator.nullableDateTime(row, 'ended_at'),
                ),
                durationSec: Value(
                  BackupValidator.nonNegativeInt(row, 'duration_sec'),
                ),
                state: Value(BackupValidator.string(row['state'], 'state')),
                runningSince: Value(
                  BackupValidator.nullableDateTime(row, 'running_since'),
                ),
                workIntervalsJson: Value(
                  jsonEncode(
                    BackupValidator.list(
                      row['work_intervals'],
                      'work_intervals',
                    ),
                  ),
                ),
                ownerDeviceId: const Value(null),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      case 'day_contexts':
        await _db
            .into(_db.dayContexts)
            .insert(
              DayContextsCompanion.insert(
                id: BackupValidator.id(row, 'id'),
                date: BackupValidator.dateOnly(row, 'date'),
                kind: BackupValidator.string(row['kind'], 'kind'),
                customLabel: Value(
                  BackupValidator.nullableString(row, 'custom_label'),
                ),
                createdAt: BackupValidator.dateTime(row, 'created_at'),
                updatedAt: BackupValidator.dateTime(row, 'updated_at'),
                deletedAt: Value(
                  BackupValidator.nullableDateTime(row, 'deleted_at'),
                ),
              ),
            );
      default:
        throw BackupValidationException('Unsupported backup table: $table');
    }
  }

  Future<void> rebuildDerivedState() async {
    final taskIds = (await _db.select(_db.tasks).get())
        .map((task) => task.id)
        .toSet();
    await TaskActualDurationService(_db).recomputeTasks(taskIds);
    await _db.statsDao.invalidateAll();
    await _db.customStatement(
      "INSERT INTO tasks_fts(tasks_fts) VALUES ('rebuild')",
    );
    final foreignKeyViolations = await _db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    if (foreignKeyViolations.isNotEmpty) {
      throw const BackupValidationException(
        'Import failed integrity checks; no changes were committed.',
      );
    }
    final integrityRows = await _db
        .customSelect('PRAGMA integrity_check')
        .get();
    final failed = integrityRows.any(
      (row) =>
          row.data.values.isEmpty ||
          row.data.values.first.toString().toLowerCase() != 'ok',
    );
    if (failed) {
      throw const BackupValidationException(
        'Import failed integrity checks; no changes were committed.',
      );
    }
  }

  Future<void> _deleteUserRows() async {
    await _db.delete(_db.timerSessions).go();
    await _db.delete(_db.dayContexts).go();
    await _db.delete(_db.taskTags).go();
    await _db.delete(_db.subtasks).go();
    await _db.delete(_db.tasks).go();
    await _db.delete(_db.taskTemplates).go();
    await _db.delete(_db.recurringRules).go();
    await _db.delete(_db.dailyReviews).go();
    await _db.delete(_db.weeklyReviews).go();
    await _db.delete(_db.tags).go();
    await _db.delete(_db.categories).go();
  }

  Future<void> _deletePortableSettings() async {
    await (_db.delete(
      _db.appSettings,
    )..where((setting) => setting.key.isIn(portableSettingKeys))).go();
  }

  String? _stringListJson(Map<String, dynamic> row, String field) {
    final values = BackupValidator.stringList(row, field);
    return values.isEmpty ? null : JsonListUtils.encode(values);
  }

  static Iterable<MapEntry<String, List<Map<String, dynamic>>>> _orderedEntries(
    Map<String, List<Map<String, dynamic>>> rows,
  ) sync* {
    for (final table in _tableOrder) {
      yield MapEntry(table, rows[table] ?? const []);
    }
  }

  static List<MapEntry<String, dynamic>> _orderedDataEntries(
    Map<String, dynamic> data,
  ) => [
    for (final table in _tableOrder) MapEntry(table, data[table]),
    MapEntry('settings', data['settings']),
  ];

  static const _tableOrder = [
    'day_contexts',
    'categories',
    'tags',
    'recurring_rules',
    'tasks',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'subtasks',
    'task_tags',
    'timer_sessions',
  ];
}
