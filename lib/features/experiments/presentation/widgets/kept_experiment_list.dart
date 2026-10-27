import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/kept_copy.dart';
import '../../providers/experiment_providers.dart';
import 'experiment_ui.dart';
import 'kept_experiment_row.dart';

/// A kept experiment that was just retired, shown as a one-line message with
/// Undo until its row reappears.
typedef KeptRetiredEntry = ({
  String experimentId,
  String name,
  bool noteSaved,
  String keptSince,
  int revision,
});

/// The Kept segment: one row per kept experiment, most recently kept first.
/// Without [matchIds] it takes no arguments, so a rebuild of the card skips
/// it; it rebuilds only when [keptSegmentProvider] changes.
class KeptExperimentList extends ConsumerStatefulWidget {
  const KeptExperimentList({super.key, this.matchIds, this.noMatchesMessage});

  /// While a page search is active: only these experiments show.
  final Set<String>? matchIds;

  /// The empty line of a search with no match in Kept, when other segments
  /// have some.
  final String? noMatchesMessage;

  @override
  ConsumerState<KeptExperimentList> createState() => _KeptExperimentListState();
}

class _KeptExperimentListState extends ConsumerState<KeptExperimentList> {
  /// Local UI state, not saved: retired lines live while Kept stays shown.
  final Map<String, KeptRetiredEntry> _retired = {};
  final Set<String> _undoing = {};

  Future<void> _undo(KeptRetiredEntry entry) async {
    if (!_undoing.add(entry.experimentId)) return;
    try {
      await ref
          .read(experimentRepositoryProvider)
          .undoRetireExperiment(
            entry.experimentId,
            expectedRevision: entry.revision,
          );
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'That change was not saved. Try again.');
      }
    } finally {
      _undoing.remove(entry.experimentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    final matchIds = widget.matchIds;
    final all = ref.watch(keptSegmentProvider).views;
    final views = matchIds == null
        ? all
        : [
            for (final v in all)
              if (matchIds.contains(v.experimentId)) v,
          ];
    final shownIds = {for (final v in views) v.experimentId};
    final items = <({String keptSince, String name, String id, Widget child})>[
      for (final v in views)
        (
          keptSince: v.keptSince,
          name: v.name,
          id: v.experimentId,
          child: KeptExperimentRow(
            key: ValueKey('kept-row-${v.experimentId}'),
            view: v,
            onRetired: (entry) {
              if (!mounted) return;
              setState(() => _retired[entry.experimentId] = entry);
            },
          ),
        ),
      for (final e in _retired.values)
        if (!shownIds.contains(e.experimentId) &&
            (matchIds == null || matchIds.contains(e.experimentId)))
          (
            keptSince: e.keptSince,
            name: e.name,
            id: e.experimentId,
            child: _KeptRetiredLine(
              key: ValueKey('kept-retired-${e.experimentId}'),
              entry: e,
              onUndo: () => _undo(e),
            ),
          ),
    ]..sort(_compare);
    if (items.isEmpty) {
      if (matchIds != null) {
        final message = widget.noMatchesMessage;
        return message == null
            ? const PageSearchNoMatches(key: ValueKey('kept-search-empty'))
            : PageSearchNoMatches(
                key: const ValueKey('kept-search-empty'),
                message: message,
              );
      }
      return Text(
        keptEmptyText(),
        key: const ValueKey('kept-empty'),
        style: styles.body.copyWith(color: styles.muted),
      );
    }
    return Column(
      key: const ValueKey('kept-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          items[i].child,
        ],
      ],
    );
  }
}

/// Most recently kept first, then name (case-insensitive), then id.
int _compare(
  ({String keptSince, String name, String id, Widget child}) a,
  ({String keptSince, String name, String id, Widget child}) b,
) {
  final bySince = b.keptSince.compareTo(a.keptSince);
  if (bySince != 0) return bySince;
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.id.compareTo(b.id);
}

class _KeptRetiredLine extends StatelessWidget {
  const _KeptRetiredLine({
    super.key,
    required this.entry,
    required this.onUndo,
  });

  final KeptRetiredEntry entry;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final styles = ExperimentStyles.of(context);
    return KeptCard(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          Text(
            keptRetiredLine(entry.name, noteSaved: entry.noteSaved),
            style: styles.note,
          ),
          ExperimentTextLink(
            key: ValueKey('kept-undo-${entry.experimentId}'),
            label: keptUndo,
            color: styles.accentText,
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}
