import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../sync/presentation/widgets/sync_status_action.dart';
import '../domain/day_context_presets.dart';
import '../providers/day_context_presets_provider.dart';

/// Settings › Day contexts: the presets the "Add day context" dialog offers,
/// each with a Break day switch. Renaming or deleting a preset leaves the
/// days that use it with their old label, so changing a break preset or its
/// switch asks first how many past days stop or start counting as breaks.
class DayContextPresetsScreen extends ConsumerWidget {
  const DayContextPresetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppThemeTokens.of(context);
    final async = ref.watch(dayContextPresetsProvider);
    final presets = async.value;
    final notifier = ref.read(dayContextPresetsProvider.notifier);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Day contexts'),
        actions: const [SyncStatusAction()],
      ),
      body: presets == null
          ? Center(
              child: async.hasError
                  ? const Text('Could not load day contexts.')
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'A break day counts in nothing: no streak, no totals, no '
                  'reasons asked. Presets are kept on this device and in '
                  'backups; other devices keep their own.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < presets.length; i++)
                        ListTile(
                          key: ValueKey('day-context-preset-$i'),
                          title: Text(presets[i].name),
                          leading: FittedBox(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(
                                  label: 'Break day: ${presets[i].name}',
                                  child: Switch(
                                    key: ValueKey(
                                      'day-context-preset-break-$i',
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    value: presets[i].isBreak,
                                    onChanged: (value) => _setBreak(
                                      context,
                                      notifier,
                                      presets[i],
                                      i,
                                      value,
                                    ),
                                  ),
                                ),
                                // The switch already announces "Break day".
                                ExcludeSemantics(
                                  child: Text(
                                    'Break day',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey('day-context-preset-rename-$i'),
                                tooltip: 'Rename ${presets[i].name}',
                                icon: Icon(
                                  Icons.edit_outlined,
                                  semanticLabel: 'Rename ${presets[i].name}',
                                ),
                                onPressed: () => _showNameDialog(
                                  context,
                                  title: 'Rename day context',
                                  initial: presets[i].name,
                                  submit: (name) => _rename(
                                    context,
                                    notifier,
                                    presets,
                                    i,
                                    name,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('day-context-preset-delete-$i'),
                                tooltip: 'Delete ${presets[i].name}',
                                icon: Icon(
                                  Icons.delete_outline,
                                  semanticLabel: 'Delete ${presets[i].name}',
                                ),
                                onPressed: presets.length <= 1
                                    ? null
                                    : () => _delete(
                                        context,
                                        notifier,
                                        presets,
                                        i,
                                      ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('day-context-preset-add'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add preset'),
                      onPressed: DayContextPresets.canAdd(presets)
                          ? () => _showNameDialog(
                              context,
                              title: 'Add day context',
                              initial: '',
                              submit: notifier.add,
                            )
                          : null,
                    ),
                    if (!DayContextPresets.canAdd(presets))
                      Text(
                        'Maximum $maxDayContextPresets',
                        key: const ValueKey('day-context-preset-max'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    TextButton(
                      key: const ValueKey('day-context-preset-reset'),
                      onPressed: () => _confirmReset(context, notifier),
                      child: const Text('Reset to defaults'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Asks before a change reclassifies past days: when [preset] is the one that
/// decides [count] past days, say how many start ([becomesBreak]) or stop
/// counting as break days. True when there is nothing to ask or the user
/// agreed.
Future<bool> _confirmReclassify(
  BuildContext context,
  DayContextPresetsNotifier notifier,
  DayContextPreset preset, {
  required bool becomesBreak,
}) async {
  final count = await notifier.pastDayCountForPreset(preset.name);
  if (count == 0 || !context.mounted) return count == 0;
  final days = count == 1 ? '1 past day' : '$count past days';
  final what = count == 1 ? 'a break day' : 'break days';
  return showConfirmDialog(
    context,
    title: 'Change break days?',
    message: becomesBreak
        ? '$days will count as $what.'
        : '$days will no longer count as $what.',
    confirmLabel: 'Continue',
    destructive: false,
  );
}

Future<void> _setBreak(
  BuildContext context,
  DayContextPresetsNotifier notifier,
  DayContextPreset preset,
  int index,
  bool isBreak,
) async {
  if (await _confirmReclassify(
    context,
    notifier,
    preset,
    becomesBreak: isBreak,
  )) {
    await notifier.setBreak(index, isBreak);
  }
}

/// Validates [name] first so a refused name never opens the question. Cancel
/// closes the name dialog and writes nothing.
Future<String?> _rename(
  BuildContext context,
  DayContextPresetsNotifier notifier,
  List<DayContextPreset> presets,
  int index,
  String name,
) async {
  final error = DayContextPresets.validateName(
    presets,
    name,
    exceptIndex: index,
  );
  if (error != null) return error;
  final preset = presets[index];
  final reclassifies =
      preset.isBreak &&
      DayContextPresets.normalize(name) !=
          DayContextPresets.normalize(preset.name);
  if (reclassifies &&
      !await _confirmReclassify(
        context,
        notifier,
        preset,
        becomesBreak: false,
      )) {
    return null;
  }
  return notifier.rename(index, name);
}

/// Deletes at once (after the question for a break preset that past days
/// use); the snackbar's Undo writes the previous list back, but only while the
/// list is still the one the delete produced.
Future<void> _delete(
  BuildContext context,
  DayContextPresetsNotifier notifier,
  List<DayContextPreset> previous,
  int index,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = previous[index].name;
  if (previous[index].isBreak &&
      !await _confirmReclassify(
        context,
        notifier,
        previous[index],
        becomesBreak: false,
      )) {
    return;
  }
  await notifier.remove(index);
  final afterDelete = [...previous]..removeAt(index);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Deleted $name'),
      // A snackbar with an action never times out unless told to (Flutter
      // defaults persist to true); match the review snackbars.
      persist: false,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => notifier.restoreIfUnchanged(previous, afterDelete),
      ),
    ),
  );
}

Future<void> _confirmReset(
  BuildContext context,
  DayContextPresetsNotifier notifier,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reset to defaults?'),
      content: const Text(
        'Your presets are replaced by the default list. Days already '
        'labelled with a removed or renamed preset keep their label, but '
        "stop counting as break days if that preset's Break switch was on.",
      ),
      actions: [
        TextButton(
          key: const ValueKey('day-context-preset-reset-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('day-context-preset-reset-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (confirmed == true) await notifier.resetToDefaults();
}

/// A name field with inline validation. [submit] returns the validation
/// message, or null once the name is stored.
Future<void> _showNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required Future<String?> Function(String name) submit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, submit: submit),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.submit,
  });

  final String title;
  final String initial;
  final Future<String?> Function(String name) submit;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final error = await widget.submit(_controller.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('day-context-preset-name'),
        controller: _controller,
        autofocus: true,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxDayContextPresetNameLength),
        ],
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _busy ? null : _save(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('day-context-preset-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
