-- Phase G: server-authoritative initial synchronization baseline for a
-- provisioned user-owned backend.
--
-- A newly connected account has to determine the existing remote Planner state
-- *before* any local Planner mutation is pushed. The existing v1/v2 protocol
-- already offers per-record compare-and-set, operation-id idempotency and a
-- monotonic change feed, but it has no way to say "I decided to adopt local
-- data because the account was empty; reject me if that is no longer true".
--
-- This migration adds the smallest mechanism that closes that gap and makes the
-- *server* the authority on the three protocol states:
--
--   * unused     - no completed baseline, no baseline claim and no durable
--                  Planner history. Only this state may be claimed.
--   * in progress- exactly one fenced claimant owns the establishment of the
--                  first baseline. Partial rows do not count as a completed
--                  remote dataset, and only the current claimant may mutate.
--   * completed  - a durable, permanent establishment event. An account with a
--                  completed baseline is established even with zero rows, and
--                  can never be claimed as unused again.
--
--   * public.planner_sync_account_state()  - authoritative discovery of that
--     state, plus a monotonic baseline token (sync_state.next_change_id) and
--     the caller's claim lease.
--   * public.planner_claim_initial_baseline()  - one atomic emptiness + baseline
--     compare-and-set that also serializes baseline establishment, renews the
--     current owner, and only ever hands a claim to a device the server judges
--     safe (live foreign claim -> held; expired foreign claim with partial
--     history -> explicit recovery required).
--   * public.planner_complete_initial_baseline()  - durably records that the
--     claimed baseline is established, including for an empty account.
--   * public.apply_sync_operation()     - the historical v1 entry point, kept
--     for compatibility and fenced exactly like v2 while a first baseline is in
--     progress, so no authenticated mutation surface can bypass the protocol.
--   * public.apply_sync_operation_v2()  - ordinary synchronization, now fenced
--     while a first baseline is in progress.
--   * public.apply_sync_operation_v3()  - the fenced mutation entry point of the
--     current claimant during the initial baseline upload; every accepted
--     mutation renews that claimant's lease, so a long upload cannot silently
--     cross the lease deadline. It is strictly an in-progress entry point: once
--     the baseline is completed it refuses every call, including the completing
--     device's, so a replaced token can never become a mutation capability.
--
-- All entry points are RPC-only (security definer, auth.uid() scoped, fixed
-- search_path) and remain client-safe: they expose counts and the caller's own
-- claim token, never another account's data and never a credential.

create table if not exists public.sync_initial_baseline (
  user_id uuid primary key references auth.users(id) on delete cascade,
  claim_token uuid not null,
  observed_next_change_id bigint not null,
  claimed_at timestamptz not null default timezone('utc', clock_timestamp()),
  completed_at timestamptz,
  constraint sync_initial_baseline_observed_valid check (
    observed_next_change_id > 0
  )
);

alter table public.sync_initial_baseline enable row level security;
revoke all on table public.sync_initial_baseline from public, anon, authenticated;
drop policy if exists sync_initial_baseline_select on public.sync_initial_baseline;
create policy sync_initial_baseline_select on public.sync_initial_baseline
  for select to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- Single source of truth for the claim lease. The lease exists so an abandoned
-- claim can eventually be taken over; it is never authority on its own, because
-- every decision below runs under the account row lock.
create or replace function public.planner_initial_baseline_lease()
returns interval
language sql
immutable
set search_path = public, pg_temp
as $$
  select interval '15 minutes'
$$;

revoke all on function public.planner_initial_baseline_lease()
  from public, anon, authenticated;

-- Durable evidence that this account ever accepted Planner data.
--
-- Conservative on purpose: accepted change rows (including tombstones),
-- live domain rows and soft-deleted domain rows all count. A partially
-- provisioned account whose every operation was rejected has no change rows,
-- no domain rows and therefore no Planner history, which is exactly the
-- protocol semantics that make "unused" provable.
create or replace function public.planner_account_has_history()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
      select 1 from public.sync_changes c
      where c.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.categories x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.tags x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.recurring_rules x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.tasks x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.task_templates x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.subtasks x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.task_tags x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.daily_reviews x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.weekly_reviews x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.timer_sessions x
      where x.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.day_contexts x
      where x.user_id = (select auth.uid())
    );
$$;

revoke all on function public.planner_account_has_history()
  from public, anon, authenticated;

-- Authoritative remote-state discovery.
--
-- `baseline_state` is the protocol state, `established` is the decision the
-- client must use: a completed baseline establishes the account even with zero
-- Planner rows, and durable pre-Phase-G Planner history establishes a legacy
-- account that must never be treated as an in-progress first upload.
create or replace function public.planner_sync_account_state()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  domain_table text;
  baseline_row public.sync_initial_baseline%rowtype;
  live_rows jsonb := '{}'::jsonb;
  tombstoned_rows jsonb := '{}'::jsonb;
  live_count bigint;
  tombstone_count bigint;
  live_total bigint := 0;
  tombstone_total bigint := 0;
  change_total bigint;
  next_change bigint;
  next_version bigint;
  history boolean;
  state_name text;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  foreach domain_table in array array[
    'categories', 'tags', 'recurring_rules', 'tasks', 'task_templates',
    'subtasks', 'task_tags', 'daily_reviews', 'weekly_reviews',
    'timer_sessions', 'day_contexts'
  ] loop
    execute format(
      'select count(*) filter (where deleted_at is null), '
      'count(*) filter (where deleted_at is not null) '
      'from public.%I where user_id = %L',
      domain_table, caller)
      into live_count, tombstone_count;
    live_rows := live_rows || jsonb_build_object(domain_table, live_count);
    tombstoned_rows := tombstoned_rows
      || jsonb_build_object(domain_table, tombstone_count);
    live_total := live_total + live_count;
    tombstone_total := tombstone_total + tombstone_count;
  end loop;

  select count(*) into change_total
  from public.sync_changes c where c.user_id = caller;

  select s.next_change_id, s.next_server_version
    into next_change, next_version
  from public.sync_state s
  where s.user_id = caller;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  history := public.planner_account_has_history();
  state_name := case
    when baseline_row.user_id is null then 'none'
    when baseline_row.completed_at is not null then 'completed'
    else 'in_progress'
  end;

  return jsonb_build_object(
    'has_history', history,
    'baseline_state', state_name,
    -- An account is established by a completed baseline (even with zero rows)
    -- or by durable pre-Phase-G Planner history. An in-progress first baseline
    -- is explicitly NOT established, so its partial rows can never be mistaken
    -- for a completed remote dataset.
    'established',
      state_name = 'completed'
      or (state_name = 'none' and history),
    'next_change_id', coalesce(next_change, 1),
    'next_server_version', coalesce(next_version, 1),
    'change_count', coalesce(change_total, 0),
    'live_row_total', live_total,
    'tombstoned_row_total', tombstone_total,
    'live_rows', live_rows,
    'tombstoned_rows', tombstoned_rows,
    'initial_baseline', case
      when baseline_row.user_id is null then null
      else jsonb_build_object(
        'token', baseline_row.claim_token,
        'observed_next_change_id', baseline_row.observed_next_change_id,
        'claimed_at', baseline_row.claimed_at,
        'completed_at', baseline_row.completed_at,
        'expired',
          baseline_row.completed_at is null
          and baseline_row.claimed_at
            + public.planner_initial_baseline_lease()
            <= timezone('utc', clock_timestamp()),
        'lease_expires_at',
          baseline_row.claimed_at + public.planner_initial_baseline_lease()
      )
    end
  );
end;
$$;

-- Atomic baseline claim.
--
-- Decision order is deliberate:
--   1. the current owner re-claiming the same token resumes and renews, even
--      when its own partial upload already produced history;
--   2. a completed baseline is permanent and can never be claimed again;
--   3. a live foreign claim blocks this caller;
--   4. an expired foreign claim is only taken over when the server can prove
--      nothing was uploaded under it - otherwise the caller is told that
--      explicit recovery is required;
--   5. otherwise the account must be provably unused (no history) and the
--      observed baseline must still match.
create or replace function public.planner_claim_initial_baseline(
  p_claim_token uuid,
  p_observed_next_change_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  current_change_id bigint;
  baseline_row public.sync_initial_baseline%rowtype;
  server_now timestamptz := timezone('utc', clock_timestamp());
  history boolean;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_claim_token is null then
    raise exception using errcode = '22023',
      message = 'Initial baseline claim token is required';
  end if;
  if p_observed_next_change_id is null or p_observed_next_change_id < 1 then
    raise exception using errcode = '22023',
      message = 'Observed initial baseline is required';
  end if;

  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  select s.next_change_id into current_change_id
  from public.sync_state s
  where s.user_id = caller
  for update;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  -- 1. The same device resumes (and renews) its own incomplete claim. This must
  --    precede the history check: this device's own earlier uploads legitimately
  --    make the account non-empty.
  if baseline_row.user_id is not null
     and baseline_row.claim_token = p_claim_token
     and baseline_row.completed_at is null then
    update public.sync_initial_baseline
    set claimed_at = server_now
    where user_id = caller;
    return jsonb_build_object(
      'status', 'claimed',
      'next_change_id', current_change_id,
      'claim_token', p_claim_token,
      'resumed', true
    );
  end if;

  -- 2. A completed baseline is a permanent establishment event.
  if baseline_row.user_id is not null
     and baseline_row.completed_at is not null then
    return jsonb_build_object(
      'status', 'remote_in_use',
      'baseline_state', 'completed',
      'next_change_id', current_change_id
    );
  end if;

  history := public.planner_account_has_history();

  -- 3./4. A foreign claim already owns establishment of the first baseline.
  if baseline_row.user_id is not null then
    if baseline_row.claimed_at
       + public.planner_initial_baseline_lease() > server_now then
      return jsonb_build_object(
        'status', 'claim_held',
        'next_change_id', current_change_id,
        'claim_token', baseline_row.claim_token,
        'claimed_at', baseline_row.claimed_at
      );
    end if;
    -- The lease lapsed, but the server cannot prove the abandoned claim never
    -- uploaded anything. Taking over would silently adopt a partial dataset.
    if history
       or current_change_id is distinct
            from baseline_row.observed_next_change_id then
      return jsonb_build_object(
        'status', 'recovery_required',
        'next_change_id', current_change_id,
        'claim_token', baseline_row.claim_token,
        'claimed_at', baseline_row.claimed_at
      );
    end if;
    if current_change_id is distinct from p_observed_next_change_id then
      return jsonb_build_object(
        'status', 'baseline_changed',
        'next_change_id', current_change_id
      );
    end if;
    update public.sync_initial_baseline
    set claim_token = p_claim_token,
        observed_next_change_id = current_change_id,
        claimed_at = server_now,
        completed_at = null
    where user_id = caller;
    return jsonb_build_object(
      'status', 'claimed',
      'next_change_id', current_change_id,
      'claim_token', p_claim_token,
      'resumed', false,
      'took_over_expired_claim', true
    );
  end if;

  -- 5. No claim exists. Durable Planner history means this is a legacy account
  --    that predates the Phase G baseline record: established, never reclaimable
  --    as an unused account.
  if history then
    return jsonb_build_object(
      'status', 'remote_in_use',
      'baseline_state', 'legacy',
      'next_change_id', current_change_id
    );
  end if;

  if current_change_id is distinct from p_observed_next_change_id then
    -- Another writer changed the account between discovery and this claim.
    return jsonb_build_object(
      'status', 'baseline_changed',
      'next_change_id', current_change_id
    );
  end if;

  insert into public.sync_initial_baseline(
    user_id, claim_token, observed_next_change_id, claimed_at, completed_at
  ) values (
    caller, p_claim_token, current_change_id, server_now, null
  )
  on conflict (user_id) do update
    set claim_token = excluded.claim_token,
        observed_next_change_id = excluded.observed_next_change_id,
        claimed_at = excluded.claimed_at,
        completed_at = null;

  return jsonb_build_object(
    'status', 'claimed',
    'next_change_id', current_change_id,
    'claim_token', p_claim_token,
    'resumed', false
  );
end;
$$;

-- Records that the claimed baseline is established. Only the current claim token
-- may complete it; a completed row is idempotent for its own token.
create or replace function public.planner_complete_initial_baseline(
  p_claim_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  server_now timestamptz := timezone('utc', clock_timestamp());
  baseline_row public.sync_initial_baseline%rowtype;
  next_change bigint;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_claim_token is null then
    raise exception using errcode = '22023',
      message = 'Initial baseline claim token is required';
  end if;

  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;
  select s.next_change_id into next_change
  from public.sync_state s
  where s.user_id = caller;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  if baseline_row.user_id is null
     or baseline_row.claim_token is distinct from p_claim_token then
    return jsonb_build_object('status', 'unknown_claim');
  end if;

  if baseline_row.completed_at is null then
    update public.sync_initial_baseline
    set completed_at = server_now
    where user_id = caller and claim_token = p_claim_token;
  end if;

  return jsonb_build_object(
    'status', 'completed',
    'next_change_id', coalesce(next_change, 1)
  );
end;
$$;

-- Split the existing v2 entry point so ordinary synchronization can be fenced
-- while - and only while - a first baseline is in progress. The base keeps every
-- unchanged validation, CAS, tombstone, title-history and idempotency rule.
alter function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) rename to apply_sync_operation_v2_prebaseline_base;
revoke all on function public.apply_sync_operation_v2_prebaseline_base(
  uuid, text, text, text, bigint, jsonb, integer
) from public, anon, authenticated;

create or replace function public.apply_sync_operation_v2(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb,
  p_payload_version integer default 2
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  baseline_row public.sync_initial_baseline%rowtype;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Serialize with claim, renewal, takeover and completion.
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  -- Fencing: while a first baseline is in progress only its fenced claimant may
  -- mutate (through apply_sync_operation_v3). An untokened ordinary mutation is
  -- refused, so a stale or unrelated writer can never add Planner data to an
  -- account whose baseline another device owns.
  if baseline_row.user_id is not null
     and baseline_row.completed_at is null then
    raise exception using errcode = 'P0001',
      message = 'No active initial baseline claim: this account is being established by a fenced first synchronization';
  end if;

  return public.apply_sync_operation_v2_prebaseline_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, p_payload, p_payload_version
  );
end;
$$;

revoke all on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) from public, anon;
grant execute on function public.apply_sync_operation_v2(
  uuid, text, text, text, bigint, jsonb, integer
) to authenticated;

-- Split the historical v1 entry point as well. Every authenticated mutation
-- surface has to be fenced while a first baseline is in progress: leaving v1
-- callable would let any authenticated client write Planner data without ever
-- participating in the baseline protocol.
alter function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) rename to apply_sync_operation_v1_prebaseline_base;
revoke all on function public.apply_sync_operation_v1_prebaseline_base(
  uuid, text, text, text, bigint, jsonb
) from public, anon, authenticated;

create or replace function public.apply_sync_operation(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  baseline_row public.sync_initial_baseline%rowtype;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Serialize with claim, renewal, takeover, completion and the other mutation
  -- entry points through the same account row lock.
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  -- Same invariant as v2: while a first baseline is in progress no untokened
  -- mutation path may touch Planner data. Historical v1 keeps its signature and
  -- its unchanged behaviour when no baseline is in progress.
  if baseline_row.user_id is not null
     and baseline_row.completed_at is null then
    raise exception using errcode = 'P0001',
      message = 'No active initial baseline claim: this account is being established by a fenced first synchronization';
  end if;

  return public.apply_sync_operation_v1_prebaseline_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, p_payload
  );
end;
$$;

revoke all on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) from public, anon;
grant execute on function public.apply_sync_operation(
  uuid, text, text, text, bigint, jsonb
) to authenticated;

-- Fenced mutation entry point of the current initial-baseline claimant.
--
-- v3 is strictly the entry point of the *in-progress* first baseline. It never
-- becomes a general authorization bypass: once the baseline is completed the
-- call is refused and ordinary synchronization must use v2. That closes the
-- stale-owner path where device A keeps a replaced token and tries to mutate
-- after device B took over and completed the baseline.
--
-- The token is resolved under the authenticated account only; a client can
-- never name another account. Every accepted mutation renews the claimant's
-- lease with the server clock, so a long upload cannot silently cross the lease
-- deadline, while a takeover replaces the token and fences the previous owner.
create or replace function public.apply_sync_operation_v3(
  p_operation_id uuid,
  p_table_name text,
  p_record_id text,
  p_operation text,
  p_expected_server_version bigint,
  p_payload jsonb,
  p_payload_version integer,
  p_baseline_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  baseline_row public.sync_initial_baseline%rowtype;
  server_now timestamptz := timezone('utc', clock_timestamp());
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_baseline_token is null then
    raise exception using errcode = '22023',
      message = 'Initial baseline claim token is required';
  end if;

  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  select * into baseline_row
  from public.sync_initial_baseline b
  where b.user_id = caller;

  if baseline_row.user_id is null then
    raise exception using errcode = 'P0001',
      message = 'No active initial baseline claim for this account';
  end if;

  if baseline_row.completed_at is not null then
    -- A completed baseline is never a v3 mutation capability. A caller holding
    -- a token that was replaced by a takeover - or the token of the completing
    -- device itself - must use ordinary synchronization (v2), where the normal
    -- operation-id idempotency, CAS and conflict rules apply. Refusing here is
    -- what makes a stale token harmless after ownership loss.
    raise exception using errcode = 'P0001',
      message = 'Initial baseline claim is no longer active: the baseline is already completed; use ordinary synchronization';
  end if;

  if baseline_row.claim_token is distinct from p_baseline_token then
    raise exception using errcode = 'P0001',
      message = 'Initial baseline claim is no longer owned by this device';
  end if;

  update public.sync_initial_baseline
  set claimed_at = server_now
  where user_id = caller and claim_token = p_baseline_token;

  return public.apply_sync_operation_v2_prebaseline_base(
    p_operation_id, p_table_name, p_record_id, p_operation,
    p_expected_server_version, p_payload, p_payload_version
  );
end;
$$;

revoke all on function public.apply_sync_operation_v3(
  uuid, text, text, text, bigint, jsonb, integer, uuid
) from public, anon;
grant execute on function public.apply_sync_operation_v3(
  uuid, text, text, text, bigint, jsonb, integer, uuid
) to authenticated;

revoke all on function public.planner_sync_account_state() from public, anon;
grant execute on function public.planner_sync_account_state() to authenticated;
revoke all on function public.planner_claim_initial_baseline(uuid, bigint)
  from public, anon;
grant execute on function public.planner_claim_initial_baseline(uuid, bigint)
  to authenticated;
revoke all on function public.planner_complete_initial_baseline(uuid)
  from public, anon;
grant execute on function public.planner_complete_initial_baseline(uuid)
  to authenticated;

-- Advertise the Phase G protocol capability. Existing clients keep working:
-- every earlier capability key is unchanged, and ordinary synchronization
-- (apply_sync_operation_v2) keeps its signature, so a client that does not know
-- about fencing is unaffected once the account is established.
create or replace function public.planner_sync_capabilities()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'protocol_version', 2,
    'schedule_duration_projection', true,
    'inbox_content_version', true,
    'due_date', true,
    'manual_actual_source', true,
    'timer_state_machine', true,
    'day_contexts', true,
    'plan_title_history', true,
    'recurrence_removal_provenance', true,
    'initial_sync_baseline', true,
    'initial_sync_fencing', true,
    'payload_versions', jsonb_build_array(1, 2)
  )
$$;

revoke all on function public.planner_sync_capabilities() from public, anon;
grant execute on function public.planner_sync_capabilities() to authenticated;
