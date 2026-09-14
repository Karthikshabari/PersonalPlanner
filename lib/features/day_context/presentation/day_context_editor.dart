import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/day_context.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/utils/date_utils.dart';
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
  final _formKey = GlobalKey<FormState>();
  late DayContextKind _kind;
  late final TextEditingController _customLabelController;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _kind = widget.initial?.kind ?? DayContextKind.office;
    _customLabelController = TextEditingController(
      text: widget.initial?.customLabel ?? '',
    );
  }

  @override
  void dispose() {
    _customLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final date = parseIsoDate(widget.date);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Day context · ${DateFormat('EEE, MMM d').format(date)}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<DayContextKind>(
                    key: const ValueKey('day-context-kind'),
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Context'),
                    items: [
                      for (final kind in DayContextKind.values)
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (kind) {
                            if (kind == null) return;
                            setState(() {
                              _kind = kind;
                              _error = null;
                            });
                          },
                  ),
                  if (_kind == DayContextKind.custom) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const ValueKey('day-context-custom-label'),
                      controller: _customLabelController,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Custom label',
                        hintText: 'Family visit',
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Enter a label.';
                        if (trimmed.length > 80) {
                          return 'Use 80 characters or fewer.';
                        }
                        return null;
                      },
                    ),
                  ],
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
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          if (widget.initial != null && widget.initial!.deletedAt == null)
            TextButton(
              key: const ValueKey('day-context-remove'),
              onPressed: _busy ? null : _remove,
              child: const Text('Remove'),
            ),
          FilledButton(
            key: const ValueKey('day-context-save'),
            onPressed: _busy ? null : _save,
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dayContextRepositoryProvider)
          .save(
            widget.date,
            _kind,
            _kind == DayContextKind.custom ? _customLabelController.text : null,
            expectedRevision: widget.initial?.revision,
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
