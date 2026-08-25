import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories_table.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<CategoryRow>> watchActiveCategories() {
    return (select(categories)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  Future<CategoryRow?> getCategoryById(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<CategoryRow>> getActiveCategories() =>
      (select(categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .get();

  Future<void> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  Future<bool> updateCategory(CategoryRow row) =>
      update(categories).replace(row);

  Future<int> softDeleteCategory(String id, DateTime deletedAt) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );
}
