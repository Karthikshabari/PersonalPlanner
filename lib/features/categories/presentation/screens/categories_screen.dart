import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../providers/category_providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: categoriesAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: categories.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
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
                trailing: category.isFocus
                    ? const Tooltip(
                        message: 'Focus category',
                        child: Icon(Icons.center_focus_strong, size: 18),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
