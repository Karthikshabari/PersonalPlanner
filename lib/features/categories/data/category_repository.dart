import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/category_dao.dart';
import '../../../core/models/category.dart';
import '../../../core/utils/planner_time_zone.dart';
import '../../../core/utils/uuid.dart';

/// What deleting a category touches, for the confirm dialog.
class CategoryUsage {
  /// Live tasks in the category, finished and past ones included.
  final int tasks;

  /// Of [tasks], those whose day is before today. They keep the category.
  final int pastTasks;
  final int rules;
  final int templates;

  const CategoryUsage({
    required this.tasks,
    required this.pastTasks,
    required this.rules,
    required this.templates,
  });
}

/// The rows [CategoryRepository.deleteCategory] cleared, so
/// [CategoryRepository.undoDelete] can put back exactly those.
class CategoryDeletion {
  final String categoryId;
  final List<String> taskIds;
  final List<String> ruleIds;
  final List<String> templateIds;

  const CategoryDeletion({
    required this.categoryId,
    required this.taskIds,
    required this.ruleIds,
    required this.templateIds,
  });
}

class CategoryRepository {
  static const String _defaultsSeededKey = 'default_categories_seeded';

  /// Stable logical identities for the built-in categories. These values are
  /// derived from a fixed application namespace, not generated per database,
  /// so two offline clients converge on the same rows.
  static const defaultCategoryKeys = <String>[
    'work',
    'personal',
    'health',
    'learning',
  ];

  /// The complete semantic definition of each built-in category. These
  /// values are also the adoption boundary: timestamps are initialization
  /// metadata, while these fields describe the category users see and edit.
  static const defaultCategoryDefinitions =
      <
        ({
          String key,
          String name,
          String colorHex,
          int sortOrder,
          bool isFocus,
        })
      >[
        (
          key: 'work',
          name: 'Work',
          colorHex: '#4285F4',
          sortOrder: 0,
          isFocus: false,
        ),
        (
          key: 'personal',
          name: 'Personal',
          colorHex: '#34A853',
          sortOrder: 1,
          isFocus: false,
        ),
        (
          key: 'health',
          name: 'Health',
          colorHex: '#EA4335',
          sortOrder: 2,
          isFocus: false,
        ),
        (
          key: 'learning',
          name: 'Learning',
          colorHex: '#FBBC04',
          sortOrder: 3,
          isFocus: false,
        ),
      ];

  static String defaultCategoryId(String key) =>
      generateDeterministicUuid('default-category:$key');

  final AppDatabase _db;
  final DateTime Function() _clock;

  CategoryRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  CategoryDao get _dao => _db.categoryDao;

  Future<Category> insertCategory(Category category) async {
    final now = DateTime.now();
    final effective = category.copyWith(
      id: category.id.isEmpty ? generateUuidV7() : category.id,
      createdAt: now,
      updatedAt: now,
    );
    await _dao.insertCategory(_toCompanion(effective));
    return effective;
  }

  Future<Category> updateCategory(Category category) async {
    final now = DateTime.now();
    final effective = category.copyWith(updatedAt: now);
    final row = await _dao.getCategoryById(effective.id);
    if (row == null) {
      throw StateError('Category ${effective.id} not found');
    }
    await _db.transaction(() async {
      await _dao.updateCategory(
        _toRow(effective, syncStatus: 1, revision: row.revision + 1),
      );
      await _db.statsDao.invalidateAll();
    });
    return effective;
  }

  /// Start of today in the planner time zone, as the UTC text stored in
  /// `tasks.start_time`.
  String _todayStartIso() =>
      PlannerTimeZone.startOfDay(_clock()).toUtc().toIso8601String();

  /// Tasks that lose the category on delete: unfinished and not in the past.
  /// Past and finished (completed, skipped, cancelled, rescheduled) tasks
  /// keep it, so history and focus minutes stay attributed.
  static const _clearableTasks =
      'category_id = ? AND deleted_at IS NULL '
      "AND status IN ('planned', 'in_progress') "
      'AND (start_time IS NULL OR start_time >= ?)';

  Future<CategoryUsage> usageOf(String categoryId) async {
    final row = await _db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM tasks WHERE category_id = ? '
          'AND deleted_at IS NULL) AS tasks, '
          '(SELECT COUNT(*) FROM tasks WHERE category_id = ? '
          'AND deleted_at IS NULL AND start_time < ?) AS past_tasks, '
          '(SELECT COUNT(*) FROM recurring_rules WHERE category_id = ? '
          'AND deleted_at IS NULL) AS rules, '
          '(SELECT COUNT(*) FROM task_templates WHERE category_id = ? '
          'AND deleted_at IS NULL) AS templates',
          variables: [
            Variable<String>(categoryId),
            Variable<String>(categoryId),
            Variable<String>(_todayStartIso()),
            Variable<String>(categoryId),
            Variable<String>(categoryId),
          ],
          readsFrom: {_db.tasks, _db.recurringRules, _db.taskTemplates},
        )
        .getSingle();
    return CategoryUsage(
      tasks: row.read<int>('tasks'),
      pastTasks: row.read<int>('past_tasks'),
      rules: row.read<int>('rules'),
      templates: row.read<int>('templates'),
    );
  }

  /// Soft-deletes the category. It is cleared only from unfinished tasks that
  /// are not in the past, and from rules and templates; the returned record
  /// feeds [undoDelete].
  Future<CategoryDeletion> deleteCategory(String categoryId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final todayIso = _todayStartIso();
    late CategoryDeletion deletion;
    await _db.transaction(() async {
      final taskVariables = [
        Variable<String>(categoryId),
        Variable<String>(todayIso),
      ];
      final taskIds = await _idsWhere('tasks', _clearableTasks, taskVariables);
      final ruleIds = await _idsWhere(
        'recurring_rules',
        'category_id = ? AND deleted_at IS NULL',
        [Variable<String>(categoryId)],
      );
      final templateIds = await _idsWhere(
        'task_templates',
        'category_id = ? AND deleted_at IS NULL',
        [Variable<String>(categoryId)],
      );
      await _db.customUpdate(
        'UPDATE tasks SET category_id = NULL, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 WHERE $_clearableTasks',
        variables: [Variable<String>(now), ...taskVariables],
        updates: {_db.tasks},
      );
      await _db.customUpdate(
        'UPDATE recurring_rules SET category_id = NULL, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE category_id = ? AND deleted_at IS NULL',
        variables: [Variable<String>(now), Variable<String>(categoryId)],
        updates: {_db.recurringRules},
      );
      await _db.customUpdate(
        'UPDATE task_templates SET category_id = NULL, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE category_id = ? AND deleted_at IS NULL',
        variables: [Variable<String>(now), Variable<String>(categoryId)],
        updates: {_db.taskTemplates},
      );
      await _db.customUpdate(
        'UPDATE categories SET deleted_at = ?, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE id = ? AND deleted_at IS NULL',
        variables: [
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(categoryId),
        ],
        updates: {_db.categories},
      );
      await _db.statsDao.invalidateAll();
      deletion = CategoryDeletion(
        categoryId: categoryId,
        taskIds: taskIds,
        ruleIds: ruleIds,
        templateIds: templateIds,
      );
    });
    return deletion;
  }

  /// Brings the category back and re-attaches it to the rows [deleteCategory]
  /// cleared. A row that has been given another category, or deleted, since
  /// is left as it is. Every write goes through the normal sync triggers.
  Future<void> undoDelete(CategoryDeletion deletion) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction(() async {
      await _db.customUpdate(
        'UPDATE categories SET deleted_at = NULL, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE id = ? AND deleted_at IS NOT NULL',
        variables: [
          Variable<String>(now),
          Variable<String>(deletion.categoryId),
        ],
        updates: {_db.categories},
      );
      for (final (table, ids, entity) in <(String, List<String>, TableInfo)>[
        ('tasks', deletion.taskIds, _db.tasks),
        ('recurring_rules', deletion.ruleIds, _db.recurringRules),
        ('task_templates', deletion.templateIds, _db.taskTemplates),
      ]) {
        for (final id in ids) {
          await _db.customUpdate(
            'UPDATE $table SET category_id = ?, updated_at = ?, '
            'sync_status = 1, revision = revision + 1 '
            'WHERE id = ? AND category_id IS NULL AND deleted_at IS NULL',
            variables: [
              Variable<String>(deletion.categoryId),
              Variable<String>(now),
              Variable<String>(id),
            ],
            updates: {entity},
          );
        }
      }
      await _db.statsDao.invalidateAll();
    });
  }

  Future<List<String>> _idsWhere(
    String table,
    String where,
    List<Variable> variables,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM $table WHERE $where',
          variables: variables,
          readsFrom: {_db.tasks, _db.recurringRules, _db.taskTemplates},
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// Persists a new sort order for the category list.
  Future<void> reorderCategories(List<String> orderedIds) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(
          _db.categories,
        )..where((c) => c.id.equals(orderedIds[i]))).write(
          CategoriesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
            syncStatus: const Value(1),
            revision: Value(
              (await _dao.getCategoryById(orderedIds[i]))!.revision + 1,
            ),
          ),
        );
      }
    });
  }

  Future<Category?> getCategoryById(String categoryId) async {
    final row = await _dao.getCategoryById(categoryId);
    return row == null ? null : _fromRow(row);
  }

  Stream<List<Category>> watchAllCategories() =>
      _dao.watchActiveCategories().map((rows) => rows.map(_fromRow).toList());

  Future<List<Category>> getAllCategories() async =>
      (await _dao.getActiveCategories()).map(_fromRow).toList();

  Future<void> seedDefaultsIfEmpty() async {
    await _db.transaction(() async {
      final marker = await (_db.select(
        _db.appSettings,
      )..where((s) => s.key.equals(_defaultsSeededKey))).getSingleOrNull();
      final now = DateTime.now();
      for (final definition in defaultCategoryDefinitions) {
        final stableId = defaultCategoryId(definition.key);
        final stable = await _dao.getCategoryById(stableId);
        if (stable != null) continue;

        // Databases created before stable identities used random UUIDs. Only
        // reconcile a legacy row when the old seed marker proves that it was
        // application-created. A user category with the same name/color is
        // otherwise left untouched and the canonical built-in is added.
        if (marker != null) {
          final legacy =
              await (_db.select(_db.categories)..where(
                    (category) =>
                        category.name.equals(definition.name) &
                        category.colorHex.equals(definition.colorHex) &
                        category.deletedAt.isNull(),
                  ))
                  .get();
          if (legacy.length == 1 && legacy.single.id != stableId) {
            await _reconcileLegacyCategory(legacy.single, stableId);
            continue;
          }
        }

        await _dao.insertCategory(
          CategoriesCompanion.insert(
            id: stableId,
            name: definition.name,
            colorHex: definition.colorHex,
            sortOrder: Value(definition.sortOrder),
            isFocus: Value(definition.isFocus),
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value(1),
            revision: const Value(1),
          ),
        );
      }
      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: _defaultsSeededKey, value: 'true'),
          );
    });
  }

  Future<void> _reconcileLegacyCategory(
    CategoryRow legacy,
    String stableId,
  ) async {
    final now = DateTime.now().toUtc();
    // Materialize the parent before moving any foreign keys. SQLite foreign
    // keys are immediate here, so updating a task/rule/template first would
    // fail before the canonical category exists.
    await _dao.insertCategory(
      CategoriesCompanion.insert(
        id: stableId,
        name: legacy.name,
        colorHex: legacy.colorHex,
        sortOrder: Value(legacy.sortOrder),
        isFocus: Value(legacy.isFocus),
        createdAt: legacy.createdAt,
        updatedAt: now,
        syncStatus: const Value(1),
        revision: const Value(1),
      ),
    );
    await _db.customUpdate(
      'UPDATE tasks SET category_id = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE category_id = ?',
      variables: [
        Variable<String>(stableId),
        Variable<String>(now.toIso8601String()),
        Variable<String>(legacy.id),
      ],
      updates: {_db.tasks},
    );
    await _db.customUpdate(
      'UPDATE recurring_rules SET category_id = ?, updated_at = ?, '
      'sync_status = 1, revision = revision + 1 WHERE category_id = ?',
      variables: [
        Variable<String>(stableId),
        Variable<String>(now.toIso8601String()),
        Variable<String>(legacy.id),
      ],
      updates: {_db.recurringRules},
    );
    await _db.customUpdate(
      'UPDATE task_templates SET category_id = ?, updated_at = ?, '
      'sync_status = 1, revision = revision + 1 WHERE category_id = ?',
      variables: [
        Variable<String>(stableId),
        Variable<String>(now.toIso8601String()),
        Variable<String>(legacy.id),
      ],
      updates: {_db.taskTemplates},
    );
    await _db.customUpdate(
      'UPDATE categories SET deleted_at = ?, updated_at = ?, sync_status = 1, '
      'revision = revision + 1 WHERE id = ? AND deleted_at IS NULL',
      variables: [
        Variable<String>(now.toIso8601String()),
        Variable<String>(now.toIso8601String()),
        Variable<String>(legacy.id),
      ],
      updates: {_db.categories},
    );
  }

  static Category _fromRow(CategoryRow row) => Category(
    id: row.id,
    name: row.name,
    colorHex: row.colorHex,
    sortOrder: row.sortOrder,
    isFocus: row.isFocus,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static CategoriesCompanion _toCompanion(Category c) =>
      CategoriesCompanion.insert(
        id: c.id,
        name: c.name,
        colorHex: c.colorHex,
        sortOrder: Value(c.sortOrder),
        isFocus: Value(c.isFocus),
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        deletedAt: Value(c.deletedAt),
        syncStatus: const Value(1),
        revision: const Value(1),
      );

  static CategoryRow _toRow(
    Category c, {
    int syncStatus = 0,
    int revision = 1,
  }) => CategoryRow(
    id: c.id,
    name: c.name,
    colorHex: c.colorHex,
    sortOrder: c.sortOrder,
    isFocus: c.isFocus,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
    deletedAt: c.deletedAt,
    syncStatus: syncStatus,
    revision: revision,
  );
}
