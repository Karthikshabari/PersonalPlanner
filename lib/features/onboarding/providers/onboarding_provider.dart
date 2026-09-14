import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';

const String onboardingCompletedKey = 'onboarding.completed';

final onboardingCompletedProvider =
    AsyncNotifierProvider<OnboardingCompletedNotifier, bool>(
      OnboardingCompletedNotifier.new,
    );

class OnboardingCompletedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final database = ref.watch(appDatabaseProvider);
    final row =
        await (database.select(database.appSettings)
              ..where((setting) => setting.key.equals(onboardingCompletedKey)))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> complete() async {
    try {
      await ref.read(appDatabaseProvider).customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [onboardingCompletedKey, 'true'],
      );
      state = const AsyncData(true);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}
