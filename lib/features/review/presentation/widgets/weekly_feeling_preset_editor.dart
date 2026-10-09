import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/weekly_feeling_presets.dart';
import '../../providers/weekly_feeling_presets_provider.dart';
import 'review_equal_grid.dart';
import 'review_snack_bar.dart';
import 'weekly_review_style.dart';

/// Edits the four feeling words. Same panel style and write-on-keystroke
/// behaviour as the quick-reason editor; a value that is blank, too long or a
/// duplicate shows a message and is not stored, and a focused field is never
/// overwritten.
class WeeklyFeelingPresetEditor extends ConsumerStatefulWidget {
  const WeeklyFeelingPresetEditor({super.key});

  @override
  ConsumerState<WeeklyFeelingPresetEditor> createState() =>
      _WeeklyFeelingPresetEditorState();
}

class _WeeklyFeelingPresetEditorState
    extends ConsumerState<WeeklyFeelingPresetEditor> {
  final List<TextEditingController> _controllers = [
    for (var i = 0; i < weeklyFeelingPresetCount; i++) TextEditingController(),
  ];
  final List<FocusNode> _focusNodes = [
    for (var i = 0; i < weeklyFeelingPresetCount; i++) FocusNode(),
  ];
  final List<String?> _errors = List.filled(weeklyFeelingPresetCount, null);

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _sync(List<String> presets) {
    for (var i = 0; i < presets.length; i++) {
      if (_controllers[i].text != presets[i] &&
          !_focusNodes[i].hasFocus &&
          _errors[i] == null) {
        _controllers[i].text = presets[i];
      }
    }
  }

  Future<void> _onChanged(int index, String value) async {
    final presets = ref.read(weeklyFeelingPresetsProvider).value;
    if (presets == null) return;
    final error = WeeklyFeelingPresets.validate(presets, index, value);
    setState(() => _errors[index] = error);
    if (error == null) {
      await ref.read(weeklyFeelingPresetsProvider.notifier).setAt(index, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final async = ref.watch(weeklyFeelingPresetsProvider);
    final presets = async.value;
    if (presets == null) {
      return Container(
        key: const ValueKey('weekly-feeling-preset-editor'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: async.hasError
            ? const Text('Could not load presets.')
            : const Center(child: CircularProgressIndicator()),
      );
    }
    _sync(presets);
    return Container(
      key: const ValueKey('weekly-feeling-preset-editor'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: WeeklyStyle.inset(context),
        borderRadius: BorderRadius.circular(WeeklyStyle.insetRadius(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Four words shown under every week. Up to '
            '$maxWeeklyFeelingPresetLength characters each.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          ReviewEqualGrid(
            // Fourteen characters plus the field's own padding.
            minCellWidth:
                measureWidestText(context, [
                  '0' * maxWeeklyFeelingPresetLength,
                ], Theme.of(context).textTheme.bodyLarge) +
                2 * AppSpacing.lg,
            spacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < weeklyFeelingPresetCount; i++)
                TextField(
                  key: ValueKey('weekly-feeling-preset-field-$i'),
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      maxWeeklyFeelingPresetLength,
                    ),
                  ],
                  decoration: WeeklyStyle.fieldDecoration(
                    context,
                    isDense: true,
                    // On the inset panel: the card colour reads as a field.
                    fill: tokens.surface,
                    hintText: 'Word ${i + 1}',
                    errorText: _errors[i],
                  ),
                  onChanged: (v) => _onChanged(i, v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('weekly-feeling-preset-reset'),
              onPressed: () async {
                await ref
                    .read(weeklyFeelingPresetsProvider.notifier)
                    .resetToDefaults();
                if (!mounted) return;
                setState(() {
                  _errors.fillRange(0, _errors.length, null);
                  for (var i = 0; i < presets.length; i++) {
                    _controllers[i].text = defaultWeeklyFeelingPresets[i];
                  }
                });
                if (context.mounted) {
                  showReviewSnackBar(context, 'Presets reset');
                }
              },
              child: const Text('Reset to defaults'),
            ),
          ),
        ],
      ),
    );
  }
}
