import 'dart:convert';

import '../../../core/models/plan_title_change.dart';

/// Strict, side-effect-free handling for the title-history value embedded in
/// a Task aggregate.  It is deliberately shared by repository, sync, backup
/// and recurrence code so every ingress applies the same invariants.
abstract final class PlanTitleHistory {
  static const _eventKeys = {
    'id',
    'previous_title',
    'new_title',
    'changed_at',
    'reverted_at',
  };

  static String normalizeTitle(String value) => value.trim();

  static List<PlanTitleChange> decodeJson(String source) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Plan title history must be valid JSON.');
    }
    if (decoded is! List) {
      throw const FormatException('Plan title history must be a JSON array.');
    }
    final events = <PlanTitleChange>[];
    for (final raw in decoded) {
      final keys = raw is Map ? raw.keys.map((key) => '$key').toSet() : null;
      if (keys == null ||
          keys.length != _eventKeys.length ||
          !keys.containsAll(_eventKeys)) {
        throw const FormatException(
          'Plan title history contains an invalid event.',
        );
      }
      try {
        final event = Map<String, dynamic>.from(raw);
        if (event['id'] is! String ||
            event['previous_title'] is! String ||
            event['new_title'] is! String ||
            event['changed_at'] is! String ||
            (event['reverted_at'] != null && event['reverted_at'] is! String)) {
          throw const FormatException();
        }
        events.add(PlanTitleChange.fromJson(event));
      } on Object {
        throw const FormatException(
          'Plan title history contains an invalid event.',
        );
      }
    }
    final canonical = canonicalize(events);
    validate(canonical, displayPlanChangeId: null, currentTitle: '');
    return canonical;
  }

  static String encodeJson(Iterable<PlanTitleChange> events) => jsonEncode(
    canonicalize(events).map((event) => event.toJson()).toList(growable: false),
  );

  static List<PlanTitleChange> canonicalize(Iterable<PlanTitleChange> source) {
    final events = source.toList(growable: false)
      ..sort((left, right) {
        final date = left.changedAt.toUtc().compareTo(right.changedAt.toUtc());
        return date != 0 ? date : left.id.compareTo(right.id);
      });
    return List.unmodifiable(events);
  }

  static void validate(
    Iterable<PlanTitleChange> history, {
    required String? displayPlanChangeId,
    required String currentTitle,
  }) {
    final ids = <String>{};
    PlanTitleChange? selected;
    for (final event in history) {
      if (!_isUuid(event.id) || !ids.add(event.id)) {
        throw const FormatException(
          'Plan title events must have unique UUID IDs.',
        );
      }
      _validateTitle(event.previousTitle, 'previous title');
      _validateTitle(event.newTitle, 'new title');
      if (!event.changedAt.isUtc ||
          (event.revertedAt != null && !event.revertedAt!.isUtc)) {
        throw const FormatException('Plan title event timestamps must be UTC.');
      }
      if (event.revertedAt != null &&
          event.revertedAt!.isBefore(event.changedAt)) {
        throw const FormatException(
          'A plan title event cannot be reverted before it changed.',
        );
      }
      if (event.id == displayPlanChangeId) selected = event;
    }
    if (displayPlanChangeId == null) return;
    if (selected == null ||
        selected.revertedAt != null ||
        normalizeTitle(selected.newTitle) != normalizeTitle(currentTitle)) {
      throw const FormatException('Plan title display selection is invalid.');
    }
  }

  static List<PlanTitleChange> appendOrRestore(
    Iterable<PlanTitleChange> source,
    PlanTitleChange event,
  ) {
    final events = source.toList(growable: true);
    final index = events.indexWhere((existing) => existing.id == event.id);
    if (index < 0) {
      events.add(event);
    } else {
      final existing = events[index];
      if (!_sameImmutableBody(existing, event)) {
        throw const FormatException(
          'Plan title event ID has conflicting immutable data.',
        );
      }
      events[index] = existing.copyWith(revertedAt: null);
    }
    return canonicalize(events);
  }

  /// Unions history by stable ID. The [chosen] side controls a shared event's
  /// reversible state; immutable event-body disagreement is data corruption,
  /// not a timestamp conflict that can safely be guessed.
  static List<PlanTitleChange> union({
    required Iterable<PlanTitleChange> chosen,
    required Iterable<PlanTitleChange> other,
  }) {
    final values = <String, PlanTitleChange>{
      for (final event in chosen) event.id: event,
    };
    for (final event in other) {
      final existing = values[event.id];
      if (existing == null) {
        values[event.id] = event;
      } else if (!_sameImmutableBody(existing, event)) {
        throw const FormatException(
          'Plan title event ID has conflicting immutable data.',
        );
      }
    }
    return canonicalize(values.values);
  }

  /// Existing event bodies are durable audit evidence. An update may add an
  /// event or change only its reversible marker, but cannot repurpose or
  /// delete a stable ID that was already stored on this Task.
  static void validateTransition({
    required Iterable<PlanTitleChange> previous,
    required Iterable<PlanTitleChange> next,
  }) {
    final nextById = {for (final event in next) event.id: event};
    for (final oldEvent in previous) {
      final candidate = nextById[oldEvent.id];
      if (candidate == null || !_sameImmutableBody(oldEvent, candidate)) {
        throw const FormatException(
          'Existing plan title events cannot be removed or changed.',
        );
      }
    }
  }

  /// Preserves all current history and marks events introduced by an aggregate
  /// command as reverted, without deleting evidence or touching newer events.
  static List<PlanTitleChange> revertedForUndo({
    required Iterable<PlanTitleChange> before,
    required Iterable<PlanTitleChange> after,
    required Iterable<PlanTitleChange> current,
    required DateTime now,
  }) {
    final baselineIds = {for (final event in before) event.id};
    final introduced = {
      for (final event in after)
        if (!baselineIds.contains(event.id)) event.id,
    };
    final merged = union(chosen: current, other: before).toList(growable: true);
    for (var index = 0; index < merged.length; index++) {
      final event = merged[index];
      if (introduced.contains(event.id) && event.revertedAt == null) {
        merged[index] = event.copyWith(revertedAt: now.toUtc());
      }
    }
    return canonicalize(merged);
  }

  static bool _sameImmutableBody(PlanTitleChange left, PlanTitleChange right) =>
      left.id == right.id &&
      left.previousTitle == right.previousTitle &&
      left.newTitle == right.newTitle &&
      left.changedAt.toUtc() == right.changedAt.toUtc();

  static void _validateTitle(String value, String label) {
    if (normalizeTitle(value).isEmpty || value.length > 500) {
      throw FormatException(
        'Plan title $label must be nonblank and at most 500 characters.',
      );
    }
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
