import '../../../core/database/daos/tag_dao.dart';
import '../../task_editor/data/tag_repository.dart';

/// The exact error texts of the start form (section 2.5).
const experimentEndBeforeStartMessage =
    'The end date must be on or after the start date.';
const experimentTargetsMessage = 'Targets must be numbers, 0 or more.';

String experimentTagInUseMessage(String tagName) =>
    'An experiment already uses the tag "$tagName". Pick a different name.';

/// Whole number from 0 to 9999 typed as digits only (ED27); null otherwise.
int? parseExperimentTarget(String text) {
  final trimmed = text.trim();
  if (!RegExp(r'^\d{1,4}$').hasMatch(trimmed)) return null;
  return int.parse(trimmed);
}

/// What the form says about the values typed so far.
class ExperimentFormValidation {
  const ExperimentFormValidation({
    required this.nameError,
    required this.endDateError,
    required this.targetsError,
    required this.infoMessage,
    required this.matchedTag,
    required this.showFirstDateButton,
    required this.canSubmit,
  });

  /// "An experiment already uses the tag ..." or null.
  final String? nameError;

  /// "The end date must be on or after the start date." or null.
  final String? endDateError;

  /// "Targets must be numbers, 0 or more." or null.
  final String? targetsError;

  /// The new-tag or existing-tag message, or null while the name is empty,
  /// in use, or the block count is still loading.
  final String? infoMessage;

  /// The existing tag the typed name resolves to (ED5), or null.
  final TagOptionRow? matchedTag;

  /// The "Use the first tagged block date" button is shown (ED26).
  final bool showFirstDateButton;

  /// "Start experiment" is enabled: a name, and no error showing.
  final bool canSubmit;
}

/// The values typed into the start form so far.
class ExperimentFormState {
  const ExperimentFormState({
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.weekdayTargetText,
    required this.weekendTargetText,
  });

  final String name;

  /// `yyyy-MM-dd`.
  final String startDate;
  final String endDate;
  final String weekdayTargetText;
  final String weekendTargetText;

  /// Validates the form. [tags] are the active tags; [blockCount] and
  /// [firstBlockDate] describe the matched tag's blocks once they are loaded.
  ExperimentFormValidation validate({
    required List<TagOptionRow> tags,
    int? blockCount,
    String? firstBlockDate,
  }) {
    final trimmed = name.trim();
    final matched = _matchTag(trimmed, tags);

    final nameError = matched != null && matched.hasExperiment
        ? experimentTagInUseMessage(matched.name)
        : null;
    final endDateError = endDate.compareTo(startDate) < 0
        ? experimentEndBeforeStartMessage
        : null;
    final targetsError =
        parseExperimentTarget(weekdayTargetText) == null ||
            parseExperimentTarget(weekendTargetText) == null
        ? experimentTargetsMessage
        : null;

    String? info;
    if (trimmed.isNotEmpty && nameError == null) {
      if (matched == null) {
        info = 'A new tag called "$trimmed" will be created.';
      } else if (blockCount != null) {
        info =
            'The tag "${matched.name}" already exists with '
            '${blockCount == 1 ? '1 block' : '$blockCount blocks'}. '
            'Blocks inside your dates count straight away.';
      }
    }

    return ExperimentFormValidation(
      nameError: nameError,
      endDateError: endDateError,
      targetsError: targetsError,
      infoMessage: info,
      matchedTag: matched,
      showFirstDateButton:
          matched != null &&
          nameError == null &&
          (blockCount ?? 0) > 0 &&
          firstBlockDate != null,
      canSubmit:
          trimmed.isNotEmpty &&
          nameError == null &&
          endDateError == null &&
          targetsError == null,
    );
  }
}

/// The tag [trimmedName] refers to by [TagRepository.normalizeTagKey]; when
/// several share the key, the one created first, then the smallest id (ED4).
TagOptionRow? _matchTag(String trimmedName, List<TagOptionRow> tags) {
  final key = TagRepository.normalizeTagKey(trimmedName);
  if (key.isEmpty) return null;
  TagOptionRow? best;
  for (final tag in tags) {
    if (TagRepository.normalizeTagKey(tag.name) != key) continue;
    if (best == null) {
      best = tag;
      continue;
    }
    final byCreated = tag.createdAt.compareTo(best.createdAt);
    if (byCreated < 0 || (byCreated == 0 && tag.id.compareTo(best.id) < 0)) {
      best = tag;
    }
  }
  return best;
}
