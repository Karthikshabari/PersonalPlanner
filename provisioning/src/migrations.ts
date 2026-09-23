// Canonical SQL bundle shared by the Worker entry module and the provisioning
// implementation.
//
// These live outside `index.ts` on purpose: a Worker entry module in modules
// format may only export functions (handlers), so exporting the migration
// bundle and the verification query from the entry point makes `wrangler dev`
// and `wrangler deploy` reject the whole Worker with
// "Incorrect type for map entry".
import syncV1 from "../../supabase/migrations/20260827000000_sync_v1.sql";
import syncV1Hardening from "../../supabase/migrations/20260829000000_sync_v1_hardening.sql";
import realUseV2 from "../../supabase/migrations/20260910000000_real_use_v2.sql";
import recurrenceRemovalProvenance from "../../supabase/migrations/20260915000000_recurrence_removal_provenance.sql";
import titleHistoryConflictOrdering from "../../supabase/migrations/20260916000000_title_history_conflict_ordering.sql";
import initialSyncBaseline from "../../supabase/migrations/20260917000000_initial_sync_baseline.sql";

/** Canonical, ordered migration bundle applied to a provisioned project. */
export const MIGRATIONS = [
  {
    name: "20260827000000_sync_v1",
    query: syncV1,
    sha256: "1b22bd8eb9eb9a52a2d9405ba30093d8125816bb7107f11fed6f404230f4369b",
  },
  {
    name: "20260829000000_sync_v1_hardening",
    query: syncV1Hardening,
    sha256: "b38c4617cfbf0ccb49db0f5c0a0a32a6b8cafab6147af2a0e20f85073b2b1083",
  },
  {
    name: "20260910000000_real_use_v2",
    query: realUseV2,
    sha256: "d79f458bb3a462ee8729b18d98599dfefd7d9f2ae742b0b66b69fe15680a0cd1",
  },
  {
    name: "20260915000000_recurrence_removal_provenance",
    query: recurrenceRemovalProvenance,
    sha256: "864fa68f1cedb4cca9a62140d27939b85f05d7b9be02dbeafcd0e4d6e886d80e",
  },
  {
    name: "20260916000000_title_history_conflict_ordering",
    query: titleHistoryConflictOrdering,
    sha256: "d01e184c1c530e57a3bba20abf2fbf302a106f916be1196ee69736260f938c13",
  },
  {
    name: "20260917000000_initial_sync_baseline",
    query: initialSyncBaseline,
    sha256: "b58df9aa235d3b2729ab9118bb7ef4fc673dd9d787e45960ec9beb6cbfc5ba99",
  },
] as const;

/** Fixed, read-mostly schema verification query. */
export const SCHEMA_VERIFICATION_SQL = `
with expected_tables(table_name) as (
  values
    ('sync_state'), ('sync_changes'), ('sync_operation_ack'),
    ('sync_initial_baseline'),
    ('categories'), ('tags'), ('recurring_rules'), ('tasks'),
    ('task_templates'), ('subtasks'), ('task_tags'), ('daily_reviews'),
    ('weekly_reviews'), ('timer_sessions'), ('day_contexts'),
    ('planner_v8_migration_recovery')
), expected_functions(signature) as (
  values
    ('public.apply_sync_operation(uuid,text,text,text,bigint,jsonb)'),
    ('public.apply_sync_operation_v1_prebaseline_base(uuid,text,text,text,bigint,jsonb)'),
    ('public.apply_sync_operation_v2(uuid,text,text,text,bigint,jsonb,integer)'),
    ('public.apply_sync_operation_v2_prebaseline_base(uuid,text,text,text,bigint,jsonb,integer)'),
    ('public.apply_sync_operation_v3(uuid,text,text,text,bigint,jsonb,integer,uuid)'),
    ('public.pull_sync_changes(bigint,integer)'),
    ('public.planner_sync_capabilities()'),
    ('public.planner_sync_account_state()'),
    ('public.planner_claim_initial_baseline(uuid,bigint)'),
    ('public.planner_complete_initial_baseline(uuid)')
), helper as (
  select pg_get_functiondef(
    'public.planner_title_history_conflict_payload(jsonb,uuid,text)'::regprocedure
  ) as definition
), wrapper_v1 as (
  select pg_get_functiondef(
    'public.apply_sync_operation(uuid,text,text,text,bigint,jsonb)'::regprocedure
  ) as definition
), base_v1 as (
  select pg_get_functiondef(
    'public.apply_sync_operation_v1_prebaseline_base(uuid,text,text,text,bigint,jsonb)'::regprocedure
  ) as definition
), wrapper_v2 as (
  select pg_get_functiondef(
    'public.apply_sync_operation_v2(uuid,text,text,text,bigint,jsonb,integer)'::regprocedure
  ) as definition
), base_v2 as (
  select pg_get_functiondef(
    'public.apply_sync_operation_v2_prebaseline_base(uuid,text,text,text,bigint,jsonb,integer)'::regprocedure
  ) as definition
), wrapper_v3 as (
  select pg_get_functiondef(
    'public.apply_sync_operation_v3(uuid,text,text,text,bigint,jsonb,integer,uuid)'::regprocedure
  ) as definition
)
select
  (select count(*) = 16 from expected_tables e
    join pg_class c on c.relname = e.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where c.relkind = 'r') as required_tables_exist,
  (select bool_and(c.relrowsecurity) from expected_tables e
    join pg_class c on c.relname = e.table_name
    join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public') as rls_enabled,
  (select count(*) = 10 from expected_functions e
    where to_regprocedure(e.signature) is not null) as required_rpcs_exist,
  has_function_privilege(
    'authenticated',
    'public.apply_sync_operation_v2(uuid,text,text,text,bigint,jsonb,integer)',
    'EXECUTE'
  ) as protocol_v2_authenticated_execute,
  not has_function_privilege(
    'anon',
    'public.planner_sync_capabilities()',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.planner_sync_capabilities()',
    'EXECUTE'
  ) as capability_grants_correct,
  not has_function_privilege(
    'authenticated',
    'public.planner_title_history_conflict_payload(jsonb,uuid,text)',
    'EXECUTE'
  ) as f03_helper_private,
  (select position('planner_validate_plan_title_history' in definition) > 0
      and position('for existing_event' in definition) > 0
      and position('planner_validate_plan_title_history' in definition)
        < position('for existing_event' in definition)
    from helper) as f03_validates_branch_before_union,
  (select position('planner_title_history_conflict_payload' in definition) > 0
    from base_v1) and
  (select position('apply_sync_operation_v1_prebaseline_base' in definition) > 0
    from wrapper_v1) and
  (select position('planner_title_history_conflict_payload' in definition) > 0
    from base_v2) and
  (select position('apply_sync_operation_v2_prebaseline_base' in definition) > 0
    from wrapper_v2) as f03_wrappers_active,
  (select position('sync_initial_baseline' in definition) > 0
      and position('No active initial baseline claim' in definition) > 0
    from wrapper_v1) and
  (select position('sync_initial_baseline' in definition) > 0
      and position('No active initial baseline claim' in definition) > 0
    from wrapper_v2) and
  (select position('p_baseline_token' in definition) > 0
      and position('no longer owned by this device' in definition) > 0
      and position('the baseline is already completed' in definition) > 0
      and position('the baseline is already completed' in definition)
        < position('apply_sync_operation_v2_prebaseline_base' in definition)
    from wrapper_v3) as initial_sync_fencing_present,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks'
      and column_name = 'recurrence_removal_reason'
  ) and exists (
    select 1 from pg_constraint
    where conname = 'tasks_recurrence_removal_reason_valid'
      and conrelid = 'public.tasks'::regclass
  ) as recurrence_provenance_present,
  not exists (
    select 1
    from pg_constraint fk
    join pg_class child on child.oid = fk.conrelid
    join pg_namespace child_ns on child_ns.oid = child.relnamespace
    join pg_class parent on parent.oid = fk.confrelid
    join pg_namespace parent_ns on parent_ns.oid = parent.relnamespace
    where fk.contype = 'f'
      and child_ns.nspname = 'public'
      and parent_ns.nspname = 'public'
      and child.relname in (
        'recurring_rules', 'tasks', 'task_templates', 'subtasks',
        'task_tags', 'timer_sessions'
      )
      and array_length(fk.conkey, 1) <> 2
  ) as relationships_owner_scoped,
  not exists (
    select 1 from expected_tables e
    where has_table_privilege('authenticated', format('public.%I', e.table_name), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', e.table_name), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', e.table_name), 'DELETE')
  ) as direct_authenticated_writes_revoked,
  (
    public.planner_sync_capabilities()->>'protocol_version' = '2'
    and public.planner_sync_capabilities()->>'plan_title_history' = 'true'
    and public.planner_sync_capabilities()->>'recurrence_removal_provenance' = 'true'
    and public.planner_sync_capabilities()->>'initial_sync_baseline' = 'true'
    and public.planner_sync_capabilities()->>'initial_sync_fencing' = 'true'
    and public.planner_sync_capabilities()->'payload_versions' = '[1, 2]'::jsonb
  ) as capability_payload_current,
  public.planner_sync_capabilities() as capabilities;
`;
