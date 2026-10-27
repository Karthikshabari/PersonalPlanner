import '../../../core/models/experiment.dart';
import '../../../core/search/page_search.dart';
import 'experiment_dashboard.dart';

/// Which experiments a page-search query matches, and how many fall in each
/// segment, so the segment labels can show counts while searching.
class ExperimentSearchMatches {
  const ExperimentSearchMatches(
    this.ids, {
    required this.running,
    required this.kept,
    required this.concluded,
  });

  final Set<String> ids;
  final int running;
  final int kept;
  final int concluded;

  /// "No matches here, 1 in Kept" for an empty segment called [here], naming
  /// the other segments that have matches; null when none has.
  String? noMatchesHere(String here) {
    final elsewhere = [
      for (final (name, count) in [
        ('Running', running),
        (keptName, kept),
        ('Concluded', concluded),
      ])
        if (name != here && count > 0) '$count in $name',
    ];
    return elsewhere.isEmpty
        ? null
        : 'No matches here, ${elsewhere.join(' and ')}';
  }
}

/// The experiments of [dashboard] whose name or description contains
/// [needle] (see [pageSearchHit]). The conclusion note is not searched.
///
/// Null for an empty [needle], so a caller keeps its normal path. [running]
/// and [concluded] count by status, the test the card uses to choose its rows,
/// and [kept] counts the Kept rows by experiment id.
ExperimentSearchMatches? matchExperiments(
  ExperimentDashboard dashboard,
  String needle,
) {
  if (needle.isEmpty) return null;
  final ids = <String>{};
  var running = 0;
  var concluded = 0;
  for (final view in dashboard.views) {
    final experiment = view.experiment;
    if (!pageSearchHit(experiment.tagName, needle) &&
        !pageSearchHit(experiment.purpose, needle)) {
      continue;
    }
    ids.add(experiment.id);
    if (experiment.status == ExperimentStatus.running) {
      running++;
    } else if (experiment.status == ExperimentStatus.concluded) {
      concluded++;
    }
  }
  return ExperimentSearchMatches(
    ids,
    running: running,
    kept: dashboard.kept.views
        .where((v) => ids.contains(v.experimentId))
        .length,
    concluded: concluded,
  );
}
