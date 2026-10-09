import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../data/experiment_repository.dart';

final experimentRepositoryProvider = Provider<ExperimentRepository>((ref) {
  return ExperimentRepository(ref.watch(appDatabaseProvider));
});
