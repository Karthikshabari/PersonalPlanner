import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/search/page_search.dart';
import 'package:personal_planner/features/review/domain/review_search.dart';

void main() {
  group('pageSearchNeedle', () {
    test('trims and lower-cases', () {
      expect(pageSearchNeedle('  Buy MILK \n'), 'buy milk');
      expect(pageSearchNeedle('   '), isEmpty);
    });
  });

  group('accents and spaces', () {
    test('foldAccents folds common Latin accents and leaves other text', () {
      expect(foldAccents('Café Ñandú Über'), 'cafe nandu uber');
      expect(foldAccents('東京 Привет'), '東京 привет');
    });

    test('cafe finds Café, whatever the case, accent or spacing', () {
      final needle = pageSearchNeedle('  CAFE ');
      expect(pageSearchHit('Café meeting', needle), isTrue);
      expect(
        pageSearchHit('Cafe  meeting', pageSearchNeedle('cafe meeting')),
        isTrue,
      );
      expect(
        pageSearchHit('cafe\nmeeting', pageSearchNeedle('Café   meeting')),
        isTrue,
      );
      expect(pageSearchHit('Cafeteria', pageSearchNeedle('café')), isTrue);
      expect(pageSearchHit('tea', needle), isFalse);
    });

    test('the Review index finds Café for cafe in days and weeks', () {
      final day = DateTime(2026, 8, 24);
      final index = ReviewSearchIndex(
        today: day,
        days: [
          ReviewSearchDay(day, [
            ReviewSearchText('Café meeting', ReviewSearchSource.task),
          ]),
        ],
        weekReviews: const [],
      );
      expect(searchReviewDays(index, pageSearchNeedle('cafe')), hasLength(1));
      expect(searchReviewWeeks(index, pageSearchNeedle('cafe')), hasLength(1));
    });
  });

  group('pageSearchHit', () {
    test('is case-insensitive', () {
      expect(pageSearchHit('Buy Milk Today', 'buy milk'), isTrue);
      expect(pageSearchHit('buy milk', 'milk'), isTrue);
    });

    test('is false for null text and for a blank or empty needle', () {
      expect(pageSearchHit(null, 'milk'), isFalse);
      expect(pageSearchHit('milk', ''), isFalse);
      expect(pageSearchHit('milk', pageSearchNeedle('   ')), isFalse);
    });

    test('matches the whole query contiguously', () {
      expect(pageSearchHit('buy milk today', 'buy milk'), isTrue);
      expect(pageSearchHit('milk to buy', 'buy milk'), isFalse);
      expect(pageSearchHit('buy some milk', 'buy milk'), isFalse);
    });
  });

  group('pageSearchSnippet', () {
    final filler = List.filled(20, 'lorem ipsum').join(' ');

    test('returns short text as one line', () {
      expect(pageSearchSnippet('one\ntwo\r\n\nthree', 'two'), 'one two three');
    });

    test('cuts long text around a match in the middle', () {
      final text = '$filler NEEDLE $filler';
      final snippet = pageSearchSnippet(text, 'needle');
      expect(snippet.length, lessThanOrEqualTo(90));
      expect(snippet.startsWith('…'), isTrue);
      expect(snippet.endsWith('…'), isTrue);
      expect(snippet.toLowerCase(), contains('needle'));
    });

    test('a match at the start only cuts the end', () {
      final snippet = pageSearchSnippet('needle $filler', 'needle');
      expect(snippet.length, lessThanOrEqualTo(90));
      expect(snippet.startsWith('needle'), isTrue);
      expect(snippet.endsWith('…'), isTrue);
    });

    test('a match at the end only cuts the start', () {
      final snippet = pageSearchSnippet('$filler needle', 'needle');
      expect(snippet.length, lessThanOrEqualTo(90));
      expect(snippet.startsWith('…'), isTrue);
      expect(snippet.endsWith('needle'), isTrue);
    });

    test('returns the start of the text when there is no match', () {
      final snippet = pageSearchSnippet(filler, 'zzz');
      expect(snippet.length, lessThanOrEqualTo(90));
      expect(snippet.startsWith('lorem ipsum'), isTrue);
      expect(snippet.endsWith('…'), isTrue);
    });

    test('honours a custom maximum', () {
      final snippet = pageSearchSnippet(filler, 'lorem', max: 20);
      expect(snippet.length, lessThanOrEqualTo(20));
    });
  });
}
