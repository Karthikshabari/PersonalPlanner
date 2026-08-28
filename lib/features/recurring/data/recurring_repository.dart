import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/recurring_rule_dao.dart';
import '../../../core/models/recurring_rule.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/uuid.dart';

/// CRUD for recurring rules (planner.md Chunk 4 #4).
class RecurringRepository {
  final AppDatabase _db;

  RecurringRepository(this._db);

  RecurringRuleDao get _dao => _db.recurringRuleDao;

  Future<RecurringRule> createRule(RecurringRule rule) async {
    final now = DateTime.now();
    final effective = rule.copyWith(
      id: rule.id.isEmpty ? generateUuidV7() : rule.id,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.insertRule(_toCompanion(effective));
    return effective;
  }

  Future<RecurringRule> updateRule(RecurringRule rule) async {
    final row = await _dao.getRuleById(rule.id);
    if (row == null) throw StateError('Recurring rule ${rule.id} not found');
    final effective = rule.copyWith(updatedAt: DateTime.now());
    await _dao.updateRule(
        _toRow(effective, syncStatus: 1, revision: row.revision + 1));
    return effective;
  }

  Future<void> deactivateRule(String ruleId) async {
    final row = await _dao.getRuleById(ruleId);
    if (row == null) return;
    await _dao.updateRule(
      row.copyWith(
        isActive: false,
        updatedAt: DateTime.now(),
        syncStatus: 1,
        revision: row.revision + 1,
      ),
    );
  }

  Future<void> deleteRule(String ruleId) =>
      _dao.softDeleteRule(ruleId, DateTime.now());

  /// Stream of all active rules (planner.md Chunk 4 #4).
  Stream<List<RecurringRule>> watchActiveRules() => _dao
      .watchActiveRules()
      .map((rows) =>
          rows.map(fromRow).where((r) => r.isActive).toList(growable: false));

  Future<List<RecurringRule>> getActiveRules() async => (await _dao.getActiveRules())
      .map(fromRow)
      .where((r) => r.isActive)
      .toList(growable: false);

  Future<RecurringRule?> getRuleById(String ruleId) async {
    final row = await _dao.getRuleById(ruleId);
    return row == null ? null : fromRow(row);
  }

  /// Adds [date] to the rule's exception dates so this single occurrence
  /// stops re-materializing ("delete this occurrence only").
  Future<void> addException(String ruleId, DateTime date) async {
    final row = await _dao.getRuleById(ruleId);
    if (row == null) return;
    final rule = fromRow(row);
    final iso = isoDateString(date);
    final exceptions =
        rule.exceptions.contains(iso) ? rule.exceptions : [...rule.exceptions, iso];
    await _dao.updateRule(row.copyWith(
      exceptionsJson: Value(encodeStringList(exceptions)),
      updatedAt: DateTime.now(),
      syncStatus: 1,
      revision: row.revision + 1,
    ));
  }

  /// Sets the inclusive last date the rule may occur on
  /// ("delete all future occurrences").
  Future<void> setEndDate(String ruleId, DateTime endDate) async {
    final row = await _dao.getRuleById(ruleId);
    if (row == null) return;
    await _dao.updateRule(row.copyWith(
      endDate: Value(isoDateString(endDate)),
      updatedAt: DateTime.now(),
      syncStatus: 1,
      revision: row.revision + 1,
    ));
  }



  static String encodeStringList(List<String> values) => JsonListUtils.encode(values);

  static List<String> decodeStringList(String? json) => JsonListUtils.decode(json);
  static RecurringRule fromRow(RecurringRuleRow row) => RecurringRule(
        id: row.id,
        rrule: row.rrule,
        taskTitle: row.taskTitle,
        taskDescription: row.taskDescription,
        durationMin: row.durationMin,
        categoryId: row.categoryId,
        priority: row.priority,
        tags: decodeStringList(row.tagsJson),
        startTimeOfDay: row.startTimeOfDay,
        startDate: parseIsoDate(row.startDate),
        endDate: row.endDate == null ? null : parseIsoDate(row.endDate!),
        isActive: row.isActive,
        exceptions: decodeStringList(row.exceptionsJson),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  static RecurringRulesCompanion _toCompanion(RecurringRule r) =>
      RecurringRulesCompanion.insert(
        id: r.id,
        rrule: r.rrule,
        taskTitle: r.taskTitle,
        taskDescription: Value(r.taskDescription),
        durationMin: r.durationMin,
        categoryId: Value(r.categoryId),
        priority: Value(r.priority),
        tagsJson: Value(encodeStringList(r.tags)),
        startTimeOfDay: r.startTimeOfDay,
        startDate: isoDateString(r.startDate),
        endDate: Value(r.endDate == null ? null : isoDateString(r.endDate!)),
        isActive: Value(r.isActive),
        exceptionsJson: Value(encodeStringList(r.exceptions)),
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deletedAt: Value(r.deletedAt),
      );

  static RecurringRuleRow _toRow(
    RecurringRule r, {
    required int syncStatus,
    required int revision,
  }) =>
      RecurringRuleRow(
        id: r.id,
        rrule: r.rrule,
        taskTitle: r.taskTitle,
        taskDescription: r.taskDescription,
        durationMin: r.durationMin,
        categoryId: r.categoryId,
        priority: r.priority,
        tagsJson: encodeStringList(r.tags),
        startTimeOfDay: r.startTimeOfDay,
        startDate: isoDateString(r.startDate),
        endDate: r.endDate == null ? null : isoDateString(r.endDate!),
        isActive: r.isActive,
        exceptionsJson: encodeStringList(r.exceptions),
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
        syncStatus: syncStatus,
        revision: revision,
      );
}
