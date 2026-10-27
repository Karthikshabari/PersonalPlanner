import '../../../core/models/enums/task_status.dart';

/// The most results one search returns.
const searchResultCap = 100;

/// Presentation-safe projection of an FTS hit.
class SearchResult {
  final String id;
  final String title;
  final bool isInbox;
  final DateTime? startTime;
  final TaskStatus status;
  final String? categoryId;
  final String? categoryColorHex;
  final double relevance;

  /// One line of the description or notes around the first matching word, when
  /// the title does not already show why the task matched.
  final String? snippet;

  const SearchResult({
    required this.id,
    required this.title,
    required this.isInbox,
    required this.startTime,
    required this.status,
    required this.categoryId,
    required this.categoryColorHex,
    required this.relevance,
    this.snippet,
  });

  DateTime? get date => startTime;
}
