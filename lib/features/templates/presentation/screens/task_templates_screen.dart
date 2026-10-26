import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../categories/providers/category_providers.dart';
import '../../../timeline/presentation/widgets/day_style.dart';
import '../../providers/template_providers.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../widgets/template_form_dialog.dart';

/// Settings → Task Templates (planner.md Chunk 4 #11): list, create, edit
/// and delete templates.
class TaskTemplatesScreen extends ConsumerWidget {
  const TaskTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('Task Templates'),
        actions: const [SyncStatusAction()],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add-template-fab'),
        tooltip: 'Add template',
        onPressed: () => showTemplateFormDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView(
        value: templatesAsync,
        onRetry: () => ref.invalidate(templatesProvider),
        builder: (templates) {
          if (categoriesAsync.hasError) {
            return ErrorPanel(
              message: friendlyErrorMessage(categoriesAsync.error!),
              onRetry: () => ref.invalidate(categoriesProvider),
            );
          }
          if (!categoriesAsync.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = categoriesAsync.requireValue;
          if (templates.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _EmptyTemplatesCard(
                  onAdd: () => showTemplateFormDialog(context, ref),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600
                  ? AppSpacing.md
                  : AppSpacing.xl,
            ).copyWith(bottom: AppSpacing.fabClearance),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              final category = categories
                  .where((c) => c.id == template.categoryId)
                  .firstOrNull;
              return Card(
                key: ValueKey('template-card-${template.id}'),
                child: ListTile(
                  leading: category == null
                      ? const Icon(Icons.bookmark_border_outlined)
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.categoryColor(
                              category.colorHex,
                              Theme.of(context).brightness,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                  title: Text(template.name),
                  subtitle: Text(
                    '${template.durationMin} min'
                    '${category == null ? '' : ' · ${category.name}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          semanticLabel: 'Edit template',
                        ),
                        tooltip: 'Edit',
                        onPressed: () => showTemplateFormDialog(
                          context,
                          ref,
                          existing: template,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('delete-template-${template.id}'),
                        icon: const Icon(
                          Icons.delete_outline,
                          semanticLabel: 'Delete template',
                        ),
                        tooltip: 'Delete',
                        onPressed: () async {
                          final confirmed = await showConfirmDialog(
                            context,
                            title: 'Delete template?',
                            message:
                                '"${template.name}" will be removed. Tasks '
                                'already created from it are not affected.',
                            confirmLabel: 'Delete',
                          );
                          if (!confirmed) return;
                          try {
                            await ref
                                .read(templateRepositoryProvider)
                                .deleteTemplate(template.id);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(friendlyErrorMessage(error)),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Quiet card shown when there are no templates, styled like the Day's empty
/// card.
class _EmptyTemplatesCard extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyTemplatesCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        key: const ValueKey('empty-templates-card'),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(DayStyle.medium(context)),
          border: Border.all(color: tokens.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bookmark_border_outlined,
                    size: 24,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Text(
                      'No templates yet.',
                      style: DayStyle.section(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Create one here, or save a task as a template from the '
                'editor.',
                style: DayStyle.secondary(context),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('empty-templates-add'),
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New template'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
