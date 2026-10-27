import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../layout/breakpoints.dart';
import '../layout/size_class_scope.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/global_search_action.dart';

const _accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const _plain = 'aaaaaaceeeeiiiinooooouuuuyy';
final _spaces = RegExp(r'\s+');

/// [text] lower-cased with common Latin accents removed, one character for
/// one character (so 'Café' becomes 'cafe'). Other text is only lower-cased.
///
/// Universal Search folds accents too (FTS unicode61), so both find the same.
String foldAccents(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final unit in lower.runes) {
    final char = String.fromCharCode(unit);
    final at = _accented.indexOf(char);
    out.write(at < 0 ? char : _plain[at]);
  }
  return out.toString();
}

/// [text] as page search compares it: trimmed, runs of whitespace collapsed
/// to one space, and passed through [foldAccents].
String pageSearchFold(String text) =>
    foldAccents(text.trim().replaceAll(_spaces, ' '));

/// The query that [pageSearchHit] compares against (see [pageSearchFold]).
String pageSearchNeedle(String raw) => pageSearchFold(raw);

/// Whether [text] contains the whole [needle], ignoring case, accents and
/// extra spaces.
///
/// Contiguous only: no word splitting, fuzziness or ranking. A blank needle
/// matches nothing, so an empty field never filters a page.
bool pageSearchHit(String? text, String needle) =>
    needle.isNotEmpty && text != null && pageSearchFold(text).contains(needle);

/// One line of [text] around the first match, at most [max] characters long.
///
/// Runs of whitespace become one space and a cut side gets a '…'. Without a match (or with
/// text that already fits) it returns the start of [text].
String pageSearchSnippet(String text, String needle, {int max = 90}) {
  final flat = text.trim().replaceAll(_spaces, ' ');
  if (flat.length <= max) return flat;
  final lower = foldAccents(flat);
  // Lower-casing can change the length (for example 'İ'); then the index of
  // the match does not point into [flat], so fall back to the start.
  final at = needle.isEmpty || lower.length != flat.length
      ? -1
      : lower.indexOf(needle);
  var start = at < 0 ? 0 : math.max(0, at - (max - needle.length) ~/ 2);
  var end = start + max;
  if (end > flat.length) {
    end = flat.length;
    start = end - max;
  }
  final cutLeft = start > 0;
  final cutRight = end < flat.length;
  if (cutLeft) start++;
  if (cutRight) end--;
  return '${cutLeft ? '…' : ''}${flat.substring(start, end)}'
      '${cutRight ? '…' : ''}';
}

/// Ctrl/Cmd+Enter would reach the global save-and-close from the field.
const _fieldKeys = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter, control: true):
      DoNothingAndStopPropagationIntent(),
  SingleActivator(LogicalKeyboardKey.enter, meta: true):
      DoNothingAndStopPropagationIntent(),
};

/// State of one page's search: open or closed, the field, and a debounced
/// query.
///
/// Created and disposed by [PageSearchScope], so it lives and dies with the
/// page. While closed it holds no timer and no listener.
class PageSearchController {
  PageSearchController({this.debounce = const Duration(milliseconds: 150)});

  final Duration debounce;
  final TextEditingController text = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'page-search');

  final _open = ValueNotifier<bool>(false);
  final _needle = ValueNotifier<String>('');
  Timer? _timer;
  FocusNode? _returnFocus;
  double? _savedOffset;
  String _pending = '';

  /// True while the field is shown.
  ValueListenable<bool> get isOpen => _open;

  /// [pageSearchNeedle] of the field after [debounce]; '' while closed or
  /// blank. Text that becomes blank publishes '' at once.
  ValueListenable<String> get needle => _needle;

  /// The page's scroll position, so close can put it back where it was.
  ScrollPosition? Function()? scrollPosition;

  /// Opens the field, or focuses it and selects its text if already open.
  ///
  /// Remembers the focused node so [close] can give focus back to it.
  void open() {
    if (_open.value) {
      focusNode.requestFocus();
      text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.text.length,
      );
      return;
    }
    final focused = FocusManager.instance.primaryFocus;
    _returnFocus = identical(focused, focusNode) ? null : focused;
    text.addListener(_onText);
    _open.value = true;
    // The field is built in the next frame, so it can only focus after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_open.value) focusNode.requestFocus();
    });
  }

  /// Clears the text and closes the field.
  ///
  /// With [restoreFocus] focus goes back to where it was before [open]. With
  /// [restoreScroll] the page returns, after the next frame, to the offset it
  /// had when the query first became non-empty.
  void close({bool restoreScroll = true, bool restoreFocus = true}) {
    if (!_open.value) return;
    _timer?.cancel();
    _timer = null;
    text.removeListener(_onText);
    text.clear();
    _pending = '';
    final offset = _savedOffset;
    _savedOffset = null;
    _needle.value = '';
    _open.value = false;
    final back = _returnFocus;
    _returnFocus = null;
    if (restoreFocus && back != null && back.context?.mounted == true) {
      back.requestFocus();
    } else {
      focusNode.unfocus();
    }
    if (restoreScroll && offset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final position = scrollPosition?.call();
        if (position == null || !position.hasPixels) return;
        position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      });
    }
  }

  void _onText() {
    final raw = pageSearchNeedle(text.text);
    // Selection changes notify too.
    if (raw == _pending) return;
    _pending = raw;
    _timer?.cancel();
    _timer = null;
    if (raw.isEmpty) {
      _publish('');
    } else {
      _timer = Timer(debounce, () => _publish(raw));
    }
  }

  void _publish(String value) {
    if (_needle.value.isEmpty && value.isNotEmpty) {
      final position = scrollPosition?.call();
      _savedOffset = position != null && position.hasPixels
          ? position.pixels
          : null;
    }
    _needle.value = value;
  }

  void dispose() {
    _timer?.cancel();
    text.removeListener(_onText);
    _open.dispose();
    _needle.dispose();
    text.dispose();
    focusNode.dispose();
  }
}

/// Tells Ctrl+F which page search belongs to the current route.
///
/// Owned by the keyboard shortcut handler. It holds controllers only, never
/// planner data, so it is the same for every account.
class PageSearchRegistry {
  final _entries =
      <({PageSearchController controller, ModalRoute<Object?> route})>[];

  void attach(PageSearchController controller, ModalRoute<Object?> route) {
    detach(controller);
    _entries.add((controller: controller, route: route));
  }

  void detach(PageSearchController controller) {
    _entries.removeWhere((entry) => identical(entry.controller, controller));
  }

  /// The newest attached controller whose route is current and active.
  ///
  /// Null on pages without a [PageSearchScope], which leaves Ctrl+F opening
  /// the universal Search.
  PageSearchController? get current {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      if (entry.route.isCurrent && entry.route.isActive) {
        return entry.controller;
      }
    }
    return null;
  }
}

/// Makes a [PageSearchRegistry] reachable from the pages below it.
class PageSearchRegistryScope extends InheritedWidget {
  const PageSearchRegistryScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final PageSearchRegistry registry;

  /// Lookup only: pages never rebuild because of the registry.
  static PageSearchRegistry? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<PageSearchRegistryScope>()
      ?.registry;

  @override
  bool updateShouldNotify(PageSearchRegistryScope old) =>
      registry != old.registry;
}

class _PageSearchInherited extends InheritedWidget {
  const _PageSearchInherited({
    required this.controller,
    required this.hint,
    required super.child,
  });

  final PageSearchController controller;
  final String hint;

  @override
  bool updateShouldNotify(_PageSearchInherited old) =>
      controller != old.controller || hint != old.hint;
}

/// Marks a page as searchable and owns its [PageSearchController].
///
/// Wrap the page in its route builder. Search closes when another route
/// covers the page, Esc closes it, and Back closes it before leaving.
class PageSearchScope extends StatefulWidget {
  const PageSearchScope({super.key, required this.hint, required this.child});

  /// Placeholder text of the field, for example 'Search Inbox'.
  final String hint;
  final Widget child;

  /// The nearest page search. No rebuild dependency: pages subscribe only to
  /// the notifiers they need.
  static PageSearchController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PageSearchInherited>()?.controller;

  static PageSearchController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No PageSearchScope above this widget.');
    return controller!;
  }

  static String? hintOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PageSearchInherited>()?.hint;

  @override
  State<PageSearchScope> createState() => _PageSearchScopeState();
}

class _PageSearchScopeState extends State<PageSearchScope> {
  late final PageSearchController _controller;
  PageSearchRegistry? _registry;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    _controller = PageSearchController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = PageSearchRegistryScope.maybeOf(context);
    final route = ModalRoute.of<Object?>(context);
    if (!identical(registry, _registry) || !identical(route, _route)) {
      _registry?.detach(_controller);
      _registry = registry;
      _route = route;
      if (registry != null && route != null) {
        registry.attach(_controller, route);
      }
    }
    // Another route covers this page (for example a pushed Search): close
    // without taking focus back from it.
    if (ModalRoute.isCurrentOf(context) == false && _controller.isOpen.value) {
      _controller.close(restoreScroll: false, restoreFocus: false);
    }
  }

  @override
  void dispose() {
    _registry?.detach(_controller);
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _controller.isOpen.value) {
      _controller.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return _PageSearchInherited(
      controller: _controller,
      hint: widget.hint,
      child: ValueListenableBuilder<bool>(
        valueListenable: _controller.isOpen,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: widget.child,
        ),
        builder: (context, open, child) => PopScope(
          canPop: !open,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _controller.close();
          },
          child: child!,
        ),
      ),
    );
  }
}

/// The AppBar title: [title] while search is closed, the field while open.
///
/// Without a [PageSearchScope] (for example a screen pumped on its own in a
/// test) it is just the `Text`.
class PageSearchTitle extends StatelessWidget {
  const PageSearchTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final controller = PageSearchScope.maybeOf(context);
    if (controller == null) return Text(title);
    final hint = PageSearchScope.hintOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isOpen,
      builder: (context, open, _) => open
          ? Shortcuts(
              shortcuts: _fieldKeys,
              child: TextField(
                key: const ValueKey('page-search-field'),
                controller: controller.text,
                focusNode: controller.focusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    key: const ValueKey('page-search-close'),
                    tooltip: 'Close search',
                    icon: const Icon(
                      Icons.close,
                      semanticLabel: 'Close search',
                    ),
                    onPressed: controller.close,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            )
          : Text(title),
    );
  }
}

bool get _isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The phone top-bar search icon of a searchable page.
///
/// Looks like [GlobalSearchAction] and shows at compact width, but opens the
/// page's own search. On Android and iOS it shows at every width, since a
/// touch tablet has no Ctrl+F. Hidden while the field is open, since the
/// field has its own close button.
class PageSearchAction extends StatelessWidget {
  const PageSearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PageSearchScope.maybeOf(context);
    if (controller == null) return const GlobalSearchAction();
    if (!DaySizeClass.of(context).isCompact && !_isTouchPlatform) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isOpen,
      builder: (context, open, _) => open
          ? const SizedBox.shrink()
          : IconButton(
              key: const ValueKey('page-search-action'),
              tooltip: 'Search',
              icon: const Icon(Icons.search, semanticLabel: 'Search'),
              onPressed: controller.open,
            ),
    );
  }
}

/// The empty state of a page search, with a way into the universal Search.
class PageSearchNoMatches extends StatelessWidget {
  const PageSearchNoMatches({super.key, this.message = 'No matches'});

  /// The line above the link; a page whose results are split in segments says
  /// where the matches are.
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.textMuted),
          ),
          TextButton(
            key: const ValueKey('page-search-everything'),
            onPressed: () {
              final query =
                  PageSearchScope.maybeOf(context)?.text.text.trim() ?? '';
              context.push(
                Uri(
                  path: '/search',
                  queryParameters: query.isEmpty ? null : {'q': query},
                ).toString(),
              );
            },
            child: const Text('Search everything'),
          ),
        ],
      ),
    );
  }
}

/// [text] with every occurrence of any of [terms] marked, ignoring case and
/// accents ('cafe' marks 'Café').
///
/// Used by the universal Search tile with one term per word and by
/// [PageSearchHighlight] with the whole page-search needle. Without a term, or
/// when folding changed the length of [text], it is a plain [Text].
class SearchHighlight extends StatelessWidget {
  const SearchHighlight(
    this.text, {
    super.key,
    required this.terms,
    this.style,
    this.maxLines,
    this.prefix = '',
  });

  /// Shown before [text] and never marked, for example a field label.
  final String prefix;
  final String text;
  final List<String> terms;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final folded = foldAccents(text);
    final wanted = [
      for (final term in terms)
        if (term.isNotEmpty) foldAccents(term),
    ];
    if (wanted.isEmpty || folded.length != text.length) {
      return Text(
        prefix + text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final pattern = RegExp(wanted.map(RegExp.escape).join('|'));
    final spans = <TextSpan>[if (prefix.isNotEmpty) TextSpan(text: prefix)];
    var cursor = 0;
    for (final match in pattern.allMatches(folded)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
            backgroundColor: scheme.primary.withValues(alpha: 0.14),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// [SearchHighlight] of the current page search. Plain text while the page
/// has no [PageSearchScope] or no query.
class PageSearchHighlight extends StatelessWidget {
  const PageSearchHighlight(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.prefix = '',
  });

  final String prefix;
  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final controller = PageSearchScope.maybeOf(context);
    if (controller == null) {
      return SearchHighlight(
        text,
        terms: const [],
        style: style,
        maxLines: maxLines,
        prefix: prefix,
      );
    }
    return ValueListenableBuilder<String>(
      valueListenable: controller.needle,
      builder: (context, needle, _) => SearchHighlight(
        text,
        terms: [needle],
        style: style,
        maxLines: maxLines,
        prefix: prefix,
      ),
    );
  }
}
