import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../timeline/presentation/providers/selected_date_provider.dart';
import '../../../timeline/presentation/providers/selected_task_provider.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/search_result.dart';
import '../../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _requestId = 0;
  AsyncValue<List<SearchResult>> _results = const AsyncValue.data(
    <SearchResult>[],
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
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

  void _openResult(SearchResult result) {
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
    return Scaffold(
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
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  labelText: 'Search tasks',
                  hintText: 'Title, description, or notes',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
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
    );
  }

  Widget _buildResults() => _results.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => ErrorPanel(message: friendlyErrorMessage(error)),
    data: (results) {
      if (_controller.text.trim().isEmpty) {
        return const Center(child: Text('Search your planned work'));
      }
      if (results.isEmpty) {
        return const Center(child: Text('No matching tasks'));
      }
      return ListView.separated(
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
    return Card(
      key: ValueKey('search-result-${result.id}'),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 9,
          backgroundColor: _categoryColor(result.categoryColorHex),
        ),
        title: _highlightedTitle(context),
        subtitle: Text(
          '${date == null ? 'Inbox' : DateFormat('MMM d, yyyy').format(date)} · '
          '${result.status.label}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _highlightedTitle(BuildContext context) {
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return Text(result.title);
    final pattern = RegExp(
      terms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(result.title)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: result.title.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: result.title.substring(match.start, match.end),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.14),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < result.title.length) {
      spans.add(TextSpan(text: result.title.substring(cursor)));
    }
    return Text.rich(
      TextSpan(style: Theme.of(context).textTheme.bodyLarge, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Color _categoryColor(String? hex) {
    if (hex == null) return AppColors.primary;
    try {
      return AppColors.parseHex(hex);
    } catch (_) {
      return AppColors.primary;
    }
  }
}
