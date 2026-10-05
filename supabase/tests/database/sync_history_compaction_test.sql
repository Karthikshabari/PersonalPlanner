begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(9);

-- These users and payload builders exist only inside this rolled-back test
-- transaction. The claims match the local Supabase auth.uid() contract.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'planner-a@example.invalid',
    '',
    '2026-09-16T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-09-16T08:00:00Z',
    '2026-09-16T08:00:00Z',
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'planner-b@example.invalid',
    '',
    '2026-09-16T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-09-16T08:00:00Z',
    '2026-09-16T08:00:00Z',
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '30000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'planner-c@example.invalid',
    '',
    '2026-09-16T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-09-16T08:00:00Z',
    '2026-09-16T08:00:00Z',
    '',
    '',
    '',
    ''
  );

create function pg_temp.planner_task_payload(
  p_id text,
  p_title text,
  p_notes text,
  p_history jsonb,
  p_display_id text,
  p_category_id text,
  p_forged_user_id uuid
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_id,
    'title', p_title,
    'description', null,
    'start_time', '2026-09-16T09:00:00.000Z',
    'end_time', '2026-09-16T10:00:00.000Z',
    'estimated_duration_min', 60,
    'actual_duration_min', null,
    'manual_duration_adjustment_min', 0,
    'manual_actual_set', 0,
    'category_id', p_category_id,
    'priority', 0,
    'status', 'planned',
    'notes', p_notes,
    'recurring_rule_id', null,
    'recurrence_removal_reason', null,
    'rescheduled_from_id', null,
    'rescheduled_to_id', null,
    'is_inbox', 0,
    'inbox_content_version', 0,
    'due_date', null,
    'missed_at', null,
    'plan_title_history_json', p_history::text,
    'display_plan_change_id', p_display_id,
    'created_at', '2026-09-16T09:00:00.000Z',
    'updated_at', '2026-09-16T09:00:00.000Z',
    'deleted_at', null
  ) || case
    when p_forged_user_id is null then '{}'::jsonb
    else jsonb_build_object('user_id', p_forged_user_id)
  end
$$;

grant execute on function pg_temp.planner_task_payload(
  text, text, text, jsonb, text, text, uuid
) to authenticated;

create function pg_temp.planner_category_payload(p_id text, p_name text)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_id,
    'name', p_name,
    'color_hex', '#4285F4',
    'sort_order', 0,
    'is_focus', 0,
    'created_at', '2026-09-16T09:00:00.000Z',
    'updated_at', '2026-09-16T09:00:00.000Z',
    'deleted_at', null
  )
$$;

grant execute on function pg_temp.planner_category_payload(text, text)
  to authenticated;

-- DB-028/DB-033: history compaction, as users A and B.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

-- Insert (change 1, version 1) and three updates (versions 2-4) of one task.
do $$
begin
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000001', 'tasks', 'compact-task', 'insert', null,
    pg_temp.planner_task_payload('compact-task', 'Title 0', null, '[]', null, null, null),
    2
  );
end;
$$;
do $$
begin
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000002', 'tasks', 'compact-task', 'update', 1,
    pg_temp.planner_task_payload('compact-task', 'Title 1', null, '[]', null, null, null),
    2
  );
end;
$$;
do $$
begin
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000003', 'tasks', 'compact-task', 'update', 2,
    pg_temp.planner_task_payload('compact-task', 'Title 2', null, '[]', null, null, null),
    2
  );
end;
$$;
do $$
begin
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000004', 'tasks', 'compact-task', 'update', 3,
    pg_temp.planner_task_payload('compact-task', 'Title 3', null, '[]', null, null, null),
    2
  );
end;
$$;

-- Backdate the first three changes by 100 days, as the test owner. The first
-- (the insert) is older than 90 days and superseded, but it is the record's
-- origin and must survive; only the two middle changes are eligible.
reset role;
update public.sync_changes
set server_timestamp = server_timestamp - interval '100 days'
where user_id = '10000000-0000-4000-8000-000000000001'
  and record_id = 'compact-task'
  and server_version in (1, 2, 3);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select is(
  public.planner_compact_sync_history()->>'changes_deleted',
  '2',
  'two superseded middle changes older than 90 days are compacted'
);

reset role;
select is(
  (select count(*) from public.sync_changes
   where record_id = 'compact-task' and server_version = 4),
  1::bigint,
  'the latest change of the record remains'
);

select is(
  (select count(*) from public.sync_changes
   where record_id = 'compact-task' and server_version = 1),
  1::bigint,
  'the first change of the record survives although it is older than 90 days'
);

select is(
  (select array_agg(server_version order by change_id)
   from public.sync_changes
   where user_id = '10000000-0000-4000-8000-000000000001'
     and record_id = 'compact-task'),
  array[1, 4]::bigint[],
  'compaction keeps exactly the first and the latest change of the record'
);

-- C-1 shape, as user C: a category is created, a task is added to it, and
-- the category is renamed three times. Only the last rename is recent. Before
-- the first-change rule, compaction left the category's only surviving
-- change after the child task, so a fresh device pulled the child first.
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '30000000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

do $$
begin
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000011', 'categories', 'compact-category',
    'insert', null,
    pg_temp.planner_category_payload('compact-category', 'Name 0'),
    2
  );
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000012', 'tasks', 'compact-child',
    'insert', null,
    pg_temp.planner_task_payload(
      'compact-child', 'Child', null, '[]', null, 'compact-category', null
    ),
    2
  );
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000013', 'categories', 'compact-category',
    'update', 1,
    pg_temp.planner_category_payload('compact-category', 'Name 1'),
    2
  );
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000014', 'categories', 'compact-category',
    'update', 3,
    pg_temp.planner_category_payload('compact-category', 'Name 2'),
    2
  );
  perform public.apply_sync_operation_v2(
    'b0000000-0000-4000-8000-000000000015', 'categories', 'compact-category',
    'update', 4,
    pg_temp.planner_category_payload('compact-category', 'Name 3'),
    2
  );
end;
$$;

reset role;
update public.sync_changes
set server_timestamp = server_timestamp - interval '100 days'
where user_id = '30000000-0000-4000-8000-000000000003'
  and server_version in (1, 2, 3, 4);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '30000000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;

select is(
  public.planner_compact_sync_history()->>'changes_deleted',
  '2',
  'only the two middle renames of the category are compacted'
);

reset role;
select is(
  (select array_agg(server_version order by change_id)
   from public.sync_changes
   where user_id = '30000000-0000-4000-8000-000000000003'
     and record_id = 'compact-category'),
  array[1, 5]::bigint[],
  'the category keeps its first change (older than 90 days) and its latest'
);

select ok(
  (select change_id from public.sync_changes
   where user_id = '30000000-0000-4000-8000-000000000003'
     and record_id = 'compact-category' and server_version = 1)
  < (select min(change_id) from public.sync_changes
     where user_id = '30000000-0000-4000-8000-000000000003'
       and record_id = 'compact-child'),
  'the parent''s surviving first change still precedes its child in the feed'
);

-- A first baseline in progress for B blocks compaction for B.
insert into public.sync_initial_baseline (user_id, claim_token, observed_next_change_id)
values ('20000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-0000000000c1', 1);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select is(
  public.planner_compact_sync_history()->>'status',
  'skipped',
  'compaction is skipped while a baseline is in progress'
);

-- An acknowledgement older than 180 days is removed.
reset role;
update public.sync_operation_ack
set created_at = created_at - interval '200 days'
where user_id = '10000000-0000-4000-8000-000000000001' and operation_id = 'b0000000-0000-4000-8000-000000000001';
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

do $$
begin
  perform public.planner_compact_sync_history();
end;
$$;

reset role;
select is(
  (select count(*) from public.sync_operation_ack
   where user_id = '10000000-0000-4000-8000-000000000001' and operation_id = 'b0000000-0000-4000-8000-000000000001'),
  0::bigint,
  'an acknowledgement older than 180 days is deleted'
);

select * from finish();
rollback;
