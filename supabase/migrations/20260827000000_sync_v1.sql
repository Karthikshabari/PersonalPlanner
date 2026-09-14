-- Personal Planner Chunk 8: account-isolated sync protocol.
-- Run with the Supabase CLI or paste into the SQL editor only after creating
-- the project. No service-role key belongs in the Flutter app.

create table if not exists public.sync_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  next_change_id bigint not null default 1,
  next_server_version bigint not null default 1,
  updated_at timestamptz not null default timezone('utc', now()),
  check (next_change_id > 0),
  check (next_server_version > 0)
);

create table if not exists public.sync_changes (
  user_id uuid not null references auth.users(id) on delete cascade,
  change_id bigint not null,
  operation_id uuid not null,
  table_name text not null,
  record_id text not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  server_version bigint not null,
  server_timestamp timestamptz not null,
  payload jsonb not null,
  primary key (user_id, change_id),
  unique (user_id, operation_id)
);

create table if not exists public.sync_operation_ack (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  table_name text not null,
  record_id text not null,
  operation text not null check (operation in ('insert', 'update', 'delete')),
  server_version bigint not null,
  change_id bigint not null,
  server_timestamp timestamptz not null,
  payload jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, operation_id)
);

create table if not exists public.categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  color_hex text not null,
  sort_order integer not null default 0,
  is_focus integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id)
);

create table if not exists public.tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id)
);

create table if not exists public.recurring_rules (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  rrule text not null,
  task_title text not null,
  task_description text,
  duration_min integer not null,
  category_id text,
  priority integer not null default 0,
  tags_json text,
  start_time_of_day text not null,
  start_date date not null,
  end_date date,
  is_active integer not null default 1,
  exceptions_json text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table if not exists public.tasks (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  title text not null,
  description text,
  start_time timestamptz,
  end_time timestamptz,
  estimated_duration_min integer,
  actual_duration_min integer,
  manual_duration_adjustment_min integer not null default 0,
  category_id text,
  priority integer not null default 0,
  status text not null default 'planned',
  notes text,
  recurring_rule_id text,
  rescheduled_from_id text,
  rescheduled_to_id text,
  is_inbox integer not null default 0,
  missed_at text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id),
  foreign key (user_id, recurring_rule_id) references public.recurring_rules(user_id, id),
  foreign key (user_id, rescheduled_from_id) references public.tasks(user_id, id),
  foreign key (user_id, rescheduled_to_id) references public.tasks(user_id, id)
);

create table if not exists public.task_templates (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  description text,
  duration_min integer not null,
  category_id text,
  priority integer not null default 0,
  tags_json text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table if not exists public.subtasks (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  task_id text not null,
  title text not null,
  is_completed integer not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id),
  foreign key (user_id, task_id) references public.tasks(user_id, id)
);

create table if not exists public.task_tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id text not null,
  tag_id text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, task_id, tag_id),
  foreign key (user_id, task_id) references public.tasks(user_id, id),
  foreign key (user_id, tag_id) references public.tags(user_id, id)
);

create table if not exists public.daily_reviews (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  date date not null,
  reflection text,
  energy_level integer,
  productivity_rating integer,
  planning_accuracy_rating integer,
  wins_json text,
  improvements_json text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id)
);

create table if not exists public.weekly_reviews (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  week_start_date date not null,
  reflection text,
  overall_rating integer,
  goals_met_json text,
  goals_missed_json text,
  next_week_focus_json text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id)
);

create table if not exists public.timer_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  task_id text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_sec integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null,
  primary key (user_id, id),
  foreign key (user_id, task_id) references public.tasks(user_id, id)
);

create index if not exists sync_changes_user_cursor_idx
  on public.sync_changes(user_id, change_id);
create index if not exists sync_changes_operation_idx
  on public.sync_changes(user_id, operation_id);
create unique index if not exists tags_active_name_idx
  on public.tags(user_id, name) where deleted_at is null;
create unique index if not exists daily_reviews_active_date_idx
  on public.daily_reviews(user_id, date) where deleted_at is null;
create unique index if not exists weekly_reviews_active_week_idx
  on public.weekly_reviews(user_id, week_start_date) where deleted_at is null;
create unique index if not exists timer_sessions_one_active_idx
  on public.timer_sessions(user_id)
  where ended_at is null and deleted_at is null;

create or replace function public.sync_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := timezone('utc', clock_timestamp());
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'categories', 'tags', 'recurring_rules', 'tasks', 'task_templates',
    'subtasks', 'task_tags', 'daily_reviews', 'weekly_reviews', 'timer_sessions'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
      'sync_updated_at_' || table_name, table_name);
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function public.sync_set_updated_at()',
      'sync_updated_at_' || table_name, table_name);
  end loop;
end;
$$;

-- RLS is explicit even though all normal writes go through the RPC. This also
-- protects accidental direct Data API use by authenticated clients.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'sync_state', 'sync_changes', 'sync_operation_ack', 'categories', 'tags',
    'recurring_rules', 'tasks', 'task_templates', 'subtasks', 'task_tags',
    'daily_reviews', 'weekly_reviews', 'timer_sessions'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    -- Domain writes are RPC-only. SELECT is enough for the pull function;
    -- keeping direct INSERT/UPDATE/DELETE ungranted prevents clients from
    -- bypassing server_version allocation and compare-and-swap.
    if table_name in ('sync_changes', 'categories', 'tags',
                      'recurring_rules', 'tasks', 'task_templates',
                      'subtasks', 'task_tags', 'daily_reviews',
                      'weekly_reviews', 'timer_sessions') then
      execute format('grant select on table public.%I to authenticated', table_name);
    end if;
    execute format('drop policy if exists %I on public.%I', table_name || '_select', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_select', table_name);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_insert', table_name);
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select auth.uid()) is not null and (select auth.uid()) = user_id) with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_update', table_name);
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_delete', table_name);
  end loop;
end;
$$;

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
  current_version bigint;
  current_snapshot jsonb;
  next_version bigint;
  next_change bigint;
  server_now timestamptz := timezone('utc', clock_timestamp());
  conflict_snapshot jsonb;
  domain_columns text;
  domain_select text;
  update_columns text;
  update_values text;
  conflict_columns text;
  enriched_payload jsonb;
  key_predicate text;
  row_snapshot jsonb;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_operation not in ('insert', 'update', 'delete') then
    raise exception using errcode = '22023', message = 'Invalid sync operation';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'Sync payload must be a JSON object';
  end if;

  if p_table_name not in (
    'tasks', 'subtasks', 'categories', 'tags', 'task_tags',
    'recurring_rules', 'task_templates', 'daily_reviews',
    'weekly_reviews', 'timer_sessions'
  ) then
    raise exception using errcode = '22023', message = 'Unsupported sync table';
  end if;

  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  select s.next_change_id, s.next_server_version
    into next_change, next_version
  from public.sync_state s
  where s.user_id = caller
  for update;

  -- The account lock serializes this lookup with the mutation. A retry that
  -- raced the original request therefore returns its original acknowledgement
  -- instead of reaching the unique operation-id constraint.
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

  if p_table_name = 'task_tags' then
    if position(':' in p_record_id) = 0 then
      raise exception using errcode = '22023', message = 'Invalid task_tags record ID';
    end if;
    key_predicate := format(
      'task_id = %L and tag_id = %L',
      split_part(p_record_id, ':', 1), split_part(p_record_id, ':', 2));
  else
    key_predicate := format('id = %L', p_record_id);
  end if;

  execute format(
    'select x.server_version, to_jsonb(x) - ''user_id'' from public.%I x where x.user_id = %L and %s for update',
    p_table_name, caller, key_predicate)
    into current_version, current_snapshot;

  if (p_operation = 'insert' and current_version is not null)
     or (p_operation <> 'insert' and current_version is null)
     or (p_expected_server_version is distinct from current_version) then
    conflict_snapshot := coalesce(current_snapshot, jsonb_build_object('deleted', true));
    return jsonb_build_object(
      'status', 'conflict',
      'server_version', 0,
      'change_id', 0,
      'actual_server_version', current_version,
      'remote_snapshot', conflict_snapshot
    );
  end if;

  enriched_payload := jsonb_set(p_payload, '{user_id}', to_jsonb(caller), true);
  enriched_payload := jsonb_set(enriched_payload, '{server_version}', to_jsonb(next_version), true);
  enriched_payload := jsonb_set(enriched_payload, '{updated_at}', to_jsonb(server_now), true);

  if p_operation = 'delete' then
    execute format(
      'update public.%I set deleted_at = coalesce(nullif(%L, '''')::timestamptz, %L::timestamptz), server_version = %L, updated_at = %L where user_id = %L and %s',
      p_table_name,
      coalesce(p_payload->>'deleted_at', ''), server_now, next_version, server_now,
      caller, key_predicate);
  else
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('r.%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('excluded.%I', c.column_name), ', ' order by c.ordinal_position)
      into domain_columns, domain_select, update_columns, update_values
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table_name
      and c.column_name not in ('user_id', 'server_version', 'updated_at')
      and case when p_table_name = 'task_tags'
        then c.column_name not in ('task_id', 'tag_id')
        else c.column_name <> 'id'
      end;

    -- The insert list includes the primary-key columns, while the update list
    -- intentionally excludes them. Build the insert list separately.
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('r.%I', c.column_name), ', ' order by c.ordinal_position)
      into domain_columns, domain_select
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table_name
      and c.column_name not in ('user_id', 'server_version', 'updated_at');

    if p_table_name = 'task_tags' then
      conflict_columns := 'user_id, task_id, tag_id';
    else
      conflict_columns := 'user_id, id';
    end if;

    execute format(
      'insert into public.%I (user_id, %s, server_version, updated_at) '
      'select %L, %s, %L, %L from jsonb_populate_record(null::public.%I, %L::jsonb) r '
      'on conflict (%s) do update set (%s, server_version, updated_at) = (%s, excluded.server_version, excluded.updated_at)',
      p_table_name, domain_columns, caller, domain_select, next_version, server_now,
      p_table_name, enriched_payload, conflict_columns, update_columns, update_values);
  end if;

  execute format(
    'select to_jsonb(x) - ''user_id'' from public.%I x where x.user_id = %L and %s',
    p_table_name, caller, key_predicate)
    into row_snapshot;

  insert into public.sync_changes(
    user_id, change_id, operation_id, table_name, record_id, operation,
    server_version, server_timestamp, payload
  ) values (
    caller, next_change, p_operation_id, p_table_name, p_record_id, p_operation,
    next_version, server_now, row_snapshot
  );
  insert into public.sync_operation_ack(
    user_id, operation_id, table_name, record_id, operation, server_version,
    change_id, server_timestamp, payload
  ) values (
    caller, p_operation_id, p_table_name, p_record_id, p_operation, next_version,
    next_change, server_now, row_snapshot
  );
  update public.sync_state
  set next_change_id = next_change + 1,
      next_server_version = next_version + 1,
      updated_at = server_now
  where user_id = caller;

  return jsonb_build_object(
    'status', 'applied',
    'server_version', next_version,
    'change_id', next_change,
    'server_timestamp', server_now
  );
end;
$$;

create or replace function public.pull_sync_changes(
  p_after_change_id bigint default 0,
  p_limit integer default 200
)
returns table(
  change_id bigint,
  operation_id uuid,
  table_name text,
  record_id text,
  operation text,
  server_version bigint,
  server_timestamp timestamptz,
  payload jsonb
)
language sql
security invoker
set search_path = public, pg_temp
as $$
  select c.change_id, c.operation_id, c.table_name, c.record_id, c.operation,
         c.server_version, c.server_timestamp, c.payload
  from public.sync_changes c
  where c.user_id = (select auth.uid())
    and c.change_id > greatest(coalesce(p_after_change_id, 0), 0)
  order by c.change_id asc
  limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

revoke all on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  from public, anon;
grant execute on function public.apply_sync_operation(uuid, text, text, text, bigint, jsonb)
  to authenticated;
revoke all on function public.pull_sync_changes(bigint, integer) from public, anon;
grant execute on function public.pull_sync_changes(bigint, integer) to authenticated;
