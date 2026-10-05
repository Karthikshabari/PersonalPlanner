begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(5);

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

-- DB-033: initial-baseline claim and fencing transitions, as user A.
-- Reports what v3 and v2 do once the baseline is completed, as one string so the
-- two post-completion behaviours are a single assertion.
create function pg_temp.planner_after_completion()
returns text
language plpgsql
as $$
declare
  v3_message text;
begin
  begin
    perform public.apply_sync_operation_v3(
      '80000000-0000-4000-8000-000000000005', 'tasks', 'after-v3', 'insert', null,
      pg_temp.planner_task_payload('after-v3', 'After v3', null, '[]', null, null, null),
      2, '70000000-0000-4000-8000-0000000000a1'
    );
    v3_message := 'v3 accepted';
  exception when others then
    v3_message := sqlerrm;
  end;
  return v3_message || ' | ' || (
    public.apply_sync_operation_v2(
      '80000000-0000-4000-8000-000000000006', 'tasks', 'after-v2', 'insert', null,
      pg_temp.planner_task_payload('after-v2', 'After v2', null, '[]', null, null, null),
      2
    )->>'status'
  );
end;
$$;

grant execute on function pg_temp.planner_after_completion() to authenticated;

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
  public.planner_claim_initial_baseline('70000000-0000-4000-8000-0000000000a1', 1)->>'status',
  'claimed',
  'A claims the initial baseline of an unused account'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '80000000-0000-4000-8000-000000000002', 'tasks', 'fenced-v2', 'insert', null,
      pg_temp.planner_task_payload('fenced-v2', 'Fenced v2', null, '[]', null, null, null),
      2
    )
  $$,
  'P0001',
  'No active initial baseline claim: this account is being established by a fenced first synchronization',
  'an untokened v2 mutation is refused while the baseline is in progress'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v3(
      '80000000-0000-4000-8000-000000000003', 'tasks', 'wrong-token', 'insert', null,
      pg_temp.planner_task_payload('wrong-token', 'Wrong token', null, '[]', null, null, null),
      2, '70000000-0000-4000-8000-0000000000b2'
    )
  $$,
  'P0001',
  'Initial baseline claim is no longer owned by this device',
  'v3 with a wrong claim token is refused'
);

select is(
  public.apply_sync_operation_v3(
      '80000000-0000-4000-8000-000000000004', 'tasks', 'right-token', 'insert', null,
      pg_temp.planner_task_payload('right-token', 'Right token', null, '[]', null, null, null),
      2, '70000000-0000-4000-8000-0000000000a1'
    )->>'status',
  'applied',
  'v3 with the claim token applies'
);

do $$
begin
  perform public.planner_complete_initial_baseline('70000000-0000-4000-8000-0000000000a1');
end;
$$;

select is(
  pg_temp.planner_after_completion(),
  'Initial baseline claim is no longer active: the baseline is already completed; use ordinary synchronization | applied',
  'after completion v3 is refused and ordinary v2 applies'
);

select * from finish();
rollback;
