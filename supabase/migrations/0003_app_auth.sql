-- ============================================================
-- 3DMP Service · 0003_app_auth.sql
-- Вход по ЛОГИНУ и ПАРОЛЮ (без email). Пароли — bcrypt-хеши (pgcrypto).
-- Сессии — токены в app_sessions. Все проверки — в SECURITY DEFINER функциях.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Порядок: 0001_init.sql → 0002_supplier.sql → 0003_app_auth.sql.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Пользователи сервиса ----------
create table if not exists public.app_users (
  id            uuid primary key default gen_random_uuid(),
  login         text unique not null,
  password_hash text not null,
  full_name     text,
  role          text not null default 'supplier',   -- owner | manager | supplier | admin
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------- Сессии (токены) ----------
create table if not exists public.app_sessions (
  token      uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);
create index if not exists app_sessions_user_idx on public.app_sessions (user_id);

-- Прямой доступ запрещён: RLS включён, публичных политик нет → только через функции.
alter table public.app_users    enable row level security;
alter table public.app_sessions enable row level security;

-- ---------- Логин ----------
create or replace function public.app_login(p_login text, p_password text)
returns table (token uuid, user_id uuid, login text, full_name text, role text)
language plpgsql security definer set search_path = public, extensions
as $$
declare
  u  public.app_users;
  tk uuid;
begin
  select * into u from public.app_users au
   where lower(au.login) = lower(trim(p_login)) and au.active
   limit 1;
  if u.id is null then return; end if;
  if u.password_hash <> extensions.crypt(p_password, u.password_hash) then return; end if;

  insert into public.app_sessions (user_id) values (u.id) returning app_sessions.token into tk;
  return query select tk, u.id, u.login, u.full_name, u.role;
end $$;

-- ---------- Текущий пользователь по токену ----------
drop function if exists public.app_me(uuid);
create function public.app_me(p_token uuid)
returns table (user_id uuid, login text, full_name text, role text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.full_name, u.role
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

-- ---------- Выход ----------
create or replace function public.app_logout(p_token uuid)
returns void language sql security definer set search_path = public
as $$ delete from public.app_sessions where token = p_token; $$;

grant execute on function public.app_login(text, text) to anon, authenticated;
grant execute on function public.app_me(uuid)          to anon, authenticated;
grant execute on function public.app_logout(uuid)      to anon, authenticated;

-- ---------- Демо-пользователи (пароли хешируются) ----------
insert into public.app_users (login, password_hash, full_name, role) values
  ('admin',    extensions.crypt('admin',    extensions.gen_salt('bf')), 'Администратор',     'admin'),
  ('owner',    extensions.crypt('owner',    extensions.gen_salt('bf')), 'Собственник 3DMP', 'owner'),
  ('manager',  extensions.crypt('manager',  extensions.gen_salt('bf')), 'Менеджер закупок',  'manager'),
  ('supplier', extensions.crypt('supplier', extensions.gen_salt('bf')), 'Поставщик Демо',    'supplier')
on conflict (login) do update
  set password_hash = excluded.password_hash,
      full_name     = excluded.full_name,
      role          = excluded.role,
      active        = true;

-- ============================================================
--  Портал закупок: доступ без Supabase Auth (по токену сессии)
--  Требует применённой 0002_supplier.sql.
-- ============================================================

-- Закупки: открытые читает кто угодно (публичная витрина).
grant select on public.tenders to anon, authenticated;
drop policy if exists tenders_read_anon on public.tenders;
create policy tenders_read_anon on public.tenders for select to anon
  using (status = 'open');

-- Предложения: связь с пользователем сервиса; прямой доступ закрываем.
alter table public.bids add column if not exists app_user_id uuid references public.app_users (id) on delete cascade;
alter table public.bids alter column supplier_id drop not null;

drop policy if exists bids_read on public.bids;
drop policy if exists bids_insert_own on public.bids;
drop policy if exists bids_update_own on public.bids;

-- Мои предложения
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

-- Подать/изменить предложение
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
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  return query select true, 'Предложение сохранено';
end $$;

grant execute on function public.supplier_my_bids(uuid)                       to anon, authenticated;
grant execute on function public.supplier_submit_bid(uuid, uuid, numeric, integer, text) to anon, authenticated;

-- Уникальность «закупка + пользователь» для upsert в supplier_submit_bid.
-- Индекс не частичный, чтобы совпадать с ON CONFLICT (tender_id, app_user_id).
create unique index if not exists bids_tender_appuser_key on public.bids (tender_id, app_user_id);
