import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/day_context.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/day_context_presets.dart';
import '../providers/day_context_presets_provider.dart';
import '../providers/day_context_providers.dart';

Future<bool?> showDayContextEditor(
  BuildContext context, {
  required String date,
  DayContext? initial,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DayContextEditor(date: date, initial: initial),
  );
}

class DayContextEditor extends ConsumerStatefulWidget {
  final String date;
  final DayContext? initial;

  const DayContextEditor({super.key, required this.date, this.initial});

  @override
  ConsumerState<DayContextEditor> createState() => _DayContextEditorState();
}

class _DayContextEditorState extends ConsumerState<DayContextEditor> {
  /// The chosen label: a preset name, or the day's old label.
  String? _selected;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial?.label;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final date = parseIsoDate(widget.date);
    final presets =
        ref.watch(dayContextPresetsProvider).value ?? defaultDayContextPresets;
    final initial = widget.initial;
    // A label no preset has any more (an old custom label, or a preset since
    // renamed or deleted) stays as an extra row, selected, so Save keeps it.
    final oldLabel =
        initial != null &&
            DayContextPresets.indexOfLabel(presets, initial.label) < 0
        ? initial.label
        : null;
    final selectedKey = _selected == null
        ? null
        : DayContextPresets.normalize(_selected!);
    Widget option(String label, {required bool isBreak, String? note}) {
      final selected = DayContextPresets.normalize(label) == selectedKey;
      return ListTile(
        key: ValueKey('day-context-option-$label'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        selected: selected,
        enabled: !_busy,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        title: Text(note == null ? label : '$label $note'),
        trailing: isBreak
            ? Text(
                'Break',
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              )
            : null,
        onTap: () => setState(() {
          _selected = label;
          _error = null;
        }),
      );
    }

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Day context · ${DateFormat('EEE, MMM d').format(date)}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final preset in presets)
                  option(preset.name, isBreak: preset.isBreak),
                if (oldLabel != null)
                  option(
                    oldLabel,
                    isBreak: false,
                    note: initial!.kind == DayContextKind.custom
                        ? '(old custom)'
                        : '(old)',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    key: const ValueKey('day-context-error'),
                    style: TextStyle(color: tokens.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          if (initial != null && initial.deletedAt == null)
            TextButton(
              key: const ValueKey('day-context-remove'),
              onPressed: _busy ? null : _remove,
              child: const Text('Remove'),
            ),
          FilledButton(
            key: const ValueKey('day-context-save'),
            onPressed: _busy || _selected == null ? null : _save,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final label = _selected;
    if (label == null) return;
    final initial = widget.initial;
    // The day's own label, unchanged: nothing to write.
    if (initial != null &&
        initial.deletedAt == null &&
        initial.label == label) {
      Navigator.of(context).pop(false);
      return;
    }
    final kind = DayContextPresets.kindForName(label);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dayContextRepositoryProvider)
          .save(
            widget.date,
            kind,
            kind == DayContextKind.custom ? label : null,
            expectedRevision: initial?.revision,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _remove() async {
    final initial = widget.initial;
    if (initial == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dayContextRepositoryProvider)
          .remove(initial.id, expectedRevision: initial.revision);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }
}

/// Shared Day and Week header action. The visible label may be truncated, but
/// its full text remains available through semantics and the tooltip.
class DayContextAction extends ConsumerWidget {
  final DateTime date;
  final bool compact;

  const DayContextAction({super.key, required this.date, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dayContextForDateProvider(date));
    final current = async.value;
    final fullLabel = current == null
        ? 'Add day context'
        : 'Day context: ${current.displayLabel}';
    final visibleLabel = current == null
        ? 'Add day context'
        : current.displayLabel;
    return Semantics(
      button: true,
      label: fullLabel,
      child: Tooltip(
        message: fullLabel,
        child: TextButton.icon(
          key: ValueKey('day-context-action-${isoDateString(date)}'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
              vertical: compact ? 2 : AppSpacing.xs,
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(
            current?.kind == DayContextKind.travel
                ? Icons.luggage_outlined
                : current?.kind == DayContextKind.holiday
                ? Icons.celebration_outlined
                : current?.kind == DayContextKind.leave
                ? Icons.event_busy_outlined
                : current?.kind == DayContextKind.office
                ? Icons.business_outlined
                : current == null
                ? Icons.add_circle_outline
                : Icons.label_outline,
            size: compact ? 15 : 17,
          ),
          label: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 120 : 220),
            child: Text(
              visibleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          onPressed: () => showDayContextEditor(
            context,
            date: isoDateString(date),
            initial: current,
          ),
        ),
      ),
    );
  }
}
