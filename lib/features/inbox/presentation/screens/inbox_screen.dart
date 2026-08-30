import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../providers/inbox_provider.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../widgets/inbox_quick_add.dart';
import '../widgets/inbox_task_tile.dart';

/// Full-screen inbox list (mobile tab, planner.md Chunk 3 #12).
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(inboxProvider);
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: const [SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: Column(
          children: [
            const InboxQuickAdd(),
            Divider(height: 1, color: tokens.outline),
            Expanded(
              child: itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorPanel(message: friendlyErrorMessage(e)),
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
      ),
    );
  }
}
