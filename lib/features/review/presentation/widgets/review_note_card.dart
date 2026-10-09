import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/review_draft.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// "Anything worth remembering?": the note field only. Saving lives in the
/// bottom bar. The text controller is created once; a re-hydration of the
/// draft (not typing) reloads it.
class ReviewNoteCard extends StatefulWidget {
  final ReviewDraft draft;
  final ValueChanged<String> onNoteChanged;

  const ReviewNoteCard({
    super.key,
    required this.draft,
    required this.onNoteChanged,
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
    const prompt =
        'What affected today’s plan, or what would you do differently next time?';
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Anything worth remembering?', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(prompt, style: weeklyCaptionStyle(context)),
          const SizedBox(height: WeeklyStyle.titleGap),
          if (!widget.draft.hydrated) const LinearProgressIndicator(),
          TextField(
            key: const ValueKey('review-note'),
            controller: _controller,
            enabled: widget.draft.hydrated,
            // Three lines tall at rest, six at most, then it scrolls inside.
            minLines: 3,
            maxLines: 6,
            decoration: WeeklyStyle.fieldDecoration(context, hintText: prompt),
            onChanged: widget.onNoteChanged,
          ),
        ],
      ),
    );
  }
}
