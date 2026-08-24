import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/category.dart';
import '../../../core/providers/database_provider.dart';

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAllCategories();
});
