begin;

-- Review redesign: mood of the day, per-task review reasons and plan-change
-- reasons. Additive and backward compatible:
-- * columns are nullable, so older clients whose payloads omit the keys still
--   apply through jsonb_populate_record;
-- * BEFORE UPDATE triggers keep the stored value when an incoming row carries
--   NULL, so an older client's edit never erases newer review data;
-- * every statement is idempotent: the file may be applied by hand first and
--   again later by the provisioning Worker.

alter table public.daily_reviews add column if not exists mood integer;
alter table public.daily_reviews add column if not exists task_reasons_json text;
alter table public.tasks add column if not exists plan_change_reasons_json text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'daily_reviews_mood_valid'
      and conrelid = 'public.daily_reviews'::regclass
  ) then
    alter table public.daily_reviews
      add constraint daily_reviews_mood_valid
      check (mood is null or mood between 1 and 4);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'daily_reviews_task_reasons_valid'
      and conrelid = 'public.daily_reviews'::regclass
  ) then
    alter table public.daily_reviews
      add constraint daily_reviews_task_reasons_valid
      check (
        task_reasons_json is null
        or jsonb_typeof(task_reasons_json::jsonb) = 'object'
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_plan_change_reasons_valid'
      and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks
      add constraint tasks_plan_change_reasons_valid
      check (
        plan_change_reasons_json is null
        or jsonb_typeof(plan_change_reasons_json::jsonb) = 'object'
      );
  end if;
end
$$;

create or replace function public.planner_preserve_review_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.mood is null then
    new.mood := old.mood;
  end if;
  if new.task_reasons_json is null then
    new.task_reasons_json := old.task_reasons_json;
  end if;
  return new;
end;
$$;

create or replace function public.planner_preserve_plan_change_reasons()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.plan_change_reasons_json is null then
    new.plan_change_reasons_json := old.plan_change_reasons_json;
  end if;
  return new;
end;
$$;

drop trigger if exists planner_preserve_review_fields on public.daily_reviews;
create trigger planner_preserve_review_fields
  before update on public.daily_reviews
  for each row execute function public.planner_preserve_review_fields();

drop trigger if exists planner_preserve_plan_change_reasons on public.tasks;
create trigger planner_preserve_plan_change_reasons
  before update on public.tasks
  for each row execute function public.planner_preserve_plan_change_reasons();

revoke all on function public.planner_preserve_review_fields()
  from public, anon, authenticated;
revoke all on function public.planner_preserve_plan_change_reasons()
  from public, anon, authenticated;

commit;
