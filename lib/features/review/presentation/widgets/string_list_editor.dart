import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Editable list of short strings — wins, improvements, goals met/missed,
/// next-week focus. Type in the field and press Enter (or +) to append;
/// the trailing X removes an entry.
class StringListEditor extends StatefulWidget {
  final String label;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String? hint;

  const StringListEditor({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onChanged([...widget.items, text]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < widget.items.length; i++)
          Row(
            children: [
              Expanded(child: Text(widget.items[i])),
              IconButton(
                key: ValueKey('${widget.label}-remove-$i'),
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  final next = [...widget.items]..removeAt(i);
                  widget.onChanged(next);
                },
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hint ?? 'Add item…',
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              tooltip: 'Add',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
