import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/inbox_item.dart';
import '../../../../core/theme/app_spacing.dart';
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
    final items =
        itemsAsync.maybeWhen(data: (i) => i, orElse: () => const <InboxItem>[]);

    return Container(
      key: const ValueKey('inbox-sidebar'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      height: _expanded ? 180 : 40,
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.inbox_outlined,
                    size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Inbox (${items.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('inbox-collapse'),
                  icon: Icon(_expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up),
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
                    child: items.isEmpty
                        ? const Center(
                            child: Text('No inbox items',
                                style: TextStyle(fontSize: 12)))
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
