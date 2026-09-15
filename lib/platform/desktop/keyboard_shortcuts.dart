import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/task.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/status_badge.dart';
import '../../features/inbox/presentation/widgets/inbox_quick_add.dart';
import '../../features/task_editor/presentation/screens/task_editor_panel.dart';
import '../../features/task_editor/providers/task_editor_action_provider.dart';
import '../../features/timeline/domain/snap_to_grid.dart';
import '../../features/timeline/presentation/providers/day_tasks_provider.dart';
import '../../features/timeline/presentation/providers/grid_settings_provider.dart';
import '../../features/timeline/presentation/providers/overlap_flags_provider.dart';
import '../../features/timeline/presentation/providers/selected_date_provider.dart';
import '../../features/timeline/presentation/providers/selected_task_provider.dart';
import '../../features/timeline/presentation/providers/timeline_action_provider.dart';
import '../../features/timeline/presentation/providers/undo_stack_provider.dart';
import '../../features/timeline/presentation/providers/day_view_controller.dart';

enum PlannerShortcutAction {
  newTask,
  addInbox,
  edit,
  delete,
  duplicate,
  cycleStatus,
  undo,
  redo,
  previousDay,
  nextDay,
  today,
  search,
  previousTask,
  nextTask,
  moveUp,
  moveDown,
  resizeUp,
  resizeDown,
  saveAndClose,
  escape,
  week,
  dailyReview,
  help,
}

class PlannerShortcutDefinition {
  final PlannerShortcutAction action;
  final String shortcut;
  final String description;
  final List<ShortcutActivator> activators;

  const PlannerShortcutDefinition({
    required this.action,
    required this.shortcut,
    required this.description,
    required this.activators,
  });
}

/// The single source of truth for desktop shortcuts and the help overlay.
abstract final class PlannerShortcutRegistry {
  static const definitions = <PlannerShortcutDefinition>[
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.newTask,
      shortcut: 'N',
      description: 'New task block at the selected time slot',
      activators: [SingleActivator(LogicalKeyboardKey.keyN)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.addInbox,
      shortcut: 'I',
      description: 'Add a new item to the Inbox',
      activators: [SingleActivator(LogicalKeyboardKey.keyI)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.edit,
      shortcut: 'E / Enter',
      description: 'Edit the selected task',
      activators: [
        SingleActivator(LogicalKeyboardKey.keyE),
        SingleActivator(LogicalKeyboardKey.enter),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.delete,
      shortcut: 'Delete / Backspace',
      description: 'Delete the selected task (with confirmation)',
      activators: [
        SingleActivator(LogicalKeyboardKey.delete),
        SingleActivator(LogicalKeyboardKey.backspace),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.duplicate,
      shortcut: 'D',
      description: 'Duplicate the selected task',
      activators: [SingleActivator(LogicalKeyboardKey.keyD)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.cycleStatus,
      shortcut: 'Space',
      description: 'Cycle the selected task status',
      activators: [SingleActivator(LogicalKeyboardKey.space)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.undo,
      shortcut: 'Ctrl+Z',
      description: 'Undo the last scheduling operation',
      activators: [SingleActivator(LogicalKeyboardKey.keyZ, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.redo,
      shortcut: 'Ctrl+Shift+Z',
      description: 'Redo the last scheduling operation',
      activators: [
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.previousDay,
      shortcut: '←',
      description: 'Navigate to the previous day',
      activators: [SingleActivator(LogicalKeyboardKey.arrowLeft)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.nextDay,
      shortcut: '→',
      description: 'Navigate to the next day',
      activators: [SingleActivator(LogicalKeyboardKey.arrowRight)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.today,
      shortcut: 'T',
      description: 'Jump to today',
      activators: [SingleActivator(LogicalKeyboardKey.keyT)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.search,
      shortcut: 'Ctrl+F',
      description: 'Open Search',
      activators: [SingleActivator(LogicalKeyboardKey.keyF, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.previousTask,
      shortcut: '↑',
      description: 'Select the previous task block',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.nextTask,
      shortcut: '↓',
      description: 'Select the next task block',
      activators: [SingleActivator(LogicalKeyboardKey.arrowDown)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.moveUp,
      shortcut: 'Ctrl+↑',
      description: 'Move the selected task up one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.moveDown,
      shortcut: 'Ctrl+↓',
      description: 'Move the selected task down one grid slot',
      activators: [
        SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.resizeUp,
      shortcut: 'Shift+↑',
      description: 'Shorten the selected task by one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.resizeDown,
      shortcut: 'Shift+↓',
      description: 'Lengthen the selected task by one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowDown, shift: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.saveAndClose,
      shortcut: 'Ctrl+Enter',
      description: 'Save and close the task editor',
      activators: [SingleActivator(LogicalKeyboardKey.enter, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.escape,
      shortcut: 'Esc',
      description: 'Close the editor, cancel a drag, or dismiss a dialog',
      activators: [SingleActivator(LogicalKeyboardKey.escape)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.week,
      shortcut: 'W',
      description: 'Switch to Week view',
      activators: [SingleActivator(LogicalKeyboardKey.keyW)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.dailyReview,
      shortcut: 'Ctrl+R',
      description: 'Open Daily Review',
      activators: [SingleActivator(LogicalKeyboardKey.keyR, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.help,
      shortcut: '?',
      description: 'Show keyboard shortcut help',
      activators: [
        SingleActivator(LogicalKeyboardKey.question),
        SingleActivator(LogicalKeyboardKey.slash, shift: true),
      ],
    ),
  ];

  static Map<ShortcutActivator, Intent> get bindings => {
    for (final definition in definitions)
      for (final activator in definition.activators)
        activator: _PlannerIntent(definition.action),
  };
}

class _PlannerIntent extends Intent {
  final PlannerShortcutAction action;

  const _PlannerIntent(this.action);
}

/// Keeps planner bindings out of the way of Flutter's text-editing shortcuts.
///
/// A [Shortcuts] widget below [DefaultTextEditingShortcuts] takes precedence
/// over the framework's default editing bindings. Returning from an action
/// because an editable control has focus is too late: [ShortcutManager] has
/// already matched the key and will consume it. This manager lets the event
/// continue to the text-editing shortcut manager instead.
class _PlannerShortcutManager extends ShortcutManager {
  final bool Function() isEditableFocused;

  _PlannerShortcutManager({required this.isEditableFocused})
    : super(shortcuts: PlannerShortcutRegistry.bindings);

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (isEditableFocused()) {
      for (final entry in shortcuts.entries) {
        if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
        final intent = entry.value;
        if (intent is _PlannerIntent &&
            intent.action != PlannerShortcutAction.escape &&
            intent.action != PlannerShortcutAction.saveAndClose) {
          return KeyEventResult.ignored;
        }
      }
    }
    return super.handleKeypress(context, event);
  }
}

class KeyboardShortcutHandler extends ConsumerStatefulWidget {
  final Widget child;

  const KeyboardShortcutHandler({super.key, required this.child});

  @override
  ConsumerState<KeyboardShortcutHandler> createState() =>
      _KeyboardShortcutHandlerState();
}

class _KeyboardShortcutHandlerState
    extends ConsumerState<KeyboardShortcutHandler> {
  bool _deleteInFlight = false;
  late final _PlannerShortcutManager _shortcutManager;

  @override
  void initState() {
    super.initState();
    _shortcutManager = _PlannerShortcutManager(
      isEditableFocused: _focusOwnsEditableControl,
    );
  }

  @override
  void dispose() {
    _shortcutManager.dispose();
    super.dispose();
  }

  bool get _isDesktop =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  BuildContext? get _navigatorContext =>
      appNavigatorKey.currentState?.overlay?.context;

  String get _currentPath =>
      appRouter.routerDelegate.currentConfiguration.uri.path;

  Task? _selectedTask() {
    final id = ref.read(selectedTaskIdProvider);
    if (id == null) return null;
    final tasks = ref.read(dayTasksProvider).value ?? const <Task>[];
    for (final task in tasks) {
      if (task.id == id && task.deletedAt == null) return task;
    }
    return null;
  }

  bool _focusOwnsEditableControl() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    bool isEditable(Widget widget) =>
        widget is EditableText ||
        widget is TextField ||
        widget is DropdownButton ||
        widget is DropdownButtonFormField ||
        widget is MenuAnchor ||
        widget is PopupMenuButton;
    if (isEditable(focusContext.widget)) return true;
    var owns = false;
    focusContext.visitAncestorElements((element) {
      final widget = element.widget;
      if (isEditable(widget)) {
        owns = true;
        return false;
      }
      return true;
    });
    return owns;
  }

  bool _focusOwnsPopupRoute() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return ModalRoute.of(focusContext) is PopupRoute<void>;
  }

  bool _isBlocked(PlannerShortcutAction action) {
    if (action == PlannerShortcutAction.escape) {
      return false;
    }
    if (_focusOwnsPopupRoute()) return true;
    if (action == PlannerShortcutAction.saveAndClose) return false;
    return _focusOwnsEditableControl();
  }

  Future<void> _invoke(PlannerShortcutAction action) async {
    if (!_isDesktop || _isBlocked(action)) return;

    switch (action) {
      case PlannerShortcutAction.newTask:
        _newTask();
      case PlannerShortcutAction.addInbox:
        final navigatorContext = _navigatorContext;
        if (navigatorContext != null) {
          await showInboxQuickAddDialog(navigatorContext, ref);
        }
      case PlannerShortcutAction.edit:
        final task = _selectedTask();
        if (task == null) return;
        ref.read(selectedTaskIdProvider.notifier).state = task.id;
        if (MediaQuery.sizeOf(context).width < AppConstants.desktopBreakpoint) {
          await TaskEditorPanel.showAsBottomSheet(context);
        } else if (_currentPath != '/day') {
          appRouter.go('/day');
        }
      case PlannerShortcutAction.delete:
        if (_deleteInFlight) return;
        final task = _selectedTask();
        if (task == null) return;
        final navigatorContext = _navigatorContext;
        if (navigatorContext == null) return;
        _deleteInFlight = true;
        try {
          await TimelineActions.deleteWithConfirmation(
            navigatorContext,
            ref,
            task,
          );
        } finally {
          _deleteInFlight = false;
        }
      case PlannerShortcutAction.duplicate:
        final task = _selectedTask();
        final navigatorContext = _navigatorContext;
        if (task != null && navigatorContext != null) {
          await TimelineActions.duplicateTask(navigatorContext, ref, task);
        }
      case PlannerShortcutAction.cycleStatus:
        final task = _selectedTask();
        if (task == null) return;
        final next = StatusBadge.nextStatus(task.status);
        if (next != task.status) {
          await TimelineActions.setStatus(ref, task, next);
        }
      case PlannerShortcutAction.undo:
        await _undo();
      case PlannerShortcutAction.redo:
        await _redo();
      case PlannerShortcutAction.previousDay:
        _changeDay(-1);
      case PlannerShortcutAction.nextDay:
        _changeDay(1);
      case PlannerShortcutAction.today:
        final now = DateTime.now();
        ref.read(selectedDateProvider.notifier).state = startOfDay(now);
      case PlannerShortcutAction.search:
        appRouter.go('/search');
      case PlannerShortcutAction.previousTask:
        _selectAdjacentTask(-1);
      case PlannerShortcutAction.nextTask:
        _selectAdjacentTask(1);
      case PlannerShortcutAction.moveUp:
        final task = _selectedTask();
        final navigatorContext = _navigatorContext;
        if (task != null && navigatorContext != null) {
          await TimelineActions.moveByGrid(navigatorContext, ref, task, -1);
        }
      case PlannerShortcutAction.moveDown:
        final task = _selectedTask();
        final navigatorContext = _navigatorContext;
        if (task != null && navigatorContext != null) {
          await TimelineActions.moveByGrid(navigatorContext, ref, task, 1);
        }
      case PlannerShortcutAction.resizeUp:
        final task = _selectedTask();
        final navigatorContext = _navigatorContext;
        if (task != null && navigatorContext != null) {
          await TimelineActions.resizeByGrid(navigatorContext, ref, task, -1);
        }
      case PlannerShortcutAction.resizeDown:
        final task = _selectedTask();
        final navigatorContext = _navigatorContext;
        if (task != null && navigatorContext != null) {
          await TimelineActions.resizeByGrid(navigatorContext, ref, task, 1);
        }
      case PlannerShortcutAction.saveAndClose:
        ref.read(taskEditorSaveRequestProvider.notifier).state++;
      case PlannerShortcutAction.escape:
        ref.read(timelineCancelRequestProvider.notifier).state++;
        ref.read(selectedTaskIdProvider.notifier).state = null;
      case PlannerShortcutAction.week:
        final location = _currentPath;
        appRouter.go(location == '/week' ? '/day' : '/week');
      case PlannerShortcutAction.dailyReview:
        appRouter.go('/review');
      case PlannerShortcutAction.help:
        await _showHelp();
    }
  }

  void _newTask() {
    final grid =
        ref.read(gridIntervalProvider).value ?? AppConstants.defaultGridMinutes;
    final selected = _selectedTask();
    final selectedDate = ref.read(selectedDateProvider);
    final now = DateTime.now();
    final rawMinutes = selected?.startTime != null
        ? minutesSinceMidnight(selected!.startTime!)
        : isSameDay(selectedDate, now)
        ? minutesSinceMidnight(now)
        : 9 * Duration.minutesPerHour;
    final minutes = snapSlotStart(rawMinutes, grid);
    ref.read(timelineQuickCreateSlotProvider.notifier).state = minutes;
    if (_currentPath != '/day') appRouter.go('/day');
  }

  void _changeDay(int delta) {
    final current = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state = addDays(current, delta);
  }

  void _selectAdjacentTask(int delta) {
    final tasks = [...(ref.read(dayTasksProvider).value ?? const <Task>[])]
      ..removeWhere((task) => task.deletedAt != null || task.startTime == null)
      ..sort((a, b) {
        final byStart = a.startTime!.compareTo(b.startTime!);
        return byStart == 0 ? a.id.compareTo(b.id) : byStart;
      });
    if (tasks.isEmpty) return;
    final selectedId = ref.read(selectedTaskIdProvider);
    final currentIndex = tasks.indexWhere((task) => task.id == selectedId);
    final nextIndex = currentIndex < 0
        ? (delta > 0 ? 0 : tasks.length - 1)
        : (currentIndex + delta).clamp(0, tasks.length - 1).toInt();
    ref.read(selectedTaskIdProvider.notifier).state = tasks[nextIndex].id;
  }

  Future<void> _undo() async {
    ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    final description = await ref.read(undoStackProvider.notifier).undo();
    if (description != null && mounted) {
      _showCommandFeedback('Undo: $description');
    }
  }

  Future<void> _redo() async {
    ref.read(keepOverlapIdsProvider.notifier).state = const <String>{};
    final description = await ref.read(undoStackProvider.notifier).redo();
    if (description != null && mounted) {
      _showCommandFeedback('Redo: $description');
    }
  }

  void _showCommandFeedback(String message) {
    final navigatorContext = _navigatorContext;
    if (navigatorContext == null) return;
    final messenger = ScaffoldMessenger.maybeOf(navigatorContext);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showHelp() {
    final navigator = appNavigatorKey.currentState;
    final overlayContext = navigator?.overlay?.context;
    if (overlayContext == null) return Future<void>.value();
    return showDialog<void>(
      context: overlayContext,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('shortcut-help-dialog'),
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 440,
          height: 520,
          child: ListView.separated(
            itemCount: PlannerShortcutRegistry.definitions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final definition = PlannerShortcutRegistry.definitions[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        definition.shortcut,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(child: Text(definition.description)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts.manager(
      manager: _shortcutManager,
      child: Actions(
        actions: {
          _PlannerIntent: CallbackAction<_PlannerIntent>(
            onInvoke: (intent) {
              unawaited(_invoke(intent.action));
              return null;
            },
          ),
        },
        child: FocusScope(autofocus: true, child: widget.child),
      ),
    );
  }
}
