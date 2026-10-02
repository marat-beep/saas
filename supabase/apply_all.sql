-- ============================================================
-- 3DMP Service · apply_all.sql — единый скрипт применения схемы
-- Собран из миграций 0001 + 0002 + 0003. Идемпотентен (можно запускать повторно).
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- После: логины admin/admin, owner/Owner12345, manager/Manager12345, supplier/Supplier12345.
-- ============================================================

-- >>>>>>>>>> 0001_init.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service В· 0001_init.sql
-- Р‘Р°Р·РѕРІР°СЏ СЃС…РµРјР° SaaS-СЃРµСЂРІРёСЃР°: РјСѓР»СЊС‚РёС‚РµРЅР°РЅС‚РЅРѕСЃС‚СЊ, РїСЂРѕС„РёР»Рё, С‡Р»РµРЅСЃС‚РІРѕ Рё RLS.
-- РџСЂРёРјРµРЅРµРЅРёРµ: Supabase в†’ SQL Editor в†’ РІСЃС‚Р°РІРёС‚СЊ С†РµР»РёРєРѕРј в†’ Run.
-- РЎС…РµРјС‹ gravirovka / norms_* РЅРµ Р·Р°С‚СЂР°РіРёРІР°СЋС‚СЃСЏ.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- РўРµРЅР°РЅС‚С‹ (Р·Р°РІРѕРґС‹/РѕСЂРіР°РЅРёР·Р°С†РёРё) ----------
create table if not exists public.tenants (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text unique,
  plan       text not null default 'start',
  status     text not null default 'active',
  created_at timestamptz not null default now()
);

-- ---------- РџСЂРѕС„РёР»Рё (1:1 Рє auth.users) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  full_name  text,
  created_at timestamptz not null default now()
);

-- ---------- Р§Р»РµРЅСЃС‚РІРѕ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ РІ С‚РµРЅР°РЅС‚Рµ + СЂРѕР»СЊ ----------
create table if not exists public.memberships (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       text not null default 'member',   -- owner | admin | member
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create index if not exists memberships_user_idx on public.memberships (user_id);
create index if not exists memberships_tenant_idx on public.memberships (tenant_id);

-- ---------- РҐРµР»РїРµСЂ: С‚РµРЅР°РЅС‚С‹ С‚РµРєСѓС‰РµРіРѕ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ ----------
-- security definer, С‡С‚РѕР±С‹ РѕР±РѕР№С‚Рё RLS РїСЂРё РІС‹С‡РёСЃР»РµРЅРёРё РїРѕР»РёС‚РёРє (Р±РµР· СЂРµРєСѓСЂСЃРёРё).
create or replace function public.current_tenant_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.memberships where user_id = auth.uid();
$$;

-- ---------- RLS ----------
alter table public.tenants     enable row level security;
alter table public.profiles    enable row level security;
alter table public.memberships enable row level security;

-- profiles: РґРѕСЃС‚СѓРї С‚РѕР»СЊРєРѕ Рє СЃРІРѕРµРјСѓ РїСЂРѕС„РёР»СЋ
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert on public.profiles for insert with check (id = auth.uid());
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- memberships: СЃРІРѕРё С‡Р»РµРЅСЃС‚РІР° РёР»Рё С‡Р»РµРЅСЃС‚РІР° СЃРІРѕРµРіРѕ С‚РµРЅР°РЅС‚Р°
drop policy if exists memberships_read on public.memberships;
create policy memberships_read on public.memberships for select
  using (user_id = auth.uid() or tenant_id in (select public.current_tenant_ids()));

-- tenants: С‚РѕР»СЊРєРѕ С‚РµРЅР°РЅС‚С‹, РіРґРµ СЃРѕСЃС‚РѕРёС‚ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ
drop policy if exists tenants_read on public.tenants;
create policy tenants_read on public.tenants for select
  using (id in (select public.current_tenant_ids()));

-- ---------- РђРІС‚РѕСЃРѕР·РґР°РЅРёРµ РїСЂРѕС„РёР»СЏ РїСЂРё СЂРµРіРёСЃС‚СЂР°С†РёРё ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- РџСЂРёРјРµС‡Р°РЅРёРµ: С‚Р°Р±Р»РёС†С‹ РґРѕРјРµРЅР° (Р·Р°РєР°Р·С‹, РЅР°СЂСЏРґС‹, РѕС‚С‡С‘С‚С‹ Рё С‚.Рї.) РґРѕР±Р°РІР»СЏСЋС‚СЃСЏ
-- РѕС‚РґРµР»СЊРЅС‹РјРё РјРёРіСЂР°С†РёСЏРјРё РїРѕСЃР»Рµ СѓС‚РІРµСЂР¶РґРµРЅРёСЏ РўР—.


-- <<<<<<<<<< 0001_init.sql <<<<<<<<<<

-- >>>>>>>>>> 0002_supplier.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service В· 0002_supplier.sql
-- РњРѕРґСѓР»СЊ В«РџРѕСЂС‚Р°Р» Р·Р°РєСѓРїРѕРє РґР»СЏ РїРѕСЃС‚Р°РІС‰РёРєРѕРІВ»: Р·Р°РєСѓРїРєРё Рё РїСЂРµРґР»РѕР¶РµРЅРёСЏ (РљРџ).
-- РџСЂРёРјРµРЅРµРЅРёРµ: Supabase в†’ SQL Editor в†’ РІСЃС‚Р°РІРёС‚СЊ С†РµР»РёРєРѕРј в†’ Run.
-- Р—Р°РІРёСЃРёС‚ РѕС‚ 0001_init.sql (auth.users). РЎС…РµРјС‹ gravirovka / norms_* РЅРµ Р·Р°С‚СЂР°РіРёРІР°РµС‚.
-- ============================================================

-- ---------- Р—Р°РєСѓРїРєРё ----------
create table if not exists public.tenders (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  category    text,
  material    text,
  qty         numeric,
  unit        text,
  customer    text,
  deadline    date,
  status      text not null default 'open',   -- open | closed | awarded
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ---------- РџСЂРµРґР»РѕР¶РµРЅРёСЏ РїРѕСЃС‚Р°РІС‰РёРєРѕРІ (РљРџ) ----------
create table if not exists public.bids (
  id            uuid primary key default gen_random_uuid(),
  tender_id     uuid not null references public.tenders (id) on delete cascade,
  supplier_id   uuid not null references auth.users (id) on delete cascade,
  supplier_name text,
  price         numeric not null default 0,
  term_days     integer,
  comment       text,
  status        text not null default 'submitted',  -- submitted | accepted | rejected
  created_at    timestamptz not null default now(),
  unique (tender_id, supplier_id)
);

create index if not exists bids_supplier_idx on public.bids (supplier_id);
create index if not exists bids_tender_idx   on public.bids (tender_id);

-- ---------- RLS ----------
alter table public.tenders enable row level security;
alter table public.bids    enable row level security;

-- Р—Р°РєСѓРїРєРё: Р°РІС‚РѕСЂРёР·РѕРІР°РЅРЅС‹Р№ РІРёРґРёС‚ РѕС‚РєСЂС‹С‚С‹Рµ; Р°РІС‚РѕСЂ вЂ” СЃРІРѕРё РІ Р»СЋР±РѕРј СЃС‚Р°С‚СѓСЃРµ.
drop policy if exists tenders_read on public.tenders;
create policy tenders_read on public.tenders for select to authenticated
  using (status = 'open' or created_by = auth.uid());

drop policy if exists tenders_insert on public.tenders;
create policy tenders_insert on public.tenders for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists tenders_update_own on public.tenders;
create policy tenders_update_own on public.tenders for update to authenticated
  using (created_by = auth.uid());

-- РџСЂРµРґР»РѕР¶РµРЅРёСЏ: РїРѕСЃС‚Р°РІС‰РёРє РІРёРґРёС‚ СЃРІРѕРё; Р·Р°РєР°Р·С‡РёРє вЂ” РїРѕ СЃРІРѕРёРј Р·Р°РєСѓРїРєР°Рј.
drop policy if exists bids_read on public.bids;
create policy bids_read on public.bids for select to authenticated
  using (
    supplier_id = auth.uid()
    or tender_id in (select id from public.tenders where created_by = auth.uid())
  );

drop policy if exists bids_insert_own on public.bids;
create policy bids_insert_own on public.bids for insert to authenticated
  with check (supplier_id = auth.uid());

drop policy if exists bids_update_own on public.bids;
create policy bids_update_own on public.bids for update to authenticated
  using (supplier_id = auth.uid()) with check (supplier_id = auth.uid());

-- ---------- Р”РµРјРѕ-Р·Р°РєСѓРїРєРё (С‚РѕР»СЊРєРѕ РµСЃР»Рё С‚Р°Р±Р»РёС†Р° РїСѓСЃС‚Р°) ----------
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status)
select v.title, v.description, v.category, v.material, v.qty, v.unit, v.customer, v.deadline, 'open'
from (values
  ('РР·РіРѕС‚РѕРІР»РµРЅРёРµ РїСЂРµСЃСЃ-С„РѕСЂРјС‹ РІС‚СѓР»РєРё', 'РљРѕРјРїР»РµРєС‚ РљР” Рё 3D-РјРѕРґРµР»СЊ РїСЂРёР»Р°РіР°СЋС‚СЃСЏ. РњР°С‚РµСЂРёР°Р» С„РѕСЂРјРѕРѕР±СЂР°Р·СѓСЋС‰РёС… вЂ” СЃС‚Р°Р»СЊ 40РҐ.', 'РћСЃРЅР°СЃС‚РєР°', 'РЎС‚Р°Р»СЊ 40РҐ', 1, 'РєРѕРјРїР»', 'РћРћРћ В«РџСЂРёРІРѕРґВ»', (current_date + 14)::date),
  ('Р¤СЂРµР·РµСЂРѕРІРєР° РєРѕСЂРїСѓСЃРЅС‹С… РґРµС‚Р°Р»РµР№, 5 РѕСЃРµР№', 'РџР°СЂС‚РёСЏ РєРѕСЂРїСѓСЃРѕРІ РёР· Р°Р»СЋРјРёРЅРёСЏ Р”16Рў, РґРѕРїСѓСЃРє В±0,05 РјРј.', 'РњРµС…Р°РЅРѕРѕР±СЂР°Р±РѕС‚РєР°', 'Р”16Рў', 200, 'С€С‚', 'РђРћ В«РЈСЂР°Р»-РЁС‚Р°РјРїВ»', (current_date + 21)::date),
  ('РўРѕРєР°СЂРЅС‹Рµ СЂР°Р±РѕС‚С‹: РІР°Р»С‹ Рё С€РµР№РєРё', 'Р’Р°Р»С‹ РёР· СЃС‚Р°Р»Рё 45, Р·Р°РєР°Р»РєР° РўР’Р§, С€Р»РёС„РѕРІРєР° С€РµРµРє.', 'РњРµС…Р°РЅРѕРѕР±СЂР°Р±РѕС‚РєР°', 'РЎС‚Р°Р»СЊ 45', 120, 'С€С‚', 'РћРћРћ В«РўРѕС‡РјР°С€-РЎРµСЂРІРёСЃВ»', (current_date + 10)::date),
  ('Р›Р°Р·РµСЂРЅР°СЏ СЂРµР·РєР° Р»РёСЃС‚Р° 4 РјРј', 'Р Р°СЃРєСЂРѕР№ Р»РёСЃС‚РѕРІ 09Р“2РЎ РїРѕ РєР°СЂС‚Рµ СЂР°СЃРєСЂРѕСЏ, РєСЂРѕРјРєР° Р±РµР· Р·Р°СѓСЃРµРЅС†РµРІ.', 'Р›Р°Р·РµСЂРЅР°СЏ СЂРµР·РєР°', '09Р“2РЎ', 60, 'Р»РёСЃС‚', 'РћРћРћ В«Р›Р°Р·РµСЂРџСЂРѕ-Р®РіВ»', (current_date + 7)::date)
) as v(title, description, category, material, qty, unit, customer, deadline)
where not exists (select 1 from public.tenders);


-- <<<<<<<<<< 0002_supplier.sql <<<<<<<<<<

-- >>>>>>>>>> 0003_app_auth.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service В· 0003_app_auth.sql
-- Р’С…РѕРґ РїРѕ Р›РћР“РРќРЈ Рё РџРђР РћР›Р® (Р±РµР· email). РџР°СЂРѕР»Рё вЂ” bcrypt-С…РµС€Рё (pgcrypto).
-- РЎРµСЃСЃРёРё вЂ” С‚РѕРєРµРЅС‹ РІ app_sessions. Р’СЃРµ РїСЂРѕРІРµСЂРєРё вЂ” РІ SECURITY DEFINER С„СѓРЅРєС†РёСЏС….
-- РџСЂРёРјРµРЅРµРЅРёРµ: Supabase в†’ SQL Editor в†’ РІСЃС‚Р°РІРёС‚СЊ С†РµР»РёРєРѕРј в†’ Run.
-- РџРѕСЂСЏРґРѕРє: 0001_init.sql в†’ 0002_supplier.sql в†’ 0003_app_auth.sql.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- РџРѕР»СЊР·РѕРІР°С‚РµР»Рё СЃРµСЂРІРёСЃР° ----------
create table if not exists public.app_users (
  id            uuid primary key default gen_random_uuid(),
  login         text unique not null,
  password_hash text not null,
  full_name     text,
  role          text not null default 'supplier',   -- owner | manager | supplier | admin
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------- РЎРµСЃСЃРёРё (С‚РѕРєРµРЅС‹) ----------
create table if not exists public.app_sessions (
  token      uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);
create index if not exists app_sessions_user_idx on public.app_sessions (user_id);

-- РџСЂСЏРјРѕР№ РґРѕСЃС‚СѓРї Р·Р°РїСЂРµС‰С‘РЅ: RLS РІРєР»СЋС‡С‘РЅ, РїСѓР±Р»РёС‡РЅС‹С… РїРѕР»РёС‚РёРє РЅРµС‚ в†’ С‚РѕР»СЊРєРѕ С‡РµСЂРµР· С„СѓРЅРєС†РёРё.
alter table public.app_users    enable row level security;
alter table public.app_sessions enable row level security;

-- ---------- Р›РѕРіРёРЅ ----------
create or replace function public.app_login(p_login text, p_password text)
returns table (token uuid, user_id uuid, login text, full_name text, role text)
language plpgsql security definer set search_path = public, extensions
as $$
declare
  u  public.app_users;
  tk uuid;
begin
  select * into u from public.app_users
   where lower(login) = lower(trim(p_login)) and active
   limit 1;
  if u.id is null then return; end if;
  if u.password_hash <> extensions.crypt(p_password, u.password_hash) then return; end if;

  insert into public.app_sessions (user_id) values (u.id) returning app_sessions.token into tk;
  return query select tk, u.id, u.login, u.full_name, u.role;
end $$;

-- ---------- РўРµРєСѓС‰РёР№ РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ РїРѕ С‚РѕРєРµРЅСѓ ----------
create or replace function public.app_me(p_token uuid)
returns table (user_id uuid, login text, full_name text, role text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.full_name, u.role
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

-- ---------- Р’С‹С…РѕРґ ----------
create or replace function public.app_logout(p_token uuid)
returns void language sql security definer set search_path = public
as $$ delete from public.app_sessions where token = p_token; $$;

grant execute on function public.app_login(text, text) to anon, authenticated;
grant execute on function public.app_me(uuid)          to anon, authenticated;
grant execute on function public.app_logout(uuid)      to anon, authenticated;

-- ---------- Р”РµРјРѕ-РїРѕР»СЊР·РѕРІР°С‚РµР»Рё (РїР°СЂРѕР»Рё С…РµС€РёСЂСѓСЋС‚СЃСЏ) ----------
insert into public.app_users (login, password_hash, full_name, role) values
  ('admin',    extensions.crypt('admin',         extensions.gen_salt('bf')), 'РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ',     'admin'),
  ('owner',    extensions.crypt('Owner12345',    extensions.gen_salt('bf')), 'РЎРѕР±СЃС‚РІРµРЅРЅРёРє 3DMP', 'owner'),
  ('manager',  extensions.crypt('Manager12345',  extensions.gen_salt('bf')), 'РњРµРЅРµРґР¶РµСЂ Р·Р°РєСѓРїРѕРє',  'manager'),
  ('supplier', extensions.crypt('Supplier12345', extensions.gen_salt('bf')), 'РџРѕСЃС‚Р°РІС‰РёРє Р”РµРјРѕ',    'supplier')
on conflict (login) do update
  set password_hash = excluded.password_hash,
      full_name     = excluded.full_name,
      role          = excluded.role,
      active        = true;

-- ============================================================
--  РџРѕСЂС‚Р°Р» Р·Р°РєСѓРїРѕРє: РґРѕСЃС‚СѓРї Р±РµР· Supabase Auth (РїРѕ С‚РѕРєРµРЅСѓ СЃРµСЃСЃРёРё)
--  РўСЂРµР±СѓРµС‚ РїСЂРёРјРµРЅС‘РЅРЅРѕР№ 0002_supplier.sql.
-- ============================================================

-- Р—Р°РєСѓРїРєРё: РѕС‚РєСЂС‹С‚С‹Рµ С‡РёС‚Р°РµС‚ РєС‚Рѕ СѓРіРѕРґРЅРѕ (РїСѓР±Р»РёС‡РЅР°СЏ РІРёС‚СЂРёРЅР°).
drop policy if exists tenders_read_anon on public.tenders;
create policy tenders_read_anon on public.tenders for select to anon
  using (status = 'open');

-- РџСЂРµРґР»РѕР¶РµРЅРёСЏ: СЃРІСЏР·СЊ СЃ РїРѕР»СЊР·РѕРІР°С‚РµР»РµРј СЃРµСЂРІРёСЃР°; РїСЂСЏРјРѕР№ РґРѕСЃС‚СѓРї Р·Р°РєСЂС‹РІР°РµРј.
alter table public.bids add column if not exists app_user_id uuid references public.app_users (id) on delete cascade;
alter table public.bids alter column supplier_id drop not null;

drop policy if exists bids_read on public.bids;
drop policy if exists bids_insert_own on public.bids;
drop policy if exists bids_update_own on public.bids;

-- РњРѕРё РїСЂРµРґР»РѕР¶РµРЅРёСЏ
create or replace function public.supplier_my_bids(p_token uuid)
returns table (id uuid, tender_id uuid, tender_title text, price numeric, term_days integer, comment text, status text, created_at timestamptz)
language sql security definer set search_path = public
as $$
  select b.id, b.tender_id, t.title, b.price, b.term_days, b.comment, b.status, b.created_at
  from public.bids b
  join public.tenders t on t.id = b.tender_id
  join public.app_sessions s on s.user_id = b.app_user_id
  where s.token = p_token and s.expires_at > now()
  order by b.created_at desc;
$$;

-- РџРѕРґР°С‚СЊ/РёР·РјРµРЅРёС‚СЊ РїСЂРµРґР»РѕР¶РµРЅРёРµ
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare
  uid uuid; uname text;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'РЎРµСЃСЃРёСЏ РЅРµРґРµР№СЃС‚РІРёС‚РµР»СЊРЅР°'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'РЈРєР°Р¶РёС‚Рµ С†РµРЅСѓ Р±РѕР»СЊС€Рµ РЅСѓР»СЏ'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  return query select true, 'РџСЂРµРґР»РѕР¶РµРЅРёРµ СЃРѕС…СЂР°РЅРµРЅРѕ';
end $$;

grant execute on function public.supplier_my_bids(uuid)                       to anon, authenticated;
grant execute on function public.supplier_submit_bid(uuid, uuid, numeric, integer, text) to anon, authenticated;

-- РЈРЅРёРєР°Р»СЊРЅРѕСЃС‚СЊ В«Р·Р°РєСѓРїРєР° + РїРѕР»СЊР·РѕРІР°С‚РµР»СЊВ» РґР»СЏ upsert РІ supplier_submit_bid.
-- РРЅРґРµРєСЃ РЅРµ С‡Р°СЃС‚РёС‡РЅС‹Р№, С‡С‚РѕР±С‹ СЃРѕРІРїР°РґР°С‚СЊ СЃ ON CONFLICT (tender_id, app_user_id).
create unique index if not exists bids_tender_appuser_key on public.bids (tender_id, app_user_id);


-- <<<<<<<<<< 0003_app_auth.sql <<<<<<<<<<

