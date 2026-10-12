begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(71);

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
    '2026-10-12T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-12T08:00:00Z',
    '2026-10-12T08:00:00Z',
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
    '2026-10-12T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-12T08:00:00Z',
    '2026-10-12T08:00:00Z',
    '',
    '',
    '',
    ''
  );

-- Fixtures, with ids that read well in failure output:
--   idea     inbox-idea-1       (an is_inbox row, the Inbox "idea")
--   session  inbox-session-1    (an ordinary block pointing at the idea)

create function pg_temp.task_payload(p_id text, p_title text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_id,
    'title', p_title,
    'description', null,
    'start_time', '2026-10-14T09:00:00.000Z',
    'end_time', '2026-10-14T10:00:00.000Z',
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
    'created_at', '2026-10-12T09:00:00.000Z',
    'updated_at', '2026-10-12T09:00:00.000Z',
    'deleted_at', null
  )
$$;

-- An Inbox idea: no schedule, content marker 1, both Inbox keys present.
create function pg_temp.idea_payload(p_id text, p_title text, p_history text)
returns jsonb
language sql
immutable
as $$
  select pg_temp.task_payload(p_id, p_title) || jsonb_build_object(
    'description', p_title,
    'start_time', null,
    'end_time', null,
    'estimated_duration_min', null,
    'is_inbox', 1,
    'inbox_content_version', 1,
    'inbox_item_id', null,
    'inbox_history_json', p_history
  )
$$;

-- A session: an ordinary scheduled block with both Inbox keys present.
create function pg_temp.session_payload(p_id text, p_title text, p_item text)
returns jsonb
language sql
immutable
as $$
  select pg_temp.task_payload(p_id, p_title) || jsonb_build_object(
    'inbox_item_id', p_item,
    'inbox_history_json', '[]'
  )
$$;

-- A history of p_count let-go events, each reopened except the last one.
create function pg_temp.history_events(p_count integer)
returns text
language sql
immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', 'let_go',
    'at', to_char(
      (timestamptz '2026-10-12 00:00:00+00' + make_interval(hours => g))
        at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'reopened_at', case when g < p_count then to_char(
      (timestamptz '2026-10-12 00:00:00+00' + make_interval(hours => g, mins => 1))
        at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') else null end
  ) order by g), '[]'::jsonb)::text
  from generate_series(1, p_count) as g
$$;

grant execute on function pg_temp.task_payload(text, text) to authenticated;
grant execute on function pg_temp.idea_payload(text, text, text) to authenticated;
grant execute on function pg_temp.session_payload(text, text, text) to authenticated;
grant execute on function pg_temp.history_events(integer) to authenticated;

-- Structure and privileges.
select has_column('public', 'tasks', 'inbox_item_id', 'tasks.inbox_item_id exists');
select has_column('public', 'tasks', 'inbox_history_json', 'tasks.inbox_history_json exists');
select ok(
  exists (select 1 from pg_constraint
    where conname = 'tasks_inbox_item_fk' and conrelid = 'public.tasks'::regclass),
  'the inbox item foreign key exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'tasks_inbox_item_not_self' and conrelid = 'public.tasks'::regclass),
  'the not-self check exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'tasks_inbox_history_array' and conrelid = 'public.tasks'::regclass),
  'the history array check exists'
);
select ok(
  exists (select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'tasks'
      and indexname = 'tasks_user_inbox_item_idx'),
  'the child-side inbox item index exists'
);
select ok(
  not has_function_privilege(
    'anon', 'public.planner_inbox_history_valid(text)', 'EXECUTE')
  and not has_function_privilege(
    'authenticated', 'public.planner_inbox_history_valid(text)', 'EXECUTE'),
  'anon and authenticated cannot execute the history validator'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.planner_apply_sync_operation_internal(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE')
  and not has_function_privilege(
    'authenticated',
    'public.planner_apply_sync_operation_internal(uuid,text,text,text,bigint,jsonb,integer,integer)',
    'EXECUTE'),
  'anon and authenticated still cannot execute the apply wrapper'
);

-- The history validator, called directly as the table owner.
select is(public.planner_inbox_history_valid('[]'), true, 'an empty history is valid');
select is(public.planner_inbox_history_valid(null), false, 'a null history is invalid');
select is(public.planner_inbox_history_valid('{}'), false, 'an object history is invalid');
select is(public.planner_inbox_history_valid('nope'), false, 'text that is not JSON is invalid');
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z","reason":"Bought it elsewhere","experiment_id":null,"reopened_at":null}]'),
  true,
  'the documented closed event is valid'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"experiment","at":"2026-10-12T09:30:00.000Z","experiment_id":"experiment:t"}]'),
  true,
  'an experiment event with an id and no reason is valid'
);

-- A time must be an ISO-8601 instant. timestamptz input alone would also
-- take words and date-only text, so these are checked before the cast.
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"now"}]'),
  false,
  'the word now is not an instant'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"tomorrow"}]'),
  false,
  'the word tomorrow is not an instant'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"2026-10-12"}]'),
  false,
  'a date-only string is not an instant'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"2026-10-12T09:30:00.000Z","reopened_at":"now"}]'),
  false,
  'the word now is not a reopened_at instant'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"2026-10-12T11:30:00+02:00"}]'),
  true,
  'an instant with a numeric offset is valid'
);
select is(
  public.planner_inbox_history_valid(
    '[{"kind":"let_go","at":"2026-10-12T09:30:00.123456Z","reopened_at":"2026-10-12T16:30:00+0530"}]'),
  true,
  'fractional seconds with Z, and a compact offset, are valid'
);

-- As A: the flow through the v2 entry point.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select is(
  public.planner_sync_capabilities()->>'inbox_sessions',
  'true',
  'the capability response advertises inbox_sessions'
);
select is(
  public.planner_sync_capabilities() @> '{"protocol_version":2,"initial_sync_baseline":true,"initial_sync_fencing":true,"payload_versions":[1,2]}'::jsonb,
  true,
  'the earlier capability keys are unchanged'
);

select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000001', 'tasks', 'inbox-idea-1', 'insert', null,
    pg_temp.idea_payload('inbox-idea-1', 'Learn C', '[]'),
    2)->>'status',
  'applied',
  'an Inbox idea with both keys is applied'
);
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000002', 'tasks', 'inbox-session-1', 'insert', null,
    pg_temp.session_payload('inbox-session-1', 'Learn C', 'inbox-idea-1'),
    2)->>'status',
  'applied',
  'a session pointing at the idea is applied'
);
select is(
  (select inbox_item_id from public.tasks where id = 'inbox-session-1'),
  'inbox-idea-1',
  'the session stores its idea id'
);

-- An older client's payload carries neither key: the stored values are kept.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000003', 'tasks', 'inbox-session-1', 'update',
    (select server_version from public.tasks where id = 'inbox-session-1'),
    pg_temp.task_payload('inbox-session-1', 'Learn C (renamed)'),
    2)->>'status',
  'applied',
  'a session update without the Inbox keys is applied'
);
select is(
  (select inbox_item_id from public.tasks where id = 'inbox-session-1'),
  'inbox-idea-1',
  'an update without the keys keeps the session link'
);
select is(
  (select inbox_history_json from public.tasks where id = 'inbox-session-1'),
  '[]',
  'an update without the keys keeps the default history'
);
select is(
  (select title from public.tasks where id = 'inbox-session-1'),
  'Learn C (renamed)',
  'the rest of the update was applied'
);

-- An explicit value is validated and stored.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000004', 'tasks', 'inbox-idea-1', 'update',
    (select server_version from public.tasks where id = 'inbox-idea-1'),
    pg_temp.idea_payload('inbox-idea-1', 'Learn C',
      '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z","reason":"Bought it elsewhere","experiment_id":null,"reopened_at":null}]'),
    2)->>'status',
  'applied',
  'closing the idea with a reason is applied'
);
select is(
  (select inbox_history_json::jsonb from public.tasks where id = 'inbox-idea-1'),
  '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z","reason":"Bought it elsewhere","experiment_id":null,"reopened_at":null}]'::jsonb,
  'the closed history is stored'
);

-- The idea's own payload without the keys keeps its history.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000005', 'tasks', 'inbox-idea-1', 'update',
    (select server_version from public.tasks where id = 'inbox-idea-1'),
    pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', '[]')
      - 'inbox_item_id' - 'inbox_history_json',
    2)->>'status',
  'applied',
  'an idea update without the Inbox keys is applied'
);
select is(
  (select jsonb_array_length(inbox_history_json::jsonb) from public.tasks where id = 'inbox-idea-1'),
  1,
  'an idea update without the keys keeps its history'
);

-- A 200-code-point reason (an emoji counts once) is accepted.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000006', 'tasks', 'inbox-idea-1', 'update',
    (select server_version from public.tasks where id = 'inbox-idea-1'),
    pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
      jsonb_build_array(jsonb_build_object(
        'kind', 'closed', 'at', '2026-10-12T09:30:00.000Z',
        'reason', repeat(chr(128512), 200),
        'experiment_id', null, 'reopened_at', null))::text),
    2)->>'status',
  'applied',
  'a reason of 200 code points is applied'
);

-- An explicit null clears the session link.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000007', 'tasks', 'inbox-session-1', 'update',
    (select server_version from public.tasks where id = 'inbox-session-1'),
    pg_temp.session_payload('inbox-session-1', 'Learn C (renamed)', null),
    2)->>'status',
  'applied',
  'a session update with an explicit null link is applied'
);
select is(
  (select inbox_item_id from public.tasks where id = 'inbox-session-1'),
  null,
  'an explicit null clears the link'
);
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000008', 'tasks', 'inbox-session-1', 'update',
    (select server_version from public.tasks where id = 'inbox-session-1'),
    pg_temp.session_payload('inbox-session-1', 'Learn C (renamed)', 'inbox-idea-1'),
    2)->>'status',
  'applied',
  'the session can be linked again'
);

-- An instant with a numeric offset is accepted: the server is lenient about
-- the offset, the app writes Z.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000020', 'tasks', 'inbox-idea-1', 'update',
    (select server_version from public.tasks where id = 'inbox-idea-1'),
    pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
      '[{"kind":"let_go","at":"2026-10-12T11:30:00+02:00"}]'),
    2)->>'status',
  'applied',
  'an event time with a numeric offset is applied'
);

-- A history of exactly 100 events is accepted.
select is(
  public.apply_sync_operation_v2(
    'f0000000-0000-4000-8000-000000000009', 'tasks', 'inbox-idea-1', 'update',
    (select server_version from public.tasks where id = 'inbox-idea-1'),
    pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', pg_temp.history_events(100)),
    2)->>'status',
  'applied',
  'a history of 100 events is applied'
);

-- Invalid payloads. Each is rejected before anything is written.
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000a', 'tasks', 'inbox-session-1', 'update',
      (select server_version from public.tasks where id = 'inbox-session-1'),
      pg_temp.session_payload('inbox-session-1', 'Learn C (renamed)', 'inbox-session-1'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a session that points at itself is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000b', 'tasks', 'inbox-session-1', 'update',
      (select server_version from public.tasks where id = 'inbox-session-1'),
      pg_temp.session_payload('inbox-session-1', 'Learn C (renamed)', '  '),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a blank inbox_item_id is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000c', 'tasks', 'inbox-session-1', 'update',
      (select server_version from public.tasks where id = 'inbox-session-1'),
      pg_temp.task_payload('inbox-session-1', 'Learn C (renamed)')
        || jsonb_build_object('inbox_item_id', 5, 'inbox_history_json', '[]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an inbox_item_id that is not text is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000d', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', '[]')
        || jsonb_build_object('inbox_history_json', '[]'::jsonb),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a history that is a JSON array instead of text is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000e', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', 'nope'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a history that is not JSON is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000000f', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', '{}'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a history that is a JSON object is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000010', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', '[1]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a history event that is not an object is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000011', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z","reason":"x","note":"extra"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an event with an unknown key is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000012', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"finished","at":"2026-10-12T09:30:00.000Z","reason":"x"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an unknown kind is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000013', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"yesterday","reason":"x"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an event time that is not an instant is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000021', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"now","reason":"x"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'the word now as an event time is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000022', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"2026-10-12","reason":"x"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a date-only event time is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000023', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"let_go","at":"2026-10-12T09:30:00.000Z","reopened_at":"tomorrow"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'the word tomorrow as a reopened_at time is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000014', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a closed event without a reason is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000015', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"closed","at":"2026-10-12T09:30:00.000Z","reason":"   "}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a blank reason is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000016', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        jsonb_build_array(jsonb_build_object(
          'kind', 'closed', 'at', '2026-10-12T09:30:00.000Z',
          'reason', repeat(chr(128512), 201)))::text),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a reason of 201 code points is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000017', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"experiment","at":"2026-10-12T09:30:00.000Z","reason":"why","experiment_id":"experiment:t"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an experiment event with a reason is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000018', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"experiment","at":"2026-10-12T09:30:00.000Z"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an experiment event without an id is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-000000000019', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"let_go","at":"2026-10-12T09:30:00.000Z","experiment_id":"experiment:t"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'an experiment id on a let-go event is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001a', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"let_go","at":"2026-10-12T09:30:00.000Z"},{"kind":"let_go","at":"2026-10-13T09:30:00.000Z"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a still-closed event that is not the last is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001b', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"let_go","at":"2026-10-13T09:30:00.000Z","reopened_at":"2026-10-13T10:00:00.000Z"},{"kind":"let_go","at":"2026-10-12T09:30:00.000Z"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'events out of order are rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001c', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)',
        '[{"kind":"let_go","at":"2026-10-12T09:30:00.000Z","reopened_at":"2026-10-12T09:00:00.000Z"}]'),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a bring back before the close is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001d', 'tasks', 'inbox-idea-1', 'update',
      (select server_version from public.tasks where id = 'inbox-idea-1'),
      pg_temp.idea_payload('inbox-idea-1', 'Learn C (edited)', pg_temp.history_events(101)),
      2)
  $$,
  '22023',
  'Invalid inbox payload',
  'a history of 101 events is rejected'
);

select is(
  (select jsonb_array_length(inbox_history_json::jsonb) from public.tasks where id = 'inbox-idea-1'),
  100,
  'the rejected writes left the stored history unchanged'
);
select is(
  (select inbox_item_id from public.tasks where id = 'inbox-session-1'),
  'inbox-idea-1',
  'the rejected writes left the stored link unchanged'
);

-- A link to a row that does not exist, or to another user's row, is refused
-- by the composite foreign key.
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001e', 'tasks', 'inbox-session-2', 'insert', null,
      pg_temp.session_payload('inbox-session-2', 'Orphan', 'no-such-idea'),
      2)
  $$,
  '23503',
  'insert or update on table "tasks" violates foreign key constraint "tasks_inbox_item_fk"',
  'a link to a missing idea is rejected'
);

-- The feed carries both keys, so another device receives them.
select is(
  (select (payload ? 'inbox_item_id') and (payload ? 'inbox_history_json')
   from public.pull_sync_changes(0, 500)
   where table_name = 'tasks' and record_id = 'inbox-session-1'
   order by change_id desc limit 1),
  true,
  'the change feed snapshot of a session carries both Inbox keys'
);
select is(
  (select payload->>'inbox_item_id'
   from public.pull_sync_changes(0, 500)
   where table_name = 'tasks' and record_id = 'inbox-session-1'
   order by change_id desc limit 1),
  'inbox-idea-1',
  'the feed snapshot carries the session link'
);

-- As B: A's idea cannot be linked to, and none of A's rows are visible.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);

select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'f0000000-0000-4000-8000-00000000001f', 'tasks', 'inbox-session-b', 'insert', null,
      pg_temp.session_payload('inbox-session-b', 'Sneaky', 'inbox-idea-1'),
      2)
  $$,
  '23503',
  'insert or update on table "tasks" violates foreign key constraint "tasks_inbox_item_fk"',
  'a link to another user''s idea is rejected'
);
select is(
  (select count(*) from public.tasks where id like 'inbox-%'),
  0::bigint,
  'B sees none of A''s Inbox rows'
);

-- The table constraints hold below the apply layer too.
reset role;

select throws_ok(
  $$ update public.tasks set inbox_item_id = id where id = 'inbox-session-1' $$,
  '23514',
  'new row for relation "tasks" violates check constraint "tasks_inbox_item_not_self"',
  'the not-self check refuses a self link'
);
select throws_ok(
  $$ update public.tasks set inbox_history_json = '{}' where id = 'inbox-idea-1' $$,
  '23514',
  'new row for relation "tasks" violates check constraint "tasks_inbox_history_array"',
  'the array check refuses an object history'
);

select * from finish();
rollback;
