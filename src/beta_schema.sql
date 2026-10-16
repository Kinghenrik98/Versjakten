-- ===== Versjakten BETA =====
create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  church text,
  emoji text,
  code text unique not null,
  created_at timestamptz default now()
);
create table if not exists groups (
  id bigint generated always as identity primary key,
  name text not null,
  emoji text,
  code text unique not null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz default now()
);
create table if not exists group_members (
  group_id bigint references groups(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, profile_id)
);
create table if not exists beta_scores (
  id bigint generated always as identity primary key,
  profile_id uuid references profiles(id) on delete cascade,
  day date not null,
  round int not null,
  attempts int,
  solved boolean not null,
  points int not null,
  guesses jsonb,
  created_at timestamptz default now(),
  unique (profile_id, day, round)
);

alter table profiles enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table beta_scores enable row level security;

create policy "läs profiler" on profiles for select using (true);
create policy "läs grupper" on groups for select using (true);
create policy "läs medlemmar" on group_members for select using (true);
create policy "läs betaresultat" on beta_scores for select using (true);

-- Koder får aldrig läsas direkt
revoke all on profiles, groups, group_members, beta_scores from anon, authenticated;
grant select (id, name, church, emoji, created_at) on profiles to anon, authenticated;
grant select (id, name, emoji, created_by, created_at) on groups to anon, authenticated;
grant select on group_members, beta_scores to anon, authenticated;

-- Hjälpfunktion: slumpkod
create or replace function vj_rand(n int) returns text language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random()*32)+1)::int, 1), '')
  from generate_series(1, n);
$$;

create or replace function create_profile(p_name text, p_church text, p_emoji text)
returns table(id uuid, code text) language plpgsql security definer set search_path = public as $$
declare v_code text; v_pre text; v_id uuid;
begin
  p_name := btrim(p_name); p_church := nullif(btrim(coalesce(p_church,'')),'');
  if length(p_name) < 2 or length(p_name) > 20 then raise exception 'Namnet måste vara 2–20 tecken'; end if;
  if p_church is not null and length(p_church) > 60 then raise exception 'För långt församlingsnamn'; end if;
  v_pre := upper(left(regexp_replace(translate(p_name,'åäöÅÄÖéÉ','aaoAAOeE'),'[^A-Za-z]','','g'),6));
  if length(v_pre) < 2 then v_pre := 'VJ'; end if;
  loop
    v_code := v_pre || '-' || vj_rand(3);
    exit when not exists (select 1 from profiles p where p.code = v_code);
  end loop;
  insert into profiles(name, church, emoji, code) values (p_name, p_church, left(coalesce(p_emoji,''),8), v_code) returning profiles.id into v_id;
  return query select v_id, v_code;
end $$;

create or replace function login_profile(p_code text)
returns table(id uuid, name text, church text, emoji text, code text) language sql security definer set search_path = public as $$
  select p.id, p.name, p.church, p.emoji, p.code from profiles p where p.code = upper(btrim(p_code));
$$;

create or replace function update_profile(p_code text, p_name text, p_church text, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
begin
  p_name := btrim(p_name); p_church := nullif(btrim(coalesce(p_church,'')),'');
  if length(p_name) < 2 or length(p_name) > 20 then raise exception 'Namnet måste vara 2–20 tecken'; end if;
  update profiles set name = p_name, church = left(p_church,60), emoji = left(coalesce(p_emoji,''),8) where code = upper(btrim(p_code));
  if not found then raise exception 'Okänd kod'; end if;
end $$;

create or replace function submit_score(p_code text, p_day date, p_round int, p_attempts int, p_solved boolean, p_points int, p_guesses jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_today date := (now() at time zone 'Europe/Stockholm')::date;
begin
  select p.id into v_id from profiles p where p.code = upper(btrim(p_code));
  if v_id is null then raise exception 'Okänd kod'; end if;
  if p_day < v_today - 1 or p_day > v_today + 1 then raise exception 'Fel dag'; end if;
  if p_round not between 1 and 3 or p_points not in (0,5,8,10,15,25,35,50) then raise exception 'Ogiltigt resultat'; end if;
  insert into beta_scores(profile_id, day, round, attempts, solved, points, guesses)
  values (v_id, p_day, p_round, p_attempts, p_solved, p_points, p_guesses)
  on conflict (profile_id, day, round) do nothing;
  if found then return 'ok'; else return 'exists'; end if;
end $$;

create or replace function create_group(p_code text, p_name text, p_emoji text)
returns table(id bigint, code text) language plpgsql security definer set search_path = public as $$
declare v_pid uuid; v_gid bigint; v_code text;
begin
  select p.id into v_pid from profiles p where p.code = upper(btrim(p_code));
  if v_pid is null then raise exception 'Okänd kod'; end if;
  p_name := btrim(p_name);
  if length(p_name) < 2 or length(p_name) > 40 then raise exception 'Gruppnamnet måste vara 2–40 tecken'; end if;
  loop
    v_code := vj_rand(3) || '-' || vj_rand(3);
    exit when not exists (select 1 from groups g where g.code = v_code);
  end loop;
  insert into groups(name, emoji, code, created_by) values (p_name, left(coalesce(p_emoji,''),8), v_code, v_pid) returning groups.id into v_gid;
  insert into group_members(group_id, profile_id) values (v_gid, v_pid);
  return query select v_gid, v_code;
end $$;

create or replace function join_group(p_code text, p_group_code text)
returns table(id bigint, name text) language plpgsql security definer set search_path = public as $$
declare v_pid uuid; v_gid bigint; v_name text;
begin
  select p.id into v_pid from profiles p where p.code = upper(btrim(p_code));
  if v_pid is null then raise exception 'Okänd kod'; end if;
  select g.id, g.name into v_gid, v_name from groups g where g.code = upper(btrim(p_group_code));
  if v_gid is null then raise exception 'Hittade ingen grupp med den koden'; end if;
  insert into group_members(group_id, profile_id) values (v_gid, v_pid) on conflict do nothing;
  return query select v_gid, v_name;
end $$;

create or replace function leave_group(p_code text, p_group_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_pid uuid;
begin
  select p.id into v_pid from profiles p where p.code = upper(btrim(p_code));
  if v_pid is null then raise exception 'Okänd kod'; end if;
  delete from group_members where group_id = p_group_id and profile_id = v_pid;
end $$;

create or replace function my_groups(p_code text)
returns table(id bigint, name text, emoji text, code text) language sql security definer set search_path = public as $$
  select g.id, g.name, g.emoji, g.code from groups g
  join group_members m on m.group_id = g.id
  join profiles p on p.id = m.profile_id
  where p.code = upper(btrim(p_code)) order by g.name;
$$;

revoke all on function vj_rand(int) from public, anon, authenticated;
grant execute on function create_profile(text,text,text), login_profile(text), update_profile(text,text,text,text),
  submit_score(text,date,int,int,boolean,int,jsonb), create_group(text,text,text), join_group(text,text),
  leave_group(text,bigint), my_groups(text) to anon, authenticated;
