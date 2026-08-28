import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/inbox_provider.dart';
import '../widgets/inbox_quick_add.dart';
import '../widgets/inbox_task_tile.dart';

/// Full-screen inbox list (mobile tab, planner.md Chunk 3 #12).
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: Column(
        children: [
          const InboxQuickAdd(),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No inbox items'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          InboxTaskTile(item: items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
