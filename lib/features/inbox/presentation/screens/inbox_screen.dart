import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/search/page_search.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/error_panel.dart';
import '../../../experiments/presentation/widgets/experiment_ui.dart';
import '../../../sync/presentation/widgets/sync_status_action.dart';
import '../../domain/inbox_board.dart';
import '../../domain/inbox_search.dart';
import '../../providers/inbox_provider.dart';
import '../widgets/inbox_idea_row.dart';
import '../widgets/inbox_quick_add.dart';
import '../widgets/inbox_reason_line.dart';

enum _Segment { open, done, dropped }

/// How many Done (or Dropped) rows show before "Show 30 more".
const _donePage = 30;

/// The few board values the screen itself needs. Equal when the sections and
/// counts are equal, so a change inside one row never rebuilds the screen;
/// each row watches its own idea.
@immutable
class _ScreenState {
  const _ScreenState({
    required this.error,
    required this.loaded,
    required this.leftOver,
    required this.ideas,
    required this.comingUp,
    required this.done,
    required this.dropped,
  });

  factory _ScreenState.from(AsyncValue<InboxBoard> board) {
    final value = board.value;
    return _ScreenState(
      error: board.hasError ? board.error : null,
      loaded: value != null,
      leftOver: value?.leftOver.toList(growable: false) ?? const [],
      ideas: value?.ideas.toList(growable: false) ?? const [],
      comingUp: value?.comingUp.toList(growable: false) ?? const [],
      done: value?.done.toList(growable: false) ?? const [],
      dropped: value?.dropped.toList(growable: false) ?? const [],
    );
  }

  final Object? error;
  final bool loaded;
  final List<String> leftOver;
  final List<String> ideas;
  final List<String> comingUp;
  final List<String> done;
  final List<String> dropped;

  int get openCount => leftOver.length + ideas.length + comingUp.length;

  /// Only the ideas in [ids], for page search. The order is kept.
  _ScreenState onlyIds(Set<String> ids) {
    List<String> pick(List<String> section) =>
        section.where(ids.contains).toList(growable: false);
    return _ScreenState(
      error: error,
      loaded: loaded,
      leftOver: pick(leftOver),
      ideas: pick(ideas),
      comingUp: pick(comingUp),
      done: pick(done),
      dropped: pick(dropped),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ScreenState &&
      other.error == error &&
      other.loaded == loaded &&
      listEquals(other.leftOver, leftOver) &&
      listEquals(other.ideas, ideas) &&
      listEquals(other.comingUp, comingUp) &&
      listEquals(other.done, done) &&
      listEquals(other.dropped, dropped);

  @override
  int get hashCode => Object.hash(
    error,
    loaded,
    Object.hashAll(leftOver),
    Object.hashAll(ideas),
    Object.hashAll(comingUp),
    Object.hashAll(done),
    Object.hashAll(dropped),
  );
}

/// One line of the list: a section header, an idea row, or "Show more".
class _Item {
  const _Item.header(this.title, this.count) : id = null, more = false;
  const _Item.row(this.id) : title = null, count = 0, more = false;
  const _Item.more() : title = null, count = 0, id = null, more = true;

  final String? title;
  final int count;
  final String? id;
  final bool more;
}

/// The Inbox: capture an idea, see where each idea stands, give it dates
/// (sessions on Day), and close it. Day stays the one source of truth for a
/// session's date, time and completion; this screen only reads it.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _scroll = ScrollController();
  final _rowKeys = <String, GlobalKey>{};
  _Segment _segment = _Segment.open;
  int _doneShown = _donePage;
  int _droppedShown = _donePage;

  // Focus request from Search: the idea to reveal, and the scroll retries.
  bool _focusQueued = false;
  String? _scrollTarget;
  int _scrollAttempts = 0;
  List<_Item> _items = const [];

  // Page search (Ctrl+F or the phone icon). The scope outlives this State.
  PageSearchController? _search;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final search = PageSearchScope.maybeOf(context);
    if (identical(search, _search)) return;
    _search?.needle.removeListener(_onNeedle);
    _search = search;
    search?.needle.addListener(_onNeedle);
    search?.scrollPosition = () => _scroll.hasClients ? _scroll.position : null;
  }

  void _onNeedle() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search?.needle.removeListener(_onNeedle);
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> _buildItems(_ScreenState state) {
    if (_segment != _Segment.open) {
      final ids = _segment == _Segment.done ? state.done : state.dropped;
      final shown = math.min(
        _segment == _Segment.done ? _doneShown : _droppedShown,
        ids.length,
      );
      return [
        for (final id in ids.take(shown)) _Item.row(id),
        if (ids.length > shown) const _Item.more(),
      ];
    }
    return [
      if (state.leftOver.isNotEmpty) ...[
        _Item.header('Left over', state.leftOver.length),
        for (final id in state.leftOver) _Item.row(id),
      ],
      if (state.ideas.isNotEmpty) ...[
        _Item.header('Ideas', state.ideas.length),
        for (final id in state.ideas) _Item.row(id),
      ],
      if (state.comingUp.isNotEmpty) ...[
        _Item.header('Coming up', state.comingUp.length),
        for (final id in state.comingUp) _Item.row(id),
      ],
    ];
  }

  /// Search asked for this idea: pick its segment, open its trail, scroll to
  /// it, then clear the request.
  void _queueFocus(String id) {
    if (_focusQueued) return;
    _focusQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusQueued = false;
      if (!mounted) return;
      final view = ref.read(inboxBoardProvider).value?.byId[id];
      ref.read(inboxFocusItemProvider.notifier).state = null;
      if (view == null) return;
      final board = ref.read(inboxBoardProvider).value!;
      // Closed and let-go ideas are Dropped; finished ideas and experiments
      // are Done.
      final segment = board.dropped.contains(id)
          ? _Segment.dropped
          : board.done.contains(id)
          ? _Segment.done
          : _Segment.open;
      setState(() {
        _segment = segment;
        if (segment != _Segment.open) {
          final index = (segment == _Segment.done ? board.done : board.dropped)
              .indexOf(id);
          final shown = segment == _Segment.done ? _doneShown : _droppedShown;
          if (index >= shown) {
            final widened = ((index ~/ _donePage) + 1) * _donePage;
            if (segment == _Segment.done) {
              _doneShown = widened;
            } else {
              _droppedShown = widened;
            }
          }
        }
        _scrollTarget = id;
        _scrollAttempts = 0;
      });
      ref.read(inboxExpandedItemProvider.notifier).state = id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    });
  }

  /// Rows are built lazily, so a target far down is not built yet: jump near
  /// it, wait a frame and try again.
  void _scrollToTarget() {
    final id = _scrollTarget;
    if (id == null || !mounted) return;
    final context = _rowKeys[id]?.currentContext;
    if (context != null && context.mounted) {
      _scrollTarget = null;
      Scrollable.ensureVisible(context, alignment: 0.05);
      return;
    }
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || ++_scrollAttempts > 8 || !_scroll.hasClients) {
      _scrollTarget = null;
      return;
    }
    _scroll.jumpTo(math.min(index * 88.0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
  }

  /// A segment whose spoken label is "Dropped, 2 items". A null [count] means
  /// the Inbox has not loaded, so no count is shown or spoken.
  ButtonSegment<_Segment> _segmentOf(_Segment value, String name, int? count) =>
      ButtonSegment(
        value: value,
        label: Semantics(
          label: count == null
              ? '$name, loading'
              : '$name, $count ${count == 1 ? 'item' : 'items'}',
          excludeSemantics: true,
          child: Text(count == null ? name : '$name ($count)'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxBoardProvider.select(_ScreenState.from));
    final focusId = ref.watch(inboxFocusItemProvider);
    if (focusId != null && state.loaded) _queueFocus(focusId);
    final tokens = AppThemeTokens.of(context);
    // Null unless a page search is active; then the lists below keep only the
    // matching ideas and the segment labels count the matches.
    final needle = _search?.needle.value ?? '';
    final matches = needle.isEmpty
        ? null
        : ref.watch(
            inboxBoardProvider.select((b) => matchInbox(b.value, needle)),
          );
    _items = state.loaded
        ? _buildItems(matches == null ? state : state.onlyIds(matches.ids))
        : const [];

    // Loading, an error or an empty list takes the place of the rows. The
    // Review line is the first line of the list, so a tall line at large text
    // scrolls instead of squeezing the list to nothing.
    Widget? status;
    if (state.error != null) {
      status = ErrorPanel(message: friendlyErrorMessage(state.error!));
    } else if (!state.loaded) {
      status = const Padding(
        padding: EdgeInsets.all(AppSpacing.huge),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading Inbox'),
        ),
      );
    } else if (matches != null && _items.isEmpty) {
      status = const PageSearchNoMatches(key: ValueKey('inbox-search-empty'));
    } else if (_items.isEmpty) {
      status = Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            switch (_segment) {
              _Segment.open => 'Nothing open. Type an idea above.',
              _Segment.done => 'Nothing finished yet.',
              _Segment.dropped => 'Nothing dropped.',
            },
            key: ValueKey('inbox-empty-${_segment.name}'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.textMuted),
          ),
        ),
      );
    }
    final body = ListView.builder(
      key: const ValueKey('inbox-list'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: 1 + (status != null ? 1 : _items.length),
      itemBuilder: (context, index) {
        if (index == 0) return const InboxReasonLine();
        if (status != null) return status;
        final item = _items[index - 1];
        if (item.more) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('inbox-show-more'),
              onPressed: () => setState(() {
                if (_segment == _Segment.done) {
                  _doneShown += _donePage;
                } else {
                  _droppedShown += _donePage;
                }
              }),
              child: const Text('Show 30 more'),
            ),
          );
        }
        if (item.id == null) {
          return Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: AppSectionHeader(
                key: ValueKey('inbox-section-${item.title}'),
                title: item.title!,
                trailing: Text(
                  '${item.count}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          );
        }
        final id = item.id!;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: InboxIdeaRow(
            key: _rowKeys.putIfAbsent(id, GlobalKey.new),
            itemId: id,
          ),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const PageSearchTitle('Inbox'),
        actions: const [PageSearchAction(), SyncStatusAction()],
      ),
      body: ColoredBox(
        color: tokens.canvas,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: experimentColumnMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InboxQuickAdd(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_Segment>(
                        key: const ValueKey('inbox-segments'),
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        segments: [
                          _segmentOf(
                            _Segment.open,
                            'Open',
                            state.loaded
                                ? matches?.open ?? state.openCount
                                : null,
                          ),
                          _segmentOf(
                            _Segment.done,
                            'Done',
                            state.loaded
                                ? matches?.done ?? state.done.length
                                : null,
                          ),
                          _segmentOf(
                            _Segment.dropped,
                            'Dropped',
                            state.loaded
                                ? matches?.dropped ?? state.dropped.length
                                : null,
                          ),
                        ],
                        selected: {_segment},
                        onSelectionChanged: (selection) =>
                            setState(() => _segment = selection.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
