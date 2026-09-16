import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/sync_dao.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../data/anonymous_data_adoption.dart';
import '../../data/auth_repository.dart';
import '../../data/sync_repository.dart';
import '../../domain/auth_session_controller.dart';
import '../../providers/sync_providers.dart';
import '../../providers/sync_settings_provider.dart';
import '../../domain/sync_models.dart';
import '../widgets/cloud_setup_card.dart';
import '../widgets/sync_status_action.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    ref.listen(syncStatusProvider, (previous, next) {
      final current = next.value;
      if (current != null &&
          current.state != SyncEngineState.synced &&
          current.state != SyncEngineState.syncing &&
          current.state != SyncEngineState.pending &&
          current.state != SyncEngineState.offline &&
          current.state != SyncEngineState.refreshPaused &&
          current.state != previous?.value?.state &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current.message ?? 'Sync failed; retry scheduled.'),
          ),
        );
      }
    });
    final sessionAsync = ref.watch(authSessionProvider);
    final authController = ref.watch(authSessionControllerProvider);
    final statusAsync = ref.watch(syncStatusProvider);
    final enabledAsync = ref.watch(syncEnabledProvider);
    final conflictsAsync = ref.watch(syncConflictsProvider);
    final permanentAsync = ref.watch(syncPermanentOperationsProvider);
    final quarantineAsync = ref.watch(syncQuarantinedChangesProvider);
    if (sessionAsync.hasError ||
        statusAsync.hasError ||
        enabledAsync.hasError ||
        conflictsAsync.hasError ||
        permanentAsync.hasError ||
        quarantineAsync.hasError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sync'),
          actions: const [SyncStatusAction()],
        ),
        body: ErrorPanel(
          message: friendlyErrorMessage(
            sessionAsync.error ??
                statusAsync.error ??
                enabledAsync.error ??
                conflictsAsync.error ??
                permanentAsync.error ??
                quarantineAsync.error!,
          ),
          onRetry: () {
            ref.invalidate(authSessionProvider);
            ref.invalidate(syncStatusProvider);
            ref.invalidate(syncEnabledProvider);
            ref.invalidate(syncConflictsProvider);
            ref.invalidate(syncPermanentOperationsProvider);
            ref.invalidate(syncQuarantinedChangesProvider);
          },
        ),
      );
    }
    if (!sessionAsync.hasValue ||
        !statusAsync.hasValue ||
        !enabledAsync.hasValue ||
        !conflictsAsync.hasValue ||
        !quarantineAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sync'),
          actions: const [SyncStatusAction()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final session = sessionAsync.requireValue;
    final status = statusAsync.requireValue;
    final enabled = enabledAsync.requireValue;
    final conflicts = conflictsAsync.requireValue;
    final permanentOperations = permanentAsync.value ?? const <SyncLogRow>[];
    final quarantinedChanges = quarantineAsync.requireValue;
    final adoptionSummary = session == null
        ? null
        : ref.watch(anonymousDataSummaryProvider);
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Sync'),
        actions: const [SyncStatusAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl,
          ),
          children: [
            if (quarantinedChanges.isNotEmpty) ...[
              _QuarantineCard(changes: quarantinedChanges),
              const SizedBox(height: 12),
            ],
            // User-owned Supabase setup. A build with static developer Supabase
            // configuration keeps the legacy path below instead, so the two
            // paths never compete for the same screen.
            if (!SupabaseConfig.isConfigured) ...[
              const CloudSetupCard(),
              const SizedBox(height: 12),
            ],
            if (!SupabaseConfig.isConfigured)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.cloud_off),
                  title: Text('Offline-only mode'),
                  subtitle: Text(
                    'Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY at build time '
                    'to enable account sync.',
                  ),
                ),
              )
            else if (session == null)
              _AuthForm()
            else ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(session.user.email ?? 'Signed-in account'),
                  subtitle: const Text(
                    'This account uses its own local SQLite database.',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Log out'),
                  ),
                ),
              ),
              if (kDebugMode && authController != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('Session diagnostics'),
                    subtitle: Text(
                      '${authController.diagnostics.length} sanitized in-memory event(s).',
                    ),
                    trailing: TextButton(
                      key: const ValueKey('auth-diagnostics-action'),
                      onPressed: () => _showAuthDiagnostics(authController),
                      child: const Text('View / export'),
                    ),
                  ),
                ),
              ],
              if (adoptionSummary != null)
                adoptionSummary.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ErrorPanel(
                      message: friendlyErrorMessage(error),
                      compact: true,
                    ),
                  ),
                  data: (summary) =>
                      summary.hasAnonymousData && !summary.keptSeparate
                      ? _AnonymousAdoptionCard(
                          summary: summary,
                          busy: _busy,
                          onImport: _importAnonymousData,
                          onKeepSeparate: _keepAnonymousDataSeparate,
                        )
                      : const SizedBox.shrink(),
                ),
              const SizedBox(height: 12),
              if (conflicts.isNotEmpty)
                _ConflictCard(
                  conflicts: conflicts,
                  busy: _busy,
                  onKeepLocal: _keepLocal,
                  onKeepRemote: _keepRemote,
                ),
              if (conflicts.isNotEmpty) const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Enable sync'),
                  subtitle: const Text(
                    'Disabling sync keeps the durable outbox and cursor intact.',
                  ),
                  value: enabled,
                  onChanged: (value) =>
                      ref.read(syncEnabledProvider.notifier).setEnabled(value),
                ),
              ),
              if (permanentOperations.isNotEmpty) ...[
                const SizedBox(height: 12),
                _PermanentFailureCard(
                  operations: permanentOperations,
                  busy: _busy,
                  onRepair: _repairPermanentOperation,
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(_statusIcon(status.state)),
                  title: Text(status.state.label),
                  subtitle: Text(
                    [
                      if (status.message != null) status.message!,
                      '${status.pendingOperations} pending operation(s)',
                      if (status.lastSuccessfulSync != null)
                        'Last sync: ${status.lastSuccessfulSync!.toLocal()}'
                      else
                        'Last sync: not yet completed',
                    ].join('\n'),
                  ),
                  trailing: FilledButton(
                    onPressed: enabled && !_busy
                        ? () => ref.read(syncEngineProvider)?.syncNow()
                        : null,
                    child: const Text('Sync now'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Anonymous data is never uploaded automatically'),
                  subtitle: Text(
                    'If this account has no local data, import from offline-only '
                    'mode only after explicit confirmation.',
                  ),
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Use offline-only mode'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider)?.signOut();
    } catch (error) {
      if (mounted) setState(() => _error = safeAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAuthDiagnostics(AuthSessionController controller) async {
    final diagnostics = const JsonEncoder.withIndent(
      '  ',
    ).convert(controller.diagnostics.map((entry) => entry.toJson()).toList());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sanitized session diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              diagnostics,
              key: const ValueKey('auth-diagnostics-content'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: diagnostics));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Sanitized diagnostics copied.'),
                  ),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _keepAnonymousDataSeparate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(anonymousDataAdoptionProvider).keepSeparate();
      ref.invalidate(anonymousDataSummaryProvider);
      if (mounted) {
        setState(() {
          _message = 'Anonymous data remains in offline-only mode.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save that choice.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importAnonymousData() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import anonymous data?'),
        content: const Text(
          'This copies the offline-only records into this signed-in account. '
          'The offline-only database is kept as a recovery copy. Any existing '
          'metadata or review conflicts must be resolved before import.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep separate'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (!choice) {
      await _keepAnonymousDataSeparate();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await ref.read(anonymousDataAdoptionProvider).adopt();
      ref.invalidate(anonymousDataSummaryProvider);
      if (mounted) {
        setState(() {
          _message =
              'Imported ${result.copiedRecords} record(s). '
              '${result.alreadyPresentRecords} already existed; sync will upload '
              'the imported records when online.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AnonymousDataAdoptionException ? error.message : 'Import could not be completed. The offline-only data was kept.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepLocal(String conflictId) => _resolveConflict(
    conflictId,
    (repository) => repository.keepLocal(conflictId),
  );

  Future<void> _keepRemote(String conflictId) => _resolveConflict(
    conflictId,
    (repository) => repository.keepRemote(conflictId),
  );

  Future<void> _resolveConflict(
    String conflictId,
    Future<void> Function(SyncRepository repository) resolve,
  ) async {
    final repository = ref.read(syncRepositoryProvider);
    if (repository == null) {
      setState(() => _error = 'Sign in and enable sync to resolve conflicts.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await resolve(repository);
      if (mounted) setState(() => _message = 'Conflict resolved.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Conflict could not be resolved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairPermanentOperation(String operationId) async {
    final repository = ref.read(syncRepositoryProvider);
    if (repository == null) {
      setState(
        () => _error = 'Sign in and enable sync to repair this failure.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.repairPermanentOperation(operationId);
      if (mounted) {
        setState(
          () => _message =
              'The repaired local record was queued. Sync it when ready.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SyncRepairException
              ? error.message
              : 'The sync failure could not be repaired safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _statusIcon(SyncEngineState? state) => switch (state) {
    SyncEngineState.synced => Icons.cloud_done,
    SyncEngineState.syncing => Icons.sync,
    SyncEngineState.pending => Icons.cloud_upload,
    SyncEngineState.offline => Icons.cloud_off,
    SyncEngineState.conflict => Icons.warning_amber,
    SyncEngineState.error => Icons.error_outline,
    SyncEngineState.partialSuccess => Icons.warning_amber,
    SyncEngineState.permanentFailure => Icons.report_problem_outlined,
    SyncEngineState.authFailure => Icons.lock_outline,
    SyncEngineState.refreshPaused => Icons.refresh,
    SyncEngineState.invalidData => Icons.data_object,
    _ => Icons.cloud_queue,
  };
}

class _QuarantineCard extends StatelessWidget {
  const _QuarantineCard({required this.changes});

  final List<SyncQuarantinedChange> changes;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Sync records need review'),
            subtitle: Text(
              'A remote change could not be applied safely. Your local data is '
              'still intact and the original payload is retained for repair.',
            ),
          ),
          for (final change in changes) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_changeLabel(change)),
              subtitle: Text(
                [
                  change.diagnostic,
                  if (change.recordedAt != null)
                    'Recorded: ${change.recordedAt!.toLocal()}',
                  'Automatic replay is disabled until the payload is repaired.',
                ].join('\n'),
              ),
              trailing: IconButton(
                tooltip: 'Copy sync review details',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _copyText(change))),
              ),
            ),
            if (change != changes.last) const Divider(),
          ],
        ],
      ),
    ),
  );

  static String _changeLabel(SyncQuarantinedChange change) {
    final table = switch (change.tableName) {
      'tasks' => 'Task',
      'categories' => 'Category',
      'tags' => 'Legacy metadata',
      'subtasks' => 'Subtask',
      'recurring_rules' => 'Recurring rule',
      'task_templates' => 'Template',
      'daily_reviews' => 'Daily review',
      'weekly_reviews' => 'Weekly review',
      'timer_sessions' => 'Timer session',
      'day_contexts' => 'Day context',
      'task_tags' => 'Legacy metadata link',
      _ => 'Remote record',
    };
    final identity = change.recordId == null || change.recordId!.isEmpty
        ? 'change ${change.changeId}'
        : change.recordId!;
    return '$table · $identity';
  }

  static String _copyText(SyncQuarantinedChange change) => [
    'Personal Planner sync review',
    _changeLabel(change),
    if (change.operation != null) 'Operation: ${change.operation}',
    'Diagnostic: ${change.diagnostic}',
    'Storage key: ${change.storageKey}',
  ].join('\n');
}

class _PermanentFailureCard extends StatelessWidget {
  const _PermanentFailureCard({
    required this.operations,
    required this.busy,
    required this.onRepair,
  });

  final List<SyncLogRow> operations;
  final bool busy;
  final ValueChanged<String> onRepair;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.build_circle_outlined),
            title: Text('Sync needs a repair'),
            subtitle: Text(
              'Edit the affected record first, then queue a validated snapshot. '
              'The invalid payload will never be retried unchanged.',
            ),
          ),
          for (final operation in operations) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_operationLabel(operation)),
              subtitle: Text(
                operation.lastError?.replaceFirst(
                      SyncDao.permanentErrorPrefix,
                      '',
                    ) ??
                    'Permanent sync error',
              ),
              trailing: OutlinedButton(
                onPressed: busy ? null : () => onRepair(operation.operationId),
                child: const Text('Retry repaired record'),
              ),
            ),
            if (operation != operations.last) const Divider(),
          ],
        ],
      ),
    ),
  );

  static String _operationLabel(SyncLogRow operation) {
    final table = switch (operation.entityTableName) {
      'tasks' => 'Task',
      'categories' => 'Category',
      'tags' => 'Legacy metadata',
      'subtasks' => 'Subtask',
      'recurring_rules' => 'Recurring rule',
      'task_templates' => 'Template',
      'daily_reviews' => 'Daily review',
      'weekly_reviews' => 'Weekly review',
      'timer_sessions' => 'Timer session',
      'task_tags' => 'Legacy metadata link',
      _ => 'Record',
    };
    return '$table · ${operation.recordId}';
  }
}

class _AnonymousAdoptionCard extends StatelessWidget {
  const _AnonymousAdoptionCard({
    required this.summary,
    required this.busy,
    required this.onImport,
    required this.onKeepSeparate,
  });

  final AnonymousDataSummary summary;
  final bool busy;
  final VoidCallback onImport;
  final VoidCallback onKeepSeparate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.move_to_inbox_outlined),
            title: Text('Offline-only data found'),
            subtitle: Text(
              'Choose explicitly whether to copy it into this account. '
              'Nothing is uploaded automatically.',
            ),
          ),
          Text('${summary.anonymousRecords} record(s) available to review.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : onImport,
                child: const Text('Import anonymous data'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onKeepSeparate,
                child: const Text('Keep it separate'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflicts,
    required this.busy,
    required this.onKeepLocal,
    required this.onKeepRemote,
  });

  final List<SyncConflictRow> conflicts;
  final bool busy;
  final ValueChanged<String> onKeepLocal;
  final ValueChanged<String> onKeepRemote;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.warning_amber),
            title: Text('Conflicts need a decision'),
            subtitle: Text(
              'Both snapshots are preserved locally. Choose which one to keep.',
            ),
          ),
          for (final conflict in conflicts) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_conflictTitle(conflict)),
              subtitle: Text(
                '${_conflictDetails(conflict)}\n'
                'Expected ${conflict.expectedServerVersion ?? 'new'} · '
                'server ${conflict.actualServerVersion ?? 'deleted'}',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => onKeepLocal(conflict.id),
                  child: const Text('Keep Local'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => onKeepRemote(conflict.id),
                  child: const Text('Keep Remote'),
                ),
              ],
            ),
            if (conflict != conflicts.last) const Divider(),
          ],
        ],
      ),
    ),
  );
}

String _conflictTitle(SyncConflictRow conflict) {
  final local = _snapshotMap(conflict.localSnapshot);
  final remote = _snapshotMap(conflict.remoteSnapshot);
  final value = local ?? remote;
  final label = switch (conflict.entityTableName) {
    'tasks' => 'Task',
    'categories' => 'Category',
    'tags' => 'Legacy metadata',
    'subtasks' => 'Subtask',
    'recurring_rules' => 'Recurring rule',
    'task_templates' => 'Template',
    'daily_reviews' => 'Daily review',
    'weekly_reviews' => 'Weekly review',
    'timer_sessions' => 'Timer session',
    'task_tags' => 'Legacy metadata link',
    _ => 'Record',
  };
  final name = value == null
      ? null
      : _displayName(conflict.entityTableName, value);
  return name == null || name.isEmpty ? label : '$label · $name';
}

String _conflictDetails(SyncConflictRow conflict) {
  final local = _snapshotMap(conflict.localSnapshot);
  final remote = _snapshotMap(conflict.remoteSnapshot);
  if (local == null || remote == null) {
    return 'Local and remote snapshots are preserved.';
  }
  final fields = <String>[];
  for (final key in {...local.keys, ...remote.keys}) {
    if (const {
      'id',
      'created_at',
      'updated_at',
      'server_version',
    }.contains(key)) {
      continue;
    }
    if (local[key] == remote[key]) continue;
    fields.add(_fieldLabel(key));
  }
  final changed = fields.isEmpty
      ? 'different snapshots'
      : fields.take(4).join(', ');
  final localState = _snapshotState(local);
  final remoteState = _snapshotState(remote);
  return 'Local: $localState · Remote: $remoteState · Changed: $changed';
}

Map<String, dynamic>? _snapshotMap(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on Object {
    return null;
  }
}

String _displayName(String table, Map<String, dynamic> snapshot) {
  final value = switch (table) {
    'tasks' || 'subtasks' => snapshot['title'],
    'categories' || 'tags' || 'task_templates' => snapshot['name'],
    'recurring_rules' => snapshot['task_title'],
    'daily_reviews' => snapshot['date'],
    'weekly_reviews' => snapshot['week_start_date'],
    _ => snapshot['id'],
  };
  final text = value?.toString().trim() ?? '';
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

String _snapshotState(Map<String, dynamic> snapshot) {
  if (snapshot['deleted_at'] != null || snapshot['deleted'] == true) {
    return 'deleted';
  }
  final status = snapshot['status'];
  return status == null ? 'active' : status.toString().replaceAll('_', ' ');
}

String _fieldLabel(String key) {
  if (const {'priority', 'tags_json', 'tag_id'}.contains(key)) {
    return 'Legacy metadata';
  }
  return key
      .replaceAll('_', ' ')
      .replaceFirstMapped(
        RegExp(r'^.'),
        (match) => match.group(0)!.toUpperCase(),
      );
}

class _AuthForm extends ConsumerStatefulWidget {
  const _AuthForm();

  @override
  ConsumerState<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<_AuthForm> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool registering = false;
  bool busy = false;
  String? error;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            registering ? 'Create account' : 'Log in',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('sync-email'),
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sync-password'),
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              child: Text(registering ? 'Register' : 'Log in'),
            ),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    registering = !registering;
                    error = null;
                    message = null;
                  }),
            child: Text(
              registering
                  ? 'Already have an account? Log in'
                  : 'Need an account? Register',
            ),
          ),
          if (message != null) Text(message!),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (auth == null) throw StateError('Sync is not configured');
      final response = registering
          ? await auth.signUp(email.text, password.text)
          : await auth.signIn(email.text, password.text);
      if (registering && response.session == null && mounted) {
        setState(() => message = 'Check your email to confirm the account.');
      }
    } catch (error) {
      if (mounted) setState(() => this.error = safeAuthError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
