import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/inbox_closure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/clock_format.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/planner_time_zone.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../experiments/presentation/widgets/experiment_start_form.dart';
import '../../../experiments/providers/experiment_providers.dart';
import '../../../task_editor/presentation/widgets/tag_field.dart'
    show maxTagNameUnits;
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../domain/inbox_board.dart';
import '../../domain/inbox_session_text.dart';
import '../../domain/inbox_status.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_badge.dart';
import 'inbox_close_panel.dart';
import 'inbox_dates_panel.dart';

String _dayText(DateTime instant) =>
    DateFormat('EEE, MMM d').format(PlannerTimeZone.toPlannerLocal(instant));

String _shortDayText(DateTime instant) =>
    DateFormat('MMM d').format(PlannerTimeZone.toPlannerLocal(instant));

String _clockText(DateTime instant) =>
    formatClock24(PlannerTimeZone.toPlannerLocal(instant));

/// How many trail lines show before the earlier ones fold away.
const _foldAfterEntries = 6;

enum _Panel { none, dates, close, letGo }

enum _Action {
  setDates,
  addDays,
  editDates,
  experiment,
  seeInInsights,
  closeIt,
  letGo,
  bringBack,
}

/// The expanded part of an Inbox row: the idea's life in time order and the
/// state-dependent footer. Reasons shown here are read only; they are written
/// in Review.
class InboxTrail extends ConsumerStatefulWidget {
  const InboxTrail({super.key, required this.view});

  final InboxIdeaView view;

  @override
  ConsumerState<InboxTrail> createState() => _InboxTrailState();
}

class _InboxTrailState extends ConsumerState<InboxTrail> {
  _Panel _panel = _Panel.none;
  bool _busy = false;
  bool _showEarlier = false;
  String? _error;
  final _footerFocus = FocusNode(debugLabel: 'inbox-footer-first');

  @override
  void initState() {
    super.initState();
    // Picks left unsaved when another idea was opened bring their panel back.
    if (ref.read(inboxDatesDraftProvider(widget.view.item.id)) != null) {
      _panel = _Panel.dates;
    }
  }

  @override
  void dispose() {
    _footerFocus.dispose();
    super.dispose();
  }

  void _openPanel(_Panel panel) => setState(() {
    _panel = panel;
    _error = null;
  });

  void _closePanel() {
    setState(() => _panel = _Panel.none);
    // Keyboard users land back on the footer instead of at the page top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _footerFocus.context != null) _footerFocus.requestFocus();
    });
  }

  Future<void> _bringBack() async {
    if (_busy) return;
    final repository = ref.read(inboxRepositoryProvider);
    final now = ref.read(inboxNowFactoryProvider)();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.bringBack(widget.view.item.id, now);
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, 'Brought back to Ideas');
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = inboxErrorText(error);
        });
      }
    }
  }

  /// Opens Insights' start form with the idea's first line as the name. The
  /// idea moves to Done only when the experiment is created: the repository
  /// call runs inside the transaction that creates it. Backing out writes
  /// nothing.
  Future<void> _startExperiment() async {
    final repository = ref.read(inboxRepositoryProvider);
    final nowFactory = ref.read(inboxNowFactoryProvider);
    final id = widget.view.item.id;
    final name = clipUtf16(
      inboxSessionText(widget.view.item.text).title,
      maxTagNameUnits,
    );
    await showExperimentStartForm(
      context,
      initialName: name,
      onCreated: (created) =>
          repository.markBecameExperiment(id, created.id, nowFactory()),
    );
  }

  void _seeInInsights() {
    final id = widget.view.experimentId;
    if (id == null) return;
    ref.read(experimentFocusProvider.notifier).state = id;
    context.go('/analytics');
  }

  void _openInDay(DateTime start, String taskId) {
    ref.read(selectedDateProvider.notifier).state = startOfDay(start);
    ref.read(selectedTaskIdProvider.notifier).state = taskId;
    ref.read(taskEditorOpenProvider.notifier).state = true;
    context.go('/day');
  }

  /// Footer actions for the idea's status, primary first (plan 7.3).
  List<_Action> _actions(InboxIdeaView view) {
    final hasHistory = view.sessions.any(
      (s) => s.status != InboxSessionStatus.dropped,
    );
    return switch (view.status) {
      InboxItemStatus.idea => [
        _Action.setDates,
        _Action.experiment,
        hasHistory ? _Action.closeIt : _Action.letGo,
      ],
      InboxItemStatus.soon => [
        _Action.editDates,
        _Action.experiment,
        _Action.closeIt,
      ],
      InboxItemStatus.left => [
        _Action.addDays,
        _Action.experiment,
        _Action.closeIt,
      ],
      InboxItemStatus.finished => const [_Action.addDays],
      InboxItemStatus.closed =>
        view.closure?.kind != InboxCloseKind.experiment
            ? const [_Action.bringBack]
            : view.experimentMissing
            ? const [_Action.bringBack]
            : const [_Action.seeInInsights],
    };
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final now = ref.watch(inboxScreenClockProvider);
    final textTheme = Theme.of(context).textTheme;
    final lineStyle = textTheme.bodySmall;

    final description = inboxSessionText(view.item.text).description;
    final entries = <_Entry>[
      _Entry(
        view.item.createdAt,
        0,
        Text('Captured ${_dayText(view.item.createdAt)}', style: lineStyle),
      ),
      for (final session in view.sessions)
        _Entry(
          session.facts.start ?? session.facts.createdAt,
          1,
          _SessionLine(
            session: session,
            now: now,
            onOpenInDay: session.status == InboxSessionStatus.dropped
                ? null
                : () => _openInDay(session.facts.start!, session.facts.id),
          ),
        ),
      for (final event in view.item.history) ...[
        _Entry(event.at, 2, Text(_eventText(event), style: lineStyle)),
        if (event.reopenedAt != null)
          _Entry(
            event.reopenedAt!,
            3,
            Text(
              'Brought back ${_shortDayText(event.reopenedAt!)}',
              style: lineStyle,
            ),
          ),
      ],
    ]..sort(_Entry.compare);

    // A long trail shows its latest lines; the rest is one tap away.
    final hidden = _showEarlier
        ? 0
        : math.max(0, entries.length - _foldAfterEntries);
    final actions = _actions(view);
    final footer = switch (_panel) {
      _Panel.dates => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: InboxDatesPanel(
          key: ValueKey('inbox-panel-dates-${view.item.id}'),
          view: view,
          onSaved: () => setState(() => _panel = _Panel.none),
          onCancel: _closePanel,
          onStartExperiment: () {
            ref.read(inboxDatesDraftProvider(view.item.id).notifier).state =
                null;
            setState(() => _panel = _Panel.none);
            _startExperiment();
          },
        ),
      ),
      _Panel.close || _Panel.letGo => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: InboxClosePanel(
          key: ValueKey('inbox-panel-${_panel.name}-${view.item.id}'),
          itemId: view.item.id,
          letGo: _panel == _Panel.letGo,
          onClosed: () => setState(() => _panel = _Panel.none),
          onCancel: _closePanel,
        ),
      ),
      _Panel.none =>
        actions.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      _footerButton(actions[i], primary: i == 0, first: i == 0),
                  ],
                ),
              ),
    };

    return Column(
      key: ValueKey('inbox-trail-${view.item.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              description,
              key: ValueKey('inbox-description-${view.item.id}'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: lineStyle?.copyWith(
                color: AppThemeTokens.of(context).textMuted,
              ),
            ),
          ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('inbox-show-earlier'),
              onPressed: () => setState(() => _showEarlier = true),
              child: Text('Show earlier ($hidden)'),
            ),
          ),
        for (final entry in entries.skip(hidden))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: entry.child,
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              _error!,
              key: const ValueKey('inbox-trail-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        // Keyed: a new trail line above must not remount an open panel.
        KeyedSubtree(key: const ValueKey('inbox-trail-footer'), child: footer),
      ],
    );
  }

  String _eventText(InboxClosure event) {
    final day = _shortDayText(event.at);
    final reason = event.reason;
    final suffix = reason == null ? '' : ' · $reason';
    return switch (event.kind) {
      InboxCloseKind.closed => 'Closed $day$suffix',
      InboxCloseKind.letGo => 'Let go $day$suffix',
      InboxCloseKind.experiment => 'Became an experiment $day',
    };
  }

  Widget _footerButton(
    _Action action, {
    required bool primary,
    required bool first,
  }) {
    final (label, key, onPressed) = switch (action) {
      _Action.setDates => (
        'Set dates',
        'inbox-action-dates',
        () => _openPanel(_Panel.dates),
      ),
      _Action.addDays => (
        'Add days',
        'inbox-action-dates',
        () => _openPanel(_Panel.dates),
      ),
      _Action.editDates => (
        'Edit dates',
        'inbox-action-dates',
        () => _openPanel(_Panel.dates),
      ),
      _Action.experiment => (
        'Start as an experiment',
        'inbox-action-experiment',
        _startExperiment,
      ),
      _Action.seeInInsights => (
        'See in Insights',
        'inbox-action-insights',
        _seeInInsights,
      ),
      _Action.closeIt => (
        'Close it',
        'inbox-action-close',
        () => _openPanel(_Panel.close),
      ),
      _Action.letGo => (
        'Let go',
        'inbox-action-let-go',
        () => _openPanel(_Panel.letGo),
      ),
      _Action.bringBack => (
        'Bring back',
        'inbox-action-bring-back',
        _bringBack,
      ),
    };
    final callback = _busy ? null : onPressed;
    final focusNode = first ? _footerFocus : null;
    return primary
        ? FilledButton.tonal(
            key: ValueKey(key),
            focusNode: focusNode,
            onPressed: callback,
            child: Text(label),
          )
        : TextButton(
            key: ValueKey(key),
            focusNode: focusNode,
            onPressed: callback,
            child: Text(label),
          );
  }
}

/// One line of the trail with the instant that orders it.
class _Entry {
  const _Entry(this.at, this.rank, this.child);

  final DateTime at;

  /// Breaks ties: captured, then sessions, then the close, then the bring back.
  final int rank;
  final Widget child;

  static int compare(_Entry a, _Entry b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.rank.compareTo(b.rank);
  }
}

/// A session: "Tue, Oct 13 · 09:00–10:00", its badge, "Open in Day", and for
/// an ended session that is not done the reason line.
class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.session,
    required this.now,
    required this.onOpenInDay,
  });

  final InboxSessionView session;
  final DateTime now;
  final VoidCallback? onOpenInDay;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final facts = session.facts;
    final start = facts.start;
    final end = facts.end;
    final when = start == null || end == null
        ? 'Not on the timeline'
        : '${_dayText(start)} · ${_clockText(start)}–${_clockText(end)}';
    final started = start != null && !start.isAfter(now);
    final ended = end != null && !end.isAfter(now);
    final reasonStatus =
        session.status == InboxSessionStatus.missed ||
        session.status == InboxSessionStatus.carried ||
        session.status == InboxSessionStatus.skipped;
    final String? reasonLine;
    if (!reasonStatus || !ended) {
      reasonLine = null;
    } else if (session.reason != null) {
      reasonLine = 'Reason: ${session.reason}';
    } else if (session.breakDay) {
      reasonLine = 'Break day. No reason needed.';
    } else {
      reasonLine = 'No reason yet. Reasons are written in Review.';
    }
    return Column(
      key: ValueKey('inbox-session-${facts.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(when, style: textTheme.bodySmall),
            InboxBadge.session(context, session.status, started: started),
            if (onOpenInDay != null)
              TextButton(
                key: ValueKey('inbox-open-day-${facts.id}'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                onPressed: onOpenInDay,
                child: const Text('Open in Day'),
              ),
          ],
        ),
        if (reasonLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              reasonLine,
              key: ValueKey('inbox-session-reason-${facts.id}'),
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ),
      ],
    );
  }
}
