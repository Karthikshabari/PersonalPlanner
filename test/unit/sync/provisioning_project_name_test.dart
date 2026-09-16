import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/sync/presentation/controllers/provisioning_ui_controller.dart';

void main() {
  // The Worker rejects names that do not satisfy this rule.
  final workerRule = RegExp(r'^personal-planner-[a-z0-9-]{3,55}$');

  test('derives a deterministic name from the provisioning transaction', () {
    const transactionId = '0123456789abcdef0123456789abcdef';

    expect(
      provisioningProjectName(transactionId),
      'personal-planner-0123456789ab',
    );
    // The same attempt always produces the same identity, so retries continue
    // to reconcile against the same project.
    expect(
      provisioningProjectName(transactionId),
      provisioningProjectName(transactionId),
    );
  });

  test('different transactions produce different project names', () {
    expect(
      provisioningProjectName('0123456789abcdef0123456789abcdef'),
      isNot(provisioningProjectName('fedcba9876543210fedcba9876543210')),
    );
  });

  test('satisfies the Worker rule and carries no personal information', () {
    final name = provisioningProjectName('aabbccddeeff00112233445566778899');

    expect(workerRule.hasMatch(name), isTrue);
    expect(name, matches(RegExp(r'^[a-z0-9-]+$')));
    for (final forbidden in <String>['@', '.', '_', ' ', '..']) {
      expect(name.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('rejects transaction ids that cannot identify an attempt', () {
    for (final transactionId in <String>[
      '',
      'short',
      'ABCDEF0123456789abcdef0123456789',
      '0123456789abcdef0123456789abcdeg',
      '0123456789abcdef0123456789abcde',
    ]) {
      expect(
        () => provisioningProjectName(transactionId),
        throwsArgumentError,
        reason: transactionId,
      );
    }
  });
}
