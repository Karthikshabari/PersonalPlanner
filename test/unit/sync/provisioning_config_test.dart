import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/config/provisioning_config.dart';
import 'package:personal_planner/features/sync/presentation/widgets/cloud_setup_card.dart';

void main() {
  test('normal builds use the public production provisioning Worker', () {
    expect(
      ProvisioningConfig.baseUri,
      Uri.parse(
        'https://personal-planner-provisioning-poc.karthikshabariper.workers.dev',
      ),
    );
  });

  test('dashboard URL contains only the validated project identity', () {
    expect(
      supabaseProjectDashboardUrl('abcdefghijklmnopqrst'),
      Uri.parse('https://supabase.com/dashboard/project/abcdefghijklmnopqrst'),
    );
    expect(
      () => supabaseProjectDashboardUrl('project?capability=secret'),
      throwsArgumentError,
    );
  });
}
