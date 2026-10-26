import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/category.dart';
import '../../../core/providers/database_provider.dart';

final categoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAllCategories();
});

/// Active tasks per category id, from one grouped query. A category without
/// tasks has no entry.
final categoryTaskCountsProvider = StreamProvider.autoDispose<Map<String, int>>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return db
        .customSelect(
          'SELECT category_id, COUNT(*) AS n FROM tasks '
          'WHERE category_id IS NOT NULL AND deleted_at IS NULL '
          'GROUP BY category_id',
          readsFrom: {db.tasks},
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<String>('category_id'): row.read<int>('n'),
          },
        );
  },
);
