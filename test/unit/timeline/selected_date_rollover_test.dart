// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerAt(FakeAsync async, DateTime start) {
    final container = ProviderContainer(
      overrides: [
        insightsNowFactoryProvider.overrideWithValue(
          () => async.getClock(start).now(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('selection that is today follows midnight', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 10, 11, 23, 30);
      final container = containerAt(async, start);
      container.listen(selectedDateRolloverProvider, (_, _) {});
      container.read(selectedDateProvider.notifier).state = startOfDay(start);

      async.elapse(const Duration(hours: 1));

      expect(
        container.read(selectedDateProvider),
        PlannerTimeZone.calendarDate(2026, 10, 12),
      );
    });
  });

  test('a browsed date stays put at midnight', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 10, 11, 23, 30);
      final container = containerAt(async, start);
      container.listen(selectedDateRolloverProvider, (_, _) {});
      final browsed = PlannerTimeZone.calendarDate(2026, 10, 5);
      container.read(selectedDateProvider.notifier).state = browsed;

      async.elapse(const Duration(hours: 1));

      expect(container.read(selectedDateProvider), browsed);
    });
  });
}
