import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';

/// Full calendar/date-time controls shared by scheduled creation and the
/// editor. Date-only controls operate on planner-local components; they never
/// pass a host-local midnight through a UTC converter.
class ScheduleFields extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime?> onStartChanged;
  final ValueChanged<DateTime?> onEndChanged;
  final bool enabled;
  final String? errorText;

  const ScheduleFields({
    super.key,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
    this.enabled = true,
    this.errorText,
  });

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Date';
    final local = PlannerTimeZone.toPlannerLocal(value);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return 'Time';
    final local = PlannerTimeZone.toPlannerLocal(value);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final initial = value == null
        ? PlannerTimeZone.toPlannerLocal(DateTime.now())
        : PlannerTimeZone.toPlannerLocal(value);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final old = value == null ? null : PlannerTimeZone.toPlannerLocal(value);
    onChanged(
      PlannerTimeZone.calendarDate(
        picked.year,
        picked.month,
        picked.day,
        hour: old?.hour ?? 9,
        minute: old?.minute ?? 0,
        second: old?.second ?? 0,
        millisecond: old?.millisecond ?? 0,
        microsecond: old?.microsecond ?? 0,
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context, {
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final local = value == null ? null : PlannerTimeZone.toPlannerLocal(value);
    final picked = await showTimePicker(
      context: context,
      initialTime: local == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: local.hour, minute: local.minute),
    );
    if (picked == null) return;
    final date = local ?? PlannerTimeZone.toPlannerLocal(DateTime.now());
    onChanged(
      PlannerTimeZone.calendarDate(
        date.year,
        date.month,
        date.day,
        hour: picked.hour,
        minute: picked.minute,
      ),
    );
  }

  Widget _endpoint(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    required String dateKey,
    required String timeKey,
  }) {
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey(dateKey),
                  onPressed: enabled
                      ? () => _pickDate(
                          context,
                          value: value,
                          onChanged: onChanged,
                        )
                      : null,
                  child: Text(_dateLabel(value)),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey(timeKey),
                  onPressed: enabled
                      ? () => _pickTime(
                          context,
                          value: value,
                          onChanged: onChanged,
                        )
                      : null,
                  child: Text(_timeLabel(value)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error =
        errorText ??
        ((start != null && end != null && !end!.isAfter(start!))
            ? 'End must be later than start'
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _endpoint(
          context,
          label: 'Start',
          value: start,
          onChanged: onStartChanged,
          dateKey: 'schedule-start-date',
          timeKey: 'schedule-start-time',
        ),
        const SizedBox(height: AppSpacing.sm),
        _endpoint(
          context,
          label: 'End',
          value: end,
          onChanged: onEndChanged,
          dateKey: 'schedule-end-date',
          timeKey: 'schedule-end-time',
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error,
            key: const ValueKey('schedule-fields-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  /// Combines a planner-local calendar date with a picked time.
  static DateTime combine(DateTime date, TimeOfDay time) {
    final local = PlannerTimeZone.toPlannerLocal(date);
    return PlannerTimeZone.calendarDate(
      local.year,
      local.month,
      local.day,
      hour: time.hour,
      minute: time.minute,
    );
  }

  /// Returns the planner-local date label used by timeline defaults.
  static String dateOf(DateTime value) => isoDateString(value);
}
