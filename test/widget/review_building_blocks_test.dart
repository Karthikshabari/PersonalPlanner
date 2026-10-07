import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/review/domain/review_reason_presets.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/presentation/widgets/mood_face.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_preset_editor.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_snack_bar.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_status_chip.dart';
import 'package:personal_planner/features/review/presentation/widgets/review_theme.dart';
import 'package:personal_planner/features/review/presentation/widgets/task_outcome_visuals.dart';

import '../helpers/test_container.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('mood faces paint all four levels', (tester) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (var l = 1; l <= 4; l++) MoodFace(level: l, size: 40)],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MoodFace), findsNWidgets(4));
    const c = Colors.teal;
    expect(
      MoodFacePainter(
        level: 1,
        color: c,
      ).shouldRepaint(MoodFacePainter(level: 2, color: c)),
      isTrue,
    );
  });

  testWidgets('status chip labels', (tester) async {
    var taps = 0;
    Widget chip(bool reviewed, int? mood) => _host(
      ReviewStatusChip(reviewed: reviewed, mood: mood, onPressed: () => taps++),
    );
    await tester.pumpWidget(chip(false, null));
    expect(find.text('Not reviewed'), findsOneWidget);
    await tester.tap(find.byType(ReviewStatusChip));
    expect(taps, 1);
    await tester.pumpWidget(chip(true, 2));
    expect(find.text('Reviewed · Great'), findsOneWidget);
    await tester.pumpWidget(chip(true, null));
    expect(find.text('Reviewed'), findsOneWidget);
  });

  testWidgets('outcome pills use exact labels', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in TaskOutcome.values) TaskOutcomePill(outcome: o),
          ],
        ),
      ),
    );
    for (final label in [
      'Completed',
      'Partly done',
      'Not started',
      'Skipped',
      'Rescheduled',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('ReviewColors.of falls back by brightness', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(ReviewColors.of(captured).mood1, const Color(0xFF1F8A80));
  });

  testWidgets('preset editor adds, removes and resets', (tester) async {
    final container = await buildTestContainer(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _host(const SingleChildScrollView(child: ReviewPresetEditor())),
      ),
    );
    await settle(tester);
    expect(find.byType(TextField), findsNWidgets(5));

    await tester.tap(find.byKey(const ValueKey('review-preset-add')));
    await settle(tester);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('review-preset-add')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('review-preset-remove-0')));
    await settle(tester);
    expect(find.byType(TextField), findsNWidgets(5));

    await tester.tap(find.byKey(const ValueKey('review-preset-reset')));
    await settle(tester);
    expect(find.text('Presets reset'), findsOneWidget);
    for (final preset in defaultReviewReasonPresets) {
      expect(find.text(preset), findsOneWidget);
    }
    await finish(tester, container);
  });

  testWidgets('snackbar helper auto-dismisses with an action', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showReviewSnackBar(
              context,
              'Saved',
              actionLabel: 'See in Overview',
              onAction: () {},
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('See in Overview'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('See in Overview'), findsNothing);
  });

  testWidgets('settings shows the Review reasons section', (tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/settings');
    await pumpApp(tester, container, surface: const Size(1400, 1400));
    await settle(tester);
    expect(find.text('Review reasons'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-preset-editor')), findsOneWidget);
    await finish(tester, container);
  });
}
