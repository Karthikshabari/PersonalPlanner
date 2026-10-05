begin;

-- DB-013: child-side indexes for owner-scoped foreign keys and the timer
-- actual-duration recompute.
create index if not exists timer_sessions_user_task_idx
  on public.timer_sessions(user_id, task_id);
create index if not exists subtasks_user_task_idx
  on public.subtasks(user_id, task_id);
create index if not exists task_tags_user_tag_idx
  on public.task_tags(user_id, tag_id);
create index if not exists tasks_user_rescheduled_from_idx
  on public.tasks(user_id, rescheduled_from_id)
  where rescheduled_from_id is not null;

-- DB-027: duplicates of the primary key and of unique(user_id, operation_id).
drop index if exists public.sync_changes_user_cursor_idx;
drop index if exists public.sync_changes_operation_idx;

-- DB-026: planner tables are RPC-written only. Remove write policies so a
-- future accidental grant cannot open direct writes, and re-assert revokes.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'sync_state', 'sync_changes', 'sync_operation_ack', 'categories', 'tags',
    'recurring_rules', 'tasks', 'task_templates', 'subtasks', 'task_tags',
    'daily_reviews', 'weekly_reviews', 'timer_sessions', 'day_contexts'
  ] loop
    execute format('drop policy if exists %I on public.%I', table_name || '_insert', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete', table_name);
    execute format('revoke insert, update, delete, truncate on table public.%I from anon, authenticated', table_name);
    execute format('revoke all on table public.%I from anon', table_name);
  end loop;
end;
$$;

revoke all on function public.apply_sync_operation_v1_unsafe(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v1_hardened(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v1_foundation(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v1_title_base(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v1_title_order_base(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v1_prebaseline_base(uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v2_title_base(uuid, text, text, text, bigint, jsonb, integer) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v2_title_order_base(uuid, text, text, text, bigint, jsonb, integer) from public, anon, authenticated;
revoke all on function public.apply_sync_operation_v2_prebaseline_base(uuid, text, text, text, bigint, jsonb, integer) from public, anon, authenticated;
revoke all on function public.planner_apply_sync_operation_internal(uuid, text, text, text, bigint, jsonb, integer, integer) from public, anon, authenticated;
revoke all on function public.planner_recompute_task_actual(uuid, text) from public, anon, authenticated;
revoke all on function public.planner_validate_timer_payload(jsonb) from public, anon, authenticated;
revoke all on function public.planner_validate_plan_title_history(text, text, text) from public, anon, authenticated;
revoke all on function public.planner_normalize_task_title_history(jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.planner_title_history_conflict_payload(jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.planner_account_has_history() from public, anon, authenticated;
revoke all on function public.planner_initial_baseline_lease() from public, anon, authenticated;
revoke all on function public.sync_set_updated_at() from public, anon, authenticated;
revoke all on function public.day_contexts_set_updated_at() from public, anon, authenticated;
revoke all on function public.sync_normalize_task_schedule() from public, anon, authenticated;
revoke all on function public.planner_timer_cache_trigger() from public, anon, authenticated;
revoke all on function public.planner_task_actual_cache_trigger() from public, anon, authenticated;

-- DB-012: narrow the reschedule-cycle check. The body is the hardened v1 body
-- (20260829000000_sync_v1_hardening.sql:22-205) with the whole-history cycle scan
-- replaced by a walk from p_record_id that runs only when the links change.
create or replace function public.apply_sync_operation_v1_hardened(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  payload_id text;
  current_from text;
  current_to text;
  links_changed boolean := false;
  has_cycle boolean := false;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Sync payload must be a JSON object';
  end if;
  if p_payload ?| array['user_id', 'server_version', 'change_id', 'server_timestamp'] then
    raise exception using errcode = '22023', message = 'Payload contains server-owned fields';
  end if;

  if p_record_id is null or btrim(p_record_id) = '' then
    raise exception using errcode = '22023', message = 'Record identity is required';
  end if;
  if p_table_name = 'task_tags' then
    if split_part(p_record_id, ':', 1) = ''
       or split_part(p_record_id, ':', 2) = ''
       or split_part(p_record_id, ':', 3) <> ''
       or p_payload->>'task_id' is distinct from split_part(p_record_id, ':', 1)
       or p_payload->>'tag_id' is distinct from split_part(p_record_id, ':', 2) then
      raise exception using errcode = '22023', message = 'Record identity does not match payload';
    end if;
  else
    payload_id := p_payload->>'id';
    if payload_id is null or payload_id is distinct from p_record_id then
      raise exception using errcode = '22023', message = 'Record identity does not match payload';
    end if;
  end if;

  -- Serialize the complete account history before any graph validation. The
  -- unsafe mutation function acquires this same row lock again, so the lock
  -- remains held through validation, CAS and change-log insertion.
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1
  from public.sync_state s
  where s.user_id = caller
  for update;

  if p_operation <> 'delete' then
    if p_table_name = 'tasks' and (
      nullif(btrim(p_payload->>'title'), '') is null
      or coalesce((p_payload->>'priority')::integer, 0) not between 0 and 4
      or coalesce((p_payload->>'is_inbox')::integer, 0) not in (0, 1)
      or (p_payload->>'estimated_duration_min')::integer <= 0
      or (p_payload->>'actual_duration_min')::integer < 0
      or p_payload->>'status' not in (
        'planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled'
      )
      or (
        p_payload->>'end_time' is not null
        and p_payload->>'start_time' is null
      )
      or (
        p_payload->>'start_time' is not null
        and p_payload->>'end_time' is not null
        and (p_payload->>'end_time')::timestamptz <=
            (p_payload->>'start_time')::timestamptz
      )
      or (
        coalesce((p_payload->>'is_inbox')::integer, 0) = 1
        and (
          p_payload->>'start_time' is not null
          or p_payload->>'end_time' is not null
        )
      )
    ) then
      raise exception using errcode = '22023', message = 'Invalid task payload';
    end if;
    if p_table_name = 'tasks' then
      select t.rescheduled_from_id, t.rescheduled_to_id
        into current_from, current_to
      from public.tasks t
      where t.user_id = caller and t.id = p_record_id;
      links_changed := not found
        or current_from is distinct from p_payload->>'rescheduled_from_id'
        or current_to is distinct from p_payload->>'rescheduled_to_id';
      if links_changed and (p_payload->>'rescheduled_from_id' is not null
                            or p_payload->>'rescheduled_to_id' is not null) then
        with recursive walk(node) as (
          select p_payload->>'rescheduled_to_id'
          where p_payload->>'rescheduled_to_id' is not null
          union
          select t.id from public.tasks t
          where t.user_id = caller and t.rescheduled_from_id = p_record_id
            and t.id <> p_record_id
          union
          select p_record_id where p_payload->>'rescheduled_from_id' = p_record_id
          union
          select s.next_id
          from walk w
          cross join lateral (
            select case when t.id = p_record_id
                        then p_payload->>'rescheduled_to_id'
                        else t.rescheduled_to_id end as next_id
              from public.tasks t
             where t.user_id = caller and t.id = w.node
            union all
            select t2.id from public.tasks t2
             where t2.user_id = caller and t2.rescheduled_from_id = w.node
               and t2.id <> p_record_id
            union all
            select p_record_id where p_payload->>'rescheduled_from_id' = w.node
          ) s
          where s.next_id is not null
        )
        select exists (select 1 from walk where node = p_record_id) into has_cycle;
        if has_cycle then
          raise exception using errcode = '22023',
            message = 'Reschedule history links must be acyclic';
        end if;
      end if;
    end if;
    if p_table_name = 'categories' and (
      nullif(btrim(p_payload->>'name'), '') is null
      or p_payload->>'color_hex' !~ '^#[0-9A-Fa-f]{6}$'
      or coalesce((p_payload->>'sort_order')::integer, 0) < 0
      or coalesce((p_payload->>'is_focus')::integer, 0) not in (0, 1)
    ) then
      raise exception using errcode = '22023', message = 'Invalid category payload';
    end if;
    if p_table_name = 'tags' and nullif(btrim(p_payload->>'name'), '') is null then
      raise exception using errcode = '22023', message = 'Invalid tag payload';
    end if;
    if p_table_name = 'subtasks' and (
      nullif(btrim(p_payload->>'title'), '') is null
      or coalesce((p_payload->>'is_completed')::integer, 0) not in (0, 1)
      or coalesce((p_payload->>'sort_order')::integer, 0) < 0
    ) then
      raise exception using errcode = '22023', message = 'Invalid subtask payload';
    end if;
    if p_table_name = 'recurring_rules' and (
      nullif(btrim(p_payload->>'rrule'), '') is null
      or nullif(btrim(p_payload->>'task_title'), '') is null
      or (p_payload->>'duration_min')::integer <= 0
      or coalesce((p_payload->>'priority')::integer, 0) not between 0 and 4
      or coalesce((p_payload->>'is_active')::integer, 1) not in (0, 1)
    ) then
      raise exception using errcode = '22023', message = 'Invalid recurring rule payload';
    end if;
    if p_table_name = 'task_templates' and (
      nullif(btrim(p_payload->>'name'), '') is null
      or (p_payload->>'duration_min')::integer <= 0
      or coalesce((p_payload->>'priority')::integer, 0) not between 0 and 4
    ) then
      raise exception using errcode = '22023', message = 'Invalid task template payload';
    end if;
    if p_table_name = 'daily_reviews' and (
      (p_payload->>'energy_level')::integer not between 1 and 5
      or (p_payload->>'productivity_rating')::integer not between 1 and 5
      or (p_payload->>'planning_accuracy_rating')::integer not between 1 and 5
    ) then
      raise exception using errcode = '22023', message = 'Invalid daily review payload';
    end if;
    if p_table_name = 'weekly_reviews' and
       (p_payload->>'overall_rating')::integer not between 1 and 5 then
      raise exception using errcode = '22023', message = 'Invalid weekly review payload';
    end if;
    if p_table_name = 'timer_sessions' and (
      coalesce((p_payload->>'duration_sec')::integer, 0) < 0
      or (
        p_payload->>'ended_at' is not null
        and (p_payload->>'ended_at')::timestamptz <
            (p_payload->>'started_at')::timestamptz
      )
    ) then
      raise exception using errcode = '22023', message = 'Invalid timer session payload';
    end if;
  end if;

  return public.apply_sync_operation_v1_unsafe(
    p_operation_id,
    p_table_name,
    p_record_id,
    p_operation,
    p_expected_server_version,
    p_payload
  );
end;
$$;

commit;
