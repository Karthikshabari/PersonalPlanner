import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the canonical migration list is exactly the reviewed release set', () {
    final migrations =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .where((name) => name.endsWith('.sql'))
            .toList()
          ..sort();

    expect(
      migrations,
      equals(<String>[
        '20260827000000_sync_v1.sql',
        '20260829000000_sync_v1_hardening.sql',
        '20260910000000_real_use_v2.sql',
        '20260915000000_recurrence_removal_provenance.sql',
        '20260916000000_title_history_conflict_ordering.sql',
        '20260917000000_initial_sync_baseline.sql',
      ]),
    );
  });

  test('the provisioning bundle hashes match every migration on disk', () {
    // The Worker's migration bundle lives in a non-entry module, because a
    // Worker entry module in modules format may only export functions.
    final bundle = File('provisioning/src/migrations.ts');
    final manifest = (bundle.existsSync()
            ? bundle
            : File('provisioning/src/index.ts'))
        .readAsStringSync();
    final entries = RegExp(
      r'name: "([0-9a-z_]+)",\s*\n\s*query: [A-Za-z0-9]+,\s*\n\s*sha256: "([0-9a-f]{64})"',
    ).allMatches(manifest).toList();

    expect(entries, hasLength(6));
    for (final entry in entries) {
      final name = entry.group(1)!;
      final expected = entry.group(2)!;
      final file = File('supabase/migrations/$name.sql');
      expect(file.existsSync(), isTrue, reason: '$name must exist');
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        expected,
        reason: '$name content must match the provisioning bundle digest',
      );
    }
    expect(
      entries.map((entry) => entry.group(1)),
      equals(<String>[
        '20260827000000_sync_v1',
        '20260829000000_sync_v1_hardening',
        '20260910000000_real_use_v2',
        '20260915000000_recurrence_removal_provenance',
        '20260916000000_title_history_conflict_ordering',
        '20260917000000_initial_sync_baseline',
      ]),
    );
  });

  test('Phase G baseline protocol is server-authoritative, fenced and RPC-only', () {
    final migration = File(
      'supabase/migrations/20260917000000_initial_sync_baseline.sql',
    ).readAsStringSync();

    expect(migration, contains('create table if not exists public.sync_initial_baseline'));
    expect(
      migration,
      contains('alter table public.sync_initial_baseline enable row level security'),
    );
    expect(
      migration,
      contains(
        'revoke all on table public.sync_initial_baseline from public, anon, authenticated',
      ),
    );
    // Emptiness/history is durable evidence, not a single-table row count.
    expect(migration, contains('create or replace function public.planner_account_has_history()'));
    expect(migration, contains('from public.sync_changes c'));
    expect(migration, contains('from public.task_tags x'));
    expect(migration, contains('from public.day_contexts x'));
    expect(
      migration,
      contains('revoke all on function public.planner_account_has_history()'),
    );

    // Discovery exposes the protocol state: an in-progress first baseline is
    // explicitly not established, and a completed baseline establishes the
    // account even with zero Planner rows.
    final discoveryBody = migration.substring(
      migration.indexOf(
        'create or replace function public.planner_sync_account_state()',
      ),
      migration.indexOf(
        'create or replace function public.planner_claim_initial_baseline(',
      ),
    );
    expect(discoveryBody, contains("'baseline_state'"));
    expect(discoveryBody, contains("'established'"));
    expect(discoveryBody, contains("then 'completed'"));
    expect(discoveryBody, contains("else 'in_progress'"));
    expect(
      discoveryBody,
      contains("or (state_name = 'none' and history)"),
    );
    expect(discoveryBody, contains("'expired'"));
    expect(discoveryBody, contains('public.planner_initial_baseline_lease()'));

    // Claim decision order: same-token resume, completed baseline, live foreign
    // claim, expired foreign claim with partial history (recovery), takeover of
    // a provably empty expired claim, legacy history, then a real claim.
    final claimBody = migration.substring(
      migration.indexOf(
        'create or replace function public.planner_claim_initial_baseline(',
      ),
      migration.indexOf(
        'create or replace function public.planner_complete_initial_baseline(',
      ),
    );
    final accountLock = claimBody.indexOf('for update');
    final idempotentReclaim = claimBody.indexOf(
      "and baseline_row.claim_token = p_claim_token",
    );
    final completedBranch = claimBody.indexOf(
      "and baseline_row.completed_at is not null then",
    );
    final liveForeign = claimBody.indexOf("'status', 'claim_held'");
    final recovery = claimBody.indexOf("'status', 'recovery_required'");
    final takeover = claimBody.indexOf("'took_over_expired_claim', true");
    final legacyHistory = claimBody.indexOf(
      '-- 5. No claim exists. Durable Planner history means this is a legacy account',
    );
    final claimInsert = claimBody.indexOf(
      'insert into public.sync_initial_baseline(',
    );
    expect(accountLock, greaterThanOrEqualTo(0));
    expect(idempotentReclaim, greaterThan(accountLock));
    expect(completedBranch, greaterThan(idempotentReclaim));
    expect(liveForeign, greaterThan(completedBranch));
    expect(recovery, greaterThan(liveForeign));
    expect(takeover, greaterThan(recovery));
    expect(legacyHistory, greaterThan(takeover));
    expect(claimInsert, greaterThan(legacyHistory));
    expect(claimBody, contains("'status', 'remote_in_use'"));
    expect(claimBody, contains("'status', 'baseline_changed'"));
    expect(claimBody, contains("'status', 'claimed'"));
    // A takeover of an expired foreign claim is only allowed when the server can
    // prove nothing was uploaded under it.
    final recoveryGuard = claimBody.substring(
      recovery - 600,
      recovery,
    );
    expect(recoveryGuard, contains('if history'));
    expect(recoveryGuard, contains('baseline_row.observed_next_change_id'));

    // Completion only marks the caller's own claim.
    expect(
      migration,
      contains(
        'where user_id = caller and claim_token = p_claim_token',
      ),
    );

    // Fencing: the ordinary v2 entry point refuses untokened mutations while a
    // first baseline is in progress, and v3 verifies and renews the claimant.
    final v2Body = migration.substring(
      migration.indexOf('create or replace function public.apply_sync_operation_v2('),
      migration.indexOf('create or replace function public.apply_sync_operation_v3('),
    );
    expect(
      migration,
      contains(
        ') rename to apply_sync_operation_v2_prebaseline_base',
      ),
    );
    expect(v2Body, contains('sync_initial_baseline'));
    expect(v2Body, contains('and baseline_row.completed_at is null then'));
    expect(v2Body, contains('No active initial baseline claim'));
    expect(
      v2Body,
      contains(
        'return public.apply_sync_operation_v2_prebaseline_base(',
      ),
    );
    final v3Body = migration.substring(
      migration.indexOf('create or replace function public.apply_sync_operation_v3('),
    );
    expect(v3Body, contains('p_baseline_token'));
    expect(v3Body, contains("message = 'Initial baseline claim token is required'"));
    expect(v3Body, contains('No active initial baseline claim for this account'));
    expect(v3Body, contains('no longer owned by this device'));
    expect(v3Body, contains('set claimed_at = server_now'));
    expect(v3Body, contains('where user_id = caller and claim_token = p_baseline_token'));
    expect(v3Body, contains('return public.apply_sync_operation_v2_prebaseline_base('));
    // v3 is strictly the in-progress entry point: a completed baseline is a
    // rejection, not a delegation, so a replaced/stale token can never mutate
    // after the replacement claimant completed the baseline.
    final v3CompletedRejection = v3Body.indexOf(
      'the baseline is already completed',
    );
    final v3Delegation = v3Body.indexOf(
      'return public.apply_sync_operation_v2_prebaseline_base(',
    );
    expect(v3CompletedRejection, greaterThanOrEqualTo(0));
    expect(
      v3Delegation,
      greaterThan(v3CompletedRejection),
      reason: 'the completed-baseline rejection must precede any delegation',
    );
    expect(
      'return public.apply_sync_operation_v2_prebaseline_base('
          .allMatches(v3Body)
          .length,
      1,
      reason: 'v3 has exactly one mutation delegation',
    );
    expect(
      v3Body.substring(v3CompletedRejection, v3Delegation),
      contains('raise exception'),
    );
    // The fenced entry point is authenticated-only and the base is private.
    expect(
      migration,
      contains(
        'revoke all on function public.apply_sync_operation_v2_prebaseline_base(',
      ),
    );
    expect(
      migration,
      contains('grant execute on function public.apply_sync_operation_v3('),
    );
    expect(migration, contains(') to authenticated;\n\nrevoke all on function '));
    expect(
      migration,
      contains('revoke all on function public.apply_sync_operation_v3('),
    );

    expect(
      migration,
      contains('grant execute on function public.planner_sync_account_state() to authenticated'),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.planner_claim_initial_baseline(uuid, bigint)',
      ),
    );
    expect(migration, contains("'initial_sync_baseline', true"));
    expect(migration, contains("'initial_sync_fencing', true"));
  });

  test('Phase G fences the historical v1 mutation surface too', () {
    final migration = File(
      'supabase/migrations/20260917000000_initial_sync_baseline.sql',
    ).readAsStringSync();

    // The reviewed v1 implementation is renamed and made private...
    expect(
      migration,
      contains(') rename to apply_sync_operation_v1_prebaseline_base'),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.apply_sync_operation_v1_prebaseline_base(',
      ),
    );
    expect(
      migration,
      contains(
        'from public, anon, authenticated;\n\ncreate or replace function public.apply_sync_operation(',
      ),
    );
    // ...and the public v1 signature stays available, now fenced.
    expect(
      migration,
      contains('create or replace function public.apply_sync_operation(\n'),
    );
    expect(
      migration,
      contains('grant execute on function public.apply_sync_operation(\n  uuid, text, text, text, bigint, jsonb\n) to authenticated;'),
    );

    final v1Body = migration.substring(
      migration.indexOf(
        'create or replace function public.apply_sync_operation(\n  p_operation_id uuid,',
      ),
      migration.indexOf(
        '-- Fenced mutation entry point of the current initial-baseline claimant.',
      ),
    );
    final accountLock = v1Body.indexOf(
      'perform 1 from public.sync_state s where s.user_id = caller for update',
    );
    final baselineLookup = v1Body.indexOf(
      'from public.sync_initial_baseline b',
    );
    final fenceRejection = v1Body.indexOf('No active initial baseline claim');
    final delegation = v1Body.indexOf(
      'return public.apply_sync_operation_v1_prebaseline_base(',
    );
    expect(accountLock, greaterThanOrEqualTo(0));
    expect(baselineLookup, greaterThan(accountLock));
    expect(fenceRejection, greaterThan(baselineLookup));
    expect(delegation, greaterThan(fenceRejection));
    expect(v1Body, contains('and baseline_row.completed_at is null then'));
    expect(v1Body, contains('raise exception'));

    // Every authenticated mutation wrapper uses the same guard shape, and both
    // reviewed bases are unreachable directly.
    final v2Body = migration.substring(
      migration.indexOf('create or replace function public.apply_sync_operation_v2('),
      migration.indexOf('-- Split the historical v1 entry point as well.'),
    );
    for (final body in <String>[v1Body, v2Body]) {
      expect(body, contains('sync_initial_baseline'));
      expect(body, contains('and baseline_row.completed_at is null then'));
      expect(body, contains('raise exception using errcode = \'P0001\''));
      expect(
        body.indexOf('raise exception using errcode = \'P0001\''),
        lessThan(body.indexOf('return public.apply_sync_operation_v')),
      );
    }
    expect(
      migration,
      contains('revoke all on function public.apply_sync_operation_v2_prebaseline_base('),
    );
  });

  test('F03 migration classifies stale title branches before transition checks', () {
    final sql = File(
      'supabase/migrations/20260916000000_title_history_conflict_ordering.sql',
    ).readAsStringSync();

    final structuralValidation = sql.indexOf(
      'perform public.planner_validate_plan_title_history',
    );
    final branchUnion = sql.indexOf(
      'branch_history := branch_history || jsonb_build_array(existing_event)',
    );
    final accountLock = sql.indexOf(
      'perform 1 from public.sync_state s where s.user_id = caller for update',
    );
    final acknowledgement = sql.indexOf(
      'where a.user_id = caller and a.operation_id = p_operation_id',
      accountLock,
    );
    final casClassification = sql.indexOf(
      'p_expected_server_version is distinct from current_version',
      acknowledgement,
    );
    final conflictPayload = sql.indexOf(
      'planner_title_history_conflict_payload',
      casClassification,
    );
    final delegatedBase = sql.indexOf(
      'apply_sync_operation_v1_title_order_base',
      conflictPayload,
    );

    expect(structuralValidation, greaterThanOrEqualTo(0));
    expect(branchUnion, greaterThan(structuralValidation));
    expect(accountLock, greaterThanOrEqualTo(0));
    expect(acknowledgement, greaterThan(accountLock));
    expect(casClassification, greaterThan(acknowledgement));
    expect(conflictPayload, greaterThan(casClassification));
    expect(delegatedBase, greaterThan(conflictPayload));
    expect(
      sql,
      contains(
        "message = 'Plan title event ID has conflicting immutable data'",
      ),
    );
    expect(sql, contains("p_operation in ('insert', 'update')"));
    expect(sql, contains('apply_sync_operation_v2_title_order_base'));
    expect(
      sql,
      contains(
        'revoke all on function public.planner_title_history_conflict_payload',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on function public.apply_sync_operation_v2_title_order_base',
      ),
    );
    expect(
      sql,
      contains('grant execute on function public.apply_sync_operation_v2'),
    );
  });

  test('F03 delegation retains server ownership and relationship guards', () {
    final foundation = File('supabase/migrations/20260827000000_sync_v1.sql')
        .readAsStringSync();
    final hardening = File(
      'supabase/migrations/20260829000000_sync_v1_hardening.sql',
    ).readAsStringSync();
    final v2 = File('supabase/migrations/20260910000000_real_use_v2.sql')
        .readAsStringSync();
    final f03 = File(
      'supabase/migrations/20260916000000_title_history_conflict_ordering.sql',
    ).readAsStringSync();

    expect(f03, contains("jsonb_typeof(canonical) <> 'object'"));
    expect(
      f03,
      contains('if acknowledged is not null then return acknowledged'),
    );
    expect(f03, contains('if stale_branch then'));
    expect(
      f03,
      contains('return public.apply_sync_operation_v2_title_order_base'),
    );
    expect(hardening, contains('Payload contains server-owned fields'));
    expect(hardening, contains('where s.user_id = caller'));
    expect(
      foundation,
      contains(
        'foreign key (user_id, category_id) references public.categories(user_id, id)',
      ),
    );
    expect(
      foundation,
      contains(
        'foreign key (user_id, task_id) references public.tasks(user_id, id)',
      ),
    );
    expect(
      v2,
      contains(
        'revoke all on function public.planner_apply_sync_operation_internal',
      ),
    );
    expect(
      f03,
      contains(
        'revoke all on function public.apply_sync_operation_v2_title_order_base',
      ),
    );
  });

  test('recurrence provenance migration is append-only and constrained', () {
    final sql = File(
      'supabase/migrations/20260915000000_recurrence_removal_provenance.sql',
    ).readAsStringSync();

    expect(sql, contains('add column if not exists recurrence_removal_reason'));
    expect(sql, contains("recurrence_removal_reason = 'rule_excluded'"));
    expect(sql, contains("'recurrence_removal_provenance', true"));
  });

  test('sync history validation is ordered after the account lock', () {
    final sql = File('supabase/migrations/20260829000000_sync_v1_hardening.sql')
        .readAsStringSync();
    final lock = sql.indexOf('perform 1');
    final historyValidation = sql.indexOf('with recursive history_edges');

    expect(lock, greaterThanOrEqualTo(0));
    expect(historyValidation, greaterThan(lock));
    expect(sql.substring(lock, historyValidation), contains('for update'));
  });

  test('R3 day-context schema and RPC preserve account isolation', () {
    final sql = File('supabase/migrations/20260910000000_real_use_v2.sql')
        .readAsStringSync();

    expect(sql, contains('create table if not exists public.day_contexts'));
    expect(sql, contains('primary key (user_id, id)'));
    expect(sql, contains('unique (user_id, date)'));
    expect(sql, contains('date text not null check'));
    expect(sql, contains('extensions.uuid_generate_v5'));
    expect(
      sql,
      contains('alter table public.day_contexts enable row level security'),
    );
    expect(sql, contains('create policy day_contexts_select'));
    expect(sql, contains("if p_table_name = 'day_contexts' then"));
    expect(sql, contains('current_version bigint;'));
    expect(sql, contains("'day_contexts', true"));
  });

  test('Foundation migration includes title history and private adapters', () {
    final sql = File('supabase/migrations/20260910000000_real_use_v2.sql')
        .readAsStringSync();

    expect(sql, contains('add column if not exists plan_title_history_json'));
    expect(sql, contains('add column if not exists display_plan_change_id'));
    expect(sql, contains('planner_validate_plan_title_history'));
    expect(sql, contains('planner_normalize_task_title_history'));
    expect(sql, contains('planner_apply_sync_operation_internal'));
    expect(
      sql,
      contains(
        'revoke all on function public.planner_apply_sync_operation_internal',
      ),
    );
    expect(sql, contains('apply_sync_operation_v1_foundation'));
    expect(sql, contains('p_client_protocol integer'));
    expect(
      sql,
      contains("p_client_protocol = 1 and p_table_name = 'day_contexts'"),
    );
    expect(sql, contains('apply_sync_operation_v1_title_base'));
    expect(sql, contains('apply_sync_operation_v2_title_base'));
    expect(
      sql,
      contains(
        'revoke all on function public.apply_sync_operation_v2_title_base',
      ),
    );
    expect(sql, contains("'plan_title_history', true"));
    expect(sql, contains('create temporary table planner_v8_semantic_tasks'));
    expect(sql, contains('migration_operation := gen_random_uuid()'));
    expect(sql, contains('insert into public.sync_changes('));
    expect(sql, contains('insert into public.sync_operation_ack('));
    expect(sql, contains("migration_operation := gen_random_uuid()"));
    expect(sql, contains('insert into public.sync_changes'));
    expect(sql, contains('insert into public.sync_operation_ack'));
    expect(
      sql.lastIndexOf('insert into public.sync_changes'),
      lessThan(sql.lastIndexOf('commit;')),
    );
  });
}
