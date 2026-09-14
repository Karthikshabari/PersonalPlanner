import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/day_context.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';

class DayContextConflictException extends StateError {
  DayContextConflictException(super.message);
}

/// Persistence boundary for one optional context per planner calendar date.
/// All dates remain date-only strings so no UTC conversion can move a context
/// to an adjacent day.
class DayContextRepository {
  DayContextRepository(this._db);

  final AppDatabase _db;

  Stream<DayContext?> watchForDate(String date) {
    _validateDate(date);
    return (_db.select(_db.dayContexts)
          ..where((row) => row.date.equals(date) & row.deletedAt.isNull()))
        .watchSingleOrNull()
        .map((row) => row == null ? null : fromRow(row));
  }

  Stream<List<DayContext>> watchRange(
    String startInclusive,
    String endExclusive,
  ) {
    _validateDate(startInclusive);
    _validateDate(endExclusive);
    if (endExclusive.compareTo(startInclusive) <= 0) {
      throw ArgumentError('Day context range must have a positive length.');
    }
    return (_db.select(_db.dayContexts)
          ..where(
            (row) =>
                row.date.isBiggerOrEqualValue(startInclusive) &
                row.date.isSmallerThanValue(endExclusive) &
                row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.date)]))
        .watch()
        .map((rows) => rows.map(fromRow).toList(growable: false));
  }

  Future<DayContext> save(
    String date,
    DayContextKind kind,
    String? customLabel, {
    int? expectedRevision,
  }) async {
    _validateDate(date);
    final normalizedLabel = _validateKindAndLabel(kind, customLabel);
    final id = generateDeterministicUuid('day-context:$date');
    late DayContext result;
    await _db.transaction(() async {
      final current = await _getByDate(date);
      if (current != null &&
          expectedRevision != null &&
          current.revision != expectedRevision) {
        throw DayContextConflictException(
          'Day context changed while it was being edited; reload it before saving.',
        );
      }
      if (current == null) {
        if (expectedRevision != null && expectedRevision != 0) {
          throw DayContextConflictException(
            'Day context was created while it was being edited; reload it before saving.',
          );
        }
        final now = DateTime.now();
        await _db
            .into(_db.dayContexts)
            .insert(
              DayContextsCompanion.insert(
                id: id,
                date: date,
                kind: kind.dbValue,
                customLabel: Value(normalizedLabel),
                createdAt: now,
                updatedAt: now,
              ),
            );
        result = DayContext(
          id: id,
          date: date,
          kind: kind,
          customLabel: normalizedLabel,
          createdAt: now,
          updatedAt: now,
          revision: 1,
        );
        return;
      }

      final now = DateTime.now();
      final nextRevision = current.revision + 1;
      final changed =
          await (_db.update(
            _db.dayContexts,
          )..where((row) => row.id.equals(current.id))).write(
            DayContextsCompanion(
              kind: Value(kind.dbValue),
              customLabel: Value(normalizedLabel),
              updatedAt: Value(now),
              deletedAt: const Value(null),
              syncStatus: const Value(1),
              revision: Value(nextRevision),
            ),
          );
      if (changed != 1) {
        throw DayContextConflictException(
          'Day context changed while it was being edited; reload it before saving.',
        );
      }
      result = DayContext(
        id: current.id,
        date: current.date,
        kind: kind,
        customLabel: normalizedLabel,
        createdAt: current.createdAt,
        updatedAt: now,
        revision: nextRevision,
      );
    });
    return result;
  }

  Future<DayContext?> remove(String id, {int? expectedRevision}) async {
    if (id.trim().isEmpty) throw ArgumentError('Context ID is required.');
    DayContext? result;
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.dayContexts,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (current == null || current.deletedAt != null) return;
      if (expectedRevision != null && current.revision != expectedRevision) {
        throw DayContextConflictException(
          'Day context changed while it was being edited; reload it before removing.',
        );
      }
      final now = DateTime.now();
      final nextRevision = current.revision + 1;
      final changed =
          await (_db.update(
            _db.dayContexts,
          )..where((row) => row.id.equals(id))).write(
            DayContextsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              syncStatus: const Value(1),
              revision: Value(nextRevision),
            ),
          );
      if (changed != 1) {
        throw DayContextConflictException(
          'Day context changed while it was being edited; reload it before removing.',
        );
      }
      result = fromRow(
        current.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          revision: nextRevision,
        ),
      );
    });
    return result;
  }

  Future<DayContextRow?> _getByDate(String date) => (_db.select(
    _db.dayContexts,
  )..where((row) => row.date.equals(date))).getSingleOrNull();

  static DayContext fromRow(DayContextRow row) => DayContext(
    id: row.id,
    date: row.date,
    kind: DayContextKind.fromDb(row.kind),
    customLabel: row.customLabel,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    revision: row.revision,
  );

  static void _validateDate(String value) {
    if (!isValidIsoDate(value)) {
      throw ArgumentError.value(
        value,
        'date',
        'must be a real yyyy-MM-dd date',
      );
    }
  }

  static String? _validateKindAndLabel(
    DayContextKind kind,
    String? customLabel,
  ) {
    if (kind != DayContextKind.custom) {
      if (customLabel != null) {
        throw ArgumentError('Preset day contexts cannot have a custom label.');
      }
      return null;
    }
    final trimmed = customLabel?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Custom day context labels must be 1–80 characters.');
    }
    return trimmed;
  }
}
