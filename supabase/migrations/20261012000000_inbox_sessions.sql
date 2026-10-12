begin;

-- Inbox sessions: tasks.inbox_item_id links a session (an ordinary block) to
-- its Inbox idea; tasks.inbox_history_json holds an idea's close / let go /
-- experiment / bring-back events. Additive and backward compatible:
-- * every existing row gets inbox_item_id null and inbox_history_json '[]';
-- * a tasks payload without one of the two keys (an older client) keeps the
--   stored value; an explicit value is validated and written;
-- * planner_apply_sync_operation_internal is replaced by the body of
--   20261010000000_kept_experiments.sql plus the inbox block below, so every
--   string the Worker verification looks for is still present;
-- * planner_sync_capabilities advertises inbox_sessions;
-- * every statement is idempotent: the file may be applied by hand first (SQL
--   Editor) and again later by the provisioning Worker.

do $$
begin
  if to_regprocedure(
    'public.planner_apply_sync_operation_internal_pre_experiments(uuid, text, text, text, bigint, jsonb, integer, integer)'
  ) is null or not exists (
    select 1 from pg_attribute
    where attrelid = 'public.experiments'::regclass
      and attname = 'target_changes_json'
      and not attisdropped
  ) then
    raise exception '20261010000000_kept_experiments.sql must be applied before 20261012000000_inbox_sessions.sql';
  end if;
end
$$;

alter table public.tasks add column if not exists inbox_item_id text null;
alter table public.tasks
  add column if not exists inbox_history_json text not null default '[]';

do $$
begin
  if not exists (select 1 from pg_constraint
      where conname = 'tasks_inbox_item_fk' and conrelid = 'public.tasks'::regclass) then
    -- MATCH SIMPLE: a null inbox_item_id is not checked, so every existing
    -- row passes without a NOT VALID step.
    alter table public.tasks add constraint tasks_inbox_item_fk
      foreign key (user_id, inbox_item_id) references public.tasks(user_id, id);
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'tasks_inbox_item_not_self' and conrelid = 'public.tasks'::regclass) then
    alter table public.tasks add constraint tasks_inbox_item_not_self
      check (inbox_item_id is null or inbox_item_id <> id);
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'tasks_inbox_history_array' and conrelid = 'public.tasks'::regclass) then
    alter table public.tasks add constraint tasks_inbox_history_array
      check (jsonb_typeof(inbox_history_json::jsonb) = 'array');
  end if;
end
$$;

create index if not exists tasks_user_inbox_item_idx
  on public.tasks(user_id, inbox_item_id)
  where inbox_item_id is not null;

-- The same rules as InboxHistory.validate in the app: at most 100 events with
-- only the five known keys; kind closed / let_go / experiment; ordered UTC
-- instants; reopened_at not before at and present on every event but the
-- last; reason null or 1-200 characters (required for closed, absent for
-- experiment); experiment_id present only for an experiment. A time must look
-- like an ISO-8601 instant (date, T, time with optional fractional seconds,
-- then Z or a numeric offset) before it is cast: timestamptz input also
-- accepts words such as now, today, tomorrow, yesterday, epoch and infinity,
-- and date-only text, none of which is a recorded instant. Any offset is
-- accepted; the app writes Z.
create or replace function public.planner_inbox_history_valid(p_history text)
returns boolean
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  doc jsonb;
  entry jsonb;
  total integer;
  event_index integer := 0;
  event_kind text;
  event_reason text;
  at_value timestamptz;
  reopened timestamptz;
  previous_at timestamptz;
  instant_pattern constant text :=
    '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)$';
begin
  if p_history is null then return false; end if;
  begin
    doc := p_history::jsonb;
  exception when others then
    return false;
  end;
  if jsonb_typeof(doc) <> 'array' then return false; end if;
  total := jsonb_array_length(doc);
  if total > 100 then return false; end if;
  for entry in select e.value from jsonb_array_elements(doc) as e loop
    event_index := event_index + 1;
    if jsonb_typeof(entry) <> 'object' then return false; end if;
    if exists (select 1 from jsonb_object_keys(entry) as k(key)
               where k.key not in ('kind', 'at', 'reason', 'experiment_id', 'reopened_at')) then
      return false;
    end if;
    event_kind := entry->>'kind';
    if event_kind is null or event_kind not in ('closed', 'let_go', 'experiment') then
      return false;
    end if;
    if jsonb_typeof(entry->'at') is distinct from 'string' then return false; end if;
    if coalesce(jsonb_typeof(entry->'reason'), 'null') not in ('string', 'null')
       or coalesce(jsonb_typeof(entry->'experiment_id'), 'null') not in ('string', 'null')
       or coalesce(jsonb_typeof(entry->'reopened_at'), 'null') not in ('string', 'null') then
      return false;
    end if;
    if (entry->>'at') !~ instant_pattern then return false; end if;
    if entry->>'reopened_at' is not null
       and (entry->>'reopened_at') !~ instant_pattern then
      return false;
    end if;
    begin
      at_value := (entry->>'at')::timestamptz;
      reopened := (entry->>'reopened_at')::timestamptz;
    exception when others then
      return false;
    end;
    if previous_at is not null and at_value < previous_at then return false; end if;
    if reopened is not null and reopened < at_value then return false; end if;
    if event_index < total and reopened is null then return false; end if;
    event_reason := entry->>'reason';
    if event_reason is not null
       and (char_length(btrim(event_reason)) = 0 or char_length(event_reason) > 200) then
      return false;
    end if;
    if event_kind = 'closed' and event_reason is null then return false; end if;
    if event_kind = 'experiment' then
      if event_reason is not null or coalesce(btrim(entry->>'experiment_id'), '') = '' then
        return false;
      end if;
    elsif entry->>'experiment_id' is not null then
      return false;
    end if;
    previous_at := at_value;
  end loop;
  return true;
end;
$$;

revoke all on function public.planner_inbox_history_valid(text)
  from public, anon, authenticated;

-- Apply layer: the same function (name, signature, parameter names and
-- attributes) as 20261010000000_kept_experiments.sql, so callers that call it
-- by name reach the new body. The only additions are the two stored_inbox_*
-- declarations and the Inbox block placed after the tag_id block.

create or replace function public.planner_apply_sync_operation_internal(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb,
  p_client_protocol integer,
  p_payload_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  canonical jsonb := p_payload;
  caller uuid := (select auth.uid());
  server_now timestamptz := timezone('utc', clock_timestamp());
  acknowledged jsonb;
  payload_valid boolean;
  current_version bigint;
  current_snapshot jsonb;
  next_change bigint;
  next_version bigint;
  enriched_payload jsonb;
  row_snapshot jsonb;
  stored_tag jsonb;
  stored_kept jsonb;
  stored_inbox_item jsonb;
  stored_inbox_history jsonb;
begin
  if p_table_name in ('experiments', 'experiment_check_ins') then
    if caller is null then
      raise exception using errcode = '42501', message = 'Authentication required';
    end if;
    if p_client_protocol not in (1, 2)
       or p_payload_version not in (1, 2)
       or (p_client_protocol = 1 and p_payload_version <> 1) then
      raise exception using errcode = '22023', message = 'Unsupported sync payload version';
    end if;
    if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
      raise exception using errcode = '22023', message = 'Sync payload must be a JSON object';
    end if;

    -- The same account lock covers validation, idempotency, CAS and the v2
    -- protocol gate. An old acknowledged operation remains retryable.
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

    if p_client_protocol = 1 and (
      select client_protocol_version
      from public.sync_state
      where user_id = caller
    ) >= 2 then
      raise exception using errcode = '55000',
        message = 'Sync protocol upgrade required: legacy client mutations are blocked';
    end if;
    if p_client_protocol = 1 then
      raise exception using errcode = '22023', message = 'Unsupported sync table';
    end if;

    if p_record_id is null or btrim(p_record_id) = ''
       or p_payload->>'id' is distinct from p_record_id then
      raise exception using errcode = '22023', message = 'Record identity does not match payload';
    end if;
    if p_operation is null or p_operation not in ('insert', 'update', 'delete') then
      raise exception using errcode = '22023', message = 'Invalid sync operation';
    end if;
    -- 20261010000000: a payload without one of the three kept keys keeps
    -- the stored value; an explicit null still clears. PL/pgSQL parameters
    -- are ordinary variables, so p_payload is replaced in place.
    if p_table_name = 'experiments' and p_operation <> 'delete'
       and not (p_payload ? 'retired_at' and p_payload ? 'retire_note'
                and p_payload ? 'target_changes_json') then
      select jsonb_build_object(
        'retired_at', e.retired_at,
        'retire_note', e.retire_note,
        'target_changes_json', e.target_changes_json
      ) into stored_kept
      from public.experiments e
      where e.user_id = caller and e.id = p_record_id;
      if not (p_payload ? 'retired_at') then
        p_payload := jsonb_set(p_payload, '{retired_at}',
          coalesce(stored_kept->'retired_at', 'null'::jsonb), true);
      end if;
      if not (p_payload ? 'retire_note') then
        p_payload := jsonb_set(p_payload, '{retire_note}',
          coalesce(stored_kept->'retire_note', 'null'::jsonb), true);
      end if;
      if not (p_payload ? 'target_changes_json') then
        p_payload := jsonb_set(p_payload, '{target_changes_json}',
          coalesce(stored_kept->'target_changes_json', to_jsonb('[]'::text)), true);
      end if;
    end if;

    if p_operation <> 'delete' then
      -- A tombstone payload carries only the record id (and, for check-ins,
      -- the experiment id), so the deterministic id can be derived only from
      -- a full snapshot. The CAS below requires the row to exist for a delete.
      if p_table_name = 'experiments' then
        if jsonb_typeof(p_payload->'tag_id') is distinct from 'string'
           or p_payload->>'id' is distinct from extensions.uuid_generate_v5(
             '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
             'personal-planner:experiment:' || (p_payload->>'tag_id')
           )::text then
          raise exception using errcode = '22023', message = 'Invalid experiment identity';
        end if;
        begin
          payload_valid := (
            btrim(p_payload->>'tag_id') <> ''
            and (
              select coalesce(bool_and(coalesce(
                d ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                and to_char(d::date, 'YYYY-MM-DD') = d, false)), false)
              from unnest(array[p_payload->>'start_date', p_payload->>'end_date']) as d
            )
            and p_payload->>'end_date' >= p_payload->>'start_date'
            and (
              p_payload->>'concluded_on' is null
              or (
                p_payload->>'concluded_on' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                and to_char((p_payload->>'concluded_on')::date, 'YYYY-MM-DD')
                  = p_payload->>'concluded_on'
              )
            )
            and jsonb_typeof(p_payload->'weekday_target_min') = 'number'
            and (p_payload->>'weekday_target_min')::integer between 0 and 9999
            and jsonb_typeof(p_payload->'weekend_target_min') = 'number'
            and (p_payload->>'weekend_target_min')::integer between 0 and 9999
            and jsonb_typeof(p_payload->'check_in_every_days') = 'number'
            and (p_payload->>'check_in_every_days')::integer in (1, 3, 7, 10, 15)
            and p_payload->>'status' in ('running', 'concluded')
            and coalesce(jsonb_typeof(p_payload->'outcome'), 'null') in ('string', 'null')
            and (p_payload->>'outcome' is null
              or p_payload->>'outcome' in ('continue_habit', 'drop'))
            and coalesce(jsonb_typeof(p_payload->'purpose'), 'null') in ('string', 'null')
            and (p_payload->>'purpose' is null or length(p_payload->>'purpose') <= 1000)
            and coalesce(jsonb_typeof(p_payload->'conclusion_note'), 'null') in ('string', 'null')
            and (p_payload->>'conclusion_note' is null
              or length(p_payload->>'conclusion_note') <= 4000)
            and (
              (p_payload->>'status' = 'running'
                and p_payload->>'outcome' is null
                and p_payload->>'conclusion_note' is null
                and p_payload->>'concluded_on' is null)
              or (p_payload->>'status' = 'concluded'
                and p_payload->>'outcome' is not null
                and p_payload->>'concluded_on' is not null)
            )
            and jsonb_typeof((coalesce(p_payload->>'extensions_json', '[]'))::jsonb) = 'array'
            and (
              select coalesce(bool_and(
                jsonb_typeof(x) = 'object'
                and x ?& array['reason', 'previous_end_date', 'new_end_date', 'made_on']
                and (select count(*) from jsonb_object_keys(x)) = 4
                and jsonb_typeof(x->'reason') = 'string'
                and btrim(x->>'reason') <> ''
                and length(x->>'reason') <= 500
                and (
                  select coalesce(bool_and(coalesce(
                    d ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                    and to_char(d::date, 'YYYY-MM-DD') = d, false)), false)
                  from unnest(array[
                    x->>'previous_end_date', x->>'new_end_date', x->>'made_on'
                  ]) as d
                )
                and x->>'new_end_date' > x->>'previous_end_date'
              ), true)
              from jsonb_array_elements((coalesce(p_payload->>'extensions_json', '[]'))::jsonb) as x
            )
            and coalesce(jsonb_typeof(p_payload->'retired_at'), 'null') in ('string', 'null')
            and (p_payload->>'retired_at' is null
              or (p_payload->>'retired_at')::timestamptz is not null)
            and coalesce(jsonb_typeof(p_payload->'retire_note'), 'null') in ('string', 'null')
            and (p_payload->>'retire_note' is null
              or (length(p_payload->>'retire_note') <= 4000
                and p_payload->>'retired_at' is not null))
            and (p_payload->>'retired_at' is null
              or (p_payload->>'status' = 'concluded'
                and p_payload->>'outcome' = 'continue_habit'))
            and jsonb_typeof(p_payload->'target_changes_json') = 'string'
            and jsonb_typeof((p_payload->>'target_changes_json')::jsonb) = 'array'
            and (jsonb_array_length((p_payload->>'target_changes_json')::jsonb) = 0
              or (p_payload->>'status' = 'concluded'
                and p_payload->>'outcome' = 'continue_habit'))
            and (
              select coalesce(bool_and(
                jsonb_typeof(x) = 'object'
                and x ?& array['effective_week_start', 'weekday_target_min',
                  'weekend_target_min', 'made_on']
                and (select count(*) from jsonb_object_keys(x)) = 4
                and jsonb_typeof(x->'effective_week_start') = 'string'
                and x->>'effective_week_start' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                and to_char((x->>'effective_week_start')::date, 'YYYY-MM-DD')
                  = x->>'effective_week_start'
                and extract(isodow from (x->>'effective_week_start')::date) = 1
                and jsonb_typeof(x->'made_on') = 'string'
                and x->>'made_on' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                and to_char((x->>'made_on')::date, 'YYYY-MM-DD') = x->>'made_on'
                and jsonb_typeof(x->'weekday_target_min') = 'number'
                and (x->>'weekday_target_min')::integer between 15 and 240
                and jsonb_typeof(x->'weekend_target_min') = 'number'
                and (x->>'weekend_target_min')::integer between 15 and 240
              ), true)
              from jsonb_array_elements((p_payload->>'target_changes_json')::jsonb) as x
            )
            and (
              select count(*) = count(distinct x->>'effective_week_start')
              from jsonb_array_elements((p_payload->>'target_changes_json')::jsonb) as x
            )
            and (p_payload->>'created_at')::timestamptz is not null
            and (p_payload->>'updated_at')::timestamptz is not null
            and (p_payload->>'deleted_at' is null
              or (p_payload->>'deleted_at')::timestamptz is not null)
          );
        exception when others then
          payload_valid := false;
        end;
        if payload_valid is not true then
          raise exception using errcode = '22023', message = 'Invalid experiment payload';
        end if;
      else
        if jsonb_typeof(p_payload->'experiment_id') is distinct from 'string'
           or jsonb_typeof(p_payload->'slot_date') is distinct from 'string'
           or p_payload->>'id' is distinct from extensions.uuid_generate_v5(
             '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
             'personal-planner:experiment-check-in:'
               || (p_payload->>'experiment_id') || ':' || (p_payload->>'slot_date')
           )::text then
          raise exception using errcode = '22023', message = 'Invalid experiment check-in identity';
        end if;
        begin
          payload_valid := (
            btrim(p_payload->>'experiment_id') <> ''
            and p_payload->>'slot_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            and to_char((p_payload->>'slot_date')::date, 'YYYY-MM-DD')
              = p_payload->>'slot_date'
            and jsonb_typeof(p_payload->'note') = 'string'
            and length(btrim(p_payload->>'note')) between 1 and 4000
            and length(p_payload->>'note') <= 4000
            and (p_payload->>'created_at')::timestamptz is not null
            and (p_payload->>'updated_at')::timestamptz is not null
            and (p_payload->>'deleted_at' is null
              or (p_payload->>'deleted_at')::timestamptz is not null)
          );
        exception when others then
          payload_valid := false;
        end;
        if payload_valid is not true then
          raise exception using errcode = '22023', message = 'Invalid experiment check-in payload';
        end if;
      end if;
    end if;

    select s.next_change_id, s.next_server_version
      into next_change, next_version
    from public.sync_state s
    where s.user_id = caller
    for update;

    if p_table_name = 'experiments' then
      select e.server_version, to_jsonb(e) - 'user_id'
        into current_version, current_snapshot
      from public.experiments e
      where e.user_id = caller and e.id = p_record_id
      for update;
    else
      select c.server_version, to_jsonb(c) - 'user_id'
        into current_version, current_snapshot
      from public.experiment_check_ins c
      where c.user_id = caller and c.id = p_record_id
      for update;
    end if;
    if (p_operation = 'insert' and current_version is not null)
       or (p_operation <> 'insert' and current_version is null)
       or p_expected_server_version is distinct from current_version then
      return jsonb_build_object(
        'status', 'conflict',
        'server_version', 0,
        'change_id', 0,
        'actual_server_version', current_version,
        'remote_snapshot', coalesce(current_snapshot, jsonb_build_object('deleted', true))
      );
    end if;

    if p_operation = 'delete' then
      if p_table_name = 'experiments' then
        update public.experiments
        set deleted_at = coalesce(nullif(p_payload->>'deleted_at', '')::timestamptz, server_now),
            server_version = next_version,
            updated_at = server_now
        where user_id = caller and id = p_record_id;
      else
        update public.experiment_check_ins
        set deleted_at = coalesce(nullif(p_payload->>'deleted_at', '')::timestamptz, server_now),
            server_version = next_version,
            updated_at = server_now
        where user_id = caller and id = p_record_id;
      end if;
    else
      enriched_payload := jsonb_set(p_payload, '{user_id}', to_jsonb(caller), true);
      enriched_payload := jsonb_set(enriched_payload, '{server_version}', to_jsonb(next_version), true);
      enriched_payload := jsonb_set(enriched_payload, '{updated_at}', to_jsonb(server_now), true);
      if p_table_name = 'experiments' then
        insert into public.experiments(
          user_id, id, tag_id, purpose, start_date, end_date,
          weekday_target_min, weekend_target_min, check_in_every_days, status,
          extensions_json, outcome, conclusion_note, concluded_on,
          retired_at, retire_note, target_changes_json,
          created_at, updated_at, deleted_at, server_version
        ) values (
          caller,
          enriched_payload->>'id',
          enriched_payload->>'tag_id',
          enriched_payload->>'purpose',
          enriched_payload->>'start_date',
          enriched_payload->>'end_date',
          (enriched_payload->>'weekday_target_min')::integer,
          (enriched_payload->>'weekend_target_min')::integer,
          (enriched_payload->>'check_in_every_days')::integer,
          enriched_payload->>'status',
          coalesce(enriched_payload->>'extensions_json', '[]'),
          enriched_payload->>'outcome',
          enriched_payload->>'conclusion_note',
          enriched_payload->>'concluded_on',
          (enriched_payload->>'retired_at')::timestamptz,
          enriched_payload->>'retire_note',
          coalesce(enriched_payload->>'target_changes_json', '[]'),
          (enriched_payload->>'created_at')::timestamptz,
          server_now,
          (enriched_payload->>'deleted_at')::timestamptz,
          next_version
        )
        on conflict (user_id, id) do update set
          tag_id = excluded.tag_id,
          purpose = excluded.purpose,
          start_date = excluded.start_date,
          end_date = excluded.end_date,
          weekday_target_min = excluded.weekday_target_min,
          weekend_target_min = excluded.weekend_target_min,
          check_in_every_days = excluded.check_in_every_days,
          status = excluded.status,
          extensions_json = excluded.extensions_json,
          outcome = excluded.outcome,
          conclusion_note = excluded.conclusion_note,
          concluded_on = excluded.concluded_on,
          retired_at = excluded.retired_at,
          retire_note = excluded.retire_note,
          target_changes_json = excluded.target_changes_json,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at,
          server_version = excluded.server_version;
      else
        insert into public.experiment_check_ins(
          user_id, id, experiment_id, slot_date, note,
          created_at, updated_at, deleted_at, server_version
        ) values (
          caller,
          enriched_payload->>'id',
          enriched_payload->>'experiment_id',
          enriched_payload->>'slot_date',
          enriched_payload->>'note',
          (enriched_payload->>'created_at')::timestamptz,
          server_now,
          (enriched_payload->>'deleted_at')::timestamptz,
          next_version
        )
        on conflict (user_id, id) do update set
          experiment_id = excluded.experiment_id,
          slot_date = excluded.slot_date,
          note = excluded.note,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at,
          server_version = excluded.server_version;
      end if;
    end if;

    if p_table_name = 'experiments' then
      select to_jsonb(e) - 'user_id' into row_snapshot
      from public.experiments e
      where e.user_id = caller and e.id = p_record_id;
    else
      select to_jsonb(c) - 'user_id' into row_snapshot
      from public.experiment_check_ins c
      where c.user_id = caller and c.id = p_record_id;
    end if;
    insert into public.sync_changes(
      user_id, change_id, operation_id, table_name, record_id, operation,
      server_version, server_timestamp, payload
    ) values (
      caller, next_change, p_operation_id, p_table_name, p_record_id,
      p_operation, next_version, server_now, row_snapshot
    );
    insert into public.sync_operation_ack(
      user_id, operation_id, table_name, record_id, operation, server_version,
      change_id, server_timestamp, payload
    ) values (
      caller, p_operation_id, p_table_name, p_record_id, p_operation,
      next_version, next_change, server_now, row_snapshot
    );
    update public.sync_state
    set next_change_id = next_change + 1,
        next_server_version = next_version + 1,
        client_protocol_version = 2,
        updated_at = server_now
    where user_id = caller;
    return jsonb_build_object(
      'status', 'applied',
      'server_version', next_version,
      'change_id', next_change,
      'server_timestamp', server_now
    );
  end if;

  -- An absent tag_id keeps the stored value (an older client's snapshot never
  -- erases a tag); an explicit null in the payload clears it and passes
  -- through untouched. The account lock is taken first so the stored value
  -- cannot change between this read and the apply.
  if p_table_name = 'tasks'
     and p_operation is distinct from 'delete'
     and caller is not null
     and p_payload is not null
     and jsonb_typeof(p_payload) = 'object'
     and not (p_payload ? 'tag_id') then
    insert into public.sync_state(user_id) values (caller)
      on conflict (user_id) do nothing;
    perform 1 from public.sync_state s where s.user_id = caller for update;
    select to_jsonb(t.tag_id) into stored_tag
    from public.tasks t
    where t.user_id = caller and t.id = p_record_id;
    canonical := jsonb_set(p_payload, '{tag_id}', coalesce(stored_tag, 'null'::jsonb), true);
  end if;

  -- Inbox: an absent inbox_item_id or inbox_history_json keeps the stored
  -- value (an older client never erases a session link or an idea's
  -- history); an explicit value is validated and passes through.
  if p_table_name = 'tasks'
     and p_operation is distinct from 'delete'
     and caller is not null
     and canonical is not null
     and jsonb_typeof(canonical) = 'object' then
    if not (canonical ? 'inbox_item_id') or not (canonical ? 'inbox_history_json') then
      insert into public.sync_state(user_id) values (caller)
        on conflict (user_id) do nothing;
      perform 1 from public.sync_state s where s.user_id = caller for update;
      select to_jsonb(t.inbox_item_id), to_jsonb(t.inbox_history_json)
        into stored_inbox_item, stored_inbox_history
      from public.tasks t
      where t.user_id = caller and t.id = p_record_id;
      if not (canonical ? 'inbox_item_id') then
        canonical := jsonb_set(canonical, '{inbox_item_id}',
          coalesce(stored_inbox_item, 'null'::jsonb), true);
      end if;
      if not (canonical ? 'inbox_history_json') then
        canonical := jsonb_set(canonical, '{inbox_history_json}',
          coalesce(stored_inbox_history, '"[]"'::jsonb), true);
      end if;
    end if;
    if coalesce(jsonb_typeof(canonical->'inbox_item_id'), 'null') not in ('null', 'string')
       or (jsonb_typeof(canonical->'inbox_item_id') = 'string'
           and (btrim(canonical->>'inbox_item_id') = ''
                or canonical->>'inbox_item_id' = p_record_id))
       or jsonb_typeof(canonical->'inbox_history_json') is distinct from 'string'
       or not public.planner_inbox_history_valid(canonical->>'inbox_history_json') then
      raise exception using errcode = '22023', message = 'Invalid inbox payload';
    end if;
  end if;

  return public.planner_apply_sync_operation_internal_pre_experiments(
    p_operation_id,
    p_table_name,
    p_record_id,
    p_operation,
    p_expected_server_version,
    canonical,
    p_client_protocol,
    p_payload_version
  );
end;
$$;

revoke all on function public.planner_apply_sync_operation_internal(
  uuid, text, text, text, bigint, jsonb, integer, integer
) from public, anon, authenticated;

-- Capability: the body of 20260917000000_initial_sync_baseline.sql plus
-- inbox_sessions, so a client can tell whether this file has been applied.
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
    'initial_sync_baseline', true,
    'initial_sync_fencing', true,
    'inbox_sessions', true,
    'payload_versions', jsonb_build_array(1, 2)
  )
$$;

revoke all on function public.planner_sync_capabilities() from public, anon;
grant execute on function public.planner_sync_capabilities() to authenticated;

commit;
