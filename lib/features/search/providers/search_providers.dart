import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../data/search_repository.dart';
import '../domain/search_result.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(appDatabaseProvider));
});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResult>, String>((ref, query) {
      return ref.watch(searchRepositoryProvider).search(query);
    });
