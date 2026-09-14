import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../categories/providers/category_providers.dart';

/// Category lookup used by the task editor. Loading and lookup failures stay
/// visible in the form so a missing category list cannot look like an empty
/// successful result.
class CategoryDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const CategoryDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    if (categoriesAsync.hasError) {
      return ErrorPanel(
        message: friendlyErrorMessage(categoriesAsync.error!),
        onRetry: () => ref.invalidate(categoriesProvider),
        compact: true,
      );
    }
    if (!categoriesAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final categories = categoriesAsync.requireValue;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final category in categories)
          DropdownMenuItem(
            value: category.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(category.colorHex.replaceFirst('#', '0xFF')),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(category.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
