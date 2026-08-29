import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rrule/rrule.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../recurring/domain/rrule_utils.dart';

/// Dialog for building a custom RRULE: frequency, interval, weekday
/// selection (weekly) and optional end date, with a live human-readable
/// preview (planner.md Chunk 4 #6). Returns the config on "Done".
Future<CustomRecurrenceConfig?> showCustomRecurrenceDialog(
  BuildContext context, {
  required DateTime anchorDate,
  CustomRecurrenceConfig? initial,
}) {
  return showDialog<CustomRecurrenceConfig>(
    context: context,
    builder: (_) => _CustomRecurrenceDialog(
      anchorDate: anchorDate,
      initial:
          initial ?? const CustomRecurrenceConfig(frequency: Frequency.weekly),
    ),
  );
}

class _CustomRecurrenceDialog extends ConsumerStatefulWidget {
  final DateTime anchorDate;
  final CustomRecurrenceConfig initial;

  const _CustomRecurrenceDialog({
    required this.anchorDate,
    required this.initial,
  });

  @override
  ConsumerState<_CustomRecurrenceDialog> createState() =>
      _CustomRecurrenceDialogState();
}

class _CustomRecurrenceDialogState
    extends ConsumerState<_CustomRecurrenceDialog> {
  late Frequency _frequency;
  late int _interval;
  late Set<int> _weekDays;
  DateTime? _endDate;
  final _intervalController = TextEditingController();
  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _weekdayValues = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  @override
  void initState() {
    super.initState();
    _frequency = widget.initial.frequency;
    _interval = widget.initial.interval;
    _weekDays = {...widget.initial.byWeekDays};
    _endDate = widget.initial.endDate;
    _intervalController.text = '$_interval';
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  CustomRecurrenceConfig get _config => CustomRecurrenceConfig(
    frequency: _frequency,
    interval: _interval.clamp(1, 365),
    byWeekDays: _frequency == Frequency.weekly ? _weekDays : {},
    endDate: _endDate,
  );

  @override
  Widget build(BuildContext context) {
    final rruleString = RruleUtils.configToRrule(_config, widget.anchorDate);
    return AlertDialog(
      title: const Text('Custom recurrence'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<Frequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: const [
                  DropdownMenuItem(
                    value: Frequency.daily,
                    child: Text('Daily'),
                  ),
                  DropdownMenuItem(
                    value: Frequency.weekly,
                    child: Text('Weekly'),
                  ),
                  DropdownMenuItem(
                    value: Frequency.monthly,
                    child: Text('Monthly'),
                  ),
                ],
                onChanged: (f) =>
                    setState(() => _frequency = f ?? Frequency.daily),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Text('Every'),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      key: const ValueKey('recurrence-interval'),
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (v) =>
                          setState(() => _interval = int.tryParse(v) ?? 1),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(switch (_frequency) {
                    Frequency.daily => 'days',
                    Frequency.weekly => 'weeks',
                    _ => 'months',
                  }),
                ],
              ),
              if (_frequency == Frequency.weekly) ...[
                const SizedBox(height: AppSpacing.md),
                const Text('Repeat on'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (var i = 0; i < _weekdayLabels.length; i++)
                      FilterChip(
                        label: Text(_weekdayLabels[i]),
                        selected: _weekDays.contains(_weekdayValues[i]),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _weekDays.add(_weekdayValues[i])
                              : _weekDays.remove(_weekdayValues[i]);
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('recurrence-end-date'),
                      icon: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _endDate == null
                            ? 'No end date'
                            : 'Until ${_endDate!.month}/${_endDate!.day}/${_endDate!.year}',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _endDate ?? addDays(widget.anchorDate, 30),
                          firstDate: widget.anchorDate,
                          lastDate: addDays(widget.anchorDate, 3650),
                        );
                        if (picked != null) setState(() => _endDate = picked);
                      },
                    ),
                  ),
                  if (_endDate != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: 'Clear end date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _endDate = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<String>(
                future: RruleUtils.describe(rruleString),
                builder: (context, snapshot) {
                  final text = snapshot.data ?? rruleString;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.preview_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(text)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_config),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
