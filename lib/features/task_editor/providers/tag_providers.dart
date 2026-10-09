import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/tag_dao.dart';
import '../../../core/providers/database_provider.dart';
import '../data/tag_repository.dart';

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
});

/// The active tags the editor offers, sorted by name ignoring case, each with
/// a flag telling whether an experiment uses it. Alive only while the editor
/// listens.
final tagOptionsProvider = StreamProvider.autoDispose<List<TagOptionRow>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).tagDao.watchTagOptions().map((rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return sorted;
  });
});
