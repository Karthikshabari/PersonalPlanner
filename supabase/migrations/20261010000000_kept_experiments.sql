begin;

-- Kept experiments: the retire fields and the weekly target history on
-- public.experiments, and the apply wrapper replaced so it writes them.
-- Additive and backward compatible:
-- * every existing row gets retired_at and retire_note null and
--   target_changes_json '[]';
-- * an experiments payload without one of the three keys (an older client or
--   an operation queued before the upgrade) keeps the stored value, while an
--   explicit null clears retired_at and retire_note;
-- * planner_sync_capabilities, planner_account_has_history,
--   planner_sync_account_state, pull_sync_changes and every earlier file are
--   unchanged; the function below is the body of
--   20261009000000_experiments.sql with the three columns added;
-- * every statement is idempotent: the file may be applied by hand first (SQL
--   Editor) and again later by the provisioning Worker.

do $$
begin
  if to_regprocedure(
    'public.planner_apply_sync_operation_internal_pre_experiments(uuid, text, text, text, bigint, jsonb, integer, integer)'
  ) is null then
    raise exception '20261009000000_experiments.sql must be applied before 20261010000000_kept_experiments.sql';
  end if;
end
$$;

alter table public.experiments add column if not exists retired_at timestamptz null;
alter table public.experiments add column if not exists retire_note text null;
alter table public.experiments
  add column if not exists target_changes_json text not null default '[]';

do $$
begin
  if not exists (select 1 from pg_constraint
      where conname = 'experiments_retire_note_length'
        and conrelid = 'public.experiments'::regclass) then
    alter table public.experiments add constraint experiments_retire_note_length
      check (retire_note is null or length(retire_note) <= 4000);
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'experiments_retire_note_needs_retired'
        and conrelid = 'public.experiments'::regclass) then
    alter table public.experiments add constraint experiments_retire_note_needs_retired
      check (retire_note is null or retired_at is not null);
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'experiments_retired_only_kept'
        and conrelid = 'public.experiments'::regclass) then
    alter table public.experiments add constraint experiments_retired_only_kept
      check (retired_at is null
        or (status = 'concluded' and outcome = 'continue_habit'));
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'experiments_target_changes_array'
        and conrelid = 'public.experiments'::regclass) then
    alter table public.experiments add constraint experiments_target_changes_array
      check (jsonb_typeof(target_changes_json::jsonb) = 'array');
  end if;
  if not exists (select 1 from pg_constraint
      where conname = 'experiments_target_changes_only_kept'
        and conrelid = 'public.experiments'::regclass) then
    alter table public.experiments add constraint experiments_target_changes_only_kept
      check (jsonb_array_length(target_changes_json::jsonb) = 0
        or (status = 'concluded' and outcome = 'continue_habit'));
  end if;
end
$$;

-- Apply layer: the same function (name, signature, parameter names and
-- attributes), so callers that call it by name reach the new body.

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

commit;
