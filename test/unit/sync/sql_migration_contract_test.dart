import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Foundation uses one appended migration after the deployed v1 pair', () {
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
      ]),
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
