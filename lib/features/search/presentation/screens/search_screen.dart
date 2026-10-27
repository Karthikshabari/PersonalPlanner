import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../inbox/providers/inbox_provider.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/search_result.dart';
import '../../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Typed in the field when the screen opens, for example the word from a
  /// page search that found nothing.
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search-input');
  Timer? _debounce;
  var _requestId = 0;
  AsyncValue<List<SearchResult>> _results = const AsyncValue.data(
    <SearchResult>[],
  );

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    if (query != null && query.trim().isNotEmpty) {
      _controller.text = query;
      _results = const AsyncValue.loading();
      _runSearch(query, ++_requestId);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final requestId = ++_requestId;
    if (value.trim().isEmpty) {
      setState(() => _results = const AsyncValue.data(<SearchResult>[]));
      return;
    }
    setState(() => _results = const AsyncValue.loading());
    _runSearch(value, requestId);
  }

  void _runSearch(String value, int requestId) {
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        // The family provider owns the repository boundary. The request id
        // ensures an older, slower Future cannot replace a newer query.
        final results = await ref.read(searchResultsProvider(value).future);
        if (!mounted || requestId != _requestId) return;
        setState(() => _results = AsyncValue.data(results));
      } catch (error, stack) {
        if (!mounted || requestId != _requestId) return;
        setState(() => _results = AsyncValue.error(error, stack));
      }
    });
  }

  /// Esc clears the query, and leaves the screen when it is already empty.
  /// Ctrl+F puts the cursor back in the field.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_controller.text.isNotEmpty) {
        _clear();
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/day');
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  void _openResult(SearchResult result) {
    // An Inbox idea has no editor on Day: open the Inbox with it expanded.
    // Its sessions are ordinary tasks and still open on Day.
    if (result.isInbox) {
      ref.read(inboxFocusItemProvider.notifier).state = result.id;
      context.go('/inbox');
      return;
    }
    final date = result.startTime;
    if (date != null) {
      ref.read(selectedDateProvider.notifier).state = startOfDay(date);
    }
    ref.read(selectedTaskIdProvider.notifier).state = result.id;
    ref.read(taskEditorOpenProvider.notifier).state = true;
    context.go('/day');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          title: const Text('Search'),
          actions: const [SyncStatusAction()],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: EdgeInsets.all(
              constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl,
            ),
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('search-input'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    labelText: 'Search tasks',
                    hintText: 'Matches the start of words in title, description or notes',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(
                              Icons.clear,
                              semanticLabel: 'Clear search',
                            ),
                            onPressed: _clear,
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() => _results.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => ErrorPanel(message: friendlyErrorMessage(error)),
    data: (results) {
      if (_controller.text.trim().isEmpty) {
        return const Center(
          child: Text(
            'Search your planned work.\n'
            'Search covers title, description and notes.',
            textAlign: TextAlign.center,
          ),
        );
      }
      if (results.isEmpty) {
        return const Center(child: Text('No matching tasks'));
      }
      final capped = results.length >= searchResultCap;
      final count = results.length == 1 ? '1 task' : '${results.length} tasks';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            capped ? 'Showing the first $searchResultCap' : count,
            key: const ValueKey('search-count'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppThemeTokens.of(context).textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('search-results'),
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final result = results[index];
                return _SearchResultTile(
                  result: result,
                  query: _controller.text,
                  onTap: () => _openResult(result),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = result.startTime;
    final snippet = result.snippet;
    return Card(
      key: ValueKey('search-result-${result.id}'),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 9,
          backgroundColor: _categoryColor(result.categoryColorHex),
        ),
        title: SearchHighlight(
          result.title,
          terms: _terms,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: 2,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snippet != null)
              SearchHighlight(
                snippet,
                terms: _terms,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
              ),
            Text(
              '${date == null ? 'Inbox' : DateFormat('MMM d, yyyy').format(date)}'
              ' · ${result.status.label}',
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  List<String> get _terms => query
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);

  Color _categoryColor(String? hex) {
    if (hex == null) return AppColors.primary;
    try {
      return AppColors.parseHex(hex);
    } catch (_) {
      return AppColors.primary;
    }
  }
}
