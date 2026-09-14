import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../categories/data/category_repository.dart';
import '../domain/search_result.dart';

class SearchRepository {
  final AppDatabase _db;

  SearchRepository(this._db);

  /// Converts user text into quoted FTS5 terms. Operators, quotes and
  /// punctuation are treated as literal separators, so malformed input can
  /// never become an FTS expression or SQL fragment.
  static String? normalizeQuery(String input) {
    final tokens = input
        .replaceAll(RegExp(r'[\u0000-\u001F]'), ' ')
        .split(RegExp(r'\s+'))
        .expand(
          (token) => token
              .replaceAll(RegExp(r'''["*^():{}\[\]\\]'''), ' ')
              .split(RegExp(r'\s+')),
        )
        .where((token) => token.trim().isNotEmpty)
        .map((token) => '"${token.replaceAll('"', '""')}"')
        .join(' AND ');
    return tokens.isEmpty ? null : tokens;
  }

  Future<List<SearchResult>> search(String input) async {
    final ftsQuery = normalizeQuery(input);
    if (ftsQuery == null) return const <SearchResult>[];

    final rows = await _db.taskDao.searchTasks(ftsQuery);
    final categories = await CategoryRepository(_db).getAllCategories();
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    return rows
        .map((row) {
          final category = row.categoryId == null
              ? null
              : categoryById[row.categoryId];
          return SearchResult(
            id: row.id,
            title: row.isInbox ? _inboxPreview(row.description) : row.title,
            isInbox: row.isInbox,
            startTime: row.startTime,
            status: TaskStatus.fromDb(row.status),
            categoryId: row.categoryId,
            categoryColorHex: category?.colorHex,
            relevance: row.relevance,
          );
        })
        .toList(growable: false);
  }

  static String _inboxPreview(String? description) {
    final firstLine = (description ?? '')
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    return firstLine.isEmpty ? 'Inbox capture' : firstLine;
  }
}
