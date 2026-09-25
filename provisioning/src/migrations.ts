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

/** Inspect the canonical static capability body without invoking the RPC. */
const capabilityBody = /create or replace function public\.planner_sync_capabilities\(\)[\s\S]*?\bas \$\$([\s\S]*?)\$\$;/iu.exec(initialSyncBaseline)?.[1];
if (!capabilityBody) throw new Error("canonical capability definition missing");
const capabilityBodyLiteral = `'${capabilityBody.replaceAll("'", "''")}'`;

/** Fixed, metadata-only verification. Every candidate gets the same query. */
export const SCHEMA_VERIFICATION_SQL = `
with expected_tables(table_name) as (
  values
    ('sync_state'), ('sync_changes'), ('sync_operation_ack'),
    ('sync_initial_baseline'),
    ('categories'), ('tags'), ('recurring_rules'), ('tasks'),
    ('task_templates'), ('subtasks'), ('task_tags'), ('daily_reviews'),
    ('weekly_reviews'), ('timer_sessions'), ('day_contexts'),
    ('planner_v8_migration_recovery')
), expected_functions(function_name, argument_types) as (
  values
    ('apply_sync_operation', array['uuid','text','text','text','int8','jsonb']),
    ('apply_sync_operation_v1_prebaseline_base', array['uuid','text','text','text','int8','jsonb']),
    ('apply_sync_operation_v2', array['uuid','text','text','text','int8','jsonb','int4']),
    ('apply_sync_operation_v2_prebaseline_base', array['uuid','text','text','text','int8','jsonb','int4']),
    ('apply_sync_operation_v3', array['uuid','text','text','text','int8','jsonb','int4','uuid']),
    ('pull_sync_changes', array['int8','int4']),
    ('planner_sync_capabilities', array[]::pg_catalog.text[]),
    ('planner_sync_account_state', array[]::pg_catalog.text[]),
    ('planner_claim_initial_baseline', array['uuid','int8']),
    ('planner_complete_initial_baseline', array['uuid'])
), planner_functions as (
  select p.oid, p.proname, p.prosrc, p.prosecdef, p.provolatile,
    p.prolang, p.prorettype, p.proconfig,
    coalesce((
      select pg_catalog.array_agg(t.typname::pg_catalog.text order by a.ordinality)
      from pg_catalog.unnest(p.proargtypes::pg_catalog.oid[]) with ordinality as a(type_oid, ordinality)
      join pg_catalog.pg_type t on t.oid = a.type_oid
      join pg_catalog.pg_namespace tn on tn.oid = t.typnamespace
      where tn.nspname = 'pg_catalog'
    ), array[]::pg_catalog.text[]) as argument_types
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
), function_definitions as (
  select proname, argument_types, pg_catalog.pg_get_functiondef(oid) as definition
  from planner_functions
  where proname in (
    'planner_title_history_conflict_payload',
    'apply_sync_operation', 'apply_sync_operation_v1_prebaseline_base',
    'apply_sync_operation_v2', 'apply_sync_operation_v2_prebaseline_base',
    'apply_sync_operation_v3'
  )
  and (
    (proname = 'planner_title_history_conflict_payload'
      and argument_types = array['jsonb','uuid','text'])
    or (proname in ('apply_sync_operation', 'apply_sync_operation_v1_prebaseline_base')
      and argument_types = array['uuid','text','text','text','int8','jsonb'])
    or (proname in ('apply_sync_operation_v2', 'apply_sync_operation_v2_prebaseline_base')
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4'])
    or (proname = 'apply_sync_operation_v3'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4','uuid'])
  )
), planner_tables as (
  select e.table_name, c.oid, c.relrowsecurity
  from expected_tables e
  join pg_catalog.pg_class c on c.relname = e.table_name and c.relkind = 'r'
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
)
select
  (select pg_catalog.count(*) = 16 from planner_tables) as required_tables_exist,
  coalesce((select pg_catalog.count(*) = 16 and pg_catalog.bool_and(relrowsecurity) from planner_tables), false) as rls_enabled,
  (select pg_catalog.count(*) = 10 from expected_functions e
    join planner_functions p on p.proname = e.function_name and p.argument_types = e.argument_types) as required_rpcs_exist,
  coalesce((select pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    from planner_functions where proname = 'apply_sync_operation_v2'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4']), false) as protocol_v2_authenticated_execute,
  coalesce((select not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      and pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    from planner_functions where proname = 'planner_sync_capabilities'
      and argument_types = array[]::pg_catalog.text[]), false) as capability_grants_correct,
  coalesce((select not pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
    from planner_functions where proname = 'planner_title_history_conflict_payload'
      and argument_types = array['jsonb','uuid','text']), false) as f03_helper_private,
  coalesce((select pg_catalog.strpos(definition, 'planner_validate_plan_title_history') > 0
      and pg_catalog.strpos(definition, 'for existing_event') > 0
      and pg_catalog.strpos(definition, 'planner_validate_plan_title_history')
        < pg_catalog.strpos(definition, 'for existing_event')
    from function_definitions where proname = 'planner_title_history_conflict_payload'
      and argument_types = array['jsonb','uuid','text']), false) as f03_validates_branch_before_union,
  coalesce((select pg_catalog.strpos(definition, 'planner_title_history_conflict_payload') > 0
    from function_definitions where proname = 'apply_sync_operation_v1_prebaseline_base'
      and argument_types = array['uuid','text','text','text','int8','jsonb']), false)
  and coalesce((select pg_catalog.strpos(definition, 'apply_sync_operation_v1_prebaseline_base') > 0
    from function_definitions where proname = 'apply_sync_operation'
      and argument_types = array['uuid','text','text','text','int8','jsonb']), false)
  and coalesce((select pg_catalog.strpos(definition, 'planner_title_history_conflict_payload') > 0
    from function_definitions where proname = 'apply_sync_operation_v2_prebaseline_base'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4']), false)
  and coalesce((select pg_catalog.strpos(definition, 'apply_sync_operation_v2_prebaseline_base') > 0
    from function_definitions where proname = 'apply_sync_operation_v2'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4']), false) as f03_wrappers_active,
  coalesce((select pg_catalog.strpos(definition, 'sync_initial_baseline') > 0
      and pg_catalog.strpos(definition, 'No active initial baseline claim') > 0
    from function_definitions where proname = 'apply_sync_operation'
      and argument_types = array['uuid','text','text','text','int8','jsonb']), false)
  and coalesce((select pg_catalog.strpos(definition, 'sync_initial_baseline') > 0
      and pg_catalog.strpos(definition, 'No active initial baseline claim') > 0
    from function_definitions where proname = 'apply_sync_operation_v2'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4']), false)
  and coalesce((select pg_catalog.strpos(definition, 'p_baseline_token') > 0
      and pg_catalog.strpos(definition, 'no longer owned by this device') > 0
      and pg_catalog.strpos(definition, 'the baseline is already completed') > 0
      and pg_catalog.strpos(definition, 'the baseline is already completed')
        < pg_catalog.strpos(definition, 'apply_sync_operation_v2_prebaseline_base')
    from function_definitions where proname = 'apply_sync_operation_v3'
      and argument_types = array['uuid','text','text','text','int8','jsonb','int4','uuid']), false) as initial_sync_fencing_present,
  exists (
    select 1 from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid = a.attrelid and c.relname = 'tasks'
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where a.attname = 'recurrence_removal_reason' and a.attnum > 0 and not a.attisdropped
  ) and exists (
    select 1 from pg_catalog.pg_constraint k
    join pg_catalog.pg_class c on c.oid = k.conrelid and c.relname = 'tasks'
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where k.conname = 'tasks_recurrence_removal_reason_valid'
  ) as recurrence_provenance_present,
  not exists (
    select 1
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_class child on child.oid = fk.conrelid
    join pg_catalog.pg_namespace child_ns on child_ns.oid = child.relnamespace
    join pg_catalog.pg_class parent on parent.oid = fk.confrelid
    join pg_catalog.pg_namespace parent_ns on parent_ns.oid = parent.relnamespace
    where fk.contype = 'f'
      and child_ns.nspname = 'public'
      and parent_ns.nspname = 'public'
      and child.relname in (
        'recurring_rules', 'tasks', 'task_templates', 'subtasks',
        'task_tags', 'timer_sessions'
      )
      and pg_catalog.array_length(fk.conkey, 1) <> 2
  ) as relationships_owner_scoped,
  (select pg_catalog.count(*) = 16 and coalesce(pg_catalog.bool_and(
    not pg_catalog.has_table_privilege('authenticated', oid, 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', oid, 'UPDATE')
    and not pg_catalog.has_table_privilege('authenticated', oid, 'DELETE')
  ), false) from planner_tables) as direct_authenticated_writes_revoked,
  coalesce((select
      prosrc = ${capabilityBodyLiteral}
      and prolang = (select oid from pg_catalog.pg_language where lanname = 'sql')
      and prorettype = (select t.oid from pg_catalog.pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        where n.nspname = 'pg_catalog' and t.typname = 'jsonb')
      and prosecdef and provolatile = 's'
      and proconfig = array['search_path=public, pg_temp']
    from planner_functions where proname = 'planner_sync_capabilities'
      and argument_types = array[]::pg_catalog.text[]), false) as capability_payload_current;
`;
