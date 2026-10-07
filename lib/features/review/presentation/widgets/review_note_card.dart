import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_draft.dart';
import 'review_theme.dart';

class ReviewNoteCard extends StatefulWidget {
  final ReviewDraft draft;
  final ValueChanged<String> onNoteChanged;
  final Widget saveButton;
  final bool showShortcutHint;

  const ReviewNoteCard({
    super.key,
    required this.draft,
    required this.onNoteChanged,
    required this.saveButton,
    required this.showShortcutHint,
  });

  @override
  State<ReviewNoteCard> createState() => _ReviewNoteCardState();
}

class _ReviewNoteCardState extends State<ReviewNoteCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.draft.note,
  );

  @override
  void didUpdateWidget(ReviewNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.hydrationVersion != widget.draft.hydrationVersion &&
        _controller.text != widget.draft.note) {
      _controller.text = widget.draft.note;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Anything worth remembering?', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'What affected today’s plan, or what would you do differently next time?',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!widget.draft.hydrated) const LinearProgressIndicator(),
          TextField(
            key: const ValueKey('review-note'),
            controller: _controller,
            enabled: widget.draft.hydrated,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'What affected today’s plan, or what would you do differently next time?',
            ),
            onChanged: widget.onNoteChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              widget.saveButton,
              if (widget.showShortcutHint)
                Text('Ctrl + Enter', style: reviewMonoStyle(context)),
            ],
          ),
        ],
      ),
    );
  }
}
