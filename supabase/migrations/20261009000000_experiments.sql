begin;

-- Experiments: an optional tag on blocks (tasks.tag_id), the experiments table
-- and the experiment check-ins table, plus a sync-apply layer for them.
-- Additive and backward compatible:
-- * tasks.tag_id is nullable; a tasks payload that lacks the key keeps the
--   stored value (an older client's edit never erases a tag) while an explicit
--   null clears it. A preserve-on-NULL trigger cannot express that, so the
--   rule lives in the apply wrapper below;
-- * nothing existing is changed: planner_sync_capabilities,
--   planner_account_has_history, planner_sync_account_state, pull_sync_changes
--   and every earlier migration file stay as they are;
-- * every statement is idempotent: the file may be applied by hand first (SQL
--   Editor) and again later by the provisioning Worker.

-- ---------------------------------------------------------------------------
-- tasks.tag_id
-- ---------------------------------------------------------------------------

alter table public.tasks add column if not exists tag_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_tag_fk'
      and conrelid = 'public.tasks'::regclass
  ) then
    -- Every tag_id is null at this point and a composite key with a null
    -- column is not checked (MATCH SIMPLE), so no NOT VALID step is needed.
    alter table public.tasks
      add constraint tasks_tag_fk
      foreign key (user_id, tag_id) references public.tags(user_id, id);
  end if;
end
$$;

create index if not exists tasks_user_tag_idx
  on public.tasks(user_id, tag_id)
  where tag_id is not null;

-- ---------------------------------------------------------------------------
-- experiments
-- ---------------------------------------------------------------------------

-- Date checks use the regex plus a to_char round trip, which does not depend
-- on the session DateStyle (unlike date::text). An impossible date such as
-- 2026-02-30 raises in the cast, which still rejects the row.
create table if not exists public.experiments (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  tag_id text not null,
  purpose text null,
  start_date text not null,
  end_date text not null,
  weekday_target_min integer not null,
  weekend_target_min integer not null,
  check_in_every_days integer not null,
  status text not null,
  extensions_json text not null default '[]',
  outcome text null,
  conclusion_note text null,
  concluded_on text null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz null,
  server_version bigint not null,
  primary key (user_id, id),
  unique (user_id, tag_id),
  foreign key (user_id, tag_id) references public.tags(user_id, id),
  check (
    start_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    and to_char(start_date::date, 'YYYY-MM-DD') = start_date
  ),
  check (
    end_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    and to_char(end_date::date, 'YYYY-MM-DD') = end_date
  ),
  check (
    concluded_on is null
    or (
      concluded_on ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      and to_char(concluded_on::date, 'YYYY-MM-DD') = concluded_on
    )
  ),
  check (end_date >= start_date),
  check (weekday_target_min between 0 and 9999),
  check (weekend_target_min between 0 and 9999),
  check (check_in_every_days in (1, 3, 7, 10, 15)),
  check (status in ('running', 'concluded')),
  check (outcome is null or outcome in ('continue_habit', 'drop')),
  check (jsonb_typeof(extensions_json::jsonb) = 'array'),
  check (purpose is null or length(purpose) <= 1000),
  check (conclusion_note is null or length(conclusion_note) <= 4000),
  check (
    (status = 'running'
      and outcome is null and conclusion_note is null and concluded_on is null)
    or (status = 'concluded'
      and outcome is not null and concluded_on is not null)
  )
);

-- ---------------------------------------------------------------------------
-- experiment_check_ins
-- ---------------------------------------------------------------------------

create table if not exists public.experiment_check_ins (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  experiment_id text not null,
  slot_date text not null,
  note text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz null,
  server_version bigint not null,
  primary key (user_id, id),
  unique (user_id, experiment_id, slot_date),
  foreign key (user_id, experiment_id) references public.experiments(user_id, id),
  check (
    slot_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    and to_char(slot_date::date, 'YYYY-MM-DD') = slot_date
  ),
  check (length(btrim(note)) between 1 and 4000)
);

create index if not exists experiment_check_ins_user_experiment_idx
  on public.experiment_check_ins(user_id, experiment_id);

-- ---------------------------------------------------------------------------
-- Triggers, row-level security and privileges (both tables)
-- ---------------------------------------------------------------------------

drop trigger if exists sync_updated_at_experiments on public.experiments;
create trigger sync_updated_at_experiments
before insert or update on public.experiments
for each row execute function public.sync_set_updated_at();

drop trigger if exists sync_updated_at_experiment_check_ins on public.experiment_check_ins;
create trigger sync_updated_at_experiment_check_ins
before insert or update on public.experiment_check_ins
for each row execute function public.sync_set_updated_at();

alter table public.experiments enable row level security;
alter table public.experiment_check_ins enable row level security;

revoke all on table public.experiments from public, anon, authenticated;
revoke all on table public.experiment_check_ins from public, anon, authenticated;
grant select on table public.experiments to authenticated;
grant select on table public.experiment_check_ins to authenticated;

drop policy if exists experiments_select on public.experiments;
drop policy if exists experiments_insert on public.experiments;
drop policy if exists experiments_update on public.experiments;
drop policy if exists experiments_delete on public.experiments;
create policy experiments_select on public.experiments
for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists experiment_check_ins_select on public.experiment_check_ins;
drop policy if exists experiment_check_ins_insert on public.experiment_check_ins;
drop policy if exists experiment_check_ins_update on public.experiment_check_ins;
drop policy if exists experiment_check_ins_delete on public.experiment_check_ins;
create policy experiment_check_ins_select on public.experiment_check_ins
for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Apply layer: wrap planner_apply_sync_operation_internal
-- ---------------------------------------------------------------------------

-- The existing function becomes planner_apply_sync_operation_internal_pre_experiments
-- (only once) and a new function with the original name and signature handles
-- the two new tables completely, adds the stored tag_id to a tasks payload
-- that lacks the key, and passes everything else on unchanged. Callers
-- (apply_sync_operation_v1_hardened and the v2 chain) call the function by
-- name, so they reach the wrapper.
--
-- The lookup uses the exact schema-qualified signature, never the name alone.
-- Case (c) is checked before case (a): a run where the wrapper already exists
-- but the renamed function does not must stop instead of renaming the wrapper
-- onto itself.
do $$
declare
  main_fn regprocedure := to_regprocedure(
    'public.planner_apply_sync_operation_internal(uuid, text, text, text, bigint, jsonb, integer, integer)'
  );
  pre_fn regprocedure := to_regprocedure(
    'public.planner_apply_sync_operation_internal_pre_experiments(uuid, text, text, text, bigint, jsonb, integer, integer)'
  );
begin
  if main_fn is null then
    raise exception 'planner_apply_sync_operation_internal(uuid, text, text, text, bigint, jsonb, integer, integer) does not exist';
  end if;
  if pre_fn is null
     and position(
       'planner_apply_sync_operation_internal_pre_experiments'
       in pg_get_functiondef(main_fn::oid)
     ) > 0 then
    -- (c) the wrapper is in place but the function it wraps is missing.
    raise exception 'planner_apply_sync_operation_internal already wraps planner_apply_sync_operation_internal_pre_experiments, which does not exist; refusing to rename the wrapper onto itself';
  end if;
  if pre_fn is null then
    -- (a) first run: move the existing body out of the way.
    alter function public.planner_apply_sync_operation_internal(
      uuid, text, text, text, bigint, jsonb, integer, integer
    ) rename to planner_apply_sync_operation_internal_pre_experiments;
  end if;
  -- (b) the renamed function exists: nothing to rename (runs 2 and 3).
end
$$;

revoke all on function public.planner_apply_sync_operation_internal_pre_experiments(
  uuid, text, text, text, bigint, jsonb, integer, integer
) from public, anon, authenticated;

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
