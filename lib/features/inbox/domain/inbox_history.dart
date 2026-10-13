import 'dart:convert';

import '../../../core/models/inbox_closure.dart';

/// Strict, side-effect-free handling for the history stored on an Inbox idea
/// (`tasks.inbox_history_json`). One validator is shared by the repository,
/// backup and sync ingress; the server function
/// `planner_inbox_history_valid` accepts exactly the same set (both are tested
/// against `test/fixtures/inbox_history_cases.json`).
///
/// Canonical rules:
/// - `at` / `reopened_at`: `yyyy-MM-ddTHH:mm:ss[.fraction]Z`, a real calendar
///   instant in UTC, year 0001 or later. No offset, no space, no reduced form.
/// - A non-null `reason` is already trimmed, not blank, 1 to 200 code points.
///   "Whitespace" is Dart's `String.trim` set (U+0009 to U+000D, U+0020,
///   U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F,
///   U+205F, U+3000, U+FEFF), the same set the server spells out.
/// - An experiment id is non-blank by the same test.
/// - Neither text contains U+0000 (`jsonb` cannot hold it).
abstract final class InboxHistory {
  static const maxEvents = 100;
  static const maxReasonLength = 200;

  /// The only accepted text form of an instant. Ranges are checked here;
  /// whether the day exists in the month is checked after parsing.
  static final _instantPattern = RegExp(
    r'^([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])'
    r'T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]+)?Z$',
  );

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
            reason.contains('\u0000') ||
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
          if (experimentId == null ||
              experimentId.trim().isEmpty ||
              experimentId.contains('\u0000')) {
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
  ///
  /// A device whose clock is behind the one that wrote the last event must
  /// still be able to close, so [at] is raised to the previous event's `at`
  /// (or its bring back, if later) instead of failing validation.
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
        at: _notBeforePrevious(history, at.toUtc()),
        reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
        experimentId: experimentId,
      ),
    ];
    validate(next);
    return List.unmodifiable(next);
  }

  /// Marks the open closure as brought back. The event itself stays. [at] is
  /// raised to the event's own `at` when this device's clock is behind it.
  static List<InboxClosure> reopen(List<InboxClosure> history, DateTime at) {
    if (!isClosed(history)) {
      throw StateError('The idea is not closed.');
    }
    final next = [
      ...history.sublist(0, history.length - 1),
      history.last.copyWith(
        reopenedAt: at.toUtc().isBefore(history.last.at)
            ? history.last.at
            : at.toUtc(),
      ),
    ];
    validate(next);
    return List.unmodifiable(next);
  }

  /// [at], or the latest instant the previous event reached when [at] is
  /// earlier (clock skew between devices).
  static DateTime _notBeforePrevious(List<InboxClosure> history, DateTime at) {
    if (history.isEmpty) return at;
    final previous = history.last;
    final floor = previous.reopenedAt ?? previous.at;
    return at.isBefore(floor) ? floor : at;
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
    // `DateTime.tryParse` is far looser than the canonical form (a space
    // separator, a comma, reduced time, basic format) and rolls impossible
    // dates over (February 30 becomes March 2), so the text is checked first
    // and the calendar day is checked after.
    final match = _instantPattern.firstMatch(value);
    final parsed = match == null ? null : DateTime.tryParse(value);
    if (match == null ||
        parsed == null ||
        !parsed.isUtc ||
        parsed.year < 1 ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!)) {
      throw const FormatException(
        'Inbox history timestamps must be ISO UTC instants.',
      );
    }
    return parsed;
  }
}
