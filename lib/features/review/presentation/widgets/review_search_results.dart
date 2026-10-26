import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../domain/review_search.dart';
import '../../providers/review_search_providers.dart';

/// Days per page of results; "Show 50 more" adds the same again.
const _pageSize = 50;

/// What a Review page search found: one card per day (Daily) or week (Weekly),
/// newest first. Tapping a card calls [onOpen] with that day or week start.
///
/// Built only while the page shows results, so the index is loaded only then.
class ReviewSearchResults extends ConsumerStatefulWidget {
  const ReviewSearchResults({
    super.key,
    required this.needle,
    required this.weekly,
    required this.onOpen,
  });

  /// Already trimmed and lower-cased (`pageSearchNeedle`).
  final String needle;
  final bool weekly;
  final ValueChanged<DateTime> onOpen;

  @override
  ConsumerState<ReviewSearchResults> createState() =>
      _ReviewSearchResultsState();
}

class _ReviewSearchResultsState extends ConsumerState<ReviewSearchResults> {
  int _shown = _pageSize;

  // Hits are worked out once per (index, needle, mode), not on every rebuild.
  ReviewSearchIndex? _hitsIndex;
  String? _hitsNeedle;
  bool? _hitsWeekly;
  List<ReviewSearchHit> _hits = const [];

  List<ReviewSearchHit> _hitsFor(ReviewSearchIndex index) {
    if (!identical(index, _hitsIndex) ||
        widget.needle != _hitsNeedle ||
        widget.weekly != _hitsWeekly) {
      if (widget.needle != _hitsNeedle || widget.weekly != _hitsWeekly) {
        _shown = _pageSize;
      }
      _hitsIndex = index;
      _hitsNeedle = widget.needle;
      _hitsWeekly = widget.weekly;
      _hits = widget.weekly
          ? searchReviewWeeks(index, widget.needle)
          : searchReviewDays(index, widget.needle);
    }
    return _hits;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewSearchIndexProvider);
    final index = async.value;
    if (index == null) {
      if (async.hasError) {
        return ErrorPanel(
          compact: true,
          message: friendlyErrorMessage(async.error!),
        );
      }
      return const AppSurface(child: LinearProgressIndicator());
    }
    final hits = _hitsFor(index);
    if (hits.isEmpty) {
      return const PageSearchNoMatches(key: ValueKey('review-search-empty'));
    }
    final shown = hits.length < _shown ? hits.length : _shown;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final hit in hits.take(shown))
            _ResultCard(
              hit: hit,
              weekly: widget.weekly,
              onTap: () => widget.onOpen(hit.date),
            ),
          if (shown < hits.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('review-search-more'),
                onPressed: () => setState(() => _shown += _pageSize),
                child: Text('Show $_pageSize more'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.hit,
    required this.weekly,
    required this.onTap,
  });

  final ReviewSearchHit hit;
  final bool weekly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = weekly
        ? '${DateFormat('MMM d').format(hit.date)} – '
              '${DateFormat('MMM d, yyyy').format(addDays(hit.date, 6))}'
        : DateFormat('EEE, MMM d, yyyy').format(hit.date);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        key: ValueKey('review-search-hit-${isoDateString(hit.date)}'),
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          title: Text(title),
          subtitle: Text(
            '${hit.source.label}: ${hit.snippet}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
