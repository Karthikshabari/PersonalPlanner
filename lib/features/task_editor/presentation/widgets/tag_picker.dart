import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/tag.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/tag_repository.dart';
import '../../providers/tag_providers.dart';

/// Multi-select chip tag picker for the task editor (planner.md Chunk 3 #9):
/// existing tags as toggle chips, typing + Enter creates/attaches a new tag.
class TagPicker extends ConsumerStatefulWidget {
  final String taskId;
  final Set<String>? selectedIds;
  final ValueChanged<Set<String>>? onChanged;

  const TagPicker({
    super.key,
    required this.taskId,
    this.selectedIds,
    this.onChanged,
  });

  @override
  ConsumerState<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<TagPicker> {
  final _newTagController = TextEditingController();

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  TagRepository get _repo => ref.read(tagRepositoryProvider);

  Future<void> _attachNew(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final tag = await _repo.getOrCreateByName(trimmed);
    if (widget.onChanged != null) {
      final current = widget.selectedIds ?? const <String>{};
      widget.onChanged!({...current, tag.id});
    } else {
      await _repo.addTagToTask(widget.taskId, tag.id);
    }
    _newTagController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final allTagsAsync = ref.watch(tagsProvider);
    final taskTagsAsync = ref.watch(tagsForTaskProvider(widget.taskId));
    final allTags =
        allTagsAsync.maybeWhen(data: (t) => t, orElse: () => const <Tag>[]);
    final Set<String> attachedIds = widget.selectedIds ??
        taskTagsAsync.maybeWhen(
            data: (t) => t.map((e) => e.id).toSet(),
            orElse: () => <String>{}) ??
        <String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final tag in allTags)
              FilterChip(
                key: ValueKey('tag-chip-${tag.name}'),
                label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                selected: attachedIds.contains(tag.id),
                onSelected: (selected) async {
                  final next = {...attachedIds};
                  if (selected) {
                    next.add(tag.id);
                  } else {
                    next.remove(tag.id);
                  }
                  if (widget.onChanged != null) {
                    widget.onChanged!(next);
                  } else {
                    if (selected) {
                      await _repo.addTagToTask(widget.taskId, tag.id);
                    } else {
                      await _repo.removeTagFromTask(widget.taskId, tag.id);
                    }
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('tag-input'),
          controller: _newTagController,
          decoration: const InputDecoration(
            labelText: 'Add tag (Enter)',
            prefixIcon: Icon(Icons.sell_outlined, size: 18),
          ),
          onSubmitted: _attachNew,
        ),
      ],
    );
  }
}
