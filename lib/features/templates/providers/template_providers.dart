import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/task_template.dart';
import '../../../core/providers/database_provider.dart';
import '../data/template_repository.dart';

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(appDatabaseProvider));
});

/// Stream of all saved task templates.
final templatesProvider = StreamProvider.autoDispose<List<TaskTemplate>>((ref) {
  return ref.watch(templateRepositoryProvider).watchAllTemplates();
});
