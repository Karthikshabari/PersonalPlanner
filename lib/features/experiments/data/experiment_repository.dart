import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/experiment_dao.dart';
import '../../../core/models/experiment.dart';
import '../../../core/models/experiment_check_in.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/uuid.dart';
import '../../task_editor/data/tag_repository.dart';
import '../domain/experiment_check_in_schedule.dart';

/// Thrown by [ExperimentRepository.createExperiment] when an experiment
/// already uses the tag the name resolves to (ED6: one experiment per tag).
class ExperimentTagInUseException implements Exception {
  const ExperimentTagInUseException(this.tagName);

  final String tagName;

  @override
  String toString() => 'An experiment already uses the tag "$tagName"';
}

/// Persistence boundary for experiments and their check-ins. Every write runs
/// in one `writeTransaction` with ordinary Drift writes, so the sync triggers
/// queue the operations. Text limits count code points (ED9) and every date
/// sum is calendar-day arithmetic (section 2.4).
class ExperimentRepository {
  ExperimentRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static const _maxTagNameUnits = 100;
  static const _maxPurposeRunes = 1000;
  static const _maxReasonRunes = 500;
  static const _maxNoteRunes = 4000;
  static const _maxTarget = 9999;
  static const _extensionDays = [7, 14, 30];

  ExperimentDao get _dao => _db.experimentDao;

  Stream<List<Experiment>> watchExperiments() => _dao.watchExperiments().map(
    (rows) => [for (final r in rows) _fromRow(r.experiment, r.tag.name)],
  );

  Stream<List<ExperimentCheckIn>> watchCheckIns(String experimentId) => _dao
      .watchCheckInsForExperiment(experimentId)
      .map((rows) => [for (final r in rows) _checkInFromRow(r)]);

  Future<Experiment> createExperiment({
    required String name,
    String? purpose,
    required String startDate,
    required String endDate,
    required int weekdayTargetMin,
    required int weekendTargetMin,
    required int checkInEveryDays,
  }) async {
    final tagName = name.trim();
    if (tagName.isEmpty || tagName.length > _maxTagNameUnits) {
      throw ArgumentError('name must be 1 to $_maxTagNameUnits characters');
    }
    final storedPurpose = _optionalText(purpose, 'purpose', _maxPurposeRunes);
    _requireDate(startDate, 'startDate');
    _requireDate(endDate, 'endDate');
    if (endDate.compareTo(startDate) < 0) {
      throw ArgumentError('endDate must be on or after the start date');
    }
    _requireTarget(weekdayTargetMin, 'weekdayTargetMin');
    _requireTarget(weekendTargetMin, 'weekendTargetMin');
    if (!experimentCheckInFrequencies.contains(checkInEveryDays)) {
      throw ArgumentError(
        'checkInEveryDays must be one of $experimentCheckInFrequencies',
      );
    }
    return _db.writeTransaction(() async {
      final tag = await TagRepository(_db).getOrCreateForName(tagName);
      if (await _dao.getExperimentByTagId(tag.id) != null) {
        throw ExperimentTagInUseException(tag.name);
      }
      final now = _clock().toUtc();
      final id = generateDeterministicUuid('experiment:${tag.id}');
      await _dao.insertExperiment(
        ExperimentsCompanion.insert(
          id: id,
          tagId: tag.id,
          purpose: Value(storedPurpose),
          startDate: startDate,
          endDate: endDate,
          weekdayTargetMin: weekdayTargetMin,
          weekendTargetMin: weekendTargetMin,
          checkInEveryDays: checkInEveryDays,
          status: Value(ExperimentStatus.running.dbValue),
          extensionsJson: const Value('[]'),
          createdAt: now,
          updatedAt: now,
          syncStatus: const Value(1),
          revision: const Value(1),
        ),
      );
      return _load(id);
    });
  }

  /// Moves the end date of a running experiment by [days] (7, 14 or 30) and
  /// records why. Allowed only on or after the current end date.
  Future<Experiment> extendExperiment(
    String experimentId, {
    required int days,
    required String reason,
    required String today,
    required int expectedRevision,
  }) async {
    if (!_extensionDays.contains(days)) {
      throw ArgumentError('days must be one of $_extensionDays');
    }
    final storedReason = _requiredText(reason, 'reason', _maxReasonRunes);
    _requireDate(today, 'today');
    return _db.writeTransaction(() async {
      final row = await _openRow(experimentId, expectedRevision, today);
      final newEnd = isoDateString(addDays(parseIsoDate(row.endDate), days));
      final extensions = [
        ..._decodeExtensions(row.extensionsJson),
        ExperimentExtension(
          reason: storedReason,
          previousEndDate: row.endDate,
          newEndDate: newEnd,
          madeOn: today,
        ),
      ];
      await _dao.updateExperiment(
        row.copyWith(
          endDate: newEnd,
          extensionsJson: jsonEncode([for (final e in extensions) e.toJson()]),
          updatedAt: _clock().toUtc(),
          syncStatus: 1,
          revision: row.revision + 1,
        ),
      );
      return _load(experimentId);
    });
  }

  /// Ends a running experiment on or after its end date.
  Future<Experiment> concludeExperiment(
    String experimentId, {
    required ExperimentOutcome outcome,
    String? note,
    required String today,
    required int expectedRevision,
  }) async {
    final storedNote = _optionalText(note, 'note', _maxNoteRunes);
    _requireDate(today, 'today');
    return _db.writeTransaction(() async {
      final row = await _openRow(experimentId, expectedRevision, today);
      await _dao.updateExperiment(
        row.copyWith(
          status: ExperimentStatus.concluded.dbValue,
          outcome: Value(outcome.dbValue),
          conclusionNote: Value(storedNote),
          concludedOn: Value(today),
          updatedAt: _clock().toUtc(),
          syncStatus: 1,
          revision: row.revision + 1,
        ),
      );
      return _load(experimentId);
    });
  }

  /// Writes the check-in for one slot of a running experiment. The slot must
  /// be dated [today] or earlier and not written yet.
  Future<ExperimentCheckIn> saveCheckIn({
    required String experimentId,
    required String slotDate,
    required String note,
    required String today,
  }) async {
    final storedNote = _requiredText(note, 'note', _maxNoteRunes);
    _requireDate(slotDate, 'slotDate');
    _requireDate(today, 'today');
    return _db.writeTransaction(() async {
      final row = await _dao.getExperimentById(experimentId);
      if (row == null || row.deletedAt != null) {
        throw StateError('Experiment $experimentId not found');
      }
      if (row.status != ExperimentStatus.running.dbValue) {
        throw StateError('Experiment $experimentId is not running');
      }
      final slots = experimentSlotDates(
        startDate: row.startDate,
        endDate: row.endDate,
        checkInEveryDays: row.checkInEveryDays,
      );
      if (!slots.contains(slotDate)) {
        throw ArgumentError(
          'slotDate is not a check-in slot of this experiment',
        );
      }
      if (slotDate.compareTo(today) > 0) {
        throw ArgumentError('slotDate is in the future');
      }
      final id = generateDeterministicUuid(
        'experiment-check-in:$experimentId:$slotDate',
      );
      if (await _dao.getCheckInById(id) != null) {
        throw StateError('A check-in for $slotDate already exists');
      }
      final now = _clock().toUtc();
      await _dao.insertCheckIn(
        ExperimentCheckInsCompanion.insert(
          id: id,
          experimentId: experimentId,
          slotDate: slotDate,
          note: storedNote,
          createdAt: now,
          updatedAt: now,
          syncStatus: const Value(1),
          revision: const Value(1),
        ),
      );
      return _checkInFromRow((await _dao.getCheckInById(id))!);
    });
  }

  /// The row of a running experiment whose end date has arrived, after the
  /// revision check shared by extend and conclude.
  Future<ExperimentRow> _openRow(
    String experimentId,
    int expectedRevision,
    String today,
  ) async {
    final row = await _dao.getExperimentById(experimentId);
    if (row == null || row.deletedAt != null) {
      throw StateError('Experiment $experimentId not found');
    }
    if (row.revision != expectedRevision) {
      throw StateError(
        'Experiment $experimentId changed while it was open; reload it.',
      );
    }
    if (row.status != ExperimentStatus.running.dbValue) {
      throw StateError('Experiment $experimentId is not running');
    }
    if (today.compareTo(row.endDate) < 0) {
      throw StateError('The end date of experiment $experimentId has not come');
    }
    return row;
  }

  Future<Experiment> _load(String id) async {
    final row = (await _dao.getExperimentById(id))!;
    final tag = await _db.tagDao.getTagById(row.tagId);
    return _fromRow(row, tag?.name ?? '');
  }

  static Experiment _fromRow(ExperimentRow row, String tagName) => Experiment(
    id: row.id,
    tagId: row.tagId,
    tagName: tagName,
    purpose: row.purpose,
    startDate: row.startDate,
    endDate: row.endDate,
    weekdayTargetMin: row.weekdayTargetMin,
    weekendTargetMin: row.weekendTargetMin,
    checkInEveryDays: row.checkInEveryDays,
    status: ExperimentStatus.fromDb(row.status),
    extensions: _decodeExtensions(row.extensionsJson),
    outcome: ExperimentOutcome.fromDb(row.outcome),
    conclusionNote: row.conclusionNote,
    concludedOn: row.concludedOn,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    revision: row.revision,
  );

  static ExperimentCheckIn _checkInFromRow(ExperimentCheckInRow row) =>
      ExperimentCheckIn(
        id: row.id,
        experimentId: row.experimentId,
        slotDate: row.slotDate,
        note: row.note,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  static List<ExperimentExtension> _decodeExtensions(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        ExperimentExtension.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  static void _requireDate(String value, String field) {
    if (!isValidIsoDate(value)) {
      throw ArgumentError('$field must be a yyyy-MM-dd date');
    }
  }

  static void _requireTarget(int value, String field) {
    if (value < 0 || value > _maxTarget) {
      throw ArgumentError('$field must be 0 to $_maxTarget');
    }
  }

  /// Trimmed text of 1 to [maxRunes] code points.
  static String _requiredText(String value, String field, int maxRunes) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.runes.length > maxRunes) {
      throw ArgumentError('$field must be 1 to $maxRunes characters');
    }
    return trimmed;
  }

  /// Trimmed text of up to [maxRunes] code points; null when empty.
  static String? _optionalText(String? value, String field, int maxRunes) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.runes.length > maxRunes) {
      throw ArgumentError('$field must be at most $maxRunes characters');
    }
    return trimmed;
  }
}
