import 'package:flutter/material.dart';

import 'review_equal_row.dart';

/// Widest of [texts] when painted on one line in [style], at the current text
/// scale. Used to decide whether a row of equal cells is wide enough.
double measureWidestText(
  BuildContext context,
  Iterable<String> texts,
  TextStyle? style,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var widest = 0.0;
  for (final text in texts) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  return widest;
}

/// Lays an even number of children out in equal-width cells: one row when
/// every cell is at least [minCellWidth] wide, otherwise rows of two. Never a
/// ragged last row, so four children are 4 or 2 + 2.
class ReviewEqualGrid extends StatelessWidget {
  const ReviewEqualGrid({
    super.key,
    required this.minCellWidth,
    required this.spacing,
    required this.children,
  }) : assert(children.length % 2 == 0);

  final double minCellWidth;
  final double spacing;
  final List<Widget> children;

  /// Whether [count] cells fit one row in [width].
  static bool fitsOneRow({
    required double width,
    required int count,
    required double minCellWidth,
    required double spacing,
  }) => (width - spacing * (count - 1)) / count >= minCellWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow =
            fitsOneRow(
              width: constraints.maxWidth,
              count: children.length,
              minCellWidth: minCellWidth,
              spacing: spacing,
            )
            ? children.length
            : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < children.length; start += perRow) ...[
              if (start > 0) SizedBox(height: spacing),
              ReviewEqualRow(
                spacing: spacing,
                children: children.sublist(start, start + perRow),
              ),
            ],
          ],
        );
      },
    );
  }
}
