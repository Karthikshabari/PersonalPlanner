begin;

-- Weekly review redesign: mood of the week (1 = Good ... 4 = Legendary) and
-- a short "How did the week feel?" text. Additive and backward compatible:
-- * columns are nullable, so older clients whose payloads omit the keys still
--   apply through jsonb_populate_record;
-- * a BEFORE UPDATE trigger keeps the stored value when an incoming row
--   carries NULL, so an older client's edit never erases mood or feeling.
--   Current clients send '' (never NULL) for an empty feeling, so clearing
--   the text still syncs;
-- * every statement is idempotent: the file may be applied by hand first and
--   again later by the provisioning Worker.

alter table public.weekly_reviews add column if not exists mood integer;
alter table public.weekly_reviews add column if not exists feeling text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'weekly_reviews_mood_valid'
      and conrelid = 'public.weekly_reviews'::regclass
  ) then
    alter table public.weekly_reviews
      add constraint weekly_reviews_mood_valid
      check (mood is null or mood between 1 and 4);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'weekly_reviews_feeling_valid'
      and conrelid = 'public.weekly_reviews'::regclass
  ) then
    alter table public.weekly_reviews
      add constraint weekly_reviews_feeling_valid
      check (feeling is null or char_length(feeling) <= 200);
  end if;
end
$$;

create or replace function public.planner_preserve_weekly_review_fields()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.mood is null then
    new.mood := old.mood;
  end if;
  if new.feeling is null then
    new.feeling := old.feeling;
  end if;
  return new;
end;
$$;

drop trigger if exists planner_preserve_weekly_review_fields on public.weekly_reviews;
create trigger planner_preserve_weekly_review_fields
  before update on public.weekly_reviews
  for each row execute function public.planner_preserve_weekly_review_fields();

revoke all on function public.planner_preserve_weekly_review_fields()
  from public, anon, authenticated;

commit;
