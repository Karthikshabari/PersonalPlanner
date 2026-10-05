begin;

-- DB-028: bounded server sync history.
--
-- Compaction, not truncation. A sync_changes row is deleted only when it is
-- neither the first nor the latest change for its (user_id, table_name,
-- record_id) and it is older than 90 days. Every record keeps its head, so a
-- device with any cursor still converges, planner_account_has_history() still
-- sees history, and sync_state counters are never touched.
--
-- Every record also keeps its origin. The server only accepts a change whose
-- parents already exist, so each parent's first change precedes every change
-- that references it. Keeping first changes therefore keeps every prefix of
-- the feed closed under parent references: a fresh device (cursor 0) or one
-- with an old cursor still receives a parent before its children, even when
-- the parent's only other surviving change is a much later edit.
--
-- Acknowledgements are kept for 180 days, longer than change compaction, so a
-- retried operation whose feed row was compacted still receives its idempotent
-- acknowledgement. After that a retry surfaces as an ordinary CAS conflict,
-- never as a double apply.
--
-- Compaction never runs while a first baseline is in progress, and each call
-- deletes at most 5000 rows per table. The client invokes it best-effort after
-- a successful sync; there is no capability flag and no scheduled job.

-- Supports the "older/newer change for the same record" probes.
create index if not exists sync_changes_user_record_idx
  on public.sync_changes(user_id, table_name, record_id, change_id);

create or replace function public.planner_compact_sync_history()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := (select auth.uid());
  changes_cutoff timestamptz := clock_timestamp() - interval '90 days';
  acks_cutoff timestamptz := clock_timestamp() - interval '180 days';
  changes_deleted integer := 0;
  acks_deleted integer := 0;
begin
  if caller is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Account lock first: serializes with apply and the baseline claim/complete
  -- RPCs, so the baseline check below cannot race a concurrent claim.
  insert into public.sync_state(user_id) values (caller)
    on conflict (user_id) do nothing;
  perform 1 from public.sync_state s where s.user_id = caller for update;

  if exists (
    select 1
    from public.sync_initial_baseline b
    where b.user_id = caller
      and b.completed_at is null
  ) then
    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'baseline_in_progress',
      'changes_deleted', 0,
      'acks_deleted', 0
    );
  end if;

  delete from public.sync_changes c
  where c.user_id = caller
    and c.change_id in (
      select old.change_id
      from public.sync_changes old
      where old.user_id = caller
        and old.server_timestamp < changes_cutoff
        -- Not the record's latest change.
        and exists (
          select 1
          from public.sync_changes newer
          where newer.user_id = old.user_id
            and newer.table_name = old.table_name
            and newer.record_id = old.record_id
            and newer.change_id > old.change_id
        )
        -- Not the record's first change. First changes are never deleted, so
        -- an older surviving row exists exactly when this one is not first.
        and exists (
          select 1
          from public.sync_changes older
          where older.user_id = old.user_id
            and older.table_name = old.table_name
            and older.record_id = old.record_id
            and older.change_id < old.change_id
        )
      order by old.change_id
      limit 5000
    );
  get diagnostics changes_deleted = row_count;

  delete from public.sync_operation_ack a
  where a.user_id = caller
    and a.operation_id in (
      select old.operation_id
      from public.sync_operation_ack old
      where old.user_id = caller
        and old.created_at < acks_cutoff
      order by old.created_at, old.operation_id
      limit 5000
    );
  get diagnostics acks_deleted = row_count;

  return jsonb_build_object(
    'status', 'compacted',
    'changes_deleted', changes_deleted,
    'acks_deleted', acks_deleted
  );
end;
$$;

revoke all on function public.planner_compact_sync_history() from public, anon;
grant execute on function public.planner_compact_sync_history() to authenticated;

commit;
