begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(43);

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

select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_sync_operation_v2(uuid,text,text,text,bigint,jsonb,integer)',
    'EXECUTE'
  ),
  'authenticated clients can execute the public protocol-2 RPC'
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

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000001',
    'tasks',
    'shared-task',
    'insert',
    null,
    pg_temp.planner_task_payload(
      'shared-task', 'Common title', null, '[]', null, null, null
    ),
    2
  )->>'status',
  'applied',
  'initial protocol-2 task insert is accepted'
);

select is(
  (select server_version from public.tasks where id = 'shared-task'),
  1::bigint,
  'initial insert allocates server version 1'
);

select is(
  (select count(*) from public.sync_changes where record_id = 'shared-task'),
  1::bigint,
  'initial insert publishes exactly one feed row'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000002',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task',
      'Device A title',
      'Device A note',
      '[{"id":"40000000-0000-7000-8000-000000000001","previous_title":"Common title","new_title":"Device A title","changed_at":"2026-09-16T09:15:00.000Z","reverted_at":null}]',
      '40000000-0000-7000-8000-000000000001',
      null,
      null
    ),
    2
  )->>'status',
  'applied',
  'a mutation with the current expected server version is accepted'
);

select is(
  (select server_version from public.tasks where id = 'shared-task'),
  2::bigint,
  'the accepted current-CAS mutation advances the row version once'
);

select is(
  (select title from public.tasks where id = 'shared-task'),
  'Device A title',
  'the accepted current-CAS mutation becomes authoritative'
);

select ok(
  (select plan_title_history_json from public.tasks where id = 'shared-task')
    like '%40000000-0000-7000-8000-000000000001%',
  'the accepted title event is stored on the authoritative task'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000002',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task',
      'Device A title',
      'Device A note',
      '[{"id":"40000000-0000-7000-8000-000000000001","previous_title":"Common title","new_title":"Device A title","changed_at":"2026-09-16T09:15:00.000Z","reverted_at":null}]',
      '40000000-0000-7000-8000-000000000001',
      null,
      null
    ),
    2
  )->>'status',
  'acknowledged',
  'a duplicate operation ID receives an idempotent acknowledgement'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000002',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task', 'ignored duplicate', null, '[]', null, null, null
    ),
    2
  )->>'server_version',
  '2',
  'the duplicate acknowledgement retains the original server version'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000002',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task', 'ignored duplicate', null, '[]', null, null, null
    ),
    2
  )->>'change_id',
  '2',
  'the duplicate acknowledgement retains the original feed identity'
);

reset role;

select is(
  (select count(*) from public.sync_operation_ack
   where operation_id = '30000000-0000-4000-8000-000000000002'),
  1::bigint,
  'the duplicate operation does not create another acknowledgement'
);

select is(
  (select count(*) from public.sync_changes
   where operation_id = '30000000-0000-4000-8000-000000000002'),
  1::bigint,
  'the duplicate operation does not publish another mutation'
);

set local role authenticated;

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000003',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task', 'Common title', 'Device B note', '[]', null, null, null
    ),
    2
  )->>'status',
  'conflict',
  'a structurally valid stale title branch returns a structured conflict'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000003',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task', 'Common title', 'Device B note', '[]', null, null, null
    ),
    2
  )->>'actual_server_version',
  '2',
  'the stale conflict reports the authoritative server version'
);

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000003',
    'tasks',
    'shared-task',
    'update',
    1,
    pg_temp.planner_task_payload(
      'shared-task', 'Common title', 'Device B note', '[]', null, null, null
    ),
    2
  )->'remote_snapshot'->>'title',
  'Device A title',
  'the stale conflict includes the existing authoritative snapshot'
);

reset role;

select is(
  (select count(*) from public.sync_operation_ack
   where operation_id = '30000000-0000-4000-8000-000000000003'),
  0::bigint,
  'a conflict does not create an acknowledgement'
);

select is(
  (select count(*) from public.sync_changes
   where operation_id = '30000000-0000-4000-8000-000000000003'),
  0::bigint,
  'a conflict does not publish a feed mutation'
);

set local role authenticated;

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '30000000-0000-4000-8000-000000000004',
      'tasks',
      'shared-task',
      'update',
      1,
      pg_temp.planner_task_payload(
        'shared-task',
        'Collision title',
        null,
        '[{"id":"40000000-0000-7000-8000-000000000001","previous_title":"Common title","new_title":"Collision title","changed_at":"2026-09-16T09:15:00.000Z","reverted_at":null}]',
        '40000000-0000-7000-8000-000000000001',
        null,
        null
      ),
      2
    )
  $$,
  '22023',
  'Plan title event ID has conflicting immutable data',
  'an immutable event-ID collision is rejected as invalid data'
);

reset role;

select is(
  (select count(*) from public.sync_operation_ack
   where operation_id = '30000000-0000-4000-8000-000000000004')
  +
  (select count(*) from public.sync_changes
   where operation_id = '30000000-0000-4000-8000-000000000004'),
  0::bigint,
  'the rejected immutable collision leaves no acknowledgement or feed row'
);

set local role authenticated;

select is(
  public.apply_sync_operation_v2(
    '30000000-0000-4000-8000-000000000005',
    'categories',
    'category-a',
    'insert',
    null,
    jsonb_build_object(
      'id', 'category-a',
      'name', 'User A category',
      'color_hex', '#4285F4',
      'sort_order', 0,
      'is_focus', 0,
      'created_at', '2026-09-16T09:00:00.000Z',
      'updated_at', '2026-09-16T09:00:00.000Z',
      'deleted_at', null
    ),
    2
  )->>'status',
  'applied',
  'User A can create the relationship target through the public RPC'
);

reset role;
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

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '30000000-0000-4000-8000-000000000006',
      'tasks',
      'shared-task',
      'update',
      2,
      pg_temp.planner_task_payload(
        'shared-task',
        'Forged ownership',
        null,
        '[]',
        null,
        null,
        '10000000-0000-4000-8000-000000000001'
      ),
      2
    )
  $$,
  '22023',
  'Payload contains server-owned fields',
  'User B cannot forge User A ownership in an RPC payload'
);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      '30000000-0000-4000-8000-000000000007',
      'tasks',
      'user-b-cross-owner-task',
      'insert',
      null,
      pg_temp.planner_task_payload(
        'user-b-cross-owner-task',
        'Cross-owner relationship',
        null,
        '[]',
        null,
        'category-a',
        null
      ),
      2
    )
  $$,
  '23503',
  'insert or update on table "tasks" violates foreign key constraint "tasks_user_id_category_id_fkey"',
  'User B cannot reference User A relationship rows'
);

select is(
  (select count(*) from public.tasks),
  0::bigint,
  'RLS exposes no User A task rows to User B'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.planner_title_history_conflict_payload(jsonb,uuid,text)',
    'EXECUTE'
  ),
  'the title-conflict payload helper is private'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.planner_apply_sync_operation_internal(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'
  ),
  'the shared internal mutation adapter is private'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_sync_operation_v1_title_order_base(uuid,text,text,text,bigint,jsonb)',
    'EXECUTE'
  ),
  'the v1 title-order base adapter is private'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_sync_operation_v2_title_order_base(uuid,text,text,text,bigint,jsonb,integer)',
    'EXECUTE'
  ),
  'the v2 title-order base adapter is private'
);

select throws_ok(
  $$
    select public.planner_apply_sync_operation_internal(
      '30000000-0000-4000-8000-000000000008',
      'tasks',
      'private-call',
      'insert',
      null,
      '{}'::jsonb,
      2,
      2
    )
  $$,
  '42501',
  'permission denied for function planner_apply_sync_operation_internal',
  'an authenticated client cannot invoke the private mutation adapter'
);

reset role;

select is(
  (select next_change_id from public.sync_state
   where user_id = '10000000-0000-4000-8000-000000000001'),
  4::bigint,
  'only the three accepted User A operations advance the feed counter'
);

select is(
  (select next_server_version from public.sync_state
   where user_id = '10000000-0000-4000-8000-000000000001'),
  4::bigint,
  'only the three accepted User A operations advance the version counter'
);

select is(
  (select client_protocol_version from public.sync_state
   where user_id = '10000000-0000-4000-8000-000000000001'),
  2,
  'accepted protocol-2 operations activate protocol version 2'
);

select is(
  (select count(*) from public.sync_changes
   where user_id = '10000000-0000-4000-8000-000000000001'),
  3::bigint,
  'the accepted operations produce exactly three User A feed rows'
);

select is(
  (select count(*) from public.sync_operation_ack
   where user_id = '10000000-0000-4000-8000-000000000001'),
  3::bigint,
  'the accepted operations produce exactly three User A acknowledgements'
);

select is(
  (select string_agg(change_id::text, ',' order by change_id)
   from public.sync_changes
   where user_id = '10000000-0000-4000-8000-000000000001'),
  '1,2,3',
  'feed change IDs remain gap-free and ordered for accepted operations'
);

select is(
  (select string_agg(server_version::text, ',' order by change_id)
   from public.sync_changes
   where user_id = '10000000-0000-4000-8000-000000000001'),
  '1,2,3',
  'server versions remain gap-free and ordered with the feed'
);

select is(
  (
    select count(*)
    from public.sync_operation_ack
    where operation_id in (
      '30000000-0000-4000-8000-000000000003',
      '30000000-0000-4000-8000-000000000004',
      '30000000-0000-4000-8000-000000000006',
      '30000000-0000-4000-8000-000000000007'
    )
  ) + (
    select count(*)
    from public.sync_changes
    where operation_id in (
      '30000000-0000-4000-8000-000000000003',
      '30000000-0000-4000-8000-000000000004',
      '30000000-0000-4000-8000-000000000006',
      '30000000-0000-4000-8000-000000000007'
    )
  ),
  0::bigint,
  'conflicted and rejected operations create no ACK or feed entries'
);

select is(
  (select title from public.tasks
   where user_id = '10000000-0000-4000-8000-000000000001'
     and id = 'shared-task'),
  'Device A title',
  'failed and stale branches never overwrite User A live state'
);

select is(
  (select server_version from public.tasks
   where user_id = '10000000-0000-4000-8000-000000000001'
     and id = 'shared-task'),
  2::bigint,
  'failed and stale branches never advance User A task version'
);

select ok(
  (select plan_title_history_json from public.tasks
   where user_id = '10000000-0000-4000-8000-000000000001'
     and id = 'shared-task')
    like '%40000000-0000-7000-8000-000000000001%',
  'failed and stale branches preserve User A immutable title history'
);

select is(
  (select count(*) from public.categories
   where user_id = '10000000-0000-4000-8000-000000000001'
     and id = 'category-a'),
  1::bigint,
  'the relationship target remains owned by User A'
);

select is(
  (select count(*) from public.tasks
   where user_id = '20000000-0000-4000-8000-000000000002'),
  0::bigint,
  'rejected User B mutations persist no task row'
);

select is(
  (select count(*) from public.sync_changes
   where user_id = '20000000-0000-4000-8000-000000000002'),
  0::bigint,
  'rejected User B mutations publish no feed row'
);

select * from finish();
rollback;
