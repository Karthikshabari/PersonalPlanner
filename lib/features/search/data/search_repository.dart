import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
import '../../../core/search/page_search.dart';
import '../../categories/data/category_repository.dart';
import '../domain/search_result.dart';

class SearchRepository {
  final AppDatabase _db;

  SearchRepository(this._db);

  /// Converts user text into quoted FTS5 terms; the last term is a prefix match. Operators, quotes and
  /// punctuation are treated as literal separators, so malformed input can
  /// never become an FTS expression or SQL fragment.
  static String? normalizeQuery(String input) {
    final words = input
        .replaceAll(RegExp(r'[\u0000-\u001F]'), ' ')
        .split(RegExp(r'\s+'))
        .expand(
          (token) => token
              .replaceAll(RegExp(r'''["*^():{}\[\]\\]'''), ' ')
              .split(RegExp(r'\s+')),
        )
        .where((token) => token.trim().isNotEmpty)
        .map((token) => '"${token.replaceAll('"', '""')}"')
        .toList();
    if (words.isEmpty) return null;
    // Type-ahead: the last word matches as a prefix, earlier words whole.
    words[words.length - 1] = '${words.last}*';
    return words.join(' AND ');
  }

  Future<List<SearchResult>> search(String input) async {
    final ftsQuery = normalizeQuery(input);
    if (ftsQuery == null) return const <SearchResult>[];

    final rows = await _db.taskDao.searchTasks(
      ftsQuery,
      limit: searchResultCap,
    );
    final categories = await CategoryRepository(_db).getAllCategories();
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    final terms = [
      for (final word in input.split(RegExp(r'\s+')))
        if (word.isNotEmpty) foldAccents(word),
    ];
    return rows
        .map((row) {
          final category = row.categoryId == null
              ? null
              : categoryById[row.categoryId];
          final title = row.isInbox
              ? _inboxPreview(row.description)
              : row.title;
          return SearchResult(
            id: row.id,
            title: title,
            isInbox: row.isInbox,
            startTime: row.startTime,
            status: TaskStatus.fromDb(row.status),
            categoryId: row.categoryId,
            categoryColorHex: category?.colorHex,
            relevance: row.relevance,
            snippet: _snippet(title, row.description, row.notes, terms),
          );
        })
        .toList(growable: false);
  }

  /// The first of [description] and [notes] that holds one of [terms], unless
  /// the [title] already does. [terms] are folded (see [foldAccents]).
  static String? _snippet(
    String title,
    String? description,
    String? notes,
    List<String> terms,
  ) {
    String? firstTerm(String? text) {
      if (text == null) return null;
      final folded = foldAccents(text);
      for (final term in terms) {
        if (folded.contains(term)) return term;
      }
      return null;
    }

    if (firstTerm(title) != null) return null;
    for (final text in [description, notes]) {
      final term = firstTerm(text);
      if (term != null) return pageSearchSnippet(text!, term);
    }
    return null;
  }

  static String _inboxPreview(String? description) {
    final firstLine = (description ?? '')
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    return firstLine.isEmpty ? 'Inbox capture' : firstLine;
  }
}
