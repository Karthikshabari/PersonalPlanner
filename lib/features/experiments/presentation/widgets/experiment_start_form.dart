import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/experiment.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../task_editor/data/tag_repository.dart';
import '../../../task_editor/presentation/widgets/tag_field.dart'
    show Utf16LengthLimitingTextInputFormatter, maxTagNameUnits;
import '../../data/experiment_repository.dart';
import '../../domain/experiment_form.dart';
import '../../domain/experiment_progress.dart';
import '../../providers/experiment_providers.dart';

/// The purpose is limited to 1000 characters. The limit is counted in UTF-16
/// code units with the tag field's formatter, which is never looser than the
/// code-point rule of ED9 and never splits an emoji.
const _maxPurposeUnits = 1000;

const _purposeLabel =
    'What are you trying out, and what do you want to find out? (optional)';

/// Presents the start form like the app's other create form (ED26): a dialog
/// at least [AppConstants.desktopBreakpoint] wide, else a scroll-controlled
/// bottom sheet that keeps clear of the keyboard. [initialName] pre-fills the
/// name (the planned "Start as an experiment" from Inbox uses it).
Future<void> showExperimentStartForm(
  BuildContext context, {
  String initialName = '',
}) {
  final desktop =
      MediaQuery.sizeOf(context).width >= AppConstants.desktopBreakpoint;
  if (desktop) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ExperimentStartForm(initialName: initialName),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: ExperimentStartForm(initialName: initialName),
    ),
  );
}

/// The "New experiment" form. It closes itself (pops its route) after the
/// experiment is created or when cancelled.
class ExperimentStartForm extends ConsumerStatefulWidget {
  const ExperimentStartForm({super.key, this.initialName = ''});

  final String initialName;

  @override
  ConsumerState<ExperimentStartForm> createState() =>
      _ExperimentStartFormState();
}

class _ExperimentStartFormState extends ConsumerState<ExperimentStartForm> {
  late final TextEditingController _name;
  late final TextEditingController _purpose;
  late final TextEditingController _weekday;
  late final TextEditingController _weekend;
  late String _startDate;
  late String _endDate;
  int _every = 1;
  bool _saving = false;

  /// Set when the repository refused the name because an experiment already
  /// uses the tag; stays until the name changes.
  String? _refusedKey;
  String? _refusedTagName;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _purpose = TextEditingController();
    _weekday = TextEditingController(text: '60');
    _weekend = TextEditingController(text: '90');
    final today = isoDateString(ref.read(insightsNowFactoryProvider)());
    _startDate = today;
    _endDate = isoDateString(addDays(parseIsoDate(today), 29));
  }

  @override
  void dispose() {
    _name.dispose();
    _purpose.dispose();
    _weekday.dispose();
    _weekend.dispose();
    super.dispose();
  }

  ExperimentFormState get _state => ExperimentFormState(
    name: _name.text,
    startDate: _startDate,
    endDate: _endDate,
    weekdayTargetText: _weekday.text,
    weekendTargetText: _weekend.text,
  );

  Future<void> _pickDate({required bool start}) async {
    final today = isoDateString(ref.read(insightsNowFactoryProvider)());
    final todayParts = _parts(today);
    final first = DateTime(todayParts.$1 - 5, todayParts.$2, todayParts.$3);
    final last = DateTime(todayParts.$1 + 5, todayParts.$2, todayParts.$3);
    final currentParts = _parts(start ? _startDate : _endDate);
    var initial = DateTime(currentParts.$1, currentParts.$2, currentParts.$3);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    // The picker returns a plain calendar date; read its parts directly.
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _startDate = iso;
      } else {
        _endDate = iso;
      }
    });
  }

  static (int, int, int) _parts(String iso) {
    final p = iso.split('-');
    return (int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String _longDate(String iso) {
    final p = _parts(iso);
    return DateFormat('EEE, MMM d, yyyy').format(DateTime(p.$1, p.$2, p.$3));
  }

  Future<void> _submit(ExperimentFormValidation validation) async {
    if (_saving || !validation.canSubmit) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(experimentRepositoryProvider)
          .createExperiment(
            name: _name.text,
            purpose: _purpose.text,
            startDate: _startDate,
            endDate: _endDate,
            weekdayTargetMin: parseExperimentTarget(_weekday.text)!,
            weekendTargetMin: parseExperimentTarget(_weekend.text)!,
            checkInEveryDays: _every,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ExperimentTagInUseException catch (error) {
      if (!mounted) return;
      setState(() {
        _refusedKey = TagRepository.normalizeTagKey(_name.text);
        _refusedTagName = error.tagName;
      });
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'The experiment was not started. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.textSecondary,
    );

    final tags = ref.watch(experimentFormTagsProvider).value ?? const [];
    var validation = _state.validate(tags: tags);
    String? firstBlockDate;
    final matched = validation.matchedTag;
    if (matched != null && !matched.hasExperiment) {
      final usage = ref.watch(tagUsageProvider(matched.id)).value;
      if (usage != null) {
        firstBlockDate = usage.firstBlockDate;
        validation = _state.validate(
          tags: tags,
          blockCount: usage.blockCount,
          firstBlockDate: firstBlockDate,
        );
      }
    }
    final refused =
        _refusedKey != null &&
        _refusedKey == TagRepository.normalizeTagKey(_name.text);
    final nameError =
        validation.nameError ??
        (refused ? experimentTagInUseMessage(_refusedTagName!) : null);
    final canSubmit = validation.canSubmit && !refused && !_saving;

    return PopScope<void>(
      canPop: !_saving,
      child: Material(
        color: tokens.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('New experiment', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const ValueKey('experiment-name'),
                  controller: _name,
                  inputFormatters: const [
                    Utf16LengthLimitingTextInputFormatter(maxTagNameUnits),
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Name (this becomes the tag)',
                    errorText: nameError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (validation.infoMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    validation.infoMessage!,
                    key: const ValueKey('experiment-tag-info'),
                    style: mutedStyle,
                  ),
                ],
                if (validation.showFirstDateButton && firstBlockDate != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('experiment-use-first-date'),
                      onPressed: () =>
                          setState(() => _startDate = firstBlockDate!),
                      child: Text(
                        'Use the first tagged block date '
                        '(${_longDate(firstBlockDate)})',
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                // A long label would be cut to one line inside the field, so
                // it is shown as wrapping text above the field instead; the
                // field carries the same text for screen readers.
                ExcludeSemantics(
                  child: Text(_purposeLabel, style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: _purposeLabel,
                  child: TextField(
                    key: const ValueKey('experiment-purpose'),
                    controller: _purpose,
                    minLines: 2,
                    maxLines: 4,
                    inputFormatters: const [
                      Utf16LengthLimitingTextInputFormatter(_maxPurposeUnits),
                    ],
                    keyboardType: TextInputType.multiline,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    _DateButton(
                      buttonKey: const ValueKey('experiment-start-date'),
                      label: 'Start date',
                      value: _longDate(_startDate),
                      onPressed: () => _pickDate(start: true),
                    ),
                    _DateButton(
                      buttonKey: const ValueKey('experiment-end-date'),
                      label: 'End date',
                      value: _longDate(_endDate),
                      onPressed: () => _pickDate(start: false),
                    ),
                  ],
                ),
                if (validation.endDateError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(validation.endDateError!, style: errorStyle),
                ],
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final weekday = _TargetField(
                      fieldKey: const ValueKey('experiment-weekday-target'),
                      controller: _weekday,
                      label: 'Weekday target (min)',
                      onChanged: () => setState(() {}),
                    );
                    final weekend = _TargetField(
                      fieldKey: const ValueKey('experiment-weekend-target'),
                      controller: _weekend,
                      label: 'Weekend target (min)',
                      onChanged: () => setState(() {}),
                    );
                    if (constraints.maxWidth < 440) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          weekday,
                          const SizedBox(height: AppSpacing.md),
                          weekend,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: weekday),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: weekend),
                      ],
                    );
                  },
                ),
                if (validation.targetsError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(validation.targetsError!, style: errorStyle),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'How often do you want to write a check-in about how it is going?',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final days in experimentCheckInFrequencies)
                      ChoiceChip(
                        key: ValueKey('experiment-frequency-$days'),
                        label: Text(experimentFrequencyLabel(days)),
                        selected: _every == days,
                        onSelected: (_) => setState(() => _every = days),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      key: const ValueKey('experiment-start-cancel'),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const ValueKey('experiment-start-submit'),
                      onPressed: canSubmit ? () => _submit(validation) : null,
                      child: const Text('Start experiment'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.buttonKey,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppThemeTokens.of(context).textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          child: Text(value),
        ),
      ],
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ],
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => onChanged(),
  );
}
