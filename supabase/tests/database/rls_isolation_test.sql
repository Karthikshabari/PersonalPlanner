begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(4);

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

-- DB-033: cross-user RLS isolation of rows, the change feed and acknowledgements.
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

-- As A: insert one task.
do $$
begin
  perform public.apply_sync_operation_v2(
    '50000000-0000-4000-8000-000000000001', 'tasks', 'rls-task', 'insert', null,
    pg_temp.planner_task_payload('rls-task', 'A private task', null, '[]', null, null, null),
    2
  );
end;
$$;

-- As B: A's data is invisible.
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

select is(
  (select count(*) from public.tasks),
  0::bigint,
  'B cannot read A tasks through RLS'
);

select is(
  (select count(*) from public.pull_sync_changes(0, 500)),
  0::bigint,
  'B does not see A change-feed rows'
);

-- As A: the owner still sees the row.
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

select is(
  (select count(*) from public.tasks where id = 'rls-task'),
  1::bigint,
  'A can read its own task'
);

-- As B: reusing A's operation id must not leak A's acknowledgement. The
-- acknowledgement lookup is caller-scoped, so B gets its own new change.
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

select isnt(
  public.apply_sync_operation_v2(
    '50000000-0000-4000-8000-000000000001', 'tasks', 'rls-task', 'insert', null,
    pg_temp.planner_task_payload('rls-task', 'B own task', null, '[]', null, null, null),
    2
  )->>'status',
  'acknowledged',
  'A operation id is not acknowledged to B'
);

select * from finish();
rollback;
