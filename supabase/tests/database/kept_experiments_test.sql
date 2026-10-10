begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(30);

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
    '2026-10-10T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-10T08:00:00Z',
    '2026-10-10T08:00:00Z',
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
    '2026-10-10T08:00:00Z',
    '{"provider":"email","providers":["email"]}',
    '{}',
    '2026-10-10T08:00:00Z',
    '2026-10-10T08:00:00Z',
    '',
    '',
    '',
    ''
  );

-- Fixed example shared with experiments_test.sql and
-- test/unit/sync/experiment_sync_test.dart:
--   tag        11111111-1111-4111-8111-111111111111
--   experiment 6a921905-9a5c-51c0-b898-e0c6985d8a72   (key experiment:<tag>)

-- The full experiments payload for the fixed tag and experiment. The three
-- kept keys are always present; the "without the keys" cases subtract them.
create function pg_temp.kept_payload(
  p_status text,
  p_outcome text,
  p_concluded_on text,
  p_retired_at text,
  p_retire_note text,
  p_target_changes text
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', '6a921905-9a5c-51c0-b898-e0c6985d8a72',
    'tag_id', '11111111-1111-4111-8111-111111111111',
    'purpose', 'Write every morning',
    'start_date', '2026-10-05',
    'end_date', '2026-11-05',
    'weekday_target_min', 60,
    'weekend_target_min', 90,
    'check_in_every_days', 7,
    'status', p_status,
    'extensions_json', '[]',
    'outcome', p_outcome,
    'conclusion_note', null,
    'concluded_on', p_concluded_on,
    'retired_at', p_retired_at,
    'retire_note', p_retire_note,
    'target_changes_json', p_target_changes,
    'created_at', '2026-10-05T08:00:00.000Z',
    'updated_at', '2026-10-10T08:00:00.000Z',
    'deleted_at', null
  )
$$;

grant execute on function pg_temp.kept_payload(text, text, text, text, text, text) to authenticated;

-- Structure.
select has_column('public', 'experiments', 'retired_at', 'experiments.retired_at exists');
select has_column('public', 'experiments', 'retire_note', 'experiments.retire_note exists');
select has_column('public', 'experiments', 'target_changes_json', 'experiments.target_changes_json exists');

select ok(
  exists (select 1 from pg_constraint
    where conname = 'experiments_retire_note_length'
      and conrelid = 'public.experiments'::regclass),
  'the retire note length constraint exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'experiments_retire_note_needs_retired'
      and conrelid = 'public.experiments'::regclass),
  'the retire note needs retired constraint exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'experiments_retired_only_kept'
      and conrelid = 'public.experiments'::regclass),
  'the retired only kept constraint exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'experiments_target_changes_array'
      and conrelid = 'public.experiments'::regclass),
  'the target changes array constraint exists'
);
select ok(
  exists (select 1 from pg_constraint
    where conname = 'experiments_target_changes_only_kept'
      and conrelid = 'public.experiments'::regclass),
  'the target changes only kept constraint exists'
);

-- As A: the flow through the v2 entry point.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000001', 'tags',
    '11111111-1111-4111-8111-111111111111', 'insert', null,
    jsonb_build_object(
      'id', '11111111-1111-4111-8111-111111111111',
      'name', 'Morning pages',
      'created_at', '2026-10-05T08:00:00.000Z',
      'updated_at', '2026-10-05T08:00:00.000Z',
      'deleted_at', null
    ),
    2)->>'status',
  'applied',
  'the tag is applied'
);

-- A running insert without the three kept keys (an older client).
select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000002', 'experiments',
    '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'insert', null,
    pg_temp.kept_payload('running', null, null, null, null, '[]')
      - 'retired_at' - 'retire_note' - 'target_changes_json',
    2)->>'status',
  'applied',
  'a running insert without the kept keys is applied'
);
select is(
  (select retired_at is null and retire_note is null and target_changes_json = '[]'
   from public.experiments where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  true,
  'the missing keys store null, null and []'
);

-- Concluded as keep, retired with a note.
select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000003', 'experiments',
    '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
    (select server_version from public.experiments
     where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
    pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09',
      '2026-10-10T08:00:00.000Z', 'Part of my mornings now.', '[]'),
    2)->>'status',
  'applied',
  'a concluded keep update with retired_at and a note is applied'
);
select is(
  (select retired_at from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  '2026-10-10T08:00:00Z'::timestamptz,
  'retired_at is stored'
);
select is(
  (select retire_note from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  'Part of my mornings now.',
  'retire_note is stored'
);

-- An update without the three keys keeps the stored values.
select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000004', 'experiments',
    '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
    (select server_version from public.experiments
     where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
    pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null, '[]')
      - 'retired_at' - 'retire_note' - 'target_changes_json',
    2)->>'status',
  'applied',
  'an update without the kept keys is applied'
);
select is(
  (select retired_at from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  '2026-10-10T08:00:00Z'::timestamptz,
  'an update without the keys keeps retired_at'
);
select is(
  (select retire_note from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  'Part of my mornings now.',
  'an update without the keys keeps the retire note'
);

-- An explicit null clears retired_at and the note (Undo).
select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000005', 'experiments',
    '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
    (select server_version from public.experiments
     where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
    pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null, '[]'),
    2)->>'status',
  'applied',
  'an update with explicit nulls is applied'
);
select is(
  (select retired_at is null and retire_note is null
   from public.experiments where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  true,
  'explicit nulls clear retired_at and the note'
);

-- A valid target change is stored.
select is(
  public.apply_sync_operation_v2(
    'e0000000-0000-4000-8000-000000000006', 'experiments',
    '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
    (select server_version from public.experiments
     where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
    pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null,
      '[{"effective_week_start":"2026-10-12","weekday_target_min":75,"weekend_target_min":90,"made_on":"2026-10-10"}]'),
    2)->>'status',
  'applied',
  'a valid target change is applied'
);
select is(
  (select target_changes_json::jsonb from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  '[{"effective_week_start":"2026-10-12","weekday_target_min":75,"weekend_target_min":90,"made_on":"2026-10-10"}]'::jsonb,
  'the target change is stored'
);

-- Invalid payloads. Each is rejected before anything is written.
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-000000000007', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'drop', '2026-10-09',
        '2026-10-10T08:00:00.000Z', null, '[]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'retired_at on a drop row is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-000000000008', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09',
        null, 'A note with no retirement.', '[]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'a retire note without retired_at is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-000000000009', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null,
        '[{"effective_week_start":"2026-10-13","weekday_target_min":75,"weekend_target_min":90,"made_on":"2026-10-10"}]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'a change week that is not a Monday (2026-10-13) is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-00000000000a', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null,
        '[{"effective_week_start":"2026-10-12","weekday_target_min":10,"weekend_target_min":90,"made_on":"2026-10-10"}]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'a target of 10 minutes is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-00000000000b', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null,
        '[{"effective_week_start":"2026-10-12","weekday_target_min":75,"weekend_target_min":90,"made_on":"2026-10-10"},{"effective_week_start":"2026-10-12","weekday_target_min":80,"weekend_target_min":95,"made_on":"2026-10-11"}]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'two changes for the same week are rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-00000000000c', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('concluded', 'continue_habit', '2026-10-09', null, null, '{}'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'target_changes_json that is an object is rejected'
);
select throws_ok(
  $$
    select public.apply_sync_operation_v2(
      'e0000000-0000-4000-8000-00000000000d', 'experiments',
      '6a921905-9a5c-51c0-b898-e0c6985d8a72', 'update',
      (select server_version from public.experiments
       where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
      pg_temp.kept_payload('running', null, null, null, null,
        '[{"effective_week_start":"2026-10-12","weekday_target_min":75,"weekend_target_min":90,"made_on":"2026-10-10"}]'),
      2)
  $$,
  '22023',
  'Invalid experiment payload',
  'a non-empty target list on a running row is rejected'
);

select is(
  (select jsonb_array_length(target_changes_json::jsonb) from public.experiments
   where id = '6a921905-9a5c-51c0-b898-e0c6985d8a72'),
  1,
  'the rejected writes left the stored target history unchanged'
);

-- As B: nothing of A's experiment rows is visible.
select set_config('request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);

select is(
  (select count(*) from public.experiments),
  0::bigint,
  'B sees none of A experiment rows'
);

select * from finish();
rollback;
