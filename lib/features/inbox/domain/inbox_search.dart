import 'package:flutter/foundation.dart';

import '../../../core/search/page_search.dart';
import 'inbox_board.dart';

/// Which Inbox ideas a page-search query matches, and how many fall in each
/// segment, so the segment labels can show counts while searching.
@immutable
class InboxSearchMatches {
  const InboxSearchMatches(
    this.ids, {
    required this.open,
    required this.done,
    required this.dropped,
  });

  final Set<String> ids;

  /// Matches among Left over, Ideas and Coming up.
  final int open;
  final int done;
  final int dropped;

  @override
  bool operator ==(Object other) =>
      other is InboxSearchMatches &&
      other.open == open &&
      other.done == done &&
      other.dropped == dropped &&
      setEquals(other.ids, ids);

  @override
  int get hashCode =>
      Object.hash(open, done, dropped, Object.hashAllUnordered(ids));
}

/// The ideas of [board] that contain [needle] (see [pageSearchHit]) in their
/// text, their closing reason, any reason in their history, or any session's
/// saved Review reason.
///
/// Null while the board has not loaded or the [needle] is empty, so a caller
/// keeps its normal path.
InboxSearchMatches? matchInbox(InboxBoard? board, String needle) {
  if (board == null || needle.isEmpty) return null;
  final ids = <String>{};
  for (final entry in board.byId.entries) {
    final view = entry.value;
    if (pageSearchHit(view.item.text, needle) ||
        pageSearchHit(view.closure?.reason, needle) ||
        view.item.history.any((event) => pageSearchHit(event.reason, needle)) ||
        view.sessions.any((session) => pageSearchHit(session.reason, needle))) {
      ids.add(entry.key);
    }
  }
  int count(List<String> section) => section.where(ids.contains).length;
  return InboxSearchMatches(
    ids,
    open: count(board.leftOver) + count(board.ideas) + count(board.comingUp),
    done: count(board.done),
    dropped: count(board.dropped),
  );
}
