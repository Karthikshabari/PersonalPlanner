import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/category.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../data/category_repository.dart';
import '../../providers/category_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';

/// Predefined color palette for new categories.
const _palette = [
  '#7C5CFC',
  '#4285F4',
  '#34A853',
  '#EA4335',
  '#FBBC04',
  '#E91E63',
  '#00BCD4',
  '#FF9800',
];

/// Spoken names for [_palette], index for index.
const _paletteNames = [
  'Purple',
  'Blue',
  'Green',
  'Red',
  'Yellow',
  'Pink',
  'Cyan',
  'Orange',
];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final taskCounts = ref.watch(categoryTaskCountsProvider).value;
    final repo = ref.read(categoryRepositoryProvider);
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Categories'),
        actions: const [SyncStatusAction()],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add-category'),
        tooltip: 'Add category',
        onPressed: () => _showEditDialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading categories',
          ),
        ),
        error: (e, _) => ErrorPanel(message: friendlyErrorMessage(e)),
        data: (categories) => ReorderableListView.builder(
          buildDefaultDragHandles: false,
          header: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Focus counts toward focus time in reviews',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600
                ? AppSpacing.md
                : AppSpacing.xl,
          ).copyWith(bottom: AppSpacing.fabClearance),
          itemCount: categories.length,
          onReorderItem: (oldIndex, newIndex) =>
              _move(context, repo, categories, oldIndex, newIndex),
          proxyDecorator: (child, index, animation) => ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.02).animate(animation),
            child: child,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            // Three 48 px buttons would leave the name almost no room.
            final compact = MediaQuery.sizeOf(context).width < 360;
            void toggleFocus() => _runCategoryMutation(
              context,
              () => repo.updateCategory(
                category.copyWith(isFocus: !category.isFocus),
              ),
            );
            void edit() => _showEditDialog(context, ref, category);
            void delete() => _confirmDelete(context, ref, category);
            // The whole row still drags after a long press, as before.
            return ReorderableDelayedDragStartListener(
              key: ValueKey('category-${category.id}'),
              index: index,
              child: Card(
                child: ListTile(
                  horizontalTitleGap: compact ? AppSpacing.sm : null,
                  contentPadding: compact
                      ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
                      : null,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ReorderHandle(
                        index: index,
                        onMoveUp: index == 0
                            ? null
                            : () => _move(
                                context,
                                repo,
                                categories,
                                index,
                                index - 1,
                              ),
                        onMoveDown: index == categories.length - 1
                            ? null
                            : () => _move(
                                context,
                                repo,
                                categories,
                                index,
                                index + 1,
                              ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.categoryColor(
                            category.colorHex,
                            Theme.of(context).brightness,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  title: Text(category.name),
                  subtitle: _usageSubtitle(
                    taskCounts?[category.id],
                    category.isFocus,
                  ),
                  trailing: compact
                      ? PopupMenuButton<VoidCallback>(
                          key: ValueKey('category-menu-${category.name}'),
                          tooltip: 'Category actions',
                          onSelected: (action) => action(),
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                              value: toggleFocus,
                              checked: category.isFocus,
                              child: const Text('Focus category'),
                            ),
                            PopupMenuItem(
                              value: edit,
                              child: const Text('Edit'),
                            ),
                            PopupMenuItem(
                              value: delete,
                              child: const Text('Delete'),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Focus category',
                              icon: Icon(
                                Icons.center_focus_strong,
                                semanticLabel: category.isFocus
                                    ? 'Focus category, on'
                                    : 'Focus category, off',
                                size: 20,
                                color: category.isFocus
                                    ? AppColors.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                              onPressed: toggleFocus,
                            ),
                            IconButton(
                              tooltip: 'Edit category',
                              key: ValueKey('edit-category-${category.name}'),
                              icon: const Icon(
                                Icons.edit_outlined,
                                semanticLabel: 'Edit category',
                                size: 18,
                              ),
                              onPressed: edit,
                            ),
                            IconButton(
                              tooltip: 'Delete category',
                              key: ValueKey('delete-category-${category.name}'),
                              icon: const Icon(
                                Icons.delete_outline,
                                semanticLabel: 'Delete category',
                                size: 18,
                              ),
                              onPressed: delete,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Moves the category at [oldIndex] to [newIndex] (the index it ends up at).
  Future<void> _move(
    BuildContext context,
    CategoryRepository repo,
    List<Category> categories,
    int oldIndex,
    int newIndex,
  ) {
    final ids = categories.map((c) => c.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    return _runCategoryMutation(context, () => repo.reorderCategories(ids));
  }

  /// "12 tasks" and/or "Focus"; nothing while the counts are loading.
  static Widget? _usageSubtitle(int? tasks, bool isFocus) {
    final parts = [
      if (tasks != null)
        tasks == 0 ? 'No tasks' : '$tasks task${tasks == 1 ? '' : 's'}',
      if (isFocus) 'Focus',
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    Category? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var selectedColor = existing?.colorHex ?? _palette.first;
    // Shown inside the dialog: a snackbar would render under its scrim.
    String? nameError;
    String? saveError;
    final repo = ref.read(categoryRepositoryProvider);

    var saving = false;
    Future<void> save(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (saving) return;
      saving = true;
      try {
        final name = nameController.text.trim();
        final error = name.isEmpty
            ? 'Enter a category name'
            : name.length > AppConstants.maxCategoryNameLength
            ? 'Name must be ${AppConstants.maxCategoryNameLength} '
                  'characters or fewer'
            : null;
        setDialogState(() {
          nameError = error;
          saveError = null;
        });
        if (error != null) return;
        // Duplicates stay allowed, but only after a warning (F-012).
        if (_hasCategoryNamed(
          ref.read(categoriesProvider).value,
          name,
          excludingId: existing?.id,
        )) {
          final createAnyway = await _confirmDuplicateName(
            dialogContext,
            name,
            renaming: existing != null,
          );
          if (createAnyway != true || !dialogContext.mounted) return;
        }
        try {
          if (existing == null) {
            final current =
                ref.read(categoriesProvider).value ?? const <Category>[];
            await repo.insertCategory(
              Category(
                id: '',
                name: name,
                colorHex: selectedColor,
                sortOrder: current.isEmpty
                    ? 0
                    : current
                              .map((c) => c.sortOrder)
                              .reduce((a, b) => a > b ? a : b) +
                          1,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
          } else {
            await repo.updateCategory(
              existing.copyWith(name: name, colorHex: selectedColor),
            );
          }
        } catch (error) {
          if (dialogContext.mounted) {
            setDialogState(() => saveError = friendlyErrorMessage(error));
          }
          return;
        }
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      } finally {
        saving = false;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('category-name'),
                controller: nameController,
                onSubmitted: (_) => save(dialogContext, setDialogState),
                maxLength: AppConstants.maxCategoryNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                onChanged: (_) {
                  if (nameError != null) {
                    setDialogState(() => nameError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: nameError,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (var i = 0; i < _palette.length; i++)
                    _PaletteSwatch(
                      key: ValueKey('palette-$i'),
                      hex: _palette[i],
                      name: _paletteNames[i],
                      selected: selectedColor == _palette[i],
                      onTap: () =>
                          setDialogState(() => selectedColor = _palette[i]),
                    ),
                ],
              ),
              if (saveError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  saveError!,
                  key: const ValueKey('category-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('save-category'),
              onPressed: () => save(dialogContext, setDialogState),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static bool _hasCategoryNamed(
    List<Category>? categories,
    String name, {
    String? excludingId,
  }) {
    final wanted = name.trim().toLowerCase();
    return (categories ?? const <Category>[]).any(
      (category) =>
          category.id != excludingId &&
          category.name.trim().toLowerCase() == wanted,
    );
  }

  Future<bool?> _confirmDuplicateName(
    BuildContext context,
    String name, {
    bool renaming = false,
  }) => showDialog<bool>(
    context: context,
    builder: (confirmContext) => AlertDialog(
      title: const Text('Duplicate category name'),
      content: Text(
        'A category named "$name" already exists. '
        '${renaming ? 'Rename' : 'Create'} anyway?',
      ),
      actions: [
        TextButton(
          key: const ValueKey('duplicate-category-cancel'),
          onPressed: () => Navigator.of(confirmContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('duplicate-category-create'),
          onPressed: () => Navigator.of(confirmContext).pop(true),
          child: Text(renaming ? 'Rename' : 'Create'),
        ),
      ],
    ),
  );

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final repo = ref.read(categoryRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final CategoryUsage usage;
    try {
      usage = await repo.usageOf(category.id);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"${category.name}" will be removed.\n\n${_usageLine(usage)} '
          'Past and finished tasks keep the category, so earlier days and '
          'focus time stay as they were. Other tasks, rules and templates '
          'lose it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-category'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final CategoryDeletion deletion;
    try {
      deletion = await repo.deleteCategory(category.id);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${category.name}"'),
        // A snackbar with an action never times out unless told to.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await repo.undoDelete(deletion);
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(content: Text(friendlyErrorMessage(error))),
              );
            }
          },
        ),
      ),
    );
  }

  static String _usageLine(CategoryUsage usage) {
    if (usage.tasks == 0 && usage.rules == 0 && usage.templates == 0) {
      return 'No tasks, rules or templates use this.';
    }
    String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    return '${count(usage.tasks, 'task')} (${usage.pastTasks} in the past), '
        '${count(usage.rules, 'rule')}, '
        '${count(usage.templates, 'template')} use this.';
  }
}

/// The drag handle of a category row, with Move up / Move down buttons as the
/// keyboard and screen-reader way to reorder.
class _ReorderHandle extends StatelessWidget {
  final int index;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _ReorderHandle({
    required this.index,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Tooltip(
            message: 'Drag to reorder',
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(Icons.drag_indicator, size: 20),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MoveButton(
              tooltip: 'Move up',
              icon: Icons.keyboard_arrow_up,
              onPressed: onMoveUp,
            ),
            _MoveButton(
              tooltip: 'Move down',
              icon: Icons.keyboard_arrow_down,
              onPressed: onMoveDown,
            ),
          ],
        ),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _MoveButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, size: 20),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 24),
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    onPressed: onPressed,
  );
}

/// One palette choice: a 44 px target that announces its colour name and
/// selected state, and marks the selection with a check, not colour alone.
class _PaletteSwatch extends StatelessWidget {
  final String hex;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteSwatch({
    super.key,
    required this.hex,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.parseHex(hex);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$name colour',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onPrimary,
                        width: 2,
                      )
                    : null,
              ),
              child: selected
                  ? Icon(Icons.check, size: 16, color: onColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _runCategoryMutation(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }
}
