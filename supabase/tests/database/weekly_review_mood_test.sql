begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(12);

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

select has_column('public', 'weekly_reviews', 'mood', 'weekly_reviews.mood exists');
select has_column('public', 'weekly_reviews', 'feeling', 'weekly_reviews.feeling exists');
select has_trigger('public', 'weekly_reviews', 'planner_preserve_weekly_review_fields', 'weekly preserve trigger exists');

create function pg_temp.weekly_payload(p_reflection text, p_extra jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', '50000000-0000-4000-8000-000000000101',
    'week_start_date', '2026-09-28',
    'reflection', p_reflection,
    'overall_rating', null,
    'goals_met_json', null, 'goals_missed_json', null,
    'next_week_focus_json', null,
    'created_at', '2026-10-04T10:00:00.000Z',
    'updated_at', '2026-10-04T10:00:00.000Z',
    'deleted_at', null
  ) || p_extra
$$;

grant execute on function pg_temp.weekly_payload(text, jsonb) to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select is(
  public.apply_sync_operation_v2(
    '40000000-0000-4000-8000-000000000101', 'weekly_reviews',
    '50000000-0000-4000-8000-000000000101', 'insert', null,
    pg_temp.weekly_payload('Start with the hardest task',
      jsonb_build_object('mood', 3, 'feeling', 'Calm, proud')),
    2)->>'status',
  'applied', 'a current client stores weekly mood and feeling');

select is(
  public.apply_sync_operation_v2(
    '40000000-0000-4000-8000-000000000102', 'weekly_reviews',
    '50000000-0000-4000-8000-000000000101', 'update',
    (select server_version from public.weekly_reviews
     where id = '50000000-0000-4000-8000-000000000101'),
    pg_temp.weekly_payload('Edited by an older client', '{}'::jsonb),
    2)->>'status',
  'applied', 'an older client update without the new keys applies');

select is(
  (select mood from public.weekly_reviews where id = '50000000-0000-4000-8000-000000000101'),
  3, 'the older client update preserves the weekly mood');

select is(
  (select feeling from public.weekly_reviews where id = '50000000-0000-4000-8000-000000000101'),
  'Calm, proud', 'the older client update preserves the feeling');

select is(
  public.apply_sync_operation_v2(
    '40000000-0000-4000-8000-000000000103', 'weekly_reviews',
    '50000000-0000-4000-8000-000000000101', 'update',
    (select server_version from public.weekly_reviews
     where id = '50000000-0000-4000-8000-000000000101'),
    pg_temp.weekly_payload('Cleared feeling',
      jsonb_build_object('mood', 2, 'feeling', '')),
    2)->>'status',
  'applied', 'a current client can clear the feeling');

select is(
  (select feeling from public.weekly_reviews where id = '50000000-0000-4000-8000-000000000101'),
  '', 'an empty feeling is stored, not preserved');

select throws_ok(
  $$ select public.apply_sync_operation_v2(
       '40000000-0000-4000-8000-000000000104', 'weekly_reviews',
       '50000000-0000-4000-8000-000000000101', 'update',
       (select server_version from public.weekly_reviews
        where id = '50000000-0000-4000-8000-000000000101'),
       pg_temp.weekly_payload('x', jsonb_build_object('mood', 5)), 2) $$,
  '23514', null, 'weekly mood outside 1..4 is rejected');

select throws_ok(
  $$ select public.apply_sync_operation_v2(
       '40000000-0000-4000-8000-000000000105', 'weekly_reviews',
       '50000000-0000-4000-8000-000000000101', 'update',
       (select server_version from public.weekly_reviews
        where id = '50000000-0000-4000-8000-000000000101'),
       pg_temp.weekly_payload('x', jsonb_build_object('feeling', repeat('x', 201))), 2) $$,
  '23514', null, 'a feeling longer than 200 characters is rejected');

select is(
  (select char_length(feeling) from public.weekly_reviews where id = '50000000-0000-4000-8000-000000000101'),
  0, 'rejected writes leave the stored feeling unchanged');

select * from finish();
rollback;
