import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/category_dao.dart';
import '../../../core/models/category.dart';
import '../../../core/utils/uuid.dart';

class CategoryRepository {
  static const String _defaultsSeededKey = 'default_categories_seeded';

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
    await _dao.updateCategory(
      _toRow(effective, syncStatus: 1, revision: row.revision + 1),
    );
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
    });
  }

  /// Persists a new sort order for the category list.
  Future<void> reorderCategories(List<String> orderedIds) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.categories)
              ..where((c) => c.id.equals(orderedIds[i])))
            .write(CategoriesCompanion(
              sortOrder: Value(i),
              updatedAt: Value(now),
              syncStatus: const Value(1),
              revision: Value(
                (await _dao.getCategoryById(orderedIds[i]))!.revision + 1,
              ),
            ));
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
      final marker = await (_db.select(_db.appSettings)
            ..where((s) => s.key.equals(_defaultsSeededKey)))
          .getSingleOrNull();
      if (marker != null) return;

      final anyCategory = await (_db.select(_db.categories)..limit(1)).get();
      if (anyCategory.isEmpty) {
        final now = DateTime.now();
        const defaults = [
          ('Work', '#4285F4'),
          ('Personal', '#34A853'),
          ('Health', '#EA4335'),
          ('Learning', '#FBBC04'),
        ];
        for (var i = 0; i < defaults.length; i++) {
          await _dao.insertCategory(CategoriesCompanion.insert(
            id: generateUuidV7(),
            name: defaults[i].$1,
            colorHex: defaults[i].$2,
            sortOrder: Value(i),
            isFocus: const Value(false),
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value(1),
            revision: const Value(1),
          ));
        }
      }
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _defaultsSeededKey,
              value: 'true',
            ),
          );
    });
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

  static CategoryRow _toRow(Category c, {int syncStatus = 0, int revision = 1}) =>
      CategoryRow(
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
