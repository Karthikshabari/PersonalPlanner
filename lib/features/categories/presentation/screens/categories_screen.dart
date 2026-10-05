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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorPanel(message: friendlyErrorMessage(e)),
        data: (categories) => ReorderableListView.builder(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600
                ? AppSpacing.md
                : AppSpacing.xl,
          ),
          itemCount: categories.length,
          onReorderItem: (oldIndex, newIndex) async {
            final ids = categories.map((c) => c.id).toList();
            final moved = ids.removeAt(oldIndex);
            ids.insert(newIndex, moved);
            await _runCategoryMutation(
              context,
              () => repo.reorderCategories(ids),
            );
          },
          proxyDecorator: (child, index, animation) => ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.02).animate(animation),
            child: child,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              key: ValueKey('category-${category.id}'),
              child: ListTile(
                leading: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.parseHex(category.colorHex),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(category.name),
                subtitle: Text(
                  category.colorHex,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Focus category',
                      icon: Icon(
                        Icons.center_focus_strong,
                        size: 20,
                        color: category.isFocus
                            ? AppColors.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => _runCategoryMutation(
                        context,
                        () => repo.updateCategory(
                          category.copyWith(isFocus: !category.isFocus),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      key: ValueKey('edit-category-${category.name}'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _showEditDialog(context, ref, category),
                    ),
                    IconButton(
                      key: ValueKey('delete-category-${category.name}'),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _confirmDelete(context, ref, category),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
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
              onPressed: () async {
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
                if (existing == null &&
                    _hasCategoryNamed(
                      ref.read(categoriesProvider).value,
                      name,
                    )) {
                  final createAnyway = await _confirmDuplicateName(
                    dialogContext,
                    name,
                  );
                  if (createAnyway != true || !dialogContext.mounted) return;
                }
                try {
                  if (existing == null) {
                    await repo.insertCategory(
                      Category(
                        id: '',
                        name: name,
                        colorHex: selectedColor,
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
                    setDialogState(
                      () => saveError = friendlyErrorMessage(error),
                    );
                  }
                  return;
                }
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static bool _hasCategoryNamed(List<Category>? categories, String name) {
    final wanted = name.trim().toLowerCase();
    return (categories ?? const <Category>[]).any(
      (category) => category.name.trim().toLowerCase() == wanted,
    );
  }

  Future<bool?> _confirmDuplicateName(BuildContext context, String name) =>
      showDialog<bool>(
        context: context,
        builder: (confirmContext) => AlertDialog(
          title: const Text('Duplicate category name'),
          content: Text(
            'A category named "$name" already exists. '
            'Create anyway?',
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
              child: const Text('Create'),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"${category.name}" will be removed. Tasks in this category will '
          'keep their data but lose the category.',
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
    if (confirmed == true && context.mounted) {
      await _runCategoryMutation(
        context,
        () => ref.read(categoryRepositoryProvider).deleteCategory(category.id),
      );
    }
  }
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
