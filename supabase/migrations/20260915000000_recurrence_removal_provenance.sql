begin;

-- Rule-exclusion tombstones arrive as full-row updates. Historical and
-- older-client tombstones stay null and therefore never authorize revival.
alter table public.tasks
  add column if not exists recurrence_removal_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_recurrence_removal_reason_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_recurrence_removal_reason_valid
      check (
        recurrence_removal_reason is null
        or recurrence_removal_reason = 'rule_excluded'
      );
  end if;
end
$$;

create or replace function public.planner_sync_capabilities()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'protocol_version', 2,
    'schedule_duration_projection', true,
    'inbox_content_version', true,
    'due_date', true,
    'manual_actual_source', true,
    'timer_state_machine', true,
    'day_contexts', true,
    'plan_title_history', true,
    'recurrence_removal_provenance', true,
    'payload_versions', jsonb_build_array(1, 2)
  )
$$;
revoke all on function public.planner_sync_capabilities() from public, anon;
grant execute on function public.planner_sync_capabilities() to authenticated;

commit;
