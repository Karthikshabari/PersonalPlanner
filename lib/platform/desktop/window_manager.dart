import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/database/app_database.dart';

const String windowBoundsSettingKey = 'window_bounds';
const Size minimumPlannerWindowSize = Size(800, 600);

/// A persisted desktop window rectangle. This small value object keeps the
/// display-clamping logic testable without a platform channel.
class SavedWindowBounds {
  final double left;
  final double top;
  final double width;
  final double height;

  const SavedWindowBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  factory SavedWindowBounds.fromRect(Rect rect) => SavedWindowBounds(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  );

  factory SavedWindowBounds.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid window bounds');
    double number(String key) {
      final raw = value[key];
      if (raw is num) return raw.toDouble();
      throw const FormatException('Invalid window bounds value');
    }

    return SavedWindowBounds(
      left: number('left'),
      top: number('top'),
      width: number('width'),
      height: number('height'),
    );
  }

  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

/// Keeps a saved window visible after a monitor is removed or its scale
/// factor changes. The window is placed on the first display when the saved
/// rectangle no longer intersects any current visible work area.
Rect clampWindowBounds(
  Rect saved,
  List<Display> displays, {
  Size minimumSize = minimumPlannerWindowSize,
}) {
  final areas = <Rect>[];
  for (final display in displays) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    if (size.width > 0 && size.height > 0) {
      areas.add(
        Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      );
    }
  }
  if (areas.isEmpty) {
    final width = saved.width
        .clamp(minimumSize.width, double.infinity)
        .toDouble();
    final height = saved.height
        .clamp(minimumSize.height, double.infinity)
        .toDouble();
    return Rect.fromLTWH(saved.left, saved.top, width, height);
  }

  final area = areas.firstWhere(
    (candidate) => saved.overlaps(candidate),
    orElse: () => areas.first,
  );
  final minimumWidth = minimumSize.width.clamp(0, area.width).toDouble();
  final minimumHeight = minimumSize.height.clamp(0, area.height).toDouble();
  final width = saved.width.clamp(minimumWidth, area.width).toDouble();
  final height = saved.height.clamp(minimumHeight, area.height).toDouble();
  final left = saved.left.clamp(area.left, area.right - width).toDouble();
  final top = saved.top.clamp(area.top, area.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// Linux window lifecycle and geometry persistence. Android has no desktop
/// window to manage, so all platform-channel calls are guarded.
class WindowStateService with WindowListener {
  WindowStateService._();

  static final instance = WindowStateService._();

  AppDatabase? _database;
  Timer? _saveDebounce;
  Future<void>? _pendingPersist;
  Future<void> Function()? _beforeClose;
  bool _initialized = false;
  bool _closing = false;

  Future<void> initialize(
    AppDatabase database, {
    Future<void> Function()? beforeClose,
  }) async {
    if (!Platform.isLinux) return;
    if (_initialized) {
      _beforeClose = beforeClose;
      await switchDatabase(database);
      return;
    }
    _database = database;
    _beforeClose = beforeClose;
    var listenerAdded = false;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(minimumPlannerWindowSize);
      windowManager.addListener(this);
      listenerAdded = true;
      await _restoreBounds();
      await windowManager.setPreventClose(true);
      _initialized = true;
    } catch (_) {
      if (listenerAdded) windowManager.removeListener(this);
      _database = null;
      _beforeClose = null;
      _initialized = false;
      rethrow;
    }
  }

  Future<void> _restoreBounds() async {
    final row =
        await (_database!.select(_database!.appSettings)
              ..where((setting) => setting.key.equals(windowBoundsSettingKey)))
            .getSingleOrNull();
    final raw = row?.value;
    Rect? saved;
    if (raw != null) {
      try {
        saved = SavedWindowBounds.fromJson(jsonDecode(raw)).rect;
      } catch (_) {
        saved = null;
      }
    }

    final displays = await screenRetriever.getAllDisplays();
    final bounds = clampWindowBounds(
      saved ?? const Rect.fromLTWH(0, 0, 1280, 720),
      displays,
    );
    await windowManager.setBounds(bounds);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      final running = _persistBounds();
      _pendingPersist = running;
      unawaited(
        running.then<void>(
          (_) {
            if (identical(_pendingPersist, running)) _pendingPersist = null;
          },
          onError: (Object _, StackTrace _) {
            if (identical(_pendingPersist, running)) _pendingPersist = null;
          },
        ),
      );
    });
  }

  Future<void> _persistBounds() async {
    final database = _database;
    if (database == null || !_initialized) return;
    final bounds = await windowManager.getBounds();
    await database.customStatement(
      'INSERT INTO app_settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [
        windowBoundsSettingKey,
        jsonEncode(SavedWindowBounds.fromRect(bounds).toJson()),
      ],
    );
  }

  Future<void> switchDatabase(AppDatabase database) async {
    if (!Platform.isLinux) return;
    if (!_initialized) {
      await initialize(database);
      return;
    }
    if (identical(_database, database)) return;
    _saveDebounce?.cancel();
    await _pendingPersist;
    try {
      await _persistBounds();
    } catch (_) {
      // Window persistence must not prevent an account database swap. The
      // pending write has already completed, so the new account can safely
      // take ownership of the window state.
    }
    _database = database;
    await _restoreBounds();
  }

  Future<void> detachDatabase(AppDatabase database) async {
    if (!Platform.isLinux || !identical(_database, database)) return;
    _saveDebounce?.cancel();
    try {
      await _pendingPersist;
      await _persistBounds();
    } finally {
      // Never leave a reference to a database that the account lifecycle is
      // about to close, even if the final persistence write fails.
      if (identical(_database, database)) _database = null;
    }
  }

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowClose() {
    unawaited(_persistThenDestroy());
  }

  Future<void> _persistThenDestroy() async {
    if (_closing) return;
    _closing = true;
    _saveDebounce?.cancel();
    try {
      await _pendingPersist;
      await _persistBounds();
    } catch (_) {
      // Continue shutdown even when the window-state write fails. Keeping the
      // close guard alive would strand the process and its database scope.
    }
    _database = null;
    try {
      await _beforeClose?.call();
    } catch (_) {
      // The owning application performs best-effort cleanup internally; the
      // native window must still be allowed to close if that cleanup reports
      // an error.
    }
    windowManager.removeListener(this);
    _initialized = false;
    _beforeClose = null;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      // Native window teardown is best effort after the listener is detached.
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _saveDebounce?.cancel();
    try {
      await _pendingPersist;
      await _persistBounds();
    } catch (_) {
      // Disposal must release the listener and database reference even when
      // the platform channel or final write is unavailable.
    } finally {
      windowManager.removeListener(this);
      _database = null;
      _beforeClose = null;
      _initialized = false;
    }
  }
}
