import '../../core/layout/breakpoints.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/task.dart';
import '../../core/router/app_router.dart';
import '../../core/search/page_search.dart';
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
import 'primary_shortcut.dart';

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

/// The sections of the shortcut help.
enum PlannerShortcutGroup {
  day('Day'),
  navigate('Navigate'),
  edit('Edit');

  const PlannerShortcutGroup(this.label);

  final String label;
}

class PlannerShortcutDefinition {
  final PlannerShortcutAction action;
  final PlannerShortcutGroup group;
  final String shortcut;
  final String description;
  final List<ShortcutActivator> activators;

  const PlannerShortcutDefinition({
    required this.action,
    required this.group,
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
      group: PlannerShortcutGroup.day,
      shortcut: 'N',
      description: 'New task block at the selected time slot',
      activators: [SingleActivator(LogicalKeyboardKey.keyN)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.addInbox,
      group: PlannerShortcutGroup.day,
      shortcut: 'I',
      description: 'Add a new item to the Inbox',
      activators: [SingleActivator(LogicalKeyboardKey.keyI)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.edit,
      group: PlannerShortcutGroup.edit,
      shortcut: 'E / Enter',
      description: 'Edit the selected task',
      activators: [
        SingleActivator(LogicalKeyboardKey.keyE),
        SingleActivator(LogicalKeyboardKey.enter),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.delete,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Delete / Backspace',
      description: 'Delete the selected task (with confirmation)',
      activators: [
        SingleActivator(LogicalKeyboardKey.delete),
        SingleActivator(LogicalKeyboardKey.backspace),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.duplicate,
      group: PlannerShortcutGroup.edit,
      shortcut: 'D',
      description: 'Duplicate the selected task',
      activators: [SingleActivator(LogicalKeyboardKey.keyD)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.cycleStatus,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Space',
      description: 'Cycle the selected task status',
      activators: [SingleActivator(LogicalKeyboardKey.space)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.undo,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Ctrl+Z',
      description: 'Undo the last scheduling operation',
      activators: [SingleActivator(LogicalKeyboardKey.keyZ, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.redo,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Ctrl+Shift+Z',
      description: 'Redo the last scheduling operation',
      activators: [
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.previousDay,
      group: PlannerShortcutGroup.day,
      shortcut: '←',
      description: 'Navigate to the previous day',
      activators: [SingleActivator(LogicalKeyboardKey.arrowLeft)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.nextDay,
      group: PlannerShortcutGroup.day,
      shortcut: '→',
      description: 'Navigate to the next day',
      activators: [SingleActivator(LogicalKeyboardKey.arrowRight)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.today,
      group: PlannerShortcutGroup.day,
      shortcut: 'T',
      description: 'Jump to today',
      activators: [SingleActivator(LogicalKeyboardKey.keyT)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.search,
      group: PlannerShortcutGroup.navigate,
      shortcut: 'Ctrl+F',
      description: 'Search this page, or open Search',
      activators: [SingleActivator(LogicalKeyboardKey.keyF, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.previousTask,
      group: PlannerShortcutGroup.navigate,
      shortcut: '↑',
      description: 'Select the previous task block',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.nextTask,
      group: PlannerShortcutGroup.navigate,
      shortcut: '↓',
      description: 'Select the next task block',
      activators: [SingleActivator(LogicalKeyboardKey.arrowDown)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.moveUp,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Ctrl+↑',
      description: 'Move the selected task up one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.moveDown,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Ctrl+↓',
      description: 'Move the selected task down one grid slot',
      activators: [
        SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
      ],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.resizeUp,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Shift+↑',
      description: 'Shorten the selected task by one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.resizeDown,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Shift+↓',
      description: 'Lengthen the selected task by one grid slot',
      activators: [SingleActivator(LogicalKeyboardKey.arrowDown, shift: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.saveAndClose,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Ctrl+Enter',
      description: 'Save the form you are in (task editor, reviews, Inbox)',
      activators: [SingleActivator(LogicalKeyboardKey.enter, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.escape,
      group: PlannerShortcutGroup.edit,
      shortcut: 'Esc',
      description: 'Close a dialog or menu, the editor, or cancel a drag',
      activators: [SingleActivator(LogicalKeyboardKey.escape)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.week,
      group: PlannerShortcutGroup.day,
      shortcut: 'W',
      description: 'Switch between Day and Week view',
      activators: [SingleActivator(LogicalKeyboardKey.keyW)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.dailyReview,
      group: PlannerShortcutGroup.navigate,
      shortcut: 'Ctrl+R',
      description: 'Open Daily Review',
      activators: [SingleActivator(LogicalKeyboardKey.keyR, control: true)],
    ),
    PlannerShortcutDefinition(
      action: PlannerShortcutAction.help,
      group: PlannerShortcutGroup.navigate,
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
        _forPlatform(activator): _PlannerIntent(definition.action),
  };

  /// The definitions are written with Control; macOS uses Command instead.
  static ShortcutActivator _forPlatform(ShortcutActivator activator) =>
      usesCommandModifier && activator is SingleActivator && activator.control
      ? primaryShortcut(activator.trigger, shift: activator.shift)
      : activator;

  /// [PlannerShortcutDefinition.shortcut] as shown on this platform.
  static String label(PlannerShortcutDefinition definition) =>
      usesCommandModifier
      ? definition.shortcut.replaceAll('Ctrl+', '⌘')
      : definition.shortcut;
}

/// Whether this platform has keyboard shortcuts; off desktop nothing is
/// matched.
bool get keyboardShortcutsAvailable =>
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

/// Opens the shortcut help dialog, the same one the `?` key shows.
Future<void> showShortcutHelp(BuildContext context) {
  final rows = <Widget>[];
  for (final group in PlannerShortcutGroup.values) {
    rows.add(_ShortcutHelpHeading(group.label));
    for (final definition in PlannerShortcutRegistry.definitions) {
      if (definition.group != group) continue;
      rows.add(
        _ShortcutHelpRow(
          PlannerShortcutRegistry.label(definition),
          definition.description,
        ),
      );
    }
    if (group == PlannerShortcutGroup.edit) {
      rows.add(
        const _ShortcutHelpRow('Enter', "In a dialog's name field: save it"),
      );
    }
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('shortcut-help-dialog'),
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 440,
        height: 520,
        child: ListView(children: rows),
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

class _ShortcutHelpHeading extends StatelessWidget {
  const _ShortcutHelpHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _ShortcutHelpRow extends StatelessWidget {
  const _ShortcutHelpRow(this.shortcut, this.description);

  final String shortcut;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            shortcut,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(description)),
      ],
    ),
  );
}

class _PlannerIntent extends Intent {
  final PlannerShortcutAction action;

  const _PlannerIntent(this.action);
}

/// Keeps planner bindings out of the way of Flutter's text-editing shortcuts
/// and of the focused control.
///
/// A [Shortcuts] widget below [DefaultTextEditingShortcuts] takes precedence
/// over the framework's default editing bindings. Returning from an action
/// because an editable control has focus is too late: [ShortcutManager] has
/// already matched the key and will consume it. This manager lets the event
/// continue to the text-editing shortcut manager instead. Search is the one
/// exception while the current page has a page search, so Ctrl+F also works
/// from a text field there.
///
/// The same holds for the keys that the app's default bindings give to
/// dialogs, menus and buttons (Esc, Enter, Space, the arrows): the planner
/// manager sits closer to the focus than those defaults, so it ignores the
/// event when the focus owns the key. Off desktop nothing is matched at all.
class _PlannerShortcutManager extends ShortcutManager {
  final bool Function() isDesktop;
  final bool Function() isEditableFocused;
  final bool Function() focusOwnsPopupRoute;
  final bool Function(KeyEvent event) focusOwnsKey;
  final bool Function() pageSearchAvailable;

  _PlannerShortcutManager({
    required this.isDesktop,
    required this.isEditableFocused,
    required this.focusOwnsPopupRoute,
    required this.focusOwnsKey,
    required this.pageSearchAvailable,
  }) : super(shortcuts: PlannerShortcutRegistry.bindings);

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (!isDesktop() || focusOwnsPopupRoute() || focusOwnsKey(event)) {
      return KeyEventResult.ignored;
    }
    if (isEditableFocused()) {
      for (final entry in shortcuts.entries) {
        if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
        final intent = entry.value;
        if (intent is _PlannerIntent &&
            intent.action != PlannerShortcutAction.escape &&
            intent.action != PlannerShortcutAction.saveAndClose &&
            !(intent.action == PlannerShortcutAction.search &&
                pageSearchAvailable())) {
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
  final _pageSearch = PageSearchRegistry();

  @override
  void initState() {
    super.initState();
    _shortcutManager = _PlannerShortcutManager(
      isDesktop: () => _isDesktop,
      isEditableFocused: _focusOwnsEditableControl,
      focusOwnsPopupRoute: _focusOwnsPopupRoute,
      focusOwnsKey: _focusOwnsKey,
      pageSearchAvailable: () => _pageSearch.current != null,
    );
  }

  @override
  void dispose() {
    _shortcutManager.dispose();
    super.dispose();
  }

  bool get _isDesktop => keyboardShortcutsAvailable;

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

  /// True when the focused control uses [event] itself: Enter and Space on
  /// anything that handles [ActivateIntent], and the arrows on that or on a
  /// menu, slider or segmented control. Keys with a modifier stay planner
  /// shortcuts.
  bool _focusOwnsKey(KeyEvent event) {
    final key = event.logicalKey;
    final activates =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    final arrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (!activates && !arrow) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (Actions.maybeFind<ActivateIntent>(focusContext) != null) return true;
    if (!arrow) return false;
    bool usesArrows(Widget widget) =>
        widget is MenuAnchor ||
        widget is MenuBar ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is SegmentedButton;
    if (usesArrows(focusContext.widget)) return true;
    var owns = false;
    focusContext.visitAncestorElements((element) {
      if (usesArrows(element.widget)) {
        owns = true;
        return false;
      }
      return true;
    });
    return owns;
  }

  bool _isBlocked(PlannerShortcutAction action) {
    if (action == PlannerShortcutAction.escape) {
      return false;
    }
    if (_focusOwnsPopupRoute()) return true;
    if (action == PlannerShortcutAction.saveAndClose) return false;
    if (action == PlannerShortcutAction.search && _pageSearch.current != null) {
      return false;
    }
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
        if (!Breakpoints.of(MediaQuery.sizeOf(context).width).hasSidePanel) {
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
        final page = _pageSearch.current;
        if (page != null) {
          page.open();
        } else {
          appRouter.go('/search');
        }
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
        // The scope's own Esc handler only sees keys while focus is inside the
        // page; this covers focus elsewhere, unless a popup route has focus.
        final page = _pageSearch.current;
        if (!_focusOwnsPopupRoute() && page != null && page.isOpen.value) {
          page.close();
          return;
        }
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
    final overlayContext = appNavigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) return Future<void>.value();
    return showShortcutHelp(overlayContext);
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
        child: PageSearchRegistryScope(
          registry: _pageSearch,
          child: FocusScope(autofocus: true, child: widget.child),
        ),
      ),
    );
  }
}
