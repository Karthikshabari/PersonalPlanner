import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/category_dao.dart';
import '../../../core/models/category.dart';
import '../../../core/utils/uuid.dart';

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

  CategoryRepository(this._db);

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

  Future<void> deleteCategory(String categoryId) async {
    // Per planner.md Chunk 3 #6: deleting a category sets tasks in it to
    // category = null instead of deleting them.
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction(() async {
      await _db.customUpdate(
        'UPDATE tasks SET category_id = NULL, updated_at = ?, '
        'sync_status = 1, revision = revision + 1 '
        'WHERE category_id = ? AND deleted_at IS NULL',
        variables: [Variable<String>(now), Variable<String>(categoryId)],
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
    });
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
