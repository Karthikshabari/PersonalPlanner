import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/review/domain/weekly_review_draft.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_feeling_card.dart';
import 'package:personal_planner/features/review/presentation/widgets/weekly_mood_card.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(disableAnimations: reduceMotion),
        child: Scaffold(
          body: ListView(padding: const EdgeInsets.all(12), children: [child]),
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _moodHost({String? hint, ValueChanged<int>? onPicked}) {
  var selected = 1;
  return StatefulBuilder(
    builder: (context, setState) => WeeklyMoodCard(
      selected: selected,
      enabled: true,
      lastWeekHint: hint,
      onChanged: (level) {
        setState(() => selected = level);
        onPicked?.call(level);
      },
    ),
  );
}

void main() {
  group('WeeklyMoodCard', () {
    testWidgets('four faces in one row at 360 dp and text scale 1.3', (
      tester,
    ) async {
      await _pump(tester, _moodHost(), textScale: 1.3);

      expect(find.text('How was the week?'), findsOneWidget);
      final firstTop = tester.getTopLeft(
        find.byKey(const ValueKey('weekly-mood-1')),
      );
      for (var level = 1; level <= 4; level++) {
        final option = find.byKey(ValueKey('weekly-mood-$level'));
        expect(tester.getTopLeft(option).dy, firstTop.dy);
        expect(tester.getSize(option).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('radio semantics with Good preselected', (tester) async {
      await _pump(tester, _moodHost());
      final handle = tester.ensureSemantics();

      expect(
        tester.getSemantics(find.byKey(const ValueKey('weekly-mood-1'))),
        isSemantics(
          label: 'Good',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          isButton: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('weekly-mood-4'))),
        isSemantics(
          label: 'Legendary',
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          isButton: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('picking a face pops it for 240 ms', (tester) async {
      int? picked;
      await _pump(tester, _moodHost(onPicked: (level) => picked = level));

      await tester.tap(find.byKey(const ValueKey('weekly-mood-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(picked, 3);
      final pop = find.byKey(const ValueKey('weekly-mood-pop-3-1'));
      expect(pop, findsOneWidget);
      final scale = tester
          .widget<Transform>(
            find.descendant(of: pop, matching: find.byType(Transform)).first,
          )
          .transform
          .getMaxScaleOnAxis();
      expect(scale, greaterThan(1.0));
      await tester.pump(const Duration(milliseconds: 200));
      final settled = tester
          .widget<Transform>(
            find.descendant(of: pop, matching: find.byType(Transform)).first,
          )
          .transform
          .getMaxScaleOnAxis();
      expect(settled, closeTo(1.0, 0.001));
    });

    testWidgets('no pop when animations are off', (tester) async {
      await _pump(tester, _moodHost(), reduceMotion: true);
      await tester.tap(find.byKey(const ValueKey('weekly-mood-2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('weekly-mood-pop-2-1')), findsNothing);
    });

    testWidgets('light haptic on Android only', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, _moodHost());

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.tap(find.byKey(const ValueKey('weekly-mood-2')));
      await tester.pump();
      expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isEmpty);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.tap(find.byKey(const ValueKey('weekly-mood-4')));
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      expect(
        calls
            .where((c) => c.method == 'HapticFeedback.vibrate')
            .map((c) => c.arguments),
        ['HapticFeedbackType.lightImpact'],
      );
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('last week hint', (tester) async {
      await _pump(tester, _moodHost(hint: 'Last week: Great'));
      expect(find.text('Last week: Great'), findsOneWidget);
    });
  });

  group('WeeklyFeelingCard', () {
    Widget feelingHost(List<String> changes, {String initial = ''}) =>
        WeeklyFeelingCard(
          draft: WeeklyReviewDraft(weekStart: DateTime(2026, 9, 28))
              .hydrateFrom(null)
              .copyWith(feeling: initial),
          onChanged: changes.add,
        );

    Finder field() => find.byKey(const ValueKey('weekly-feeling'));
    String text(WidgetTester tester) =>
        tester.widget<TextField>(field()).controller!.text;

    testWidgets('placeholder, chips and counter', (tester) async {
      final changes = <String>[];
      await _pump(tester, feelingHost(changes));

      expect(find.text('How did the week feel?'), findsOneWidget);
      expect(
        find.text('A line or two about how this week felt.'),
        findsOneWidget,
      );
      for (final word in [
        'Focused',
        'Calm',
        'Energised',
        'Busy',
        'Tired',
        'Proud',
      ]) {
        expect(find.text(word), findsOneWidget);
      }
      expect(find.text('0 / 200'), findsOneWidget);

      await tester.tap(find.text('Focused'));
      await tester.pump();
      await tester.tap(find.text('Calm'));
      await tester.pump();
      expect(text(tester), 'Focused, calm');
      expect(changes.last, 'Focused, calm');
      expect(find.text('13 / 200'), findsOneWidget);
    });

    testWidgets('typing is limited to 200 characters', (tester) async {
      final changes = <String>[];
      await _pump(tester, feelingHost(changes));

      await tester.enterText(field(), 'x' * 250);
      await tester.pump();
      expect(text(tester).runes.length, 200);
      expect(find.text('200 / 200'), findsOneWidget);
    });

    testWidgets('a chip that would pass 200 characters is ignored', (
      tester,
    ) async {
      final changes = <String>[];
      await _pump(tester, feelingHost(changes, initial: 'x' * 195));

      await tester.tap(find.text('Energised'));
      await tester.pump();
      expect(text(tester), 'x' * 195);
      expect(changes, isEmpty);
    });
  });
}
