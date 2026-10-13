import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/task.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/clock_format.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/time_picker_24h.dart';
import '../../domain/inbox_board.dart';
import '../../domain/inbox_dates.dart';
import '../../domain/inbox_status.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_close_panel.dart' show inboxErrorText;

const _lengthLabels = <int, String>{30: '30m', 60: '60m', 90: '90m', 120: '2h'};

String _hhmm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _lengthWords(int minutes) => switch (minutes) {
  60 => '1 hour',
  120 => '2 hours',
  _ => '$minutes minutes',
};

/// The inline panel behind Set dates, Add days and Edit dates: pick up to 14
/// planner days, one time and length, and Save. Save replaces the idea's
/// upcoming sessions, carries its missed ones and never touches the rest
/// (repository rules, plan 9.A). Cancel changes nothing.
class InboxDatesPanel extends ConsumerStatefulWidget {
  const InboxDatesPanel({
    super.key,
    required this.view,
    required this.onSaved,
    required this.onCancel,
    required this.onStartExperiment,
  });

  final InboxIdeaView view;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  /// The experiment hint's button; the panel is closed by the caller.
  final VoidCallback onStartExperiment;

  @override
  ConsumerState<InboxDatesPanel> createState() => _InboxDatesPanelState();
}

class _InboxDatesPanelState extends ConsumerState<InboxDatesPanel> {
  /// Picked planner dates (`yyyy-MM-dd`) with their own time of day.
  final _picked = <String, TimeOfDay>{};
  late TimeOfDay _allTime;
  late int _length;

  /// What the idea holds now; Save stays off until the picks differ from it.
  late final String _initialSignature;

  /// Day's blocks in the 14-day window, read once when the panel opens.
  List<Task> _windowTasks = const [];
  bool _busy = false;
  String? _error;
  String? _note;
  final _firstFocus = FocusNode(debugLabel: 'inbox-dates-first');

  DateTime get _now => ref.read(inboxNowFactoryProvider)();

  @override
  void initState() {
    super.initState();
    final now = _now;
    final facts = [for (final s in widget.view.sessions) s.facts];
    final replaceable = replaceableInboxSessions(facts, now);

    var time = const TimeOfDay(hour: inboxDefaultStartHour, minute: 0);
    var length = inboxDefaultLengthMin;
    if (replaceable.isNotEmpty) {
      final first = replaceable.first;
      time = TimeOfDay.fromDateTime(
        PlannerTimeZone.toPlannerLocal(first.start!),
      );
      final minutes = first.end!.difference(first.start!).inMinutes;
      if (inboxSlotLengths.contains(minutes)) length = minutes;
    }
    _allTime = time;
    _length = length;
    for (final session in replaceable) {
      _picked.putIfAbsent(
        isoDateString(session.start!),
        () => TimeOfDay.fromDateTime(
          PlannerTimeZone.toPlannerLocal(session.start!),
        ),
      );
    }
    _initialSignature = _signature();

    // A legacy due date inside the window is offered as a pick.
    final due = widget.view.item.dueDate;
    if (replaceable.isEmpty &&
        due != null &&
        isValidIsoDate(due) &&
        inboxWindowDates(now).contains(due) &&
        _slotErrorFor(due, now) == null) {
      _picked[due] = _allTime;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstFocus.requestFocus();
    });
    _loadWindowTasks(now);
  }

  @override
  void dispose() {
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _loadWindowTasks(DateTime now) async {
    final dates = inboxWindowDates(now);
    final (start, _) = PlannerTimeZone.dayBounds(inboxSlotStart(dates.first));
    final (_, end) = PlannerTimeZone.dayBounds(inboxSlotStart(dates.last));
    try {
      final tasks = await ref
          .read(taskRepositoryProvider)
          .getScheduledTasksBetween(start, end);
      if (mounted) setState(() => _windowTasks = tasks);
    } catch (_) {
      // Overlap warnings are a hint; Save does not depend on them.
    }
  }

  String _signature() {
    final dates = _picked.keys.toList()..sort();
    return [
      for (final date in dates) '$date@${_hhmm(_picked[date]!)}',
      if (_picked.isNotEmpty) 'len$_length',
    ].join('|');
  }

  InboxSlot _slot(String date) {
    final time = _picked[date] ?? _allTime;
    return InboxSlot(
      start: inboxSlotStart(date, hour: time.hour, minute: time.minute),
      lengthMin: _length,
    );
  }

  String? _slotErrorFor(String date, DateTime now) =>
      inboxSlotError(_slot(date), now);

  /// Dates that already hold a done or a started session: shown picked and
  /// locked, never changed.
  Map<String, String> _lockedDates(DateTime now) {
    final locked = <String, String>{};
    for (final session in widget.view.sessions) {
      final start = session.facts.start;
      if (start == null) continue;
      final date = isoDateString(start);
      if (session.status == InboxSessionStatus.done) {
        locked[date] = 'Done';
      } else if (session.status == InboxSessionStatus.upcoming &&
          !start.isAfter(now)) {
        locked.putIfAbsent(date, () => 'Started');
      }
    }
    return locked;
  }

  void _toggle(String date) => setState(() {
    _error = null;
    if (_picked.remove(date) == null) _picked[date] = _allTime;
  });

  void _quickPick(InboxQuickPick pick) => setState(() {
    _error = null;
    final locked = _lockedDates(_now);
    final dates = inboxQuickPickDates(pick, _now);
    _picked.removeWhere((date, _) => !dates.contains(date));
    for (final date in dates) {
      if (!locked.containsKey(date)) _picked.putIfAbsent(date, () => _allTime);
    }
  });

  Future<void> _pickAllTime() async {
    final time = await showTimePicker24h(
      context: context,
      initialTime: _allTime,
    );
    if (time == null || !mounted) return;
    setState(() {
      _allTime = time;
      for (final date in _picked.keys.toList()) {
        _picked[date] = time;
      }
    });
  }

  Future<void> _pickRowTime(String date) async {
    final time = await showTimePicker24h(
      context: context,
      initialTime: _picked[date] ?? _allTime,
    );
    if (time == null || !mounted) return;
    setState(() => _picked[date] = time);
  }

  /// A new day began while the panel was open: drop picks before today.
  void _dropStale(DateTime now) {
    final window = inboxWindowDates(now).toSet();
    final stale = _picked.keys.where((d) => !window.contains(d)).toList();
    if (stale.isEmpty) return;
    setState(() {
      stale.forEach(_picked.remove);
      _note = 'It is a new day. Yesterday was removed from your picks.';
    });
  }

  bool _canSave(DateTime now) {
    if (_busy || _signature() == _initialSignature) return false;
    return _picked.keys.every((date) => _slotErrorFor(date, now) == null);
  }

  Future<void> _save() async {
    // Always re-validated with a fresh clock (midnight, a time that passed).
    final now = _now;
    if (!_canSave(now)) {
      // The build that enabled Save used an older clock; show what is wrong.
      setState(() {});
      return;
    }
    final stale = _picked.keys
        .where((d) => !inboxWindowDates(now).contains(d))
        .toList();
    if (stale.isNotEmpty) {
      _dropStale(now);
      return;
    }
    final dates = _picked.keys.toList()..sort();
    final slots = [for (final date in dates) _slot(date)];
    final repository = ref.read(inboxRepositoryProvider);
    final id = widget.view.item.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.saveDates(id, slots, now);
      if (!mounted) return;
      showAppToast(context, slots.isEmpty ? 'Dates removed' : 'Dates saved');
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = inboxErrorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The clock fires at planner midnight and on resume; it only triggers the
    // rebuild and the check. Validation reads a fresh time.
    ref.listen(inboxScreenClockProvider, (_, _) => _dropStale(_now));
    ref.watch(inboxScreenClockProvider);
    final now = _now;
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: tokens.textMuted);
    final window = inboxWindowDates(now);
    final locked = _lockedDates(now);
    final facts = [for (final s in widget.view.sessions) s.facts];
    final replaceableIds = {
      for (final s in replaceableInboxSessions(facts, now)) s.id,
    };
    final pickedDates = _picked.keys.toList()..sort();
    final overlaps = inboxSlotOverlaps(
      slots: [for (final date in pickedDates) _slot(date)],
      windowTasks: _windowTasks,
      replaceableIds: replaceableIds,
    );
    final afterWindow = inboxAfterWindowSessions(facts, now).length;
    final canSave = _canSave(now);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Column(
        key: const ValueKey('inbox-dates-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ActionChip(
                key: const ValueKey('inbox-quick-tomorrow'),
                focusNode: _firstFocus,
                label: const Text('Tomorrow'),
                onPressed: () => _quickPick(InboxQuickPick.tomorrow),
              ),
              ActionChip(
                key: const ValueKey('inbox-quick-3days'),
                label: const Text('Next 3 days'),
                onPressed: () => _quickPick(InboxQuickPick.nextThreeDays),
              ),
              ActionChip(
                key: const ValueKey('inbox-quick-5weekdays'),
                label: const Text('Next 5 weekdays'),
                onPressed: () => _quickPick(InboxQuickPick.nextFiveWeekdays),
              ),
              ActionChip(
                key: const ValueKey('inbox-quick-clear'),
                label: const Text('Clear'),
                onPressed: () => _quickPick(InboxQuickPick.clear),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs + 2,
            runSpacing: AppSpacing.xs + 2,
            children: [
              for (var i = 0; i < window.length; i++)
                _dateChip(window[i], today: i == 0, now: now, locked: locked),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'You can plan up to 2 weeks ahead. Errands planned further '
                  'out usually get moved before you reach them, and Review '
                  'looks at one week at a time. To repeat something for a '
                  'month, start an experiment in Insights.',
                  key: const ValueKey('inbox-horizon-copy'),
                  style: muted,
                ),
              ),
              TextButton(
                key: const ValueKey('inbox-open-insights'),
                onPressed: () => context.go('/analytics'),
                child: const Text('Open Insights'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('inbox-time-all'),
                onPressed: _busy ? null : _pickAllTime,
                child: Text('Time for all ${_hhmm(_allTime)} ▾'),
              ),
              Text('Length', style: textTheme.bodySmall),
              for (final entry in _lengthLabels.entries)
                ChoiceChip(
                  key: ValueKey('inbox-length-${entry.key}'),
                  label: Text(entry.value),
                  selected: _length == entry.key,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _length = entry.key;
                          _error = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in locked.entries)
            _lockedRow(entry.key, entry.value, muted),
          for (final date in pickedDates)
            if (!locked.containsKey(date))
              _pickedRow(date, now, overlaps[date], muted),
          if (afterWindow > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                afterWindow == 1
                    ? '1 session after the 2-week window stays as planned in Day.'
                    : '$afterWindow sessions after the 2-week window stay as planned in Day.',
                key: const ValueKey('inbox-after-window'),
                style: muted,
              ),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _note!,
                key: const ValueKey('inbox-dates-note'),
                style: muted,
              ),
            ),
          if (_picked.length > 7) ...[
            const SizedBox(height: AppSpacing.sm),
            AppSurface(
              key: const ValueKey('inbox-experiment-hint'),
              color: tokens.surfaceSubtle,
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      'That is a lot of days for one errand. If you want to '
                      'see how it is going, start an experiment in Insights '
                      'instead.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('inbox-hint-experiment'),
                    onPressed: _busy ? null : widget.onStartExperiment,
                    child: const Text('Start as an experiment'),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _error!,
                key: const ValueKey('inbox-panel-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton(
                key: const ValueKey('inbox-panel-cancel'),
                onPressed: _busy ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('inbox-panel-submit'),
                onPressed: canSave ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateChip(
    String date, {
    required bool today,
    required DateTime now,
    required Map<String, String> locked,
  }) {
    final day = parseIsoDate(date);
    final isLocked = locked.containsKey(date);
    final selected = isLocked || _picked.containsKey(date);
    final passed = today && _slotErrorFor(date, now) != null;
    // A picked day that became invalid stays enabled so it can be removed.
    final enabled = !_busy && !isLocked && (selected || !passed);
    final label = today ? 'Today' : DateFormat('EEE d').format(day);
    final time = _hhmm(_picked[date] ?? _allTime);
    final spoken = DateFormat('EEEE, MMMM d').format(day);
    final semantics = isLocked
        ? '$spoken, selected, ${locked[date]!.toLowerCase()}, locked'
        : passed && !selected
        ? '${today ? 'Today' : spoken}, not available, that time has passed'
        : selected
        ? '$spoken, selected, $time for ${_lengthWords(_length)}'
        : '$spoken, not selected';
    return Semantics(
      label: semantics,
      button: true,
      selected: selected,
      enabled: enabled,
      excludeSemantics: true,
      onTap: enabled ? () => _toggle(date) : null,
      child: Tooltip(
        message: passed && !selected ? 'That time has passed' : '',
        excludeFromSemantics: true,
        child: FilterChip(
          key: ValueKey('inbox-date-$date'),
          label: Text(label),
          selected: selected,
          onSelected: enabled ? (_) => _toggle(date) : null,
        ),
      ),
    );
  }

  Widget _lockedRow(String date, String kind, TextStyle? muted) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      '${DateFormat('EEE, MMM d').format(parseIsoDate(date))}   $kind (locked)',
      key: ValueKey('inbox-locked-$date'),
      style: muted,
    ),
  );

  Widget _pickedRow(
    String date,
    DateTime now,
    List<Task>? overlapping,
    TextStyle? muted,
  ) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final slot = _slot(date);
    final end = PlannerTimeZone.toPlannerLocal(slot.end);
    final endsNextDay = isoDateString(slot.end) != date;
    final invalid = inboxSlotError(slot, now) != null;
    final first = overlapping?.first;
    String overlapText = '';
    if (first != null) {
      final start = PlannerTimeZone.toPlannerLocal(first.startTime!);
      final finish = PlannerTimeZone.toPlannerLocal(first.endTime!);
      final more = overlapping!.length - 1;
      overlapText =
          'Overlaps "${first.title}" ${formatClock24(start)}–${formatClock24(finish)}'
          '${more > 0 ? ' and $more more' : ''}. '
          'Change the time or save to keep both.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                DateFormat('EEE, MMM d').format(parseIsoDate(date)),
                style: textTheme.bodyMedium,
              ),
              TextButton(
                key: ValueKey('inbox-time-$date'),
                onPressed: _busy ? null : () => _pickRowTime(date),
                child: Text('${_hhmm(_picked[date]!)} ▾'),
              ),
              Text(
                endsNextDay
                    ? 'ends next day ${formatClock24(end)}'
                    : 'ends ${formatClock24(end)}',
                style: muted,
              ),
            ],
          ),
          if (invalid)
            Text(
              'That time has passed.',
              key: ValueKey('inbox-invalid-$date'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (overlapText.isNotEmpty)
            Text(
              overlapText,
              key: ValueKey('inbox-overlap-$date'),
              style: textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
        ],
      ),
    );
  }
}
