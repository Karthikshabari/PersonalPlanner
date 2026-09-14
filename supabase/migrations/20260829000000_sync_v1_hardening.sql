-- Chunk 9A: harden the already-applied v1 RPC without rewriting its migration.

alter function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  rename to apply_sync_operation_v1_unsafe;

revoke all on function public.apply_sync_operation_v1_unsafe(
  uuid, text, text, text, bigint, jsonb
) from public, anon, authenticated;

create or replace function public.apply_sync_operation(
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
    if p_table_name = 'tasks' and exists (
      with recursive history_edges(from_id, to_id) as (
        select t.id,
          case when t.id = p_record_id
            then p_payload->>'rescheduled_to_id'
            else t.rescheduled_to_id
          end
        from public.tasks t
        where t.user_id = auth.uid()
        union all
        select case when t.id = p_record_id
            then p_payload->>'rescheduled_from_id'
            else t.rescheduled_from_id
          end,
          t.id
        from public.tasks t
        where t.user_id = auth.uid()
        union all
        select p_record_id, p_payload->>'rescheduled_to_id'
        where not exists (
          select 1 from public.tasks t
          where t.user_id = auth.uid() and t.id = p_record_id
        )
        union all
        select p_payload->>'rescheduled_from_id', p_record_id
        where not exists (
          select 1 from public.tasks t
          where t.user_id = auth.uid() and t.id = p_record_id
        )
      ),
      walk(start_id, current_id) as (
        select from_id, to_id
        from history_edges
        where from_id is not null and to_id is not null
        union
        select w.start_id, e.to_id
        from walk w
        join history_edges e on e.from_id = w.current_id
        where e.to_id is not null
      )
      select 1 from walk where start_id = current_id
    ) then
      raise exception using errcode = '22023',
        message = 'Reschedule history links must be acyclic';
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

grant execute on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) to authenticated;
revoke all on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) from public, anon;

alter table public.categories
  add constraint categories_focus_valid check (is_focus in (0, 1)),
  add constraint categories_sort_valid check (sort_order >= 0),
  add constraint categories_color_valid check (color_hex ~ '^#[0-9A-Fa-f]{6}$');
alter table public.tasks
  add constraint tasks_priority_valid check (priority between 0 and 4),
  add constraint tasks_status_valid check (
    status in ('planned', 'in_progress', 'completed', 'skipped', 'cancelled', 'rescheduled')
  ),
  add constraint tasks_inbox_valid check (is_inbox in (0, 1)),
  add constraint tasks_duration_valid check (
    (estimated_duration_min is null or estimated_duration_min > 0) and
    coalesce(actual_duration_min, 0) >= 0
  ),
  add constraint tasks_time_valid check (
    (end_time is null or start_time is not null) and
    (start_time is null or end_time is null or end_time > start_time)
  ),
  add constraint tasks_inbox_schedule_valid check (
    is_inbox = 0 or (start_time is null and end_time is null)
  );
alter table public.subtasks
  add constraint subtasks_completed_valid check (is_completed in (0, 1)),
  add constraint subtasks_sort_valid check (sort_order >= 0);
alter table public.recurring_rules
  add constraint recurring_duration_valid check (duration_min > 0),
  add constraint recurring_priority_valid check (priority between 0 and 4),
  add constraint recurring_active_valid check (is_active in (0, 1));
alter table public.task_templates
  add constraint templates_duration_valid check (duration_min > 0),
  add constraint templates_priority_valid check (priority between 0 and 4);
alter table public.daily_reviews
  add constraint daily_energy_valid check (energy_level is null or energy_level between 1 and 5),
  add constraint daily_productivity_valid check (productivity_rating is null or productivity_rating between 1 and 5),
  add constraint daily_accuracy_valid check (planning_accuracy_rating is null or planning_accuracy_rating between 1 and 5);
alter table public.weekly_reviews
  add constraint weekly_rating_valid check (overall_rating is null or overall_rating between 1 and 5);
alter table public.timer_sessions
  add constraint timer_duration_valid check (duration_sec >= 0),
  add constraint timer_time_valid check (ended_at is null or ended_at >= started_at);
