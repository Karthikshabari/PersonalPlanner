import '../../../core/database/app_database.dart';
import '../domain/initial_sync_models.dart';
import 'planner_data_probe.dart';

/// Durable, account-scoped persistence of the Phase G first-sync state.
///
/// The state lives in `app_settings` of the account database under the
/// `sync.initial_sync.` prefix. Because the database file itself is derived
/// from the canonical `(projectRef, authUserId)` scope, Project A / user X can
/// never reuse Project B / user X's first-sync state.
class InitialSyncStateStore {
  InitialSyncStateStore(this._db);

  static const String prefix = 'sync.initial_sync.';
  static const String phaseKey = '${prefix}phase';
  static const String claimTokenKey = '${prefix}claim_token';
  static const String baselineKey = '${prefix}baseline_change_id';
  static const String detailKey = '${prefix}detail';
  static const String updatedAtKey = '${prefix}updated_at';

  final AppDatabase _db;

  Future<InitialSyncRecord> read() async =>
      _decode(await _db.syncDao.readSettingsWithPrefix(prefix));

  Stream<InitialSyncRecord> watch() =>
      _db.syncDao.watchSettingsWithPrefix(prefix).map(_decode);

  Future<void> write(InitialSyncRecord record) async {
    final now = record.updatedAt ?? DateTime.now().toUtc();
    final values = <String, String>{
      phaseKey: record.phase.wireValue,
      updatedAtKey: now.toIso8601String(),
    };
    final claimToken = record.claimToken;
    final baseline = record.observedBaselineChangeId;
    final detail = record.detail;
    // One transaction: a crash can never leave a phase that disagrees with its
    // claim token or baseline.
    await _db.transaction(() async {
      await _db.syncDao.writeSettings(values);
      if (claimToken == null) {
        await _db.syncDao.deleteSetting(claimTokenKey);
      } else {
        await _db.syncDao.setSetting(claimTokenKey, claimToken);
      }
      if (baseline == null) {
        await _db.syncDao.deleteSetting(baselineKey);
      } else {
        await _db.syncDao.setSetting(baselineKey, '$baseline');
      }
      if (detail == null) {
        await _db.syncDao.deleteSetting(detailKey);
      } else {
        await _db.syncDao.setSetting(detailKey, encodeInitialSyncDetail(detail));
      }
    });
  }

  /// Atomically publishes `phase = complete` **only while** the durable outbox
  /// holds no local Planner operation.
  ///
  /// This is the completion gate of the remote-first restore. Its two
  /// statements run in one SQLite transaction, and the first statement writes
  /// (`INSERT ... DO NOTHING`), so SQLite takes the write lock before the
  /// conditional `UPDATE` evaluates the outbox predicate. A local Planner
  /// mutation is a separate transaction on this same database connection, so it
  /// can only be ordered
  ///
  ///  * before this transaction: its `sync_log` row is visible to the predicate
  ///    and the transition is refused (`false`), or
  ///  * after this transaction commits: `complete` is already durable and
  ///    ordinary post-baseline synchronization owns the mutation.
  ///
  /// There is therefore no instant where a local mutation can commit between
  /// the clean decision and the durable completion transition.
  ///
  /// [onBoundary] is a test-only seam: it runs inside this transaction, after
  /// the caller's clean pre-check and before the conditional statement, so a
  /// test can inject a genuine local write at exactly the boundary. Production
  /// never sets it.
  Future<bool> writeCompleteIfLocalWorkClean(
    InitialSyncRecord record, {
    Future<void> Function()? onBoundary,
  }) async {
    var completed = false;
    await _db.transaction(() async {
      if (onBoundary != null) await onBoundary();
      // Make sure the phase row exists without ever clobbering an existing
      // value; this write also acquires the connection's write lock.
      await _db.customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO NOTHING',
        [phaseKey, InitialSyncPhase.unresolved.wireValue],
      );
      await _db.customStatement(
        'UPDATE app_settings SET value = ? WHERE key = ? AND NOT EXISTS ('
        'SELECT 1 FROM sync_log WHERE state IN '
        '${PlannerDataProbe.activeOperationStatesSql})',
        [InitialSyncPhase.complete.wireValue, phaseKey],
      );
      final changed =
          (await _db.customSelect('SELECT changes() AS count').getSingle())
              .read<int>('count');
      if (changed == 0) return;
      completed = true;
      final now = record.updatedAt ?? DateTime.now().toUtc();
      await _db.syncDao.setSetting(updatedAtKey, now.toIso8601String());
      final claimToken = record.claimToken;
      final baseline = record.observedBaselineChangeId;
      final detail = record.detail;
      if (claimToken == null) {
        await _db.syncDao.deleteSetting(claimTokenKey);
      } else {
        await _db.syncDao.setSetting(claimTokenKey, claimToken);
      }
      if (baseline == null) {
        await _db.syncDao.deleteSetting(baselineKey);
      } else {
        await _db.syncDao.setSetting(baselineKey, '$baseline');
      }
      if (detail == null) {
        await _db.syncDao.deleteSetting(detailKey);
      } else {
        await _db.syncDao.setSetting(detailKey, encodeInitialSyncDetail(detail));
      }
    });
    return completed;
  }

  static InitialSyncRecord _decode(Map<String, String> settings) {
    final phase =
        InitialSyncPhase.tryParse(settings[phaseKey]) ??
        InitialSyncPhase.unresolved;
    final token = settings[claimTokenKey];
    final baseline = int.tryParse(settings[baselineKey] ?? '');
    return InitialSyncRecord(
      phase: phase,
      claimToken: token == null || token.isEmpty ? null : token,
      observedBaselineChangeId: baseline,
      detail: decodeInitialSyncDetail(settings[detailKey]),
      updatedAt: DateTime.tryParse(settings[updatedAtKey] ?? '')?.toUtc(),
    );
  }
}
