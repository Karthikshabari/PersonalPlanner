import '../../../core/models/enums/task_status.dart';

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

  const SearchResult({
    required this.id,
    required this.title,
    required this.isInbox,
    required this.startTime,
    required this.status,
    required this.categoryId,
    required this.categoryColorHex,
    required this.relevance,
  });

  DateTime? get date => startTime;
}
