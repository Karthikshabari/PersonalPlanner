import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/adaptive_layout.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../inbox/providers/inbox_provider.dart';
import '../../../onboarding/providers/onboarding_provider.dart';
import '../../../recurring/providers/recurring_providers.dart';
import '../../../review/providers/review_providers.dart';
import '../../providers/notification_settings_providers.dart';
import '../../data/backup_service.dart';
import '../../../task_editor/providers/subtask_providers.dart';
import '../../../task_editor/providers/tag_providers.dart';
import '../../../templates/providers/template_providers.dart';
import '../../../timeline/presentation/providers/day_tasks_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../../timeline/presentation/providers/grid_settings_provider.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _backupBusy = false;
  String? _backupMessage;
  String? _backupError;

  void _openSecondary(BuildContext context, String location) {
    if (isDesktopWidth(MediaQuery.sizeOf(context).width)) {
      context.go(location);
    } else {
      context.push(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gridAsync = ref.watch(gridIntervalProvider);
    final themeAsync = ref.watch(themeModeProvider);
    if (gridAsync.hasError || themeAsync.hasError) {
      final error = gridAsync.hasError ? gridAsync.error! : themeAsync.error!;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: const [SyncStatusAction()],
        ),
        body: ErrorPanel(
          message: friendlyErrorMessage(error),
          onRetry: () {
            ref.invalidate(gridIntervalProvider);
            ref.invalidate(themeModeProvider);
          },
        ),
      );
    }
    if (!gridAsync.hasValue || !themeAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final gridInterval = gridAsync.requireValue;
    final themeMode = themeAsync.requireValue;
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [SyncStatusAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl,
          ),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Categories'),
                subtitle: const Text('Manage categories and colors'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSecondary(context, '/categories'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                key: const ValueKey('tags-tile'),
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Tags'),
                subtitle: const Text('Manage task tags'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSecondary(context, '/settings/tags'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                key: const ValueKey('templates-tile'),
                leading: const Icon(Icons.bookmark_border_outlined),
                title: const Text('Task Templates'),
                subtitle: const Text('Reusable task presets'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSecondary(context, '/templates'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                key: const ValueKey('notifications-tile'),
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: const Text('Daily review reminder'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSecondary(context, '/settings/notifications'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: ListTile(
                key: const ValueKey('sync-tile'),
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Sync'),
                subtitle: const Text('Account, offline mode and sync status'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openSecondary(context, '/settings/sync'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.grid_on_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Timeline grid interval',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Snap spacing for drag, resize and quick create',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DropdownButton<int>(
                        key: const ValueKey('grid-interval-dropdown'),
                        value: gridInterval,
                        items: [
                          for (final minutes in AppConstants.gridOptions)
                            DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes min'),
                            ),
                        ],
                        onChanged: (minutes) {
                          if (minutes == null) return;
                          _runPreferenceChange(
                            () => ref
                                .read(gridIntervalProvider.notifier)
                                .setInterval(minutes),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const Icon(Icons.brightness_6_outlined),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appearance',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'System, light or dark',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<ThemeMode>(
                      key: const ValueKey('theme-mode-dropdown'),
                      value: themeMode,
                      items: [
                        for (final mode in ThemeMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(_themeModeLabel(mode)),
                          ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          _runPreferenceChange(
                            () => ref
                                .read(themeModeProvider.notifier)
                                .setMode(mode),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildBackupCard(context),
            if (_backupMessage != null || _backupError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              if (_backupError != null)
                ErrorPanel(message: _backupError!, compact: true)
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(_backupMessage!),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runPreferenceChange(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Widget _buildBackupCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.import_export_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup and restore',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Export your local data or import a validated backup',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('backup-export-button'),
                onPressed: _backupBusy ? null : _exportBackup,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export backup'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('backup-import-button'),
                onPressed: _backupBusy ? null : _showImportDialog,
                icon: const Icon(Icons.upload_outlined),
                label: const Text('Import backup'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _exportBackup() async {
    setState(() {
      _backupBusy = true;
      _backupError = null;
      _backupMessage = null;
    });
    try {
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export Personal Planner backup',
        fileName: 'personal_planner_backup_$timestamp.json',
        bytes: Uint8List.fromList(
          utf8.encode(
            await BackupService(ref.read(appDatabaseProvider)).exportJson(),
          ),
        ),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (uri == null) return;
      if (mounted) {
        setState(() => _backupMessage = 'Backup exported to $uri');
      }
    } catch (error) {
      if (mounted) setState(() => _backupError = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _showImportDialog() async {
    var replace = false;
    var ownershipConfirmed = false;
    final choice = await showDialog<({bool replace, bool ownershipConfirmed})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose a Personal Planner JSON backup. The file will be validated before any data is changed.',
                ),
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ownershipConfirmed,
                  onChanged: (value) =>
                      setDialogState(() => ownershipConfirmed = value ?? false),
                  title: const Text(
                    'I own this backup and approve this import',
                  ),
                  subtitle: const Text(
                    'This explicitly adopts the file into the current local account.',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: replace,
                  onChanged: (value) =>
                      setDialogState(() => replace = value ?? false),
                  title: const Text('Replace local data'),
                  subtitle: const Text(
                    'Merge is safer. Replace needs confirmation and creates a pre-import backup.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: ownershipConfirmed
                  ? () => Navigator.of(dialogContext).pop((
                      replace: replace,
                      ownershipConfirmed: ownershipConfirmed,
                    ))
                  : null,
              child: const Text('Validate and import'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final selected = await FilePicker.pickFile(
      dialogTitle: 'Choose Personal Planner backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (!mounted || selected == null) return;
    await _importBackup(
      selected,
      replace: choice.replace,
      ownershipConfirmed: choice.ownershipConfirmed,
    );
  }

  Future<void> _importBackup(
    PlatformFile selected, {
    required bool replace,
    required bool ownershipConfirmed,
  }) async {
    setState(() {
      _backupBusy = true;
      _backupError = null;
      _backupMessage = null;
    });
    try {
      final source = utf8.decode(
        await selected.readAsBytes(),
        allowMalformed: false,
      );
      final service = BackupService(ref.read(appDatabaseProvider));
      if (replace) {
        final preImport = await service.exportJson();
        final directory = await getApplicationDocumentsDirectory();
        final recovery = File(
          '${directory.path}/personal_planner_pre_import_backup.json',
        );
        await recovery.writeAsString(preImport);
        if (!mounted) return;
        final confirmed = await showConfirmDialog(
          context,
          title: 'Replace local data?',
          message: 'All current local planner data will be replaced. A recovery backup was saved first.',
          confirmLabel: 'Replace',
        );
        if (!confirmed) return;
        await service.replaceFromJson(
          source,
          preImportBackup: preImport,
          confirmed: true,
          ownershipConfirmed: ownershipConfirmed,
        );
        _invalidatePortableProviders();
        if (mounted) setState(() => _backupMessage = 'Backup restored.');
      } else {
        final result = await service.importJson(
          source,
          ownershipConfirmed: ownershipConfirmed,
        );
        _invalidatePortableProviders();
        if (mounted) {
          setState(
            () => _backupMessage = result.hasConflicts
                ? 'Imported ${result.inserted} row(s); ${result.conflicts.length} conflict(s) were preserved.'
                : 'Imported ${result.inserted} row(s); skipped ${result.skipped} unchanged row(s).',
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _backupError = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _invalidatePortableProviders() {
    ref.invalidate(analyticsSnapshotProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(inboxClockProvider);
    ref.invalidate(inboxProvider);
    ref.invalidate(onboardingCompletedProvider);
    ref.invalidate(recurringRuleProvider);
    ref.invalidate(dayMaterializationProvider);
    ref.invalidate(dailyReviewProvider);
    ref.invalidate(weeklyReviewProvider);
    ref.invalidate(dailyStatsProvider);
    ref.invalidate(weeklyStatsProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(tagsForTaskProvider);
    ref.invalidate(subtasksForTaskProvider);
    ref.invalidate(subtaskCountsProvider);
    ref.invalidate(templatesProvider);
    ref.invalidate(dayTasksProvider);
    ref.invalidate(dayTasksForDateProvider);
    ref.invalidate(selectedTaskByIdProvider);
    ref.invalidate(gridIntervalProvider);
    ref.invalidate(themeModeProvider);
    ref.invalidate(reviewReminderEnabledProvider);
    ref.invalidate(reviewReminderMinutesProvider);
  }

  static String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
