import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'review_equal_row.dart';

/// Any number of children in equal-width cells. The column count comes from
/// the grid's own width ([minCellWidth] per cell, at most [maxColumns]); a
/// partly filled last row keeps the same cell width instead of stretching.
class ReviewCellGrid extends StatelessWidget {
  const ReviewCellGrid({
    super.key,
    required this.minCellWidth,
    required this.spacing,
    required this.children,
    this.maxColumns = 3,
  }) : assert(maxColumns >= 1);

  final double minCellWidth;
  final double spacing;
  final int maxColumns;
  final List<Widget> children;

  /// Columns that fit [width]: as many as leave every cell at least
  /// [minCellWidth] wide, between 1 and [maxColumns] (and no more than
  /// [count]).
  static int columnsFor({
    required double width,
    required double minCellWidth,
    required double spacing,
    required int maxColumns,
    required int count,
  }) {
    final fit = ((width + spacing) / (minCellWidth + spacing)).floor();
    return math.max(1, math.min(fit, math.min(maxColumns, math.max(1, count))));
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          width: constraints.maxWidth,
          minCellWidth: minCellWidth,
          spacing: spacing,
          maxColumns: maxColumns,
          count: children.length,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start > 0) SizedBox(height: spacing),
              ReviewEqualRow(
                spacing: spacing,
                children: [
                  for (var i = start; i < start + columns; i++)
                    i < children.length ? children[i] : const SizedBox.shrink(),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
