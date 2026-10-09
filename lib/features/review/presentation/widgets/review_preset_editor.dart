import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_reason_presets.dart';
import '../../providers/review_reason_presets_provider.dart';
import 'review_cell_grid.dart';
import 'review_equal_grid.dart';
import 'review_snack_bar.dart';
import 'weekly_review_style.dart';

/// Edits the quick-reason presets. Writes on every keystroke (cheap local
/// write) and never replaces the text of a focused field.
///
/// With [grid] (the Daily review) the fields sit in equal-width cells, two
/// columns on a wide card and one on a narrow one, on the inset surface.
/// Nothing has a fixed height: the panel is as tall as its content.
class ReviewPresetEditor extends ConsumerStatefulWidget {
  const ReviewPresetEditor({super.key, this.grid = false});

  final bool grid;

  @override
  ConsumerState<ReviewPresetEditor> createState() => _ReviewPresetEditorState();
}

class _ReviewPresetEditorState extends ConsumerState<ReviewPresetEditor> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];

  @override
  void dispose() {
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  void _sync(List<String> presets) {
    if (_controllers.length != presets.length) {
      _disposeFields();
      for (final preset in presets) {
        _controllers.add(TextEditingController(text: preset));
        _focusNodes.add(FocusNode());
      }
      return;
    }
    for (var i = 0; i < presets.length; i++) {
      if (_controllers[i].text != presets[i] && !_focusNodes[i].hasFocus) {
        _controllers[i].text = presets[i];
      }
    }
  }

  /// One preset: its field and the remove button.
  Widget _presetRow(
    BuildContext context,
    int index,
    ReviewReasonPresetsNotifier notifier,
  ) {
    final tokens = AppThemeTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('review-preset-field-$index'),
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxReviewReasonPresetLength),
            ],
            decoration: widget.grid
                // On the inset panel: the card colour reads as a field.
                ? WeeklyStyle.fieldDecoration(
                    context,
                    isDense: true,
                    fill: tokens.surface,
                    hintText: 'Preset ${index + 1}',
                  )
                : InputDecoration(
                    isDense: true,
                    hintText: 'Preset ${index + 1}',
                  ),
            onChanged: (v) => notifier.updateAt(index, v),
          ),
        ),
        IconButton(
          key: ValueKey('review-preset-remove-$index'),
          tooltip: 'Remove preset ${index + 1}',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => notifier.removeAt(index),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final async = ref.watch(reviewReasonPresetsProvider);
    final presets = async.value;
    if (presets == null) {
      return Container(
        key: const ValueKey('review-preset-editor'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: async.hasError
            ? const Text('Could not load presets.')
            : const Center(child: CircularProgressIndicator()),
      );
    }
    _sync(presets);
    final notifier = ref.read(reviewReasonPresetsProvider.notifier);
    final Widget fields = widget.grid
        ? ReviewCellGrid(
            // Fourteen characters, the field's own padding and the 48 dp
            // remove button; two columns only when two cells fit.
            minCellWidth:
                measureWidestText(context, [
                  '0' * 14,
                ], Theme.of(context).textTheme.bodyLarge) +
                2 * AppSpacing.lg +
                48,
            spacing: AppSpacing.sm,
            maxColumns: 2,
            children: [
              for (var i = 0; i < presets.length; i++)
                _presetRow(context, i, notifier),
            ],
          )
        : Column(
            children: [
              for (var i = 0; i < presets.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _presetRow(context, i, notifier),
                ),
            ],
          );
    return Container(
      key: const ValueKey('review-preset-editor'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: widget.grid ? WeeklyStyle.inset(context) : tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(
          widget.grid ? WeeklyStyle.insetRadius(context) : tokens.radiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quick reasons shown under every task. Up to six.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          fields,
          if (widget.grid) const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                key: const ValueKey('review-preset-add'),
                onPressed: presets.length >= maxReviewReasonPresets
                    ? null
                    : () async {
                        await notifier.add();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _focusNodes.isNotEmpty) {
                            _focusNodes.last.requestFocus();
                          }
                        });
                      },
                child: const Text('+ Add preset'),
              ),
              OutlinedButton(
                key: const ValueKey('review-preset-reset'),
                onPressed: () async {
                  await notifier.resetToDefaults();
                  if (context.mounted) {
                    showReviewSnackBar(context, 'Presets reset');
                  }
                },
                child: const Text('Reset to defaults'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
