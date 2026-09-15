import 'backup_codec.dart';
import 'backup_format.dart';
import 'backup_validator.dart';

typedef BackupRowEquivalence = bool Function(
  String table,
  Map<String, dynamic> local,
  Map<String, dynamic> incoming,
);

typedef BackupSettingEquivalence = bool Function(
  String key,
  String local,
  String incoming,
);

/// A write-free result of comparing an incoming backup with the current local
/// domain. The complete plan is built before the transaction mutates SQLite.
class BackupMergePlan {
  final Map<String, List<Map<String, dynamic>>> rowsToInsert;
  final Map<String, String> settingsToInsert;
  final int skipped;
  final List<BackupConflict> conflicts;

  const BackupMergePlan({
    required this.rowsToInsert,
    required this.settingsToInsert,
    required this.skipped,
    required this.conflicts,
  });

  int get insertedCount =>
      rowsToInsert.values.fold(0, (count, rows) => count + rows.length) +
      settingsToInsert.length;
}

class BackupMergePlanner {
  BackupMergePlan build({
    required Map<String, dynamic> incoming,
    required Map<String, dynamic> local,
    BackupRowEquivalence? rowEquivalence,
    BackupSettingEquivalence? settingEquivalence,
  }) {
    final localRows = <String, Map<String, Map<String, dynamic>>>{};
    for (final table in BackupValidator.tableNames) {
      final rows = <String, Map<String, dynamic>>{};
      for (final raw in BackupValidator.list(local[table], table)) {
        final row = BackupValidator.map(raw, '$table row');
        rows[BackupValidator.entryId(table, row)] = row;
      }
      localRows[table] = rows;
    }

    final candidates = <String, List<Map<String, dynamic>>>{
      for (final table in BackupValidator.tableNames)
        table: <Map<String, dynamic>>[],
    };
    final directConflicts = <String>{};
    final conflictsByKey = <String, BackupConflict>{};
    var skipped = 0;

    void addConflict(String table, String id, BackupConflictKind kind) {
      final key = _key(table, id);
      conflictsByKey.putIfAbsent(
        key,
        () => BackupConflict(table: table, id: id, kind: kind),
      );
    }

    for (final table in BackupValidator.tableNames) {
      for (final raw in BackupValidator.list(incoming[table], table)) {
        final row = BackupValidator.map(raw, '$table row');
        final id = BackupValidator.entryId(table, row);
        final old = localRows[table]![id];
        if (old == null) {
          candidates[table]!.add(row);
        } else if (BackupCodec.canonicalJson(old) ==
                BackupCodec.canonicalJson(row) ||
            rowEquivalence?.call(table, old, row) == true) {
          skipped++;
        } else {
          directConflicts.add(_key(table, id));
          addConflict(table, id, BackupConflictKind.differing);
        }
      }
    }

    final localSettings = <String, String>{
      for (final entry in BackupValidator.map(
        local['settings'],
        'settings',
      ).entries)
        entry.key: BackupValidator.string(
          entry.value,
          'settings[${entry.key}]',
        ),
    };
    final settingsToInsert = <String, String>{};
    for (final entry in BackupValidator.map(
      incoming['settings'],
      'settings',
    ).entries) {
      final old = localSettings[entry.key];
      final value = BackupValidator.string(
        entry.value,
        'settings[${entry.key}]',
      );
      if (old == null) {
        settingsToInsert[entry.key] = value;
      } else if (old == value ||
          settingEquivalence?.call(entry.key, old, value) == true) {
        skipped++;
      } else {
        addConflict('settings', entry.key, BackupConflictKind.differing);
      }
    }

    // A blocked row is added to the same conflict report exactly once. The
    // fixed-point walk closes over transitive dependencies (for example a
    // conflicting category -> blocked recurring rule -> blocked task ->
    // blocked subtask/timer relationship).
    final blocked = <String>{...directConflicts};
    var changed = true;
    while (changed) {
      changed = false;
      for (final table in BackupValidator.tableNames) {
        for (final row in candidates[table]!) {
          final id = BackupValidator.entryId(table, row);
          final key = _key(table, id);
          if (blocked.contains(key)) continue;
          final dependencies = _dependencies(table, row);
          if (dependencies.any(blocked.contains)) {
            blocked.add(key);
            addConflict(table, id, BackupConflictKind.blocked);
            changed = true;
          }
        }
      }
    }

    final rowsToInsert = <String, List<Map<String, dynamic>>>{
      for (final table in BackupValidator.tableNames)
        table: [
          for (final row in candidates[table]!)
            if (!blocked.contains(
              _key(table, BackupValidator.entryId(table, row)),
            ))
              row,
        ],
    };
    final conflicts = conflictsByKey.values.toList()
      ..sort((a, b) {
        final table = a.table.compareTo(b.table);
        return table == 0 ? a.id.compareTo(b.id) : table;
      });
    return BackupMergePlan(
      rowsToInsert: rowsToInsert,
      settingsToInsert: Map.unmodifiable(settingsToInsert),
      skipped: skipped,
      conflicts: List.unmodifiable(conflicts),
    );
  }

  static String _key(String table, String id) => '$table\u0000$id';

  static Iterable<String> _dependencies(
    String table,
    Map<String, dynamic> row,
  ) sync* {
    String? nullable(String field) => row[field]?.toString();
    String key(String parentTable, String id) => _key(parentTable, id);
    switch (table) {
      case 'recurring_rules':
      case 'task_templates':
        final category = nullable('category_id');
        if (category != null) yield key('categories', category);
        for (final tag in BackupValidator.idList(row, 'tags')) {
          yield key('tags', tag);
        }
      case 'tasks':
        final category = nullable('category_id');
        if (category != null) yield key('categories', category);
        final rule = nullable('recurring_rule_id');
        if (rule != null) yield key('recurring_rules', rule);
        for (final field in const [
          'rescheduled_from_id',
          'rescheduled_to_id',
        ]) {
          final task = nullable(field);
          if (task != null) yield key('tasks', task);
        }
      case 'subtasks':
      case 'timer_sessions':
        final task = nullable('task_id');
        if (task != null) yield key('tasks', task);
      case 'task_tags':
        final task = nullable('task_id');
        final tag = nullable('tag_id');
        if (task != null) yield key('tasks', task);
        if (tag != null) yield key('tags', tag);
    }
  }
}
