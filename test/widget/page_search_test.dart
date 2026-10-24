import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/layout/breakpoints.dart';
import 'package:personal_planner/core/layout/size_class_scope.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/search/page_search.dart';
import 'package:personal_planner/core/widgets/global_search_action.dart';
import 'package:personal_planner/platform/desktop/keyboard_shortcuts.dart';

const _field = ValueKey('page-search-field');
const _note = ValueKey('probe-note');

class _Probe extends StatelessWidget {
  const _Probe({this.onCtrlEnter});

  final VoidCallback? onCtrlEnter;

  @override
  Widget build(BuildContext context) {
    return PageSearchScope(
      hint: 'Search probe',
      child: Scaffold(
        appBar: AppBar(
          title: const PageSearchTitle('Probe'),
          actions: const [PageSearchAction()],
        ),
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                onCtrlEnter?.call(),
          },
          child: const TextField(key: _note),
        ),
      ),
    );
  }
}

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      builder: (context, child) => KeyboardShortcutHandler(child: child!),
      home: const Scaffold(body: Text('base')),
    ),
  );
}

Future<void> _pushProbe(WidgetTester tester, Widget page) async {
  appNavigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  await tester.pumpAndSettle();
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

PageSearchController _controller(WidgetTester tester) =>
    PageSearchScope.maybeOf(tester.element(find.byKey(_note)))!;

/// [testWidgets] on Linux, so the desktop shortcuts are active.
///
/// The override is reset inside the test body: the framework checks it before
/// tearDown runs.
void _desktopTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _desktopTest('closed: the title is plain and there is no field', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, const _Probe());

    expect(find.text('Probe'), findsOneWidget);
    expect(find.byKey(_field), findsNothing);
  });

  _desktopTest(
    'Ctrl+F from another text field opens the field and keeps text',
    (tester) async {
      await tester.pumpWidget(_app());
      await _pushProbe(tester, const _Probe());

      await tester.tap(find.byKey(_note));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'my note',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();

      await _ctrl(tester, LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(find.byKey(_field), findsOneWidget);
      expect(find.text('Probe'), findsNothing);
      expect(_controller(tester).focusNode.hasPrimaryFocus, isTrue);
      expect(find.text('my note'), findsOneWidget);
    },
  );

  _desktopTest('the query is published after the debounce', (tester) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, const _Probe());
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    await tester.pump();

    final controller = _controller(tester);
    controller.text.text = 'abc';
    await tester.pump();
    expect(controller.needle.value, isEmpty);

    await tester.pump(const Duration(milliseconds: 149));
    expect(controller.needle.value, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.needle.value, 'abc');

    controller.text.text = '  ';
    await tester.pump();
    expect(controller.needle.value, isEmpty);
  });

  _desktopTest('Esc closes the field and focus returns to the note', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, const _Probe());
    await tester.tap(find.byKey(_note));
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;

    await _ctrl(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(_field), findsNothing);
    expect(find.text('Probe'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, before);
    expect(_controller(tester).isOpen.value, isFalse);
  });

  _desktopTest('Ctrl+Enter in the field does not reach outer shortcuts', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(_app());
    await _pushProbe(tester, _Probe(onCtrlEnter: () => saves++));
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    await tester.pump();

    await _ctrl(tester, LogicalKeyboardKey.enter);

    expect(saves, 0);
    expect(find.byKey(_field), findsOneWidget);

    // In the note box (outside the search field) the same keys still work.
    await tester.tap(find.byKey(_note));
    await tester.pump();
    await _ctrl(tester, LogicalKeyboardKey.enter);
    expect(saves, 1);
  });

  _desktopTest('Back closes search first, then leaves the page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, const _Probe());
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_field), findsNothing);
    expect(find.byKey(_note), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_note), findsNothing);
    expect(find.text('base'), findsOneWidget);
  });

  _desktopTest('another route on top closes search and takes Ctrl+F back', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pushProbe(tester, const _Probe());
    final controller = _controller(tester);
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(controller.isOpen.value, isTrue);

    await _pushProbe(tester, const Scaffold(body: Text('covering')));

    expect(controller.isOpen.value, isFalse);
    expect(find.text('covering'), findsOneWidget);
  });

  _desktopTest('PageSearchAction opens the field at compact width only', (
    tester,
  ) async {
    Widget host(WindowSizeClass sizeClass) => MaterialApp(
      home: DaySizeClass(sizeClass: sizeClass, child: const _Probe()),
    );

    await tester.pumpWidget(host(WindowSizeClass.compact));
    final action = find.byKey(const ValueKey('page-search-action'));
    expect(action, findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);

    await tester.tap(action);
    await tester.pump();
    expect(find.byKey(_field), findsOneWidget);
    // The action gives way to the field's own close button.
    expect(action, findsNothing);

    await tester.tap(find.byKey(const ValueKey('page-search-close')));
    await tester.pump();
    expect(find.byKey(_field), findsNothing);
    expect(action, findsOneWidget);

    await tester.pumpWidget(host(WindowSizeClass.expanded));
    expect(action, findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  _desktopTest(
    'without a scope the title is Text and the action is the global one',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DaySizeClass(
            sizeClass: WindowSizeClass.compact,
            child: Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: Row(
                  children: [PageSearchTitle('Plain'), PageSearchAction()],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Plain'), findsOneWidget);
      expect(find.byType(GlobalSearchAction), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-search-action')),
        findsOneWidget,
      );
    },
  );
}
