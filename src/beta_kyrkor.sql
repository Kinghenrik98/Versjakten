-- ===== Versjakten BETA: församlingsregister + ort =====
create table if not exists churches (
  id bigint generated always as identity primary key,
  name text not null,
  city text not null,
  approved boolean not null default false,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz default now()
);
create unique index if not exists churches_uniq on churches (lower(name), lower(city));
alter table churches enable row level security;
drop policy if exists "läs kyrkor" on churches;
create policy "läs kyrkor" on churches for select using (true);
revoke all on churches from anon, authenticated;
grant select on churches to anon, authenticated;

alter table profiles add column if not exists church_id bigint references churches(id) on delete set null;
alter table profiles add column if not exists city text;
grant select (church_id, city) on profiles to anon, authenticated;

create or replace function vj_church_label(p_id bigint) returns text
language sql stable security definer set search_path = public as $$
  select case when position(lower(c.city) in lower(c.name)) > 0 then c.name else c.name || ' ' || c.city end
  from churches c where c.id = p_id;
$$;

-- Skapar (p_code = null) eller uppdaterar en profil
create or replace function save_profile(p_code text, p_name text, p_emoji text, p_church_id bigint,
  p_city text, p_new_church text, p_new_church_city text)
returns table(out_id uuid, out_code text, out_church_id bigint)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text; v_pre text; v_cid bigint;
begin
  p_name := btrim(coalesce(p_name,''));
  p_city := nullif(btrim(coalesce(p_city,'')),'');
  p_new_church := nullif(btrim(coalesce(p_new_church,'')),'');
  p_new_church_city := nullif(btrim(coalesce(p_new_church_city,'')),'');
  if length(p_name) < 2 or length(p_name) > 20 then raise exception 'Namnet måste vara 2–20 tecken'; end if;
  if p_city is not null and length(p_city) > 40 then raise exception 'För långt ortnamn'; end if;

  if p_code is null then
    v_pre := upper(left(regexp_replace(translate(p_name,'åäöÅÄÖéÉ','aaoAAOeE'),'[^A-Za-z]','','g'),6));
    if length(v_pre) < 2 then v_pre := 'VJ'; end if;
    loop
      v_code := v_pre || '-' || vj_rand(3);
      exit when not exists (select 1 from profiles p where p.code = v_code);
    end loop;
    insert into profiles(name, emoji, code) values (p_name, left(coalesce(p_emoji,''),8), v_code)
      returning profiles.id into v_id;
  else
    select p.id, p.code into v_id, v_code from profiles p where p.code = upper(btrim(p_code));
    if v_id is null then raise exception 'Okänd kod'; end if;
  end if;

  if p_new_church is not null then
    if length(p_new_church) < 2 or length(p_new_church) > 60 then raise exception 'Församlingens namn måste vara 2–60 tecken'; end if;
    if p_new_church_city is null or length(p_new_church_city) > 40 then raise exception 'Fyll i ort för den nya församlingen'; end if;
    select c.id into v_cid from churches c where lower(c.name) = lower(p_new_church) and lower(c.city) = lower(p_new_church_city);
    if v_cid is null then
      insert into churches(name, city, created_by) values (p_new_church, p_new_church_city, v_id) returning churches.id into v_cid;
    end if;
  elsif p_church_id is not null then
    select c.id into v_cid from churches c where c.id = p_church_id and (c.approved or c.created_by = v_id);
    if v_cid is null then raise exception 'Okänd församling'; end if;
  end if;

  update profiles set name = p_name, emoji = left(coalesce(p_emoji,''),8), city = p_city,
    church_id = v_cid, church = vj_church_label(v_cid)
  where profiles.id = v_id;
  return query select v_id, v_code, v_cid;
end $$;
grant execute on function save_profile(text,text,text,bigint,text,text,text) to anon, authenticated;

-- Flytta över dagens testare
insert into churches(name, city, approved) values ('Pingstkyrkan', 'Katrineholm', true) on conflict do nothing;
update profiles set church_id = (select id from churches where name = 'Pingstkyrkan' and city = 'Katrineholm'),
  city = 'Katrineholm', church = 'Pingstkyrkan Katrineholm'
  where id in ('305e4a4a-3c51-4d43-a2aa-76a407bc7256', 'c8da86cb-1e6c-41af-a802-0c989f35f151');
update profiles set city = 'Karlskoga', church = null where id = '563efd5c-5659-420a-95bf-7a36eff000a2';
update profiles set city = 'Kumla' where id = 'e3858522-c47c-4226-9206-dfe1ed4de319';
