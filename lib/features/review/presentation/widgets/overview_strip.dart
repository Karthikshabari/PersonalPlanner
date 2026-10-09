import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../domain/review_mood.dart';
import '../../domain/weekly_review_numbers.dart';
import 'mood_face.dart';
import 'review_equal_grid.dart';
import 'review_theme.dart';
import 'weekly_review_style.dart';

/// Building blocks shared by the Overview day strip and week strip: the lazy
/// strip itself (edge fades, arrows, whole-tile scrolling), the selectable
/// tile frame, the small tag, the face / progress slots, the legend, and the
/// measured tile size. Presentation only; the strips own the data.

/// Whether the platform is touch-only (phones and tablets), where swiping
/// replaces the arrow buttons on narrow screens.
bool get overviewTouchOnly =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Screens narrower than this hide the strip arrows on touch-only platforms.
const double overviewArrowsMinScreenWidth = 600;

/// The Android selection haptic; nothing on desktop.
void overviewSelectionHaptic() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    HapticFeedback.selectionClick();
  }
}

// ---------------------------------------------------------------------------
// Text styles
// ---------------------------------------------------------------------------

/// The three text levels of a tile, shared by the tile bodies and by
/// [OverviewTileMetrics] so the size is measured with the styles that render.
abstract final class OverviewTileText {
  /// Weekday / "Today" and "No tasks": the shared 12 px caption.
  static TextStyle caption(BuildContext context) => weeklyCaptionStyle(context);

  /// The date or the week range: body, semibold.
  static TextStyle date(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
  }

  /// The completion value, as in Weekly's day tiles.
  static TextStyle percent(BuildContext context) =>
      reviewMonoStyle(context, fontSize: 13).copyWith(
        color: AppThemeTokens.of(context).textPrimary,
        fontWeight: FontWeight.w500,
      );

  /// Tag text, as in Weekly's day tiles (12 px label, muted).
  static TextStyle tag(BuildContext context) =>
      (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
        color: AppThemeTokens.of(context).textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
}

/// WCAG contrast ratio of two opaque colours.
double overviewContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [color] as text on [background]: unchanged when it already reads at 4.5:1,
/// otherwise mixed toward [toward] (the primary text colour) in the smallest
/// steps that get there. Keeps the tier hue recognisable where a pale tier
/// colour would be too faint on the light card.
Color overviewReadable(Color color, Color background, Color toward) {
  for (var step = 0; step <= 10; step++) {
    final mixed = Color.lerp(color, toward, step / 10)!;
    if (overviewContrast(mixed, background) >= 4.5) return mixed;
  }
  return toward;
}

// ---------------------------------------------------------------------------
// Tile metrics
// ---------------------------------------------------------------------------

/// Width and height every tile of one mode shares. Both come from the real
/// text at the current text scale (never from the data), so all tiles grow
/// equally and no line can overflow.
@immutable
class OverviewTileMetrics {
  const OverviewTileMetrics({required this.width, required this.height});

  final double width;
  final double height;

  static const double horizontalPadding = 8;
  static const double verticalPadding = 10;
  static const double gap = 4;
  static const double border = 1;
  static const double faceSize = 30;
  static const double barHeight = 4;
  static const double tagHorizontalPadding = 6;
  static const double tagVerticalPadding = 2;
  static const double tagIconSize = 12;
  static const double minWidth = 96;

  /// Width of the content column for a tile [width] wide.
  static double contentWidthOf(double width) =>
      width - 2 * (horizontalPadding + border);

  static Size _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  static OverviewTileMetrics measure(
    BuildContext context, {
    required bool weeks,
    required bool hasContext,
  }) {
    final caption = OverviewTileText.caption(context);
    final date = OverviewTileText.date(context);
    final percent = OverviewTileText.percent(context);
    final tag = OverviewTileText.tag(context);

    // Month names differ in width, so measure all twelve (the digits are
    // tabular). A week range crosses a month boundary at most.
    var dateWidth = 0.0;
    var dateHeight = 0.0;
    for (var month = 1; month <= 12; month++) {
      final start = DateTime(2025, month, 28);
      final label = weeks
          ? weekRangeLabel(start, start.add(const Duration(days: 6)))
          : DateFormat('MMM d').format(start);
      final size = _measure(context, label, date);
      dateWidth = math.max(dateWidth, size.width);
      dateHeight = math.max(dateHeight, size.height);
    }
    final eyebrow = weeks ? Size.zero : _measure(context, 'Today', caption);
    final noTasks = _measure(context, 'No tasks', caption);
    final percentSize = _measure(context, '100%', percent);
    final valueHeight = math.max(noTasks.height, percentSize.height);

    var tagWidth = 0.0;
    var tagTextHeight = 0.0;
    for (final label in [...reviewMoodLabels, 'Not reviewed', 'Reviewed']) {
      final size = _measure(context, label, tag);
      tagWidth = math.max(tagWidth, size.width);
      tagTextHeight = math.max(tagTextHeight, size.height);
    }
    final tagHeight = tagTextHeight + 2 * tagVerticalPadding;
    final contextTagHeight =
        math.max(tagTextHeight, tagIconSize) + 2 * tagVerticalPadding;

    final content = [
      eyebrow.width,
      dateWidth,
      noTasks.width,
      percentSize.width,
      tagWidth + 2 * tagHorizontalPadding,
    ].reduce(math.max);
    final width = math.max(
      minWidth,
      content + 2 * (horizontalPadding + border),
    );

    var height = 2 * (verticalPadding + border);
    if (!weeks) height += eyebrow.height + gap;
    height += dateHeight + gap;
    height += faceSize + gap;
    height += valueHeight + gap;
    height += barHeight + gap;
    height += tagHeight;
    if (hasContext) height += gap + contextTagHeight;
    return OverviewTileMetrics(
      width: width.ceilToDouble(),
      height: height.ceilToDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OverviewTileMetrics &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/// The selected tile of a strip. Each tile listens to its own flag, so
/// selecting rebuilds only the tile that lost the selection, the tile that
/// gained it, and whatever listens to [listenable] (the summary row).
class OverviewSelection<K> {
  OverviewSelection(K initial) : _value = ValueNotifier<K>(initial);

  final ValueNotifier<K> _value;
  final Map<K, ValueNotifier<bool>> _flags = {};

  K get value => _value.value;
  ValueListenable<K> get listenable => _value;

  /// The flag a tile for [key] listens to. Created on first use, so only
  /// tiles that were built cost anything.
  ValueListenable<bool> flag(K key) =>
      _flags.putIfAbsent(key, () => ValueNotifier<bool>(key == _value.value));

  void select(K key) {
    final previous = _value.value;
    if (previous == key) return;
    _value.value = key;
    _flags[previous]?.value = false;
    _flags[key]?.value = true;
  }

  void dispose() {
    _value.dispose();
    for (final flag in _flags.values) {
      flag.dispose();
    }
    _flags.clear();
  }
}

// ---------------------------------------------------------------------------
// Tile frame
// ---------------------------------------------------------------------------

/// The interactive shell of a tile: the inset surface (tonal hover, accent
/// border and faint tint when selected), the pressed scale, the 2 px focus
/// ring, the pointer cursor, Enter / Space activation and the button
/// semantics. [child] is built once by the strip and is not rebuilt by hover,
/// press, focus or selection.
class OverviewTileFrame extends StatefulWidget {
  const OverviewTileFrame({
    super.key,
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.child,
  });

  final ValueListenable<bool> selected;

  /// What a screen reader says, without "selected" (that is a semantics flag).
  final String label;
  final VoidCallback onSelect;
  final Widget child;

  @override
  State<OverviewTileFrame> createState() => _OverviewTileFrameState();
}

class _OverviewTileFrameState extends State<OverviewTileFrame> {
  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  late bool _selected = widget.selected.value;
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        _activate();
        return null;
      },
    ),
  };

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_onSelectedChanged);
  }

  @override
  void didUpdateWidget(OverviewTileFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      oldWidget.selected.removeListener(_onSelectedChanged);
      widget.selected.addListener(_onSelectedChanged);
      _selected = widget.selected.value;
    }
  }

  @override
  void dispose() {
    widget.selected.removeListener(_onSelectedChanged);
    super.dispose();
  }

  void _onSelectedChanged() {
    final value = widget.selected.value;
    if (value != _selected) setState(() => _selected = value);
  }

  void _activate() {
    if (!_selected) overviewSelectionHaptic();
    widget.onSelect();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(WeeklyStyle.insetRadius(context));
    final base = _hovered
        ? WeeklyStyle.insetHover(context)
        : WeeklyStyle.inset(context);
    // Selection is a fill plus a border, never colour alone.
    final fill = _selected
        ? Color.alphaBlend(accent.withValues(alpha: 0.12), base)
        : base;
    return Semantics(
      container: true,
      button: true,
      selected: _selected,
      focusable: true,
      focused: _focused,
      label: widget.label,
      onTap: _activate,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: _shortcuts,
        actions: _actions,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? WeeklyStyle.pressedScale : 1.0,
            duration: WeeklyStyle.quickFor(context),
            curve: WeeklyStyle.curve,
            child: AnimatedContainer(
              duration: WeeklyStyle.quickFor(context),
              curve: WeeklyStyle.curve,
              padding: const EdgeInsets.symmetric(
                horizontal: OverviewTileMetrics.horizontalPadding,
                vertical: OverviewTileMetrics.verticalPadding,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(
                  color: _selected ? accent : Colors.transparent,
                  width: OverviewTileMetrics.border,
                ),
              ),
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: tokens.focus, width: 2),
                    )
                  : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile parts
// ---------------------------------------------------------------------------

/// The face for a reviewed tile, the dashed circle for an unreviewed one.
/// Both are painted graphics, so they sit behind a repaint boundary.
class OverviewTileFace extends StatelessWidget {
  const OverviewTileFace({super.key, required this.mood});

  final int? mood;

  @override
  Widget build(BuildContext context) {
    final level = mood;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: OverviewTileMetrics.faceSize,
        child: level != null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ReviewColors.of(context)
                      .mood(level)
                      .withValues(alpha: 0.16),
                ),
                child: MoodFace(
                  level: level,
                  size: OverviewTileMetrics.faceSize,
                ),
              )
            : CustomPaint(
                painter: _DashedCirclePainter(
                  AppThemeTokens.of(context).textMuted,
                ),
              ),
      ),
    );
  }
}

/// A dashed circle whose dash path is built once per size and reused.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);

  static const double _stroke = 1.5;
  static const double _dash = 4;
  static const double _gap = 3;
  static Path? _cached;
  static Size? _cachedSize;

  final Color color;

  static Path _pathFor(Size size) {
    if (_cachedSize == size && _cached != null) return _cached!;
    final circle = Path()..addOval((Offset.zero & size).deflate(_stroke / 2));
    final dashes = Path();
    for (final metric in circle.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        dashes.addPath(
          metric.extractPath(
            distance,
            math.min(distance + _dash, metric.length),
          ),
          Offset.zero,
        );
        distance += _dash + _gap;
      }
    }
    _cachedSize = size;
    return _cached = dashes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _pathFor(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Weekly's day-tile progress bar: a 4 px track in the outline colour and a
/// success fill. Without a value only the reserved space is left, so the tags
/// below line up across tiles.
class OverviewTileProgress extends StatelessWidget {
  const OverviewTileProgress({super.key, required this.percent});

  final int? percent;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    return SizedBox(
      width: double.infinity,
      height: OverviewTileMetrics.barHeight,
      child: value == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value / 100,
                minHeight: OverviewTileMetrics.barHeight,
                color: ReviewColors.of(context).success,
                backgroundColor: AppThemeTokens.of(context).outline,
              ),
            ),
    );
  }
}

/// The small status pill of Weekly's day tiles: "Not reviewed", the tier name
/// (in the tier colour) or the day-context label with its icon. One line; a
/// long label is ellipsized and the tooltip carries the full text.
class OverviewTag extends StatelessWidget {
  const OverviewTag({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final style = OverviewTileText.tag(context)
        .copyWith(color: color ?? tokens.textMuted);
    final tag = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(WeeklyStyle.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OverviewTileMetrics.tagHorizontalPadding,
          vertical: OverviewTileMetrics.tagVerticalPadding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: OverviewTileMetrics.tagIconSize,
                color: style.color,
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
    // Only the open-ended day-context label can be cut; the fixed labels are
    // measured to fit.
    if (icon == null) return tag;
    return Tooltip(message: label, excludeFromSemantics: true, child: tag);
  }
}

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

/// The four tier faces with their names. Static. One row when it fits, a 2 × 2
/// grid of equal cells otherwise.
class OverviewLegend extends StatelessWidget {
  const OverviewLegend({super.key});

  static const double _icon = 18;
  static const double _iconGap = 6;
  static const double _rowGap = 24;

  @override
  Widget build(BuildContext context) {
    final style = weeklyCaptionStyle(context);
    final labelWidth = measureWidestText(context, reviewMoodLabels, style);
    final cell = _icon + _iconGap + labelWidth;
    Widget item(int level) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: MoodFace(level: level, size: _icon),
        ),
        const SizedBox(width: _iconGap),
        Flexible(child: Text(reviewMoodLabel(level), style: style)),
      ],
    );
    final items = [for (var level = 1; level <= 4; level++) item(level)];
    return LayoutBuilder(
      key: const ValueKey('overview-legend'),
      builder: (context, constraints) {
        final oneRow = 4 * cell + 3 * _rowGap <= constraints.maxWidth;
        if (oneRow) {
          return Wrap(
            spacing: _rowGap,
            runSpacing: AppSpacing.sm,
            children: items,
          );
        }
        return ReviewEqualGrid(
          minCellWidth: cell,
          spacing: AppSpacing.sm,
          children: items,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Edge fade and arrows
// ---------------------------------------------------------------------------

/// Gradient from the card colour to transparent over the first 24 px of a
/// scrolling edge. It uses the surface token, so it follows light and dark
/// themes, ignores pointers, and fades in and out only when animations are on.
class ReviewStripEdgeFade extends StatelessWidget {
  const ReviewStripEdgeFade({
    super.key,
    required this.alignment,
    required this.visible,
  });

  static const double width = 24;

  final Alignment alignment;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final surface = AppThemeTokens.of(context).surface;
    final left = alignment == Alignment.centerLeft;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: width,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: WeeklyStyle.quickFor(context),
          curve: WeeklyStyle.curve,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: alignment,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [surface, surface.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48 dp scroll button. It reads as disabled at the end of the strip, and
/// the tooltip is its label for screen readers.
class ReviewStripArrowButton extends StatelessWidget {
  const ReviewStripArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final inset = WeeklyStyle.inset(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeeklyStyle.insetRadius(context)),
    );
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(icon, size: 22),
        onPressed: onPressed,
        style:
            IconButton.styleFrom(
              backgroundColor: inset,
              disabledBackgroundColor: inset,
              hoverColor: tokens.textPrimary.withValues(alpha: 0.08),
              fixedSize: const Size.square(48),
              minimumSize: const Size.square(48),
              shape: shape,
            ).copyWith(
              side: WidgetStateBorderSide.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: tokens.focus, width: 2)
                    : BorderSide.none,
              ),
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strip
// ---------------------------------------------------------------------------

@immutable
class _Edges {
  const _Edges({required this.older, required this.newer});

  final bool older;
  final bool newer;

  @override
  bool operator ==(Object other) =>
      other is _Edges && other.older == older && other.newer == newer;

  @override
  int get hashCode => Object.hash(older, newer);
}

/// A horizontal, lazily built strip of equally sized tiles, newest at the
/// right edge. Scrolling state (edge fades, arrow enablement) lives in value
/// notifiers, so scrolling never rebuilds the tiles.
class OverviewStrip extends StatefulWidget {
  const OverviewStrip({
    super.key,
    required this.keyPrefix,
    required this.listKey,
    required this.itemCount,
    required this.tileMetrics,
    required this.itemBuilder,
    required this.hasMore,
    required this.onLoadMore,
    required this.olderTooltip,
    required this.newerTooltip,
  });

  /// `overview` or `overview-week`: `<prefix>-older`, `-newer`, `-fade-older`
  /// and `-fade-newer` are the keys of the arrows and fades.
  final String keyPrefix;
  final Key listKey;
  final int itemCount;
  final OverviewTileMetrics tileMetrics;

  /// Builds the tile for [index] (0 = newest). Called only for visible tiles
  /// and a small cache around them.
  final IndexedWidgetBuilder itemBuilder;

  /// More history can be loaded beyond [itemCount].
  final bool hasMore;
  final VoidCallback onLoadMore;
  final String olderTooltip;
  final String newerTooltip;

  /// Space between two tiles.
  static const double tileGap = 8;

  /// Space above and below the tiles inside the strip.
  static const double verticalInset = 4;

  @override
  State<OverviewStrip> createState() => _OverviewStripState();
}

class _OverviewStripState extends State<OverviewStrip> {
  final _controller = ScrollController();
  final _edges = ValueNotifier<_Edges>(
    const _Edges(older: false, newer: false),
  );

  /// Distance between the start of one tile and the next, as laid out.
  double _extent = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void didUpdateWidget(OverviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasMore != widget.hasMore ||
        oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _updateEdges(_controller.position);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _edges.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_controller.hasClients || !widget.hasMore) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      widget.onLoadMore();
    }
  }

  // The strip is reversed: pixel 0 is the newest end (at the right).
  void _updateEdges(ScrollMetrics metrics) {
    final newer = metrics.pixels > metrics.minScrollExtent + 0.5;
    final older =
        metrics.pixels < metrics.maxScrollExtent - 0.5 || widget.hasMore;
    _edges.value = _Edges(older: older, newer: newer);
    _maybeLoadMore();
  }

  /// Scrolls whole tiles: the number of fully visible tiles minus one, so the
  /// last tile you saw stays in view. [direction] 1 goes to older tiles.
  void _scrollTiles(int direction) {
    if (!_controller.hasClients) return;
    _maybeLoadMore();
    final position = _controller.position;
    final visible = math.max(1, (position.viewportDimension / _extent).floor());
    final step = math.max(1, visible - 1);
    final index = (position.pixels / _extent).round();
    final target = ((index + direction * step) * _extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showArrows =
        !(overviewTouchOnly &&
            MediaQuery.sizeOf(context).width < overviewArrowsMinScreenWidth);
    final prefix = widget.keyPrefix;
    final tileGap = OverviewStrip.tileGap;
    return LayoutBuilder(
      builder: (context, constraints) {
        final arrowSpace = showArrows ? 2 * (48 + AppSpacing.sm) : 0.0;
        final viewport = math.max(0.0, constraints.maxWidth - arrowSpace);
        // A tile is never wider than the strip, so one always fits whole.
        _extent = math.max(
          1.0,
          math.min(widget.tileMetrics.width + tileGap, viewport),
        );
        final list = Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent || !_controller.hasClients) {
              return;
            }
            final delta = event.scrollDelta.dy != 0
                ? event.scrollDelta.dy
                : event.scrollDelta.dx;
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              final p = _controller.position;
              _controller.jumpTo(
                (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent),
              );
            });
          },
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) {
              _updateEdges(n.metrics);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) _updateEdges(n.metrics);
                return false;
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.builder(
                  key: widget.listKey,
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  reverse: true, // index 0 (the newest) sits at the right edge
                  itemExtent: _extent,
                  itemCount: widget.itemCount,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OverviewStrip.tileGap / 2,
                      vertical: OverviewStrip.verticalInset,
                    ),
                    child: widget.itemBuilder(context, index),
                  ),
                ),
              ),
            ),
          ),
        );
        final strip = SizedBox(
          height: widget.tileMetrics.height + 2 * OverviewStrip.verticalInset,
          child: Stack(
            children: [
              list,
              ValueListenableBuilder<_Edges>(
                valueListenable: _edges,
                builder: (context, edges, _) => ReviewStripEdgeFade(
                  key: ValueKey('$prefix-fade-older'),
                  alignment: Alignment.centerLeft,
                  visible: edges.older,
                ),
              ),
              ValueListenableBuilder<_Edges>(
                valueListenable: _edges,
                builder: (context, edges, _) => ReviewStripEdgeFade(
                  key: ValueKey('$prefix-fade-newer'),
                  alignment: Alignment.centerRight,
                  visible: edges.newer,
                ),
              ),
            ],
          ),
        );
        // Tab order: the earlier arrow, the tiles left to right, the later
        // arrow. Position alone would put cached tiles that sit beside the
        // viewport before the arrow.
        final tiles = FocusTraversalGroup(child: strip);
        if (!showArrows) return tiles;
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: ValueListenableBuilder<_Edges>(
                  valueListenable: _edges,
                  builder: (context, edges, _) => ReviewStripArrowButton(
                    key: ValueKey('$prefix-older'),
                    icon: Icons.chevron_left_rounded,
                    tooltip: widget.olderTooltip,
                    onPressed: edges.older ? () => _scrollTiles(1) : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: tiles,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: ValueListenableBuilder<_Edges>(
                  valueListenable: _edges,
                  builder: (context, edges, _) => ReviewStripArrowButton(
                    key: ValueKey('$prefix-newer'),
                    icon: Icons.chevron_right_rounded,
                    tooltip: widget.newerTooltip,
                    onPressed: edges.newer ? () => _scrollTiles(-1) : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
