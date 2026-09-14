-- Personal Planner R11/S2 compatibility rollout.
-- This migration is appended after the released v1/hardening migrations.
-- It does not rewrite either deployed migration or weaken the RPC/RLS boundary.

begin;

create schema if not exists extensions;
create extension if not exists "uuid-ossp" with schema extensions;

-- R12/R15 source fields are added only in this pending appended migration.
-- Existing IDs, ended timestamps and measured seconds remain untouched.
alter table public.sync_state
  add column if not exists client_protocol_version integer not null default 1;
alter table public.tasks
  add column if not exists manual_actual_set integer not null default 0,
  add column if not exists inbox_content_version integer not null default 0,
  add column if not exists due_date text,
  add column if not exists plan_title_history_json text not null default '[]',
  add column if not exists display_plan_change_id text;
alter table public.timer_sessions
  add column if not exists state text not null default 'finished',
  add column if not exists running_since timestamptz,
  add column if not exists work_intervals_json text not null default '[]',
  add column if not exists owner_device_id uuid;

-- Historical rows retain their exact recorded duration. An open v1 row is
-- unclaimed running work, never an inferred finished source.
update public.timer_sessions
set state = case when ended_at is null then 'running' else 'finished' end,
    running_since = case when ended_at is null then started_at else null end,
    work_intervals_json = '[]',
    owner_device_id = null
where state not in ('running', 'paused', 'finished')
   or (ended_at is null and (state <> 'running' or running_since is null))
   or (ended_at is not null and (state <> 'finished' or running_since is not null))
   or work_intervals_json is null;

drop index if exists public.timer_sessions_one_active_idx;
create unique index if not exists idx_timer_one_running_owner
  on public.timer_sessions(user_id, owner_device_id)
  where state = 'running' and deleted_at is null and owner_device_id is not null;
create unique index if not exists idx_timer_one_unfinished_owner_task
  on public.timer_sessions(user_id, owner_device_id, task_id)
  where state in ('running', 'paused')
    and deleted_at is null
    and owner_device_id is not null;
create index if not exists idx_timer_owner_state_updated
  on public.timer_sessions(user_id, owner_device_id, state, updated_at desc)
  where deleted_at is null;

-- Capture the identities whose semantic source/content fields will change.
-- This transaction-local set drives one canonical feed reconciliation after
-- every backfill and constraint has completed.
create temporary table planner_v8_semantic_tasks (
  user_id uuid not null,
  id text not null,
  primary key (user_id, id)
) on commit drop;
insert into planner_v8_semantic_tasks(user_id, id)
select user_id, id
from public.tasks
where (is_inbox = 1 and inbox_content_version = 0)
   or actual_duration_min is not null
   or manual_duration_adjustment_min <> 0;

-- R3 adds a parentless date-only entity. The deterministic id and composite
-- date uniqueness preserve one context identity through tombstone restore.
create table if not exists public.day_contexts (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  date text not null check (
    date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    and date::date::text = date
  ),
  kind text not null check (kind in ('office', 'holiday', 'leave', 'travel', 'custom')),
  custom_label text null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz null,
  server_version bigint not null,
  primary key (user_id, id),
  unique (user_id, date),
  check (
    (kind = 'custom' and custom_label is not null and length(btrim(custom_label)) between 1 and 80)
    or (kind <> 'custom' and custom_label is null)
  )
);

create or replace function public.day_contexts_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := timezone('utc', clock_timestamp());
  return new;
end;
$$;
revoke all on function public.day_contexts_set_updated_at()
  from public, anon, authenticated;

drop trigger if exists sync_updated_at_day_contexts on public.day_contexts;
create trigger sync_updated_at_day_contexts
before insert or update on public.day_contexts
for each row execute function public.day_contexts_set_updated_at();

alter table public.day_contexts enable row level security;
revoke all on table public.day_contexts from public, anon, authenticated;
grant select on table public.day_contexts to authenticated;
drop policy if exists day_contexts_select on public.day_contexts;
drop policy if exists day_contexts_insert on public.day_contexts;
drop policy if exists day_contexts_update on public.day_contexts;
drop policy if exists day_contexts_delete on public.day_contexts;
create policy day_contexts_select on public.day_contexts
for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);
create policy day_contexts_insert on public.day_contexts
for insert to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);
create policy day_contexts_update on public.day_contexts
for update to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);
create policy day_contexts_delete on public.day_contexts
for delete to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_inbox_content_version_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_inbox_content_version_valid
      check (inbox_content_version in (0, 1));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_due_date_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_due_date_valid
      check (
        due_date is null
        or (
          due_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          and due_date::date::text = due_date
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_manual_actual_set_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_manual_actual_set_valid
      check (manual_actual_set in (0, 1));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'timer_sessions_state_valid'
      and conrelid = 'public.timer_sessions'::regclass
  ) then
    alter table public.timer_sessions add constraint timer_sessions_state_valid
      check (state in ('running', 'paused', 'finished'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'timer_sessions_state_bounds_valid'
      and conrelid = 'public.timer_sessions'::regclass
  ) then
    alter table public.timer_sessions add constraint timer_sessions_state_bounds_valid
      check (
        (state = 'running' and running_since is not null and ended_at is null)
        or (state = 'paused' and running_since is null and ended_at is null)
        or (state = 'finished' and running_since is null and ended_at is not null)
      );
  end if;
end;
$$;

-- Preserve the original cache values before the one-time server repair. This
-- table is private evidence for a later repair/review tool.
create table if not exists public.planner_v8_migration_recovery (
  user_id uuid not null references auth.users(id) on delete cascade,
  table_name text not null,
  record_id text not null,
  payload jsonb not null,
  reason text not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, table_name, record_id)
);
alter table public.planner_v8_migration_recovery enable row level security;
revoke all on table public.planner_v8_migration_recovery from public, anon, authenticated;

insert into public.planner_v8_migration_recovery(
  user_id, table_name, record_id, payload, reason
)
select
  t.user_id,
  'tasks',
  t.id,
  to_jsonb(t) - 'user_id',
  'Preserved pre-v8 task cache/source projections during v8 rollout'
from public.tasks t
where exists (
  select 1 from planner_v8_semantic_tasks semantic
  where semantic.user_id = t.user_id and semantic.id = t.id
)
or t.estimated_duration_min is distinct from case
  when t.is_inbox = 1 then null
  when t.start_time is null or t.end_time is null then null
  when t.end_time <= t.start_time then null
  else greatest(1, floor(extract(epoch from (t.end_time - t.start_time)) / 60)::integer)
end
or (
  t.actual_duration_min is not null
  and t.manual_duration_adjustment_min = 0
  and t.actual_duration_min is distinct from coalesce((
    select sum(s.duration_sec) / 60
    from public.timer_sessions s
    where s.user_id = t.user_id
      and s.task_id = t.id
      and s.state = 'finished'
      and s.ended_at is not null
      and s.deleted_at is null
  ), 0)
)
on conflict (user_id, table_name, record_id) do nothing;

-- Inbox rows are never scheduled. Incomplete legacy schedules remain
-- incomplete; this migration does not fabricate an endpoint.
update public.tasks
set
  start_time = case when is_inbox = 1 then null else start_time end,
  end_time = case when is_inbox = 1 then null else end_time end,
  estimated_duration_min = case
    when is_inbox = 1 then null
    when start_time is null or end_time is null then null
    when end_time <= start_time then null
    else greatest(1, floor(extract(epoch from (end_time - start_time)) / 60)::integer)
  end
where estimated_duration_min is distinct from case
  when is_inbox = 1 then null
  when start_time is null or end_time is null then null
  when end_time <= start_time then null
  else greatest(1, floor(extract(epoch from (end_time - start_time)) / 60)::integer)
end
or (is_inbox = 1 and (start_time is not null or end_time is not null));

insert into public.planner_v8_migration_recovery(
  user_id, table_name, record_id, payload, reason
)
select
  t.user_id,
  'tasks',
  t.id,
  to_jsonb(t) - 'user_id',
  'Migrated legacy explicit Inbox content without trimming'
from public.tasks t
where t.is_inbox = 1 and t.inbox_content_version = 0
on conflict (user_id, table_name, record_id) do nothing;

update public.tasks
set description = case
    when description is null or description = '' then title
    when description = title then description
    else title || E'\n\n' || description
  end,
  inbox_content_version = 1
where is_inbox = 1 and inbox_content_version = 0;

-- Preserve anomalous open rows for explicit recovery review. They are not
-- finalised or included in Actual Duration by this migration.
insert into public.planner_v8_migration_recovery(
  user_id, table_name, record_id, payload, reason
)
select
  s.user_id,
  'timer_sessions',
  s.id,
  to_jsonb(s) - 'user_id',
  'Legacy open timer has nonzero duration and requires explicit recovery'
from public.timer_sessions s
where s.state = 'running' and s.duration_sec <> 0
on conflict (user_id, table_name, record_id) do nothing;

-- One-time source inference preserves the old visible total when a v1 row
-- had only a cache. It runs once in the migration, after all finished source
-- rows are available, and never rewrites timer measurements.
with complete_history as (
  select user_id, task_id, coalesce(sum(duration_sec) / 60, 0)::integer as minutes
  from public.timer_sessions
  where state = 'finished' and ended_at is not null and deleted_at is null
  group by user_id, task_id
)
update public.tasks t
set manual_duration_adjustment_min = case
      when t.actual_duration_min is not null
       and t.manual_duration_adjustment_min = 0
        then t.actual_duration_min - coalesce(h.minutes, 0)
      else t.manual_duration_adjustment_min
    end,
    manual_actual_set = case
      when t.actual_duration_min is not null
        or t.manual_duration_adjustment_min <> 0 then 1
      else t.manual_actual_set
    end
from complete_history h
where h.user_id = t.user_id
  and h.task_id = t.id
  and (
    (t.actual_duration_min is not null and t.manual_duration_adjustment_min = 0)
    or t.manual_duration_adjustment_min <> 0
  );

update public.tasks t
set manual_duration_adjustment_min = t.actual_duration_min,
    manual_actual_set = 1
where t.actual_duration_min is not null
  and t.manual_duration_adjustment_min = 0
  and not exists (
    select 1 from public.timer_sessions s
    where s.user_id = t.user_id
      and s.task_id = t.id
      and s.state = 'finished'
      and s.ended_at is not null
      and s.deleted_at is null
  );

-- Keep the cache projection canonical for all future server-side task writes,
-- including the legacy RPC while accounts are being upgraded.
create or replace function public.sync_normalize_task_schedule()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.is_inbox = 1 then
    new.start_time := null;
    new.end_time := null;
    new.estimated_duration_min := null;
  elsif new.start_time is null or new.end_time is null then
    new.estimated_duration_min := null;
  elsif new.end_time > new.start_time then
    new.estimated_duration_min := greatest(
      1,
      floor(extract(epoch from (new.end_time - new.start_time)) / 60)::integer
    );
  else
    new.estimated_duration_min := null;
  end if;
  return new;
end;
$$;
revoke all on function public.sync_normalize_task_schedule()
  from public, anon, authenticated;

drop trigger if exists sync_normalize_task_schedule on public.tasks;
create trigger sync_normalize_task_schedule
before insert or update on public.tasks
for each row execute function public.sync_normalize_task_schedule();

-- Cache derivation is deliberately narrow: it never increments a Task's
-- semantic server version, writes a Task feed row, or changes updated_at.
create or replace function public.planner_recompute_task_actual(
  p_user_id uuid,
  p_task_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  source_minutes integer;
  source_count integer;
  adjustment integer;
  manual_set integer;
  displayed integer;
begin
  select t.manual_duration_adjustment_min, t.manual_actual_set
    into adjustment, manual_set
  from public.tasks t
  where t.user_id = p_user_id and t.id = p_task_id
  for update;
  if not found then return; end if;

  select coalesce(sum(s.duration_sec) / 60, 0)::integer, count(*)::integer
    into source_minutes, source_count
  from public.timer_sessions s
  where s.user_id = p_user_id
    and s.task_id = p_task_id
    and s.state = 'finished'
    and s.ended_at is not null
    and s.deleted_at is null;

  displayed := case when source_count = 0 and manual_set = 0 then null
                    else greatest(0, source_minutes + adjustment) end;
  update public.tasks
  set actual_duration_min = displayed
  where user_id = p_user_id
    and id = p_task_id
    and actual_duration_min is distinct from displayed;
end;
$$;
revoke all on function public.planner_recompute_task_actual(uuid, text)
  from public, anon, authenticated;

create or replace function public.planner_timer_cache_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' or
     (tg_op = 'UPDATE' and old.task_id is distinct from new.task_id) then
    perform public.planner_recompute_task_actual(old.user_id, old.task_id);
  end if;
  if tg_op <> 'DELETE' then
    perform public.planner_recompute_task_actual(new.user_id, new.task_id);
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.planner_timer_cache_trigger()
  from public, anon, authenticated;

create or replace function public.planner_task_actual_cache_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' or
     old.manual_duration_adjustment_min is distinct from new.manual_duration_adjustment_min or
     old.manual_actual_set is distinct from new.manual_actual_set then
    perform public.planner_recompute_task_actual(new.user_id, new.id);
  end if;
  return new;
end;
$$;
revoke all on function public.planner_task_actual_cache_trigger()
  from public, anon, authenticated;

drop trigger if exists planner_timer_actual_cache on public.timer_sessions;
create trigger planner_timer_actual_cache
after insert or update or delete on public.timer_sessions
for each row execute function public.planner_timer_cache_trigger();
drop trigger if exists planner_task_actual_cache on public.tasks;
create trigger planner_task_actual_cache
after insert or update of manual_duration_adjustment_min, manual_actual_set
  on public.tasks
for each row execute function public.planner_task_actual_cache_trigger();

-- Preserve semantic Task timestamps when only a compatibility projection is
-- refreshed. All other writes retain the existing timestamp contract.
create or replace function public.sync_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'tasks' and tg_op = 'UPDATE'
     and (to_jsonb(new) - array['actual_duration_min', 'estimated_duration_min', 'updated_at'])
         is not distinct from
         (to_jsonb(old) - array['actual_duration_min', 'estimated_duration_min', 'updated_at']) then
    new.updated_at := old.updated_at;
  else
    new.updated_at := timezone('utc', clock_timestamp());
  end if;
  return new;
end;
$$;

-- Recalculate every v1 cache after source inference, once the full server
-- history is available rather than from an incomplete child prefix.
do $$
declare task_row record;
begin
  update public.tasks
  set manual_actual_set = 1
  where manual_duration_adjustment_min <> 0 and manual_actual_set = 0;
  for task_row in select user_id, id from public.tasks loop
    perform public.planner_recompute_task_actual(task_row.user_id, task_row.id);
  end loop;
end;
$$;

-- The deployed public v1 function remains callable only for accounts that
-- have not activated protocol 2. Its hardened body is retained privately;
-- the wrapper checks an acknowledged retry before enforcing the account gate.
alter function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  rename to apply_sync_operation_v1_hardened;
revoke all on function public.apply_sync_operation_v1_hardened(
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
  acknowledged jsonb;
  canonical jsonb := p_payload;
  source_minutes integer;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state where user_id = caller for update;
  select jsonb_build_object(
    'status', 'acknowledged', 'server_version', a.server_version,
    'change_id', a.change_id, 'server_timestamp', a.server_timestamp
  ) into acknowledged
  from public.sync_operation_ack a
  where a.user_id = caller and a.operation_id = p_operation_id;
  if acknowledged is not null then return acknowledged; end if;
  if (select client_protocol_version from public.sync_state where user_id = caller) >= 2 then
    raise exception using errcode = '55000',
      message = 'Sync protocol upgrade required: legacy client mutations are blocked';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Sync payload must be a JSON object';
  end if;
  if p_table_name = 'tasks' and p_operation <> 'delete' then
    if canonical->>'actual_duration_min' is not null
       and coalesce((canonical->>'manual_duration_adjustment_min')::integer, 0) = 0 then
      select coalesce(sum(s.duration_sec) / 60, 0)::integer into source_minutes
      from public.timer_sessions s
      where s.user_id = caller and s.task_id = p_record_id
        and s.state = 'finished' and s.ended_at is not null and s.deleted_at is null;
      canonical := jsonb_set(
        canonical,
        '{manual_duration_adjustment_min}',
        to_jsonb((canonical->>'actual_duration_min')::integer - source_minutes),
        true
      );
    end if;
    canonical := jsonb_set(canonical, '{manual_actual_set}',
      to_jsonb(case when coalesce((canonical->>'manual_duration_adjustment_min')::integer, 0) <> 0
                        or canonical->>'actual_duration_min' is not null then 1 else 0 end), true);
  elsif p_table_name = 'timer_sessions' and p_operation <> 'delete' then
    canonical := jsonb_set(canonical, '{state}',
      to_jsonb(case when canonical->>'ended_at' is null then 'running' else 'finished' end), true);
    canonical := jsonb_set(canonical, '{running_since}',
      case when canonical->>'ended_at' is null
           then to_jsonb(canonical->>'started_at') else 'null'::jsonb end, true);
    canonical := jsonb_set(canonical, '{work_intervals_json}', '"[]"'::jsonb, true);
    canonical := jsonb_set(canonical, '{owner_device_id}', 'null'::jsonb, true);
  end if;
  return public.apply_sync_operation_v1_hardened(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, canonical
  );
end;
$$;
revoke all on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  from public, anon;
grant execute on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  to authenticated;

create or replace function public.planner_validate_timer_payload(p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  interval_value jsonb;
  interval_start timestamptz;
  interval_end timestamptz;
  previous_end timestamptz;
  interval_seconds integer;
  interval_total integer := 0;
  duration integer;
  state_value text;
begin
  duration := (p_payload->>'duration_sec')::integer;
  state_value := p_payload->>'state';
  if duration is null or duration < 0 or state_value not in ('running', 'paused', 'finished') then
    raise exception using errcode = '22023', message = 'Invalid timer state or duration';
  end if;
  if (state_value = 'running' and (p_payload->>'running_since' is null or p_payload->>'ended_at' is not null))
     or (state_value = 'paused' and (p_payload->>'running_since' is not null or p_payload->>'ended_at' is not null))
     or (state_value = 'finished' and (p_payload->>'running_since' is not null or p_payload->>'ended_at' is null)) then
    raise exception using errcode = '22023', message = 'Invalid timer state bounds';
  end if;
  if p_payload->>'owner_device_id' is not null and
     p_payload->>'owner_device_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode = '22023', message = 'Invalid timer owner device ID';
  end if;
  if jsonb_typeof((p_payload->>'work_intervals_json')::jsonb) <> 'array' then
    raise exception using errcode = '22023', message = 'Timer work intervals must be an array';
  end if;
  for interval_value in select value from jsonb_array_elements((p_payload->>'work_intervals_json')::jsonb) loop
    interval_start := (interval_value->>'start_at')::timestamptz;
    interval_end := (interval_value->>'end_at')::timestamptz;
    interval_seconds := (interval_value->>'duration_sec')::integer;
    if interval_start is null or interval_end is null or interval_seconds is null
       or interval_seconds < 0 or interval_end < interval_start
       or interval_seconds <> floor(extract(epoch from (interval_end - interval_start)))::integer
       or (previous_end is not null and interval_start < previous_end) then
      raise exception using errcode = '22023', message = 'Invalid timer work interval';
    end if;
    previous_end := interval_end;
    interval_total := interval_total + interval_seconds;
  end loop;
  if (p_payload->>'work_intervals_json') <> '[]' and interval_total <> duration then
    raise exception using errcode = '22023', message = 'Timer intervals must sum to duration';
  end if;
end;
$$;
revoke all on function public.planner_validate_timer_payload(jsonb)
  from public, anon, authenticated;

-- Both public protocol signatures delegate to this private entry point. The
-- v1 Foundation adapter remains private underneath it so old durable payloads
-- retain the exact hardened CAS/ack/feed behavior that originally accepted
-- them, while protocol 2 adds the current canonical validation and entities.
alter function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  rename to apply_sync_operation_v1_foundation;
revoke all on function public.apply_sync_operation_v1_foundation(
  uuid, text, text, text, bigint, jsonb
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
  start_at timestamptz;
  end_at timestamptz;
  current_description text;
  current_marker integer;
  current_due_date text;
  current_version bigint;
  current_snapshot jsonb;
  next_version bigint;
  next_change bigint;
  server_now timestamptz := timezone('utc', clock_timestamp());
  conflict_snapshot jsonb;
  enriched_payload jsonb;
  row_snapshot jsonb;
  acknowledged jsonb;
  response jsonb;
  source_minutes integer;
  current_timer_state text;
  current_timer_task text;
begin
  if (select auth.uid()) is null then
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
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
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
  if p_client_protocol = 1 and p_table_name = 'day_contexts' then
    raise exception using errcode = '22023', message = 'Unsupported sync table';
  end if;

  if p_table_name = 'day_contexts' then
    if p_record_id is null or btrim(p_record_id) = ''
       or p_payload->>'id' is distinct from p_record_id then
      raise exception using errcode = '22023', message = 'Record identity does not match payload';
    end if;
    if p_payload->>'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       or (p_payload->>'date')::date::text <> p_payload->>'date'
       or p_payload->>'id' is distinct from extensions.uuid_generate_v5(
         '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
         'personal-planner:day-context:' || (p_payload->>'date')
       )::text then
      raise exception using errcode = '22023', message = 'Invalid day context identity';
    end if;
    if p_operation not in ('insert', 'update', 'delete') then
      raise exception using errcode = '22023', message = 'Invalid sync operation';
    end if;
    if p_operation <> 'delete' then
      if p_payload->>'kind' not in ('office', 'holiday', 'leave', 'travel', 'custom')
         or p_payload->>'created_at' is null
         or p_payload->>'updated_at' is null
         or (p_payload->>'kind' = 'custom' and (
           p_payload->>'custom_label' is null
           or btrim(p_payload->>'custom_label') <> p_payload->>'custom_label'
           or length(p_payload->>'custom_label') not between 1 and 80
         ))
         or (p_payload->>'kind' <> 'custom' and p_payload->>'custom_label' is not null) then
        raise exception using errcode = '22023', message = 'Invalid day context payload';
      end if;
    end if;

    insert into public.sync_state(user_id) values (caller)
      on conflict (user_id) do nothing;
    select s.next_change_id, s.next_server_version
      into next_change, next_version
    from public.sync_state s
    where s.user_id = caller
    for update;

    select jsonb_build_object(
      'status', 'acknowledged',
      'server_version', a.server_version,
      'change_id', a.change_id,
      'server_timestamp', a.server_timestamp
    ) into row_snapshot
    from public.sync_operation_ack a
    where a.user_id = caller and a.operation_id = p_operation_id;
    if row_snapshot is not null then
      return row_snapshot;
    end if;

    select d.server_version, to_jsonb(d) - 'user_id'
      into current_version, current_snapshot
    from public.day_contexts d
    where d.user_id = caller and d.id = p_record_id
    for update;
    if (p_operation = 'insert' and current_version is not null)
       or (p_operation <> 'insert' and current_version is null)
       or p_expected_server_version is distinct from current_version then
      conflict_snapshot := coalesce(current_snapshot, jsonb_build_object('deleted', true));
      return jsonb_build_object(
        'status', 'conflict',
        'server_version', 0,
        'change_id', 0,
        'actual_server_version', current_version,
        'remote_snapshot', conflict_snapshot
      );
    end if;

    if p_operation = 'delete' then
      update public.day_contexts
      set deleted_at = coalesce(nullif(p_payload->>'deleted_at', '')::timestamptz, server_now),
          server_version = next_version,
          updated_at = server_now
      where user_id = caller and id = p_record_id;
    else
      enriched_payload := jsonb_set(p_payload, '{user_id}', to_jsonb(caller), true);
      enriched_payload := jsonb_set(enriched_payload, '{server_version}', to_jsonb(next_version), true);
      enriched_payload := jsonb_set(enriched_payload, '{updated_at}', to_jsonb(server_now), true);
      insert into public.day_contexts(
        user_id, id, date, kind, custom_label, created_at, updated_at,
        deleted_at, server_version
      ) values (
        caller,
        enriched_payload->>'id',
        enriched_payload->>'date',
        enriched_payload->>'kind',
        enriched_payload->>'custom_label',
        (enriched_payload->>'created_at')::timestamptz,
        server_now,
        (enriched_payload->>'deleted_at')::timestamptz,
        next_version
      )
      on conflict (user_id, id) do update set
        date = excluded.date,
        kind = excluded.kind,
        custom_label = excluded.custom_label,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        server_version = excluded.server_version;
    end if;

    select to_jsonb(d) - 'user_id'
      into row_snapshot
    from public.day_contexts d
    where d.user_id = caller and d.id = p_record_id;
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

  if p_table_name = 'tasks' and p_operation <> 'delete' then
    if not (canonical ? 'inbox_content_version') or
       not (canonical ? 'due_date') then
      select t.description, t.inbox_content_version, t.due_date
        into current_description, current_marker, current_due_date
      from public.tasks t
      where t.user_id = auth.uid() and t.id = p_record_id;
    end if;
    if not (canonical ? 'inbox_content_version') then
      if coalesce((canonical->>'is_inbox')::integer, 0) = 1 then
        if nullif(canonical->>'description', '') is null and current_marker = 1 then
          canonical := jsonb_set(canonical, '{description}', to_jsonb(current_description), true);
        elsif nullif(canonical->>'description', '') is null then
          canonical := jsonb_set(canonical, '{description}', to_jsonb(coalesce(canonical->>'title', '')), true);
        elsif canonical->>'description' is distinct from canonical->>'title' then
          canonical := jsonb_set(
            canonical,
            '{description}',
            to_jsonb((coalesce(canonical->>'title', '') || E'\n\n' || coalesce(canonical->>'description', ''))),
            true
          );
        end if;
        canonical := jsonb_set(canonical, '{inbox_content_version}', '1'::jsonb, true);
      else
        canonical := jsonb_set(canonical, '{inbox_content_version}', '0'::jsonb, true);
      end if;
    end if;
    if not (canonical ? 'due_date') then
      canonical := jsonb_set(
        canonical,
        '{due_date}',
        coalesce(to_jsonb(current_due_date), 'null'::jsonb),
        true
      );
    end if;
    if p_payload_version = 1
       and canonical->>'actual_duration_min' is not null
       and coalesce((canonical->>'manual_duration_adjustment_min')::integer, 0) = 0 then
      select coalesce(sum(s.duration_sec) / 60, 0)::integer into source_minutes
      from public.timer_sessions s
      where s.user_id = caller and s.task_id = p_record_id
        and s.state = 'finished' and s.ended_at is not null and s.deleted_at is null;
      canonical := jsonb_set(
        canonical,
        '{manual_duration_adjustment_min}',
        to_jsonb((canonical->>'actual_duration_min')::integer - source_minutes),
        true
      );
    end if;
    if not (canonical ? 'manual_actual_set') then
      canonical := jsonb_set(
        canonical,
        '{manual_actual_set}',
        to_jsonb(case when canonical->>'actual_duration_min' is not null
                            or coalesce((canonical->>'manual_duration_adjustment_min')::integer, 0) <> 0
                       then 1 else 0 end),
        true
      );
    end if;
  end if;

  if p_table_name = 'tasks' and p_operation <> 'delete' then
    if coalesce((canonical->>'inbox_content_version')::integer, 0) not in (0, 1) then
      raise exception using errcode = '22023', message = 'Invalid Inbox content version';
    end if;
    if canonical ? 'due_date' and canonical->>'due_date' is not null and (
      canonical->>'due_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or (canonical->>'due_date')::date::text <> canonical->>'due_date'
    ) then
      raise exception using errcode = '22023', message = 'Invalid due date';
    end if;
    if coalesce((canonical->>'manual_actual_set')::integer, -1) not in (0, 1)
       or canonical->>'manual_duration_adjustment_min' is null then
      raise exception using errcode = '22023', message = 'Invalid manual actual source';
    end if;
    if coalesce((canonical->>'is_inbox')::integer, 0) = 1 then
      canonical := jsonb_set(canonical, '{start_time}', 'null'::jsonb, true);
      canonical := jsonb_set(canonical, '{end_time}', 'null'::jsonb, true);
      canonical := jsonb_set(canonical, '{estimated_duration_min}', 'null'::jsonb, true);
    elsif canonical->>'start_time' is null or canonical->>'end_time' is null then
      canonical := jsonb_set(canonical, '{estimated_duration_min}', 'null'::jsonb, true);
    else
      start_at := (canonical->>'start_time')::timestamptz;
      end_at := (canonical->>'end_time')::timestamptz;
      if end_at > start_at then
        canonical := jsonb_set(
          canonical,
          '{estimated_duration_min}',
          to_jsonb(greatest(1, floor(extract(epoch from (end_at - start_at)) / 60)::integer)),
          true
        );
      else
        canonical := jsonb_set(canonical, '{estimated_duration_min}', 'null'::jsonb, true);
      end if;
    end if;
  end if;

  if p_table_name = 'timer_sessions' and p_operation <> 'delete' then
    if p_payload_version = 1 then
      canonical := jsonb_set(canonical, '{state}',
        to_jsonb(case when canonical->>'ended_at' is null then 'running' else 'finished' end), true);
      canonical := jsonb_set(canonical, '{running_since}',
        case when canonical->>'ended_at' is null
             then to_jsonb(canonical->>'started_at') else 'null'::jsonb end, true);
      canonical := jsonb_set(canonical, '{work_intervals_json}', '"[]"'::jsonb, true);
      canonical := jsonb_set(canonical, '{owner_device_id}', 'null'::jsonb, true);
    elsif not (canonical ? 'state') then
      canonical := jsonb_set(canonical, '{state}',
        to_jsonb(case when canonical->>'ended_at' is null then 'running' else 'finished' end), true);
    end if;
    if not (canonical ? 'running_since') then
      canonical := jsonb_set(canonical, '{running_since}',
        case when canonical->>'state' = 'running'
             then to_jsonb(canonical->>'started_at') else 'null'::jsonb end, true);
    end if;
    if not (canonical ? 'work_intervals_json') then
      canonical := jsonb_set(canonical, '{work_intervals_json}', '"[]"'::jsonb, true);
    end if;
    if not (canonical ? 'owner_device_id') then
      canonical := jsonb_set(canonical, '{owner_device_id}', 'null'::jsonb, true);
    end if;
    perform public.planner_validate_timer_payload(canonical);
    select s.state, s.task_id into current_timer_state, current_timer_task
    from public.timer_sessions s
    where s.user_id = caller and s.id = p_record_id
    for update;
    if current_timer_state = 'finished' and canonical->>'state' <> 'finished' then
      raise exception using errcode = '22023',
        message = 'Finished timer sessions cannot be reopened';
    end if;
    if current_timer_task is not null and current_timer_task <> canonical->>'task_id' then
      raise exception using errcode = '22023',
        message = 'Timer session task_id is immutable';
    end if;
  end if;

  response := public.apply_sync_operation_v1_hardened(
    p_operation_id,
    p_table_name,
    p_record_id,
    p_operation,
    p_expected_server_version,
    canonical
  );
  if p_client_protocol = 2 and response->>'status' = 'applied' then
    update public.sync_state
    set client_protocol_version = 2
    where user_id = caller;
  end if;
  return response;
end;
$$;

revoke all on function public.planner_apply_sync_operation_internal(
  uuid, text, text, text, bigint, jsonb, integer, integer
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
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.planner_apply_sync_operation_internal(
    p_operation_id,
    p_table_name,
    p_record_id,
    p_operation,
    p_expected_server_version,
    p_payload,
    1,
    1
  )
$$;
revoke all on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) to authenticated;

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
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.planner_apply_sync_operation_internal(
    p_operation_id,
    p_table_name,
    p_record_id,
    p_operation,
    p_expected_server_version,
    p_payload,
    2,
    p_payload_version
  )
$$;
revoke all on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) from public, anon;
grant execute on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) to authenticated;

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
    'payload_versions', jsonb_build_array(1, 2)
  )
$$;
revoke all on function public.planner_sync_capabilities() from public, anon;
grant execute on function public.planner_sync_capabilities() to authenticated;

-- R14 title history is part of the same coordinated Foundation rollout. Old
-- Task rows deliberately gain empty history rather than invented events.
alter table public.tasks
  add column if not exists plan_title_history_json text not null default '[]',
  add column if not exists display_plan_change_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_plan_title_history_json_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_plan_title_history_json_valid
      check (jsonb_typeof(plan_title_history_json::jsonb) = 'array');
  end if;
end;
$$;

create or replace function public.planner_validate_plan_title_history(
  p_history text,
  p_display_id text,
  p_current_title text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  event_value jsonb;
  event_id text;
  previous_title text;
  new_title text;
  changed_at timestamptz;
  reverted_at timestamptz;
  changed_at_text text;
  reverted_at_text text;
  ids text[] := '{}';
  selected boolean := false;
begin
  if p_history is null or jsonb_typeof(p_history::jsonb) <> 'array' then
    raise exception using errcode = '22023',
      message = 'Plan title history must be a JSON array';
  end if;
  for event_value in select value from jsonb_array_elements(p_history::jsonb) loop
    if jsonb_typeof(event_value) <> 'object'
       or not (event_value ?& array['id', 'previous_title', 'new_title', 'changed_at', 'reverted_at']) then
      raise exception using errcode = '22023', message = 'Invalid plan title event';
    end if;
    if exists (
      select 1
      from jsonb_object_keys(event_value) as object_key(key)
      where not (key = any(array['id', 'previous_title', 'new_title', 'changed_at', 'reverted_at']))
    )
       or jsonb_typeof(event_value->'id') <> 'string'
       or jsonb_typeof(event_value->'previous_title') <> 'string'
       or jsonb_typeof(event_value->'new_title') <> 'string'
       or jsonb_typeof(event_value->'changed_at') <> 'string'
       or (event_value->'reverted_at' <> 'null'::jsonb and jsonb_typeof(event_value->'reverted_at') <> 'string') then
      raise exception using errcode = '22023', message = 'Invalid plan title event';
    end if;
    event_id := event_value->>'id';
    previous_title := event_value->>'previous_title';
    new_title := event_value->>'new_title';
    changed_at_text := event_value->>'changed_at';
    reverted_at_text := event_value->>'reverted_at';
    changed_at := changed_at_text::timestamptz;
    reverted_at := reverted_at_text::timestamptz;
    if event_id is null
       or event_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or event_id = any(ids)
       or previous_title is null or btrim(previous_title) = '' or length(previous_title) > 500
       or new_title is null or btrim(new_title) = '' or length(new_title) > 500
       or changed_at is null or changed_at_text !~ 'Z$'
       or (reverted_at_text is not null and reverted_at_text !~ 'Z$')
       or (reverted_at is not null and reverted_at < changed_at) then
      raise exception using errcode = '22023', message = 'Invalid plan title event';
    end if;
    ids := array_append(ids, event_id);
    if p_display_id = event_id then
      if reverted_at is not null or btrim(new_title) <> btrim(coalesce(p_current_title, '')) then
        raise exception using errcode = '22023',
          message = 'Invalid plan title display selection';
      end if;
      selected := true;
    end if;
  end loop;
  if p_display_id is not null and not selected then
    raise exception using errcode = '22023',
      message = 'Invalid plan title display selection';
  end if;
end;
$$;
revoke all on function public.planner_validate_plan_title_history(text, text, text)
  from public, anon, authenticated;

-- Legacy durable operations and feed entries omit these fields. Preserve the
-- server row's history on update, or use empty defaults for a new row.
create or replace function public.planner_normalize_task_title_history(
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
  existing_event jsonb;
  next_event jsonb;
begin
  if canonical is null or jsonb_typeof(canonical) <> 'object' then
    raise exception using errcode = '22023', message = 'Task payload must be an object';
  end if;
  select plan_title_history_json, display_plan_change_id
    into current_history, current_display
  from public.tasks
  where user_id = p_user_id and id = p_record_id;
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
  perform public.planner_validate_plan_title_history(
    canonical->>'plan_title_history_json',
    canonical->>'display_plan_change_id',
    canonical->>'title'
  );
  for existing_event in
    select value
    from jsonb_array_elements(coalesce(current_history, '[]')::jsonb)
  loop
    select value into next_event
    from jsonb_array_elements((canonical->>'plan_title_history_json')::jsonb)
    where value->>'id' = existing_event->>'id';
    if next_event is null
       or (next_event - 'reverted_at') <> (existing_event - 'reverted_at') then
      raise exception using errcode = '22023',
        message = 'Existing plan title events cannot be removed or changed';
    end if;
  end loop;
  return canonical;
end;
$$;
revoke all on function public.planner_normalize_task_title_history(jsonb, uuid, text)
  from public, anon, authenticated;

-- Wrap both protocol entry points. The private bases retain the established
-- account lock, idempotent acknowledgement, CAS, feed and RLS behavior.
alter function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) rename to apply_sync_operation_v1_title_base;
revoke all on function public.apply_sync_operation_v1_title_base(
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
  if p_table_name = 'tasks' and p_operation <> 'delete' then
    canonical := public.planner_normalize_task_title_history(
      canonical, caller, p_record_id
    );
  end if;
  return public.apply_sync_operation_v1_title_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, canonical
  );
end;
$$;
revoke all on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  from public, anon;
grant execute on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  to authenticated;

alter function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) rename to apply_sync_operation_v2_title_base;
revoke all on function public.apply_sync_operation_v2_title_base(
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
  if p_table_name = 'tasks' and p_operation <> 'delete' then
    canonical := public.planner_normalize_task_title_history(
      canonical, caller, p_record_id
    );
  end if;
  return public.apply_sync_operation_v2_title_base(
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
    'payload_versions', jsonb_build_array(1, 2)
  )
$$;
revoke all on function public.planner_sync_capabilities() from public, anon;
grant execute on function public.planner_sync_capabilities() to authenticated;

-- Publish exactly one final canonical snapshot after every preserved legacy
-- operation for each Task whose Inbox/manual source semantics were migrated.
-- The fresh operation identity is migration-owned; no historical operation,
-- acknowledgement, cursor, conflict, or server version is rewritten.
do $$
declare
  task_row record;
  next_change bigint;
  next_version bigint;
  server_now timestamptz;
  migration_operation uuid;
  row_snapshot jsonb;
  operation_name text;
begin
  for task_row in
    select semantic.user_id, semantic.id
    from planner_v8_semantic_tasks semantic
    order by semantic.user_id, semantic.id
  loop
    insert into public.sync_state(user_id) values (task_row.user_id)
      on conflict (user_id) do nothing;
    select state.next_change_id, state.next_server_version
      into next_change, next_version
    from public.sync_state state
    where state.user_id = task_row.user_id
    for update;

    server_now := timezone('utc', clock_timestamp());
    migration_operation := gen_random_uuid();
    update public.tasks
    set server_version = next_version,
        updated_at = server_now
    where user_id = task_row.user_id and id = task_row.id;
    select to_jsonb(task) - 'user_id',
           case when task.deleted_at is null then 'update' else 'delete' end
      into row_snapshot, operation_name
    from public.tasks task
    where task.user_id = task_row.user_id and task.id = task_row.id;

    insert into public.sync_changes(
      user_id, change_id, operation_id, table_name, record_id, operation,
      server_version, server_timestamp, payload
    ) values (
      task_row.user_id, next_change, migration_operation, 'tasks', task_row.id,
      operation_name, next_version, server_now, row_snapshot
    );
    insert into public.sync_operation_ack(
      user_id, operation_id, table_name, record_id, operation, server_version,
      change_id, server_timestamp, payload
    ) values (
      task_row.user_id, migration_operation, 'tasks', task_row.id,
      operation_name, next_version, next_change, server_now, row_snapshot
    );
    update public.sync_state
    set next_change_id = next_change + 1,
        next_server_version = next_version + 1,
        updated_at = server_now
    where user_id = task_row.user_id;
  end loop;
end;
$$;

commit;
