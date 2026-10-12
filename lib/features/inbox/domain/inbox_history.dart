import 'dart:convert';

import '../../../core/models/inbox_closure.dart';

/// Strict, side-effect-free handling for the history stored on an Inbox idea
/// (`tasks.inbox_history_json`). One validator is shared by the repository,
/// backup and sync ingress; the server function
/// `planner_inbox_history_valid` enforces the same rules.
abstract final class InboxHistory {
  static const maxEvents = 100;
  static const maxReasonLength = 200;

  static const _eventKeys = {
    'kind',
    'at',
    'reason',
    'experiment_id',
    'reopened_at',
  };

  /// Parses the stored JSON text. Throws [FormatException] for anything that
  /// is not a valid history, so callers never see a half-valid value.
  static List<InboxClosure> decodeJson(String source) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Inbox history must be valid JSON.');
    }
    return fromJsonList(decoded);
  }

  /// Builds a validated history from an already-decoded JSON array (the shape
  /// a backup document carries).
  static List<InboxClosure> fromJsonList(Object? decoded) {
    if (decoded is! List) {
      throw const FormatException('Inbox history must be a JSON array.');
    }
    if (decoded.length > maxEvents) {
      throw const FormatException('Inbox history has too many events.');
    }
    final events = <InboxClosure>[];
    for (final raw in decoded) {
      events.add(_parseEvent(raw));
    }
    validate(events);
    return List.unmodifiable(events);
  }

  static String encodeJson(Iterable<InboxClosure> events) =>
      jsonEncode(toJsonList(events));

  static List<Map<String, Object?>> toJsonList(Iterable<InboxClosure> events) =>
      [
        for (final event in events)
          {
            'kind': event.kind.dbValue,
            'at': event.at.toUtc().toIso8601String(),
            'reason': event.reason,
            'experiment_id': event.experimentId,
            'reopened_at': event.reopenedAt?.toUtc().toIso8601String(),
          },
      ];

  /// Throws [FormatException] unless [history] satisfies every rule.
  static void validate(Iterable<InboxClosure> history) {
    final events = history.toList(growable: false);
    if (events.length > maxEvents) {
      throw const FormatException('Inbox history has too many events.');
    }
    DateTime? previousAt;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final isLast = index == events.length - 1;
      if (!event.at.isUtc ||
          (event.reopenedAt != null && !event.reopenedAt!.isUtc)) {
        throw const FormatException('Inbox history timestamps must be UTC.');
      }
      if (previousAt != null && event.at.isBefore(previousAt)) {
        throw const FormatException('Inbox history events are out of order.');
      }
      previousAt = event.at;
      final reopenedAt = event.reopenedAt;
      if (reopenedAt != null && reopenedAt.isBefore(event.at)) {
        throw const FormatException(
          'An Inbox history event cannot be reopened before it was closed.',
        );
      }
      if (!isLast && reopenedAt == null) {
        throw const FormatException(
          'Only the last Inbox history event may be still closed.',
        );
      }
      final reason = event.reason;
      if (reason != null) {
        if (reason.trim().isEmpty ||
            reason != reason.trim() ||
            reason.runes.length > maxReasonLength) {
          throw const FormatException(
            'An Inbox reason must be trimmed text of 1 to 200 characters.',
          );
        }
      }
      switch (event.kind) {
        case InboxCloseKind.closed:
          if (reason == null) {
            throw const FormatException('Closing an idea needs a reason.');
          }
          if (event.experimentId != null) {
            throw const FormatException(
              'Only an experiment event carries an experiment id.',
            );
          }
        case InboxCloseKind.letGo:
          if (event.experimentId != null) {
            throw const FormatException(
              'Only an experiment event carries an experiment id.',
            );
          }
        case InboxCloseKind.experiment:
          if (reason != null) {
            throw const FormatException(
              'An experiment event carries no reason.',
            );
          }
          final experimentId = event.experimentId;
          if (experimentId == null || experimentId.trim().isEmpty) {
            throw const FormatException(
              'An experiment event needs an experiment id.',
            );
          }
      }
    }
  }

  /// True while the last event has not been reversed by Bring back.
  static bool isClosed(List<InboxClosure> history) =>
      history.isNotEmpty && history.last.reopenedAt == null;

  /// The event that currently holds the idea closed, or null.
  static InboxClosure? openClosure(List<InboxClosure> history) =>
      isClosed(history) ? history.last : null;

  /// The most recent Bring back instant, or null if the idea was never
  /// brought back.
  static DateTime? lastReopenedAt(List<InboxClosure> history) {
    DateTime? latest;
    for (final event in history) {
      final reopened = event.reopenedAt;
      if (reopened != null && (latest == null || reopened.isAfter(latest))) {
        latest = reopened;
      }
    }
    return latest;
  }

  /// Appends a closing event. Refuses an idea that is already closed.
  static List<InboxClosure> close(
    List<InboxClosure> history, {
    required InboxCloseKind kind,
    required DateTime at,
    String? reason,
    String? experimentId,
  }) {
    if (isClosed(history)) {
      throw StateError('The idea is already closed.');
    }
    final trimmed = reason?.trim();
    final next = [
      ...history,
      InboxClosure(
        kind: kind,
        at: at.toUtc(),
        reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
        experimentId: experimentId,
      ),
    ];
    validate(next);
    return List.unmodifiable(next);
  }

  /// Marks the open closure as brought back. The event itself stays.
  static List<InboxClosure> reopen(List<InboxClosure> history, DateTime at) {
    if (!isClosed(history)) {
      throw StateError('The idea is not closed.');
    }
    final next = [
      ...history.sublist(0, history.length - 1),
      history.last.copyWith(reopenedAt: at.toUtc()),
    ];
    validate(next);
    return List.unmodifiable(next);
  }

  static InboxClosure _parseEvent(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Inbox history contains an invalid event.');
    }
    final keys = raw.keys.map((key) => '$key').toSet();
    if (!_eventKeys.containsAll(keys)) {
      throw const FormatException(
        'Inbox history contains an unknown event key.',
      );
    }
    final kindValue = raw['kind'];
    final atValue = raw['at'];
    final reason = raw['reason'];
    final experimentId = raw['experiment_id'];
    final reopenedValue = raw['reopened_at'];
    final kind = kindValue is String
        ? InboxCloseKind.values
              .where((candidate) => candidate.dbValue == kindValue)
              .firstOrNull
        : null;
    if (kind == null ||
        atValue is! String ||
        (reason != null && reason is! String) ||
        (experimentId != null && experimentId is! String) ||
        (reopenedValue != null && reopenedValue is! String)) {
      throw const FormatException('Inbox history contains an invalid event.');
    }
    return InboxClosure(
      kind: kind,
      at: _parseInstant(atValue),
      reason: reason as String?,
      experimentId: experimentId as String?,
      reopenedAt: reopenedValue == null
          ? null
          : _parseInstant(reopenedValue as String),
    );
  }

  static DateTime _parseInstant(String value) {
    // `DateTime.parse` turns an offset instant into a UTC value, so the
    // canonical `Z` form is checked on the text itself.
    final parsed = value.endsWith('Z') ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException(
        'Inbox history timestamps must be ISO UTC instants.',
      );
    }
    return parsed;
  }
}
