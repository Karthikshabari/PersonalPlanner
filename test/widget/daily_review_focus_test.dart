import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';

import '../helpers/daily_review_fixtures.dart';
import '../helpers/test_container.dart';

/// Tab follows the reading order in both layouts. The long list runs under
/// the bottom bar's screen position, so each card and the bar are separate
/// traversal groups; without them Tab hopped to Save between two controls.
void main() {
  /// A short name for what holds the focus: a widget key, or a tooltip.
  String? focusName() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? name;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget.key is ValueKey<String>) {
        name = (widget.key! as ValueKey<String>).value;
        return false;
      }
      if (widget is Tooltip) {
        name = 'chip:${widget.message}';
        return false;
      }
      return true;
    });
    return name;
  }

  Future<List<String>> tabThrough(WidgetTester tester) async {
    final order = <String>[];
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 50));
      final name = focusName();
      if (name != null) order.add(name);
      if (name == 'review-save') break;
    }
    return order;
  }

  for (final (label, size) in [
    ('wide', const Size(1400, 1000)),
    ('narrow', const Size(390, 900)),
  ]) {
    testWidgets('Tab order follows the reading order ($label)', (tester) async {
      late List<String> ids;
      final container = await pumpDaily(
        tester,
        surface: size,
        seeds: [
          const DailySeed('Alpha', status: TaskStatus.skipped),
          const DailySeed('Beta', status: TaskStatus.skipped),
          const DailySeed('Gamma', status: TaskStatus.completed),
        ],
        onSeeded: (v) => ids = v,
      );
      final order = await tabThrough(tester);
      int at(String name) {
        final index = order.indexOf(name);
        expect(index, isNonNegative, reason: '$name not reached: $order');
        return index;
      }

      final header = at('review-today');
      final edit = at('review-edit-presets');
      final alpha = at('review-reason-${ids[0]}');
      final beta = at('review-reason-${ids[1]}');
      final mood = [for (var l = 1; l <= 4; l++) at('review-mood-$l')];
      final note = at('review-note');
      final save = at('review-save');

      expect(mood, [...mood]..sort(), reason: 'tiles left to right, top down');
      expect(header, lessThan(edit));
      expect(edit, lessThan(alpha));
      expect(alpha, lessThan(beta));
      expect(note, lessThan(save));
      expect(save, order.length - 1, reason: 'the bar comes last');

      // Alpha's own chips come between Alpha's field and Beta's field, and
      // each control is reached once (no hopping back and forth).
      final chips = [
        for (var i = 0; i < order.length; i++)
          if (order[i].startsWith('chip:')) i,
      ];
      expect(chips.where((i) => i > alpha && i < beta), isNotEmpty);
      expect(
        order.where((n) => n == 'review-save'),
        hasLength(1),
        reason: 'Save is reached once, last: $order',
      );

      if (label == 'wide') {
        // Rating (top right) before the task list; the note after it.
        expect(mood.last, lessThan(edit));
        expect(beta, lessThan(note));
      } else {
        // One column: the list, then the rating, then the note.
        expect(beta, lessThan(mood.first));
        expect(mood.last, lessThan(note));
      }
      await finish(tester, container);
    });
  }
}
