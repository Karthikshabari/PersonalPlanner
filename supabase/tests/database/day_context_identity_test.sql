begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(2);

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

-- DB-033: day-context identity is the deterministic UUIDv5 of the date.
-- Computed as the test owner, before the role switch.
select set_config(
  'planner_test.day_context_id',
  extensions.uuid_generate_v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'personal-planner:day-context:2026-10-04'
  )::text,
  true
);

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

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '90000000-0000-4000-8000-000000000001', 'day_contexts', '0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a', 'insert', null,
      jsonb_build_object(
        'id', '0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a', 'date', '2026-10-04', 'kind', 'office',
        'custom_label', null,
        'created_at', '2026-10-04T08:00:00.000Z',
        'updated_at', '2026-10-04T08:00:00.000Z',
        'deleted_at', null
      ),
      2
    )
  $$,
  '22023',
  'Invalid day context identity',
  'a day context with a random id is rejected'
);

select is(
  public.apply_sync_operation_v2(
      '90000000-0000-4000-8000-000000000002', 'day_contexts', current_setting('planner_test.day_context_id'), 'insert', null,
      jsonb_build_object(
        'id', current_setting('planner_test.day_context_id'), 'date', '2026-10-04', 'kind', 'office',
        'custom_label', null,
        'created_at', '2026-10-04T08:00:00.000Z',
        'updated_at', '2026-10-04T08:00:00.000Z',
        'deleted_at', null
      ),
      2
    )->>'status',
  'applied',
  'a day context with the deterministic date identity is applied'
);

select * from finish();
rollback;
