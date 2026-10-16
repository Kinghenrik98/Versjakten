-- ===== Versjakten: adminsida =====
-- Admin = en vanlig profil med is_admin = true. Adminsidan använder koden som redan finns sparad på telefonen.
alter table profiles add column if not exists is_admin boolean not null default false;
update profiles set is_admin = true where id = 'c8da86cb-1e6c-41af-a802-0c989f35f151';  -- Henke

create or replace function vj_admin_id(p_code text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  select p.id into v from profiles p where p.code = upper(btrim(p_code)) and p.is_admin;
  if v is null then raise exception 'Ingen behörighet'; end if;
  return v;
end $$;
revoke all on function vj_admin_id(text) from public, anon, authenticated;

create or replace function admin_users(p_code text)
returns table(id uuid, name text, emoji text, church text, church_id bigint, city text, created_at timestamptz,
  rounds bigint, points bigint, last_day date, days bigint, mara_best int, groups bigint, is_admin boolean)
language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  return query
  select p.id, p.name, p.emoji, p.church, p.church_id, p.city, p.created_at,
    (select count(*) from beta_scores s where s.profile_id = p.id),
    (select coalesce(sum(s.points),0) from beta_scores s where s.profile_id = p.id),
    (select max(s.day) from beta_scores s where s.profile_id = p.id),
    (select count(distinct s.day) from beta_scores s where s.profile_id = p.id),
    (select max(m.length) from marathon_runs m where m.profile_id = p.id),
    (select count(*) from group_members g where g.profile_id = p.id),
    p.is_admin
  from profiles p order by p.created_at desc;
end $$;

create or replace function admin_churches(p_code text)
returns table(id bigint, name text, city text, approved boolean, created_by_name text, created_at timestamptz, members bigint)
language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  return query
  select c.id, c.name, c.city, c.approved, (select p.name from profiles p where p.id = c.created_by), c.created_at,
    (select count(*) from profiles p where p.church_id = c.id)
  from churches c order by c.approved, c.created_at desc;
end $$;

create or replace function admin_save_church(p_code text, p_id bigint, p_name text, p_city text, p_approved boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  p_name := btrim(p_name); p_city := btrim(p_city);
  if length(p_name) < 2 or length(p_city) < 2 then raise exception 'Namn och ort måste fyllas i'; end if;
  if p_id is null then
    insert into churches(name, city, approved) values (p_name, p_city, coalesce(p_approved,true));
  else
    update churches set name = p_name, city = p_city, approved = p_approved where churches.id = p_id;
    update profiles set church = vj_church_label(p_id) where church_id = p_id;
  end if;
end $$;

-- Slå ihop: alla medlemmar flyttas till p_into, p_from tas bort
create or replace function admin_merge_church(p_code text, p_from bigint, p_into bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  if p_from = p_into then raise exception 'Välj två olika församlingar'; end if;
  if not exists (select 1 from churches where churches.id = p_into) then raise exception 'Okänd församling'; end if;
  update profiles set church_id = p_into, church = vj_church_label(p_into) where church_id = p_from;
  delete from churches where churches.id = p_from;
end $$;

-- Neka ett förslag: medlemmarna blir utan församling, förslaget tas bort
create or replace function admin_reject_church(p_code text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  update profiles set church_id = null, church = null where church_id = p_id;
  delete from churches where churches.id = p_id;
end $$;

-- Sätt församling/ort på en användare (t.ex. för att städa)
create or replace function admin_set_user_church(p_code text, p_user uuid, p_church_id bigint, p_city text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vj_admin_id(p_code);
  update profiles set church_id = p_church_id, church = vj_church_label(p_church_id),
    city = nullif(btrim(coalesce(p_city,'')),'') where profiles.id = p_user;
end $$;

grant execute on function admin_users(text), admin_churches(text), admin_save_church(text,bigint,text,text,boolean),
  admin_merge_church(text,bigint,bigint), admin_reject_church(text,bigint), admin_set_user_church(text,uuid,bigint,text)
  to anon, authenticated;
