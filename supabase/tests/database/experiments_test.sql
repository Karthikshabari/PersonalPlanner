begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(32);

-- Test-only users, rolled back with the transaction.
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
    '2026-10-09T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-09T08:00:00Z',
    '2026-10-09T08:00:00Z',
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
    '2026-10-09T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-09T08:00:00Z',
    '2026-10-09T08:00:00Z',
    '',
    '',
    '',
    ''
  );

-- Fixed example shared with the Dart test
-- (test/unit/sync/experiment_sync_test.dart): the server and the app must make
-- experiment and check-in ids the same way.
--   tag        11111111-1111-4111-8111-111111111111
--   experiment 6a921905-9a5c-51c0-b898-e0c6985d8a72   (key experiment:<tag>)
--   check-in   52ddb265-2dac-5d4c-9d51-657bc6f99153   (key experiment-check-in:<experiment>:2026-10-05)

create function pg_temp.experiment_payload(
  p_id text,
  p_tag_id text,
  p_start text,
  p_frequency integer
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_id,
    'tag_id', p_tag_id,
    'purpose', 'Learn C properly',
    'start_date', p_start,
    'end_date', '2026-11-05',
    'weekday_target_min', 60,
    'weekend_target_min', 90,
    'check_in_every_days', p_frequency,
    'status', 'running',
    'extensions_json', '[]',
    'outcome', null,
    'conclusion_note', null,
    'concluded_on', null,
    'created_at', '2026-10-05T08:00:00.000Z',
    'updated_at', '2026-10-05T08:00:00.000Z',
    'deleted_at', null
  )
$$;

create function pg_temp.task_payload(p_id text, p_title text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_id,
    'title', p_title,
    'description', null,
    'start_time', '2026-10-05T09:00:00.000Z',
    'end_time', '2026-10-05T10:00:00.000Z',
    'estimated_duration_min', 60,
    'actual_duration_min', null,
    'manual_duration_adjustment_min', 0,
    'manual_actual_set', 0,
    'category_id', null,
    'priority', 0,
    'status', 'planned',
    'notes', null,
    'recurring_rule_id', null,
    'recurrence_removal_reason', null,
    'rescheduled_from_id', null,
    'rescheduled_to_id', null,
    'is_inbox', 0,
    'inbox_content_version', 0,
    'due_date', null,
    'missed_at', null,
    'plan_title_history_json', '[]',
    'display_plan_change_id', null,
    'created_at', '2026-10-05T09:00:00.000Z',
    'updated_at', '2026-10-05T09:00:00.000Z',
    'deleted_at', null
  )
$$;

grant execute on function pg_temp.experiment_payload(text, text, text, integer) to authenticated;
grant execute on function pg_temp.task_payload(text, text) to authenticated;

-- Ids are computed here, before the role switch, with the same function and
-- namespace the apply layer uses.
select set_config('planner_test.tag_id', '11111111-1111-4111-8111-111111111111', true);
select set_config(
  'planner_test.experiment_id',
  extensions.uuid_generate_v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'personal-planner:experiment:11111111-1111-4111-8111-111111111111'
  )::text,
  true
);
select set_config(
  'planner_test.check_in_id',
  extensions.uuid_generate_v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'personal-planner:experiment-check-in:'
      || current_setting('planner_test.experiment_id') || ':2026-10-05'
  )::text,
  true
);

-- Structure and privileges.
select has_table('public', 'experiments', 'experiments exists');
select has_table('public', 'experiment_check_ins', 'experiment_check_ins exists');
select has_column('public', 'tasks', 'tag_id', 'tasks.tag_id exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.experiments'::regclass),
  'RLS is enabled on experiments'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.experiment_check_ins'::regclass),
  'RLS is enabled on experiment_check_ins'
);

select is(
  current_setting('planner_test.experiment_id'),
  '6a921905-9a5c-51c0-b898-e0c6985d8a72',
  'the server makes the fixed example experiment id'
);
select is(
  current_setting('planner_test.check_in_id'),
  '52ddb265-2dac-5d4c-9d51-657bc6f99153',
  'the server makes the fixed example check-in id'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.planner_apply_sync_operation_internal(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'
  ),
  'anon cannot execute the apply wrapper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.planner_apply_sync_operation_internal(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute the apply wrapper'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.planner_apply_sync_operation_internal_pre_experiments(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'
  ),
  'anon cannot execute the renamed apply function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.planner_apply_sync_operation_internal_pre_experiments(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'
  ),
  'authenticated cannot execute the renamed apply function'
);

select ok(
  not has_table_privilege('anon', 'public.experiments', 'SELECT'),
  'anon cannot select experiments'
);
select ok(
  not has_table_privilege('anon', 'public.experiment_check_ins', 'SELECT'),
  'anon cannot select experiment_check_ins'
);
select ok(
  not has_table_privilege('authenticated', 'public.experiments', 'INSERT'),
  'authenticated cannot insert experiments directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.experiment_check_ins', 'INSERT'),
  'authenticated cannot insert experiment_check_ins directly'
);

-- B has done nothing yet: the legacy protocol is refused for the new tables.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
set local role authenticated;

select throws_ok(
  $$
    select public.apply_sync_operation(
      'b0000000-0000-4000-8000-000000000001', 'experiments',
      current_setting('planner_test.experiment_id'), 'insert', null,
      pg_temp.experiment_payload(
        current_setting('planner_test.experiment_id'),
        current_setting('planner_test.tag_id'), '2026-10-05', 1)
    )
  $$,
  '22023',
  'Unsupported sync table',
  'a protocol 1 call for experiments is rejected'
);

-- As A: the full flow through the v2 entry point.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000001', 'tags',
    current_setting('planner_test.tag_id'), 'insert', null,
    jsonb_build_object(
      'id', current_setting('planner_test.tag_id'),
      'name', 'Learn C',
      'created_at', '2026-10-05T08:00:00.000Z',
      'updated_at', '2026-10-05T08:00:00.000Z',
      'deleted_at', null
    ),
    2)->>'status',
  'applied',
  'the tag is applied'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'c0000000-0000-4000-8000-000000000002', 'experiments',
      '0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a', 'insert', null,
      pg_temp.experiment_payload(
        '0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a',
        current_setting('planner_test.tag_id'), '2026-10-05', 1),
      2)
  $$,
  '22023',
  'Invalid experiment identity',
  'an experiment with a wrong id is rejected'
);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000003', 'experiments',
    current_setting('planner_test.experiment_id'), 'insert', null,
    pg_temp.experiment_payload(
      current_setting('planner_test.experiment_id'),
      current_setting('planner_test.tag_id'), '2026-10-05', 1),
    2)->>'status',
  'applied',
  'an experiment with the deterministic id is applied'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'c0000000-0000-4000-8000-000000000004', 'experiments',
      current_setting('planner_test.experiment_id'), 'update', 1,
      pg_temp.experiment_payload(
        current_setting('planner_test.experiment_id'),
        current_setting('planner_test.tag_id'), '2026-02-30', 1),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'an experiment with the impossible start date 2026-02-30 is rejected'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'c0000000-0000-4000-8000-000000000005', 'experiments',
      current_setting('planner_test.experiment_id'), 'update', 1,
      pg_temp.experiment_payload(
        current_setting('planner_test.experiment_id'),
        current_setting('planner_test.tag_id'), '2026-10-05', 2),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'an experiment with check-in frequency 2 is rejected'
);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000006', 'experiment_check_ins',
    current_setting('planner_test.check_in_id'), 'insert', null,
    jsonb_build_object(
      'id', current_setting('planner_test.check_in_id'),
      'experiment_id', current_setting('planner_test.experiment_id'),
      'slot_date', '2026-10-05',
      'note', 'Slow start, pointers feel odd.',
      'created_at', '2026-10-05T20:00:00.000Z',
      'updated_at', '2026-10-05T20:00:00.000Z',
      'deleted_at', null
    ),
    2)->>'status',
  'applied',
  'a check-in with the deterministic id is applied'
);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000007', 'experiment_check_ins',
    current_setting('planner_test.check_in_id'), 'insert', null,
    jsonb_build_object(
      'id', current_setting('planner_test.check_in_id'),
      'experiment_id', current_setting('planner_test.experiment_id'),
      'slot_date', '2026-10-05',
      'note', 'A second write for the same slot.',
      'created_at', '2026-10-05T21:00:00.000Z',
      'updated_at', '2026-10-05T21:00:00.000Z',
      'deleted_at', null
    ),
    2)->>'status',
  'conflict',
  'a second insert of the same check-in id is a conflict'
);

-- tasks.tag_id: stored, kept when the key is absent, cleared by explicit null.
select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000008', 'tasks', 'tagged-task', 'insert', null,
    pg_temp.task_payload('tagged-task', 'Read chapter 1')
      || jsonb_build_object('tag_id', current_setting('planner_test.tag_id')),
    2)->>'status',
  'applied',
  'a task carrying tag_id is applied'
);
select is(
  (select tag_id from public.tasks where id = 'tagged-task'),
  current_setting('planner_test.tag_id'),
  'the task stores its tag_id'
);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-000000000009', 'tasks', 'tagged-task', 'update',
    (select server_version from public.tasks where id = 'tagged-task'),
    pg_temp.task_payload('tagged-task', 'Read chapter 1 (renamed)'),
    2)->>'status',
  'applied',
  'a task update without the tag_id key is applied'
);
select is(
  (select tag_id from public.tasks where id = 'tagged-task'),
  current_setting('planner_test.tag_id'),
  'an update without the tag_id key keeps the stored tag'
);

select is(
  public.apply_sync_operation_v2(
    'c0000000-0000-4000-8000-00000000000a', 'tasks', 'tagged-task', 'update',
    (select server_version from public.tasks where id = 'tagged-task'),
    pg_temp.task_payload('tagged-task', 'Read chapter 1 (renamed)')
      || jsonb_build_object('tag_id', null),
    2)->>'status',
  'applied',
  'a task update with an explicit null tag_id is applied'
);
select is(
  (select tag_id from public.tasks where id = 'tagged-task'),
  null,
  'an explicit null tag_id clears the tag'
);

select is(
  (select count(*) from public.experiments),
  1::bigint,
  'A reads its own experiment'
);
select is(
  (select count(*) from public.pull_sync_changes(0, 500)
   where table_name in ('experiments', 'experiment_check_ins')),
  2::bigint,
  'the change feed carries the experiment and the check-in'
);

-- As B: nothing of A's experiment rows is visible.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);

select is(
  (select count(*) from public.experiments)
    + (select count(*) from public.experiment_check_ins),
  0::bigint,
  'B sees none of A experiment rows'
);

select * from finish();
rollback;
