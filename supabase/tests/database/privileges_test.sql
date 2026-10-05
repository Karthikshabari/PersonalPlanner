begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(6);

-- DB-026: anon has no direct writes on planner tables, and the SECURITY DEFINER
-- helpers / unsafe base RPCs are not executable by API roles.
select ok(
  not has_table_privilege('anon', 'public.tasks', 'INSERT'),
  'anon cannot insert tasks'
);
select ok(
  not has_table_privilege('anon', 'public.tasks', 'UPDATE'),
  'anon cannot update tasks'
);
select ok(
  not has_table_privilege('anon', 'public.tasks', 'DELETE'),
  'anon cannot delete tasks'
);
select ok(
  not has_table_privilege('anon', 'public.day_contexts', 'INSERT'),
  'anon cannot insert day_contexts'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.planner_recompute_task_actual(uuid,text)',
    'EXECUTE'
  ),
  'anon cannot execute helper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_sync_operation_v1_unsafe(uuid,text,text,text,bigint,jsonb)',
    'EXECUTE'
  ),
  'authenticated cannot execute unsafe base'
);

select * from finish();
rollback;
