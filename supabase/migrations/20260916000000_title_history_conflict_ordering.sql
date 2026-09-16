begin;

-- A stale task branch is structurally valid even when it does not contain a
-- title event introduced only on the current server branch. Build a
-- validation-only union for the existing title wrapper so all of its normal
-- payload, ownership, relationship, and CAS checks still run. This payload is
-- used only after the account lock has established that CAS must conflict; it
-- can therefore never become authoritative state.
create or replace function public.planner_title_history_conflict_payload(
  p_payload jsonb,
  p_user_id uuid,
  p_record_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  canonical jsonb := p_payload;
  current_history text;
  current_display text;
  branch_history jsonb;
  existing_event jsonb;
  branch_event jsonb;
begin
  if canonical is null or jsonb_typeof(canonical) <> 'object' then
    raise exception using errcode = '22023', message = 'Task payload must be an object';
  end if;

  select t.plan_title_history_json, t.display_plan_change_id
    into current_history, current_display
  from public.tasks t
  where t.user_id = p_user_id and t.id = p_record_id;

  if not (canonical ? 'plan_title_history_json') then
    canonical := jsonb_set(
      canonical,
      '{plan_title_history_json}',
      to_jsonb(coalesce(current_history, '[]')),
      true
    );
  end if;
  if not (canonical ? 'display_plan_change_id') then
    canonical := jsonb_set(
      canonical,
      '{display_plan_change_id}',
      coalesce(to_jsonb(current_display), 'null'::jsonb),
      true
    );
  end if;

  -- Validate the incoming branch itself before adding any server-only event.
  perform public.planner_validate_plan_title_history(
    canonical->>'plan_title_history_json',
    canonical->>'display_plan_change_id',
    canonical->>'title'
  );
  branch_history := (canonical->>'plan_title_history_json')::jsonb;

  for existing_event in
    select value
    from jsonb_array_elements(coalesce(current_history, '[]')::jsonb)
  loop
    select value into branch_event
    from jsonb_array_elements(branch_history)
    where value->>'id' = existing_event->>'id';

    if branch_event is null then
      branch_history := branch_history || jsonb_build_array(existing_event);
    elsif (branch_event - 'reverted_at') <> (existing_event - 'reverted_at') then
      raise exception using errcode = '22023',
        message = 'Plan title event ID has conflicting immutable data';
    end if;
  end loop;

  return jsonb_set(
    canonical,
    '{plan_title_history_json}',
    to_jsonb(branch_history::text),
    true
  );
end;
$$;
revoke all on function public.planner_title_history_conflict_payload(
  jsonb, uuid, text
) from public, anon, authenticated;

-- Preserve the deployed title-history wrappers as private bases. The new
-- entry points perform idempotency and CAS classification under the same
-- per-account lock, then delegate every result through those bases.
alter function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) rename to apply_sync_operation_v1_title_order_base;
revoke all on function public.apply_sync_operation_v1_title_order_base(
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
  canonical jsonb := p_payload;
  acknowledged jsonb;
  current_version bigint;
  stale_branch boolean := false;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  select jsonb_build_object(
    'status', 'acknowledged', 'server_version', a.server_version,
    'change_id', a.change_id, 'server_timestamp', a.server_timestamp
  ) into acknowledged
  from public.sync_operation_ack a
  where a.user_id = caller and a.operation_id = p_operation_id;
  if acknowledged is not null then return acknowledged; end if;

  if p_table_name = 'tasks' and p_operation in ('insert', 'update') then
    select t.server_version into current_version
    from public.tasks t
    where t.user_id = caller and t.id = p_record_id;
    stale_branch :=
      (p_operation = 'insert' and current_version is not null)
      or (p_operation = 'update' and current_version is null)
      or p_expected_server_version is distinct from current_version;
    if stale_branch then
      canonical := public.planner_title_history_conflict_payload(
        canonical, caller, p_record_id
      );
    end if;
  end if;

  return public.apply_sync_operation_v1_title_order_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, canonical
  );
end;
$$;
revoke all on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) to authenticated;

alter function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) rename to apply_sync_operation_v2_title_order_base;
revoke all on function public.apply_sync_operation_v2_title_order_base(
  uuid, text, text, text, bigint, jsonb, integer
) from public, anon, authenticated;

create or replace function public.apply_sync_operation_v2(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb,
  p_payload_version integer default 2
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  canonical jsonb := p_payload;
  acknowledged jsonb;
  current_version bigint;
  stale_branch boolean := false;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  select jsonb_build_object(
    'status', 'acknowledged', 'server_version', a.server_version,
    'change_id', a.change_id, 'server_timestamp', a.server_timestamp
  ) into acknowledged
  from public.sync_operation_ack a
  where a.user_id = caller and a.operation_id = p_operation_id;
  if acknowledged is not null then return acknowledged; end if;

  if p_payload_version not in (1, 2) then
    raise exception using errcode = '22023',
      message = 'Unsupported sync payload version';
  end if;
  if p_table_name = 'tasks' and p_operation in ('insert', 'update') then
    select t.server_version into current_version
    from public.tasks t
    where t.user_id = caller and t.id = p_record_id;
    stale_branch :=
      (p_operation = 'insert' and current_version is not null)
      or (p_operation = 'update' and current_version is null)
      or p_expected_server_version is distinct from current_version;
    if stale_branch then
      canonical := public.planner_title_history_conflict_payload(
        canonical, caller, p_record_id
      );
    end if;
  end if;

  return public.apply_sync_operation_v2_title_order_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, canonical, p_payload_version
  );
end;
$$;
revoke all on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) from public, anon;
grant execute on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) to authenticated;

commit;
