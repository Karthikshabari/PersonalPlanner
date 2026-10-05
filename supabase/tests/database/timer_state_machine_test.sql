begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(3);

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

-- DB-033: timer state-machine rejections, as user A through protocol 2.
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

-- Task 1 (version 1), running timer (version 2), finish (version 3).
do $$
begin
  perform public.apply_sync_operation_v2(
    '60000000-0000-4000-8000-000000000001', 'tasks', 'timer-task', 'insert', null,
    pg_temp.planner_task_payload('timer-task', 'Timed task', null, '[]', null, null, null),
    2
  );
end;
$$;
do $$
begin
  perform public.apply_sync_operation_v2(
      '60000000-0000-4000-8000-000000000002', 'timer_sessions', 'timer-1', 'insert', null,
      jsonb_build_object(
        'id', 'timer-1', 'task_id', 'timer-task',
        'started_at', '2026-09-16T09:00:00.000Z',
        'ended_at', null, 'duration_sec', 0,
        'created_at', '2026-09-16T09:00:00.000Z',
        'updated_at', '2026-09-16T09:00:00.000Z',
        'deleted_at', null, 'state', 'running', 'running_since', '2026-09-16T09:00:00.000Z',
        'work_intervals_json', '[]', 'owner_device_id', null
      ),
      2
    );
  perform public.apply_sync_operation_v2(
      '60000000-0000-4000-8000-000000000003', 'timer_sessions', 'timer-1', 'update', 2,
      jsonb_build_object(
        'id', 'timer-1', 'task_id', 'timer-task',
        'started_at', '2026-09-16T09:00:00.000Z',
        'ended_at', '2026-09-16T09:30:00.000Z', 'duration_sec', 1800,
        'created_at', '2026-09-16T09:00:00.000Z',
        'updated_at', '2026-09-16T09:00:00.000Z',
        'deleted_at', null, 'state', 'finished', 'running_since', null,
        'work_intervals_json', '[]', 'owner_device_id', null
      ),
      2
    );
end;
$$;

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '60000000-0000-4000-8000-000000000004', 'timer_sessions', 'timer-1', 'update', 3,
      jsonb_build_object(
        'id', 'timer-1', 'task_id', 'timer-task',
        'started_at', '2026-09-16T09:00:00.000Z',
        'ended_at', null, 'duration_sec', 1800,
        'created_at', '2026-09-16T09:00:00.000Z',
        'updated_at', '2026-09-16T09:00:00.000Z',
        'deleted_at', null, 'state', 'paused', 'running_since', null,
        'work_intervals_json', '[]', 'owner_device_id', null
      ),
      2
    )
  $$,
  '22023',
  'Finished timer sessions cannot be reopened',
  'a finished timer cannot be reopened as paused'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '60000000-0000-4000-8000-000000000005', 'timer_sessions', 'timer-1', 'update', 3,
      jsonb_build_object(
        'id', 'timer-1', 'task_id', 'other-task',
        'started_at', '2026-09-16T09:00:00.000Z',
        'ended_at', '2026-09-16T09:30:00.000Z', 'duration_sec', 1800,
        'created_at', '2026-09-16T09:00:00.000Z',
        'updated_at', '2026-09-16T09:00:00.000Z',
        'deleted_at', null, 'state', 'finished', 'running_since', null,
        'work_intervals_json', '[]', 'owner_device_id', null
      ),
      2
    )
  $$,
  '22023',
  'Timer session task_id is immutable',
  'a timer cannot move to another task'
);

-- Retrying the finish operation id returns its original acknowledgement.
select is(
  public.apply_sync_operation_v2(
      '60000000-0000-4000-8000-000000000003', 'timer_sessions', 'timer-1', 'update', 2,
      jsonb_build_object(
        'id', 'timer-1', 'task_id', 'timer-task',
        'started_at', '2026-09-16T09:00:00.000Z',
        'ended_at', '2026-09-16T09:30:00.000Z', 'duration_sec', 1800,
        'created_at', '2026-09-16T09:00:00.000Z',
        'updated_at', '2026-09-16T09:00:00.000Z',
        'deleted_at', null, 'state', 'finished', 'running_since', null,
        'work_intervals_json', '[]', 'owner_device_id', null
      ),
      2
    )->>'status',
  'acknowledged',
  'an idempotent retry of the finish operation is acknowledged'
);

select * from finish();
rollback;
