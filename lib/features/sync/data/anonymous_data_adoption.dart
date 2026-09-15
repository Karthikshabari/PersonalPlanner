import '../../../core/database/app_database.dart';
import '../../categories/data/category_repository.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../settings/data/backup_codec.dart';
import '../../settings/data/backup_database_applier.dart';
import '../../settings/data/backup_merge_planner.dart';

const _adoptionDecisionKey = 'sync.anonymous_adoption_decision';

/// Counts are deliberately read from both databases so the UI can explain
/// what will be copied before the user confirms. The anonymous database is
/// never deleted by this service.
class AnonymousDataSummary {
  final int anonymousRecords;
  final int accountRecords;
  final String? decision;

  const AnonymousDataSummary({
    required this.anonymousRecords,
    required this.accountRecords,
    required this.decision,
  });

  bool get hasAnonymousData => anonymousRecords > 0;
  bool get keptSeparate => decision == 'separate';
}

class AnonymousDataAdoptionResult {
  final int copiedRecords;
  final int alreadyPresentRecords;

  const AnonymousDataAdoptionResult({
    required this.copiedRecords,
    required this.alreadyPresentRecords,
  });
}

class AnonymousDataAdoptionException implements Exception {
  final String message;

  const AnonymousDataAdoptionException(this.message);

  @override
  String toString() => message;
}

/// Copies anonymous rows into the currently authenticated account database.
/// Inserts are idempotent by local primary key, are ordered around foreign
/// keys, and leave the source database untouched for recovery/confirmation.
class AnonymousDataAdoptionService {
  AnonymousDataAdoptionService(
    this._accountDatabase, {
    Future<AppDatabase> Function()? anonymousDatabaseFactory,
  }) : _anonymousDatabaseFactory = anonymousDatabaseFactory ?? AppDatabase.open;

  final AppDatabase _accountDatabase;
  final Future<AppDatabase> Function() _anonymousDatabaseFactory;

  static const _tables = [
    'day_contexts',
    'categories',
    'tags',
    'recurring_rules',
    'tasks',
    'task_templates',
    'daily_reviews',
    'weekly_reviews',
    'subtasks',
    'task_tags',
    'timer_sessions',
  ];

  Future<AnonymousDataSummary> inspect() async {
    final anonymous = await _anonymousDatabaseFactory();
    try {
      return AnonymousDataSummary(
        anonymousRecords: await _countRows(anonymous),
        accountRecords: await _countRows(_accountDatabase),
        decision: await _decision(_accountDatabase),
      );
    } finally {
      await anonymous.close();
    }
  }

  Future<void> keepSeparate() async {
    await _accountDatabase
        .into(_accountDatabase.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _adoptionDecisionKey,
            value: 'separate',
          ),
        );
  }

  Future<AnonymousDataAdoptionResult> adopt() async {
    final anonymous = await _anonymousDatabaseFactory();
    try {
      // Both stores are captured as portable snapshots before any account
      // write. The account snapshot is recaptured inside its transaction so
      // a concurrent account mutation cannot turn a previously equal ID into
      // an unchecked overwrite.
      final incoming = await BackupCodec.exportData(anonymous);
      late BackupMergePlan plan;

      // defer_foreign_keys allows task reschedule links to refer to a task
      // later in the same batch while the transaction remains atomic.
      await _accountDatabase.transaction(() async {
        await _accountDatabase.customStatement(
          'PRAGMA defer_foreign_keys = ON',
        );
        final local = await BackupCodec.exportData(_accountDatabase);
        plan = BackupMergePlanner().build(
          incoming: incoming,
          local: local,
          rowEquivalence: _adoptionRowEquivalence,
          settingEquivalence: _adoptionSettingEquivalence,
        );
        if (plan.conflicts.isNotEmpty) {
          final first = plan.conflicts.first;
          throw AnonymousDataAdoptionException(
            'Anonymous data conflicts with ${first.table} ${first.id}. '
            'Resolve it before importing anonymous data.',
          );
        }
        await BackupDatabaseApplier(_accountDatabase).applyMerge(plan);
        await _retainSourceOnboardingCompletion(incoming);
        await _accountDatabase
            .into(_accountDatabase.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: _adoptionDecisionKey,
                value: 'imported',
              ),
            );
      });
      final incomingRecords = _tables.fold<int>(
        0,
        (count, table) => count + (incoming[table] as List).length,
      );
      return AnonymousDataAdoptionResult(
        copiedRecords: plan.insertedCount,
        alreadyPresentRecords: incomingRecords - plan.insertedCount,
      );
    } finally {
      await anonymous.close();
    }
  }

  Future<int> _countRows(AppDatabase database) async {
    var total = 0;
    for (final table in _tables) {
      final result = await database
          .customSelect('SELECT COUNT(*) AS count FROM $table')
          .getSingle();
      total += result.read<int>('count');
    }
    return total;
  }

  Future<String?> _decision(AppDatabase database) async {
    final row =
        await (database.select(database.appSettings)
              ..where((setting) => setting.key.equals(_adoptionDecisionKey)))
            .getSingleOrNull();
    return row?.value;
  }

  static bool _adoptionRowEquivalence(
    String table,
    Map<String, dynamic> local,
    Map<String, dynamic> incoming,
  ) {
    if (table != 'categories') return false;

    final id = incoming['id'];
    if (id is! String || local['id'] != id) return false;
    for (final definition in CategoryRepository.defaultCategoryDefinitions) {
      if (CategoryRepository.defaultCategoryId(definition.key) != id) {
        continue;
      }
      return _isUntouchedDefault(local, definition) &&
          _isUntouchedDefault(incoming, definition);
    }
    return false;
  }

  static bool _isUntouchedDefault(
    Map<String, dynamic> row,
    ({String key, String name, String colorHex, int sortOrder, bool isFocus})
    definition,
  ) =>
      row['id'] == CategoryRepository.defaultCategoryId(definition.key) &&
      row['name'] == definition.name &&
      row['color_hex'] == definition.colorHex &&
      row['sort_order'] == definition.sortOrder &&
      row['is_focus'] == definition.isFocus &&
      row['deleted_at'] == null;

  static bool _adoptionSettingEquivalence(
    String key,
    String local,
    String incoming,
  ) =>
      key == onboardingCompletedKey &&
      const {'true', 'false'}.contains(local) &&
      const {'true', 'false'}.contains(incoming);

  Future<void> _retainSourceOnboardingCompletion(
    Map<String, dynamic> incoming,
  ) async {
    final settings = incoming['settings'];
    if (settings is! Map || settings[onboardingCompletedKey] != 'true') {
      return;
    }
    if (await _accountDatabase.syncDao.getSetting(onboardingCompletedKey) !=
        'true') {
      await _accountDatabase.syncDao.setSetting(onboardingCompletedKey, 'true');
    }
  }
}
