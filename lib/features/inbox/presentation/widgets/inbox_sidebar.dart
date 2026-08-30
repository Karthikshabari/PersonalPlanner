import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/inbox_item.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/inbox_provider.dart';
import 'inbox_quick_add.dart';
import 'inbox_task_tile.dart';

/// Collapsible bottom strip (desktop, planner.md Chunk 3 #11): quick-add plus
/// a scrollable row of inbox items and overdue tasks.
class InboxSidebar extends ConsumerStatefulWidget {
  const InboxSidebar({super.key});

  @override
  ConsumerState<InboxSidebar> createState() => _InboxSidebarState();
}

class _InboxSidebarState extends ConsumerState<InboxSidebar> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inboxProvider);
    final items = itemsAsync.value ?? const <InboxItem>[];
    final tokens = AppThemeTokens.of(context);

    return Container(
      key: const ValueKey('inbox-sidebar'),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        border: Border(top: BorderSide(color: tokens.outline)),
      ),
      height: _expanded ? 176 : 44,
      child: Column(
        children: [
          Container(
            height: 44,
            color: tokens.surface,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.selected,
                    borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  ),
                  child: Icon(
                    Icons.inbox_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  itemsAsync.hasValue ? 'Inbox (${items.length})' : 'Inbox',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('inbox-collapse'),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded)
            Expanded(
              child: Column(
                children: [
                  const InboxQuickAdd(),
                  Expanded(
                    child: itemsAsync.hasError
                        ? ErrorPanel(
                            message: friendlyErrorMessage(itemsAsync.error!),
                            onRetry: () => ref.invalidate(inboxProvider),
                            compact: true,
                          )
                        : !itemsAsync.hasValue
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                        ? Center(
                            child: Text(
                              'No inbox items',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                InboxTaskTile(item: items[index]),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
