import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/category_dao.dart';
import '../../../core/models/category.dart';
import '../../../core/utils/uuid.dart';

class CategoryRepository {
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
    await _dao.updateCategory(_toRow(effective, syncStatus: row.syncStatus, revision: row.revision));
    return effective;
  }

  Future<void> deleteCategory(String categoryId) async {
    await _dao.softDeleteCategory(categoryId, DateTime.now());
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
    final existing = await _dao.getActiveCategories();
    if (existing.isNotEmpty) return;
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
      ));
    }
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
