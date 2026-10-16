-- ===== Versjakten BETA: gruppverser + gruppchatt =====
create table if not exists group_scores (
  id bigint generated always as identity primary key,
  group_id bigint references groups(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  day date not null,
  round int not null,
  attempts int,
  solved boolean not null,
  points int not null,
  guesses jsonb,
  created_at timestamptz default now(),
  unique (group_id, profile_id, day, round)
);
alter table group_scores enable row level security;
drop policy if exists "läs gruppresultat" on group_scores;
create policy "läs gruppresultat" on group_scores for select using (true);
revoke all on group_scores from anon, authenticated;
grant select on group_scores to anon, authenticated;

create table if not exists group_messages (
  id bigint generated always as identity primary key,
  group_id bigint references groups(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  kind text not null default 'msg' check (kind in ('msg','result','prayer')),
  body text not null check (length(body) between 1 and 500),
  spoiler boolean not null default false,
  created_at timestamptz default now()
);
create index if not exists group_messages_g on group_messages (group_id, id);
alter table group_messages enable row level security;
revoke all on group_messages from anon, authenticated;   -- bara via funktionerna nedan (medlemmar)

create table if not exists message_reactions (
  message_id bigint references group_messages(id) on delete cascade,
  profile_id uuid references profiles(id) on delete cascade,
  emoji text not null check (emoji in ('🙏','❤️','🔥','😂','👏')),
  primary key (message_id, profile_id, emoji)
);
alter table message_reactions enable row level security;
revoke all on message_reactions from anon, authenticated;

-- Kontroll: koden finns och personen är med i gruppen
create or replace function vj_member(p_code text, p_group bigint) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  select p.id into v from profiles p join group_members m on m.profile_id = p.id
  where p.code = upper(btrim(p_code)) and m.group_id = p_group;
  if v is null then raise exception 'Du är inte med i gruppen'; end if;
  return v;
end $$;
revoke all on function vj_member(text,bigint) from public, anon, authenticated;

create or replace function submit_group_score(p_code text, p_group bigint, p_day date, p_round int,
  p_attempts int, p_solved boolean, p_points int, p_guesses jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare v uuid; v_today date := (now() at time zone 'Europe/Stockholm')::date;
begin
  v := vj_member(p_code, p_group);
  if p_day < v_today - 1 or p_day > v_today + 1 then raise exception 'Fel dag'; end if;
  if p_round not between 1 and 5 or p_points not in (0,5,8,10,15,25,35,50) then raise exception 'Ogiltigt resultat'; end if;
  insert into group_scores(group_id, profile_id, day, round, attempts, solved, points, guesses)
  values (p_group, v, p_day, p_round, p_attempts, p_solved, p_points, p_guesses)
  on conflict (group_id, profile_id, day, round) do nothing;
  if found then return 'ok'; else return 'exists'; end if;
end $$;

create or replace function get_messages(p_code text, p_group bigint)
returns table(id bigint, profile_id uuid, kind text, body text, spoiler boolean, created_at timestamptz, reactions jsonb)
language plpgsql security definer set search_path = public as $$
begin
  perform vj_member(p_code, p_group);
  return query
  select m.id, m.profile_id, m.kind, m.body, m.spoiler, m.created_at,
    coalesce((select jsonb_object_agg(x.emoji, x.who) from
      (select r.emoji, jsonb_agg(r.profile_id) as who from message_reactions r where r.message_id = m.id group by r.emoji) x), '{}'::jsonb)
  from (select * from group_messages g where g.group_id = p_group order by g.id desc limit 150) m
  order by m.id;
end $$;

create or replace function send_message(p_code text, p_group bigint, p_body text, p_kind text, p_spoiler boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v uuid; v_id bigint;
begin
  v := vj_member(p_code, p_group);
  p_body := btrim(coalesce(p_body,''));
  if length(p_body) < 1 or length(p_body) > 500 then raise exception 'Meddelandet måste vara 1–500 tecken'; end if;
  if coalesce(p_kind,'msg') not in ('msg','result','prayer') then raise exception 'Ogiltig typ'; end if;
  if exists (select 1 from group_messages g where g.profile_id = v and g.created_at > now() - interval '2 seconds') then
    raise exception 'Lugn i stormen – vänta en sekund'; end if;
  insert into group_messages(group_id, profile_id, kind, body, spoiler)
  values (p_group, v, coalesce(p_kind,'msg'), p_body, coalesce(p_spoiler,false)) returning group_messages.id into v_id;
  return v_id;
end $$;

create or replace function react_message(p_code text, p_message bigint, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid; v_group bigint;
begin
  select g.group_id into v_group from group_messages g where g.id = p_message;
  if v_group is null then raise exception 'Meddelandet finns inte'; end if;
  v := vj_member(p_code, v_group);
  if exists (select 1 from message_reactions r where r.message_id = p_message and r.profile_id = v and r.emoji = p_emoji) then
    delete from message_reactions r where r.message_id = p_message and r.profile_id = v and r.emoji = p_emoji;
  else
    insert into message_reactions(message_id, profile_id, emoji) values (p_message, v, p_emoji);
  end if;
end $$;

-- Ta bort: avsändaren, gruppens skapare eller admin
create or replace function delete_message(p_code text, p_message bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid; v_admin boolean; v_group bigint; v_sender uuid; v_owner uuid;
begin
  select p.id, p.is_admin into v, v_admin from profiles p where p.code = upper(btrim(p_code));
  if v is null then raise exception 'Okänd kod'; end if;
  select g.group_id, g.profile_id into v_group, v_sender from group_messages g where g.id = p_message;
  if v_group is null then return; end if;
  select gr.created_by into v_owner from groups gr where gr.id = v_group;
  if v <> v_sender and v is distinct from v_owner and not v_admin then raise exception 'Du får inte ta bort det här'; end if;
  delete from group_messages where group_messages.id = p_message;
end $$;

-- Senaste meddelande per grupp (för "nya meddelanden"-prickar)
create or replace function my_group_activity(p_code text)
returns table(group_id bigint, last_id bigint, created_by uuid)
language sql stable security definer set search_path = public as $$
  select m.group_id, (select max(g.id) from group_messages g where g.group_id = m.group_id),
    (select gr.created_by from groups gr where gr.id = m.group_id)
  from group_members m join profiles p on p.id = m.profile_id
  where p.code = upper(btrim(p_code));
$$;

grant execute on function submit_group_score(text,bigint,date,int,int,boolean,int,jsonb), get_messages(text,bigint),
  send_message(text,bigint,text,text,boolean), react_message(text,bigint,text), delete_message(text,bigint),
  my_group_activity(text) to anon, authenticated;
