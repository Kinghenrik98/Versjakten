-- ===== Versjakten BETA: Maraton =====
create table if not exists marathon_runs (
  id bigint generated always as identity primary key,
  profile_id uuid references profiles(id) on delete cascade,
  length int not null,
  fell_on int,
  created_at timestamptz default now()
);
alter table marathon_runs enable row level security;
create policy "läs maraton" on marathon_runs for select using (true);
revoke all on marathon_runs from anon, authenticated;
grant select on marathon_runs to anon, authenticated;

create or replace function submit_marathon(p_code text, p_length int, p_fell_on int)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select p.id into v_id from profiles p where p.code = upper(btrim(p_code));
  if v_id is null then raise exception 'Okänd kod'; end if;
  if p_length < 1 or p_length > 2000 then raise exception 'Ogiltigt resultat'; end if;
  if exists (select 1 from marathon_runs m where m.profile_id = v_id and m.created_at > now() - interval '10 seconds') then
    raise exception 'För snabbt';
  end if;
  insert into marathon_runs(profile_id, length, fell_on) values (v_id, p_length, p_fell_on);
  return 'ok';
end $$;
grant execute on function submit_marathon(text,int,int) to anon, authenticated;
