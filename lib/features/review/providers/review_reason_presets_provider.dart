import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../domain/review_reason_presets.dart';

/// Quick reasons shown under every unfinished task. Stored per device in
/// `app_settings`; not synced and not part of portable backup.
final reviewReasonPresetsProvider =
    AsyncNotifierProvider<ReviewReasonPresetsNotifier, List<String>>(
      ReviewReasonPresetsNotifier.new,
    );

class ReviewReasonPresetsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final db = ref.watch(appDatabaseProvider);
    final raw = await db.syncDao.getSetting(reviewReasonPresetsSettingKey);
    return List.unmodifiable(ReviewReasonPresets.decode(raw));
  }

  List<String> get _current => state.value ?? defaultReviewReasonPresets;

  Future<void> add() async {
    if (_current.length >= maxReviewReasonPresets) return;
    await _write([..._current, '']);
  }

  Future<void> updateAt(int index, String value) async {
    if (index < 0 || index >= _current.length) return;
    final clipped = value.length > maxReviewReasonPresetLength
        ? value.substring(0, maxReviewReasonPresetLength)
        : value;
    await _write([..._current]..[index] = clipped);
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _current.length) return;
    await _write([..._current]..removeAt(index));
  }

  Future<void> resetToDefaults() => _write(List.of(defaultReviewReasonPresets));

  /// Returns false when [text] cannot be saved (see canSaveAsPreset).
  Future<bool> saveAsPreset(String text) async {
    if (!ReviewReasonPresets.canSaveAsPreset(_current, text)) return false;
    await _write(ReviewReasonPresets.withSaved(_current, text));
    return true;
  }

  Future<void> _write(List<String> next) async {
    final previous = _current;
    state = AsyncData(List.unmodifiable(next));
    try {
      await ref
          .read(appDatabaseProvider)
          .syncDao
          .setSetting(
            reviewReasonPresetsSettingKey,
            ReviewReasonPresets.encode(next),
          );
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
