begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(10);

-- Test-only user, rolled back with the transaction.
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
  );

select has_column('public', 'daily_reviews', 'mood', 'daily_reviews.mood exists');
select has_column('public', 'daily_reviews', 'task_reasons_json', 'daily_reviews.task_reasons_json exists');
select has_column('public', 'tasks', 'plan_change_reasons_json', 'tasks.plan_change_reasons_json exists');
select has_trigger('public', 'daily_reviews', 'planner_preserve_review_fields', 'review preserve trigger exists');
select has_trigger('public', 'tasks', 'planner_preserve_plan_change_reasons', 'plan-change preserve trigger exists');

create function pg_temp.review_payload(p_reflection text, p_extra jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', '50000000-0000-4000-8000-000000000001',
    'date', '2026-10-07',
    'reflection', p_reflection,
    'energy_level', null, 'productivity_rating', null,
    'planning_accuracy_rating', null,
    'wins_json', null, 'improvements_json', null,
    'created_at', '2026-10-07T10:00:00.000Z',
    'updated_at', '2026-10-07T10:00:00.000Z',
    'deleted_at', null
  ) || p_extra
$$;

grant execute on function pg_temp.review_payload(text, jsonb) to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select is(
  public.apply_sync_operation_v2(
    '40000000-0000-4000-8000-000000000001', 'daily_reviews',
    '50000000-0000-4000-8000-000000000001', 'insert', null,
    pg_temp.review_payload('Good day',
      jsonb_build_object('mood', 3, 'task_reasons_json', '{"t1":"Blocked"}')),
    2)->>'status',
  'applied', 'a current client stores mood and reasons');

select is(
  public.apply_sync_operation_v2(
    '40000000-0000-4000-8000-000000000002', 'daily_reviews',
    '50000000-0000-4000-8000-000000000001', 'update',
    (select server_version from public.daily_reviews
     where id = '50000000-0000-4000-8000-000000000001'),
    pg_temp.review_payload('Edited by an older client', '{}'::jsonb),
    2)->>'status',
  'applied', 'an older client update without the new keys applies');

select is(
  (select mood from public.daily_reviews where id = '50000000-0000-4000-8000-000000000001'),
  3, 'the older client update preserves mood');

select is(
  (select task_reasons_json from public.daily_reviews where id = '50000000-0000-4000-8000-000000000001'),
  '{"t1":"Blocked"}', 'the older client update preserves reasons');

select throws_ok(
  $$ select public.apply_sync_operation_v2(
       '40000000-0000-4000-8000-000000000003', 'daily_reviews',
       '50000000-0000-4000-8000-000000000001', 'update',
       (select server_version from public.daily_reviews
        where id = '50000000-0000-4000-8000-000000000001'),
       pg_temp.review_payload('x', jsonb_build_object('mood', 5)), 2) $$,
  '23514', null, 'mood outside 1..4 is rejected');

select * from finish();
rollback;
