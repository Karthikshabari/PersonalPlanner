import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/utils/acyclic_links.dart';

void main() {
  test('validates a long history chain without quadratic revisits', () {
    final graph = <String, Set<String>>{
      for (var index = 0; index < 5000; index++)
        'task-$index': index == 4999 ? <String>{} : {'task-${index + 1}'},
    };

    expect(() => validateAcyclicLinks(graph), returnsNormally);
  });

  test('retains cycle and branch rejection', () {
    expect(
      () => validateAcyclicLinks({
        'a': {'b'},
        'b': {'a'},
      }),
      throwsA(isA<StateError>()),
    );
    expect(
      () => validateAcyclicLinks({
        'a': {'b', 'c'},
      }),
      throwsA(isA<StateError>()),
    );
  });
}
