import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_cell_grid.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_equal_row.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_layout.dart';

void main() {
  group('ReviewLayout.isWide', () {
    test('switches at the same width as the Weekly review', () {
      // The content column (window - 2 x 16, at most 1000) must be >= 760.
      expect(ReviewLayout.isWide(791), isFalse);
      expect(ReviewLayout.isWide(792), isTrue);
      expect(ReviewLayout.isWide(320), isFalse);
      expect(ReviewLayout.isWide(2560), isTrue);
    });
  });

  group('ReviewCellGrid.columnsFor', () {
    int columns(double width, {double min = 140, int count = 6, int max = 3}) =>
        ReviewCellGrid.columnsFor(
          width: width,
          minCellWidth: min,
          spacing: 8,
          maxColumns: max,
          count: count,
        );

    test('as many columns as keep every cell at the minimum width', () {
      expect(columns(100), 1, reason: 'very narrow: one column');
      expect(columns(287), 1);
      expect(columns(288), 2, reason: '2 x 140 + 8');
      expect(columns(435), 2);
      expect(columns(436), 3, reason: '3 x 140 + 2 x 8 = 436');
      expect(columns(440), 3);
      expect(columns(2000), 3, reason: 'capped at maxColumns');
    });

    test('never more columns than children, never fewer than one', () {
      expect(columns(2000, count: 2), 2);
      expect(columns(2000, count: 1), 1);
      expect(columns(2000, count: 0), 1);
      expect(columns(0), 1);
    });
  });

  group('ReviewCellGrid layout', () {
    Future<List<Rect>> cells(
      WidgetTester tester,
      int count, {
      double width = 440,
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ReviewCellGrid(
                minCellWidth: 140,
                spacing: 8,
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      key: ValueKey('cell-$i'),
                      height: 40 + (i % 2) * 6,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return [
        for (var i = 0; i < count; i++)
          tester.getRect(find.byKey(ValueKey('cell-$i'))),
      ];
    }

    for (final count in [1, 2, 3, 4, 5, 7, 8, 11]) {
      testWidgets('$count children: equal widths, no ragged last row', (
        tester,
      ) async {
        final rects = await cells(tester, count);
        expect({for (final r in rects) r.width.toStringAsFixed(2)}.length, 1);
        final perRow = rects.where((r) => r.top == rects.first.top).length;
        expect(perRow, count < 3 ? count : 3);
        // Every row but the last is full; cells in a row share a height.
        for (var i = 0; i < rects.length; i++) {
          final row = i ~/ perRow;
          final same = rects.where((r) => r.top == rects[i].top);
          expect(
            same.length,
            row < (count - 1) ~/ perRow ? perRow : same.length,
          );
          expect({for (final r in same) r.height}.length, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ReviewEqualRow flexes', () {
    testWidgets('split the width 3 : 2 and keep one height', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 512,
              child: ReviewEqualRow(
                spacing: 12,
                flexes: [3, 2],
                children: [
                  SizedBox(key: ValueKey('a'), height: 30),
                  SizedBox(key: ValueKey('b'), height: 70),
                ],
              ),
            ),
          ),
        ),
      );
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(a.width, closeTo(300, 0.01));
      expect(b.width, closeTo(200, 0.01));
      expect(b.left - a.right, closeTo(12, 0.01));
      expect(a.height, 70);
      expect(b.height, 70);
    });

    testWidgets('no flexes (or the wrong number) means equal widths', (
      tester,
    ) async {
      for (final flexes in <List<int>?>[
        null,
        const [1, 2, 3],
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 512,
                child: ReviewEqualRow(
                  spacing: 12,
                  flexes: flexes,
                  children: const [
                    SizedBox(key: ValueKey('a'), height: 30),
                    SizedBox(key: ValueKey('b'), height: 30),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byKey(const ValueKey('a'))).width, 250);
        expect(tester.getSize(find.byKey(const ValueKey('b'))).width, 250);
      }
    });
  });
}
