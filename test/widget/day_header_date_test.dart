import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/day_responsive_fixture.dart';
import '../helpers/test_container.dart';

/// The compact Day top bar picks the date format by measuring the real text.
/// Ahem (every glyph one em wide) is far wider than a real font, so these
/// tests load the SDK's Roboto (as test/golden does); the Ahem case at
/// 320x700 lives in day_responsive_layout_test.dart.
void main() {
  setUpAll(() async {
    final root =
        Platform.environment['FLUTTER_ROOT'] ?? '/home/ks/development/flutter';
    final loader = FontLoader('Roboto');
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      final bytes = File('$root/bin/cache/artifacts/material_fonts/$name')
          .readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  final dateButton = find.byKey(const ValueKey('day-date-button'));
  final today = find.byKey(const ValueKey('day-today'));
  final dateText = find.descendant(of: dateButton, matching: find.byType(Text));

  /// Today is an OutlinedButton, or an IconButton when the row is tight.
  VoidCallback? todayPressed(WidgetTester tester) {
    final widget = tester.widget(today);
    return widget is IconButton
        ? widget.onPressed
        : (widget as OutlinedButton).onPressed;
  }

  late ProviderContainer opened;

  Future<void> finish(WidgetTester tester) => teardownApp(tester, opened);

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size,
    double scale,
  ) async {
    final container = await pumpResponsiveDay(
      tester,
      size: size,
      textScale: scale,
      blocks: false,
    );
    opened = container;
    return container;
  }

  void expectDateOnOneLine(WidgetTester tester) {
    expect(dateText, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: dateButton, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    final shown = tester.widget<Text>(dateText).data!;
    // Ellipsis would replace the tail of the string with a single character.
    expect(shown, isNot(contains('…')));
    expect(
      tester.getRect(dateText).right,
      lessThanOrEqualTo(tester.getRect(dateButton).right),
    );
  }

  group('compact top bar date', () {
    testWidgets('360x800 at text scale 1.0 shows the long form', (
      tester,
    ) async {
      await pump(tester, const Size(360, 800), 1.0);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(dateText).data, 'Tue, Mar 10');
      expectDateOnOneLine(tester);
      expect(todayPressed(tester), isNotNull);
      await finish(tester);
    });

    testWidgets('360x800 at text scale 1.5 is not ellipsized', (tester) async {
      await pump(tester, const Size(360, 800), 1.5);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(dateText).data, isNot('Tue, Mar 10'));
      expect(tester.widget<Text>(dateText).data, contains('Mar 10'));
      expectDateOnOneLine(tester);
      await finish(tester);
    });

    testWidgets('320x700 at text scale 1.5 shows the date', (tester) async {
      await pump(tester, const Size(320, 700), 1.5);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(dateText).data, 'Mar 10');
      expectDateOnOneLine(tester);
      // Too narrow for a text button: Today is an icon, still a 48 dp target.
      expect(todayPressed(tester), isNotNull);
      expect(tester.getSize(today).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(today).height, greaterThanOrEqualTo(48));
      await finish(tester);
    });

    testWidgets('320x700 at text scale 1.0 is not ellipsized', (tester) async {
      await pump(tester, const Size(320, 700), 1.0);
      expect(tester.takeException(), isNull);
      expectDateOnOneLine(tester);
      await finish(tester);
    });

    for (final (size, scale) in [
      (const Size(360, 800), 1.0),
      (const Size(360, 800), 1.5),
      (const Size(320, 700), 1.0),
      (const Size(320, 700), 1.5),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} at $scale '
          'announces the full date', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, size, scale);
        expect(
          tester.getSemantics(dateButton),
          matchesSemantics(
            label: 'Tuesday, March 10, 2026',
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        handle.dispose();
        await finish(tester);
      });
    }

    for (final (size, scale) in [
      (const Size(360, 800), 1.0),
      (const Size(360, 800), 1.5),
      (const Size(320, 700), 1.0),
      (const Size(320, 700), 1.5),
    ]) {
      testWidgets('Today is disabled on today and enabled on another day at '
          '${size.width.toInt()}x${size.height.toInt()} text scale $scale', (
        tester,
      ) async {
        final container = await pump(tester, size, scale);
        // The fixture shows a past day, so Today is enabled.
        expect(todayPressed(tester), isNotNull);
        final now = container.read(insightsNowFactoryProvider)();
        container.read(selectedDateProvider.notifier).state = DateTime(
          now.year,
          now.month,
          now.day,
        );
        await tester.pump();
        await tester.pump();
        expect(today, findsOneWidget);
        expect(todayPressed(tester), isNull);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  });
}
