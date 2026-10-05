-- 3DMP Service · apply_all.sql — единая схема (0001..0052), идемпотентно.

-- >>>>>>>>>> 0001_init.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0001_init.sql
-- Базовая схема SaaS-сервиса: мультитенантность, профили, членство и RLS.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Схемы gravirovka / norms_* не затрагиваются.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- Тенанты (заводы/организации) ----------
create table if not exists public.tenants (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text unique,
  plan       text not null default 'start',
  status     text not null default 'active',
  created_at timestamptz not null default now()
);

-- ---------- Профили (1:1 к auth.users) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  full_name  text,
  created_at timestamptz not null default now()
);

-- ---------- Членство пользователя в тенанте + роль ----------
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

-- ---------- Хелпер: тенанты текущего пользователя ----------
-- security definer, чтобы обойти RLS при вычислении политик (без рекурсии).
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

-- profiles: доступ только к своему профилю
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert on public.profiles for insert with check (id = auth.uid());
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- memberships: свои членства или членства своего тенанта
drop policy if exists memberships_read on public.memberships;
create policy memberships_read on public.memberships for select
  using (user_id = auth.uid() or tenant_id in (select public.current_tenant_ids()));

-- tenants: только тенанты, где состоит пользователь
drop policy if exists tenants_read on public.tenants;
create policy tenants_read on public.tenants for select
  using (id in (select public.current_tenant_ids()));

-- ---------- Автосоздание профиля при регистрации ----------
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

-- Примечание: таблицы домена (заказы, наряды, отчёты и т.п.) добавляются
-- отдельными миграциями после утверждения ТЗ.
-- <<<<<<<<<< 0001_init.sql <<<<<<<<<<

-- >>>>>>>>>> 0002_supplier.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0002_supplier.sql
-- Модуль «Портал закупок для поставщиков»: закупки и предложения (КП).
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Зависит от 0001_init.sql (auth.users). Схемы gravirovka / norms_* не затрагивает.
-- ============================================================

-- ---------- Закупки ----------
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

-- ---------- Предложения поставщиков (КП) ----------
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

-- Закупки: авторизованный видит открытые; автор — свои в любом статусе.
drop policy if exists tenders_read on public.tenders;
create policy tenders_read on public.tenders for select to authenticated
  using (status = 'open' or created_by = auth.uid());

drop policy if exists tenders_insert on public.tenders;
create policy tenders_insert on public.tenders for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists tenders_update_own on public.tenders;
create policy tenders_update_own on public.tenders for update to authenticated
  using (created_by = auth.uid());

-- Предложения: поставщик видит свои; заказчик — по своим закупкам.
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

-- ---------- Демо-закупки (только если таблица пуста) ----------
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status)
select v.title, v.description, v.category, v.material, v.qty, v.unit, v.customer, v.deadline, 'open'
from (values
  ('Изготовление пресс-формы втулки', 'Комплект КД и 3D-модель прилагаются. Материал формообразующих — сталь 40Х.', 'Оснастка', 'Сталь 40Х', 1, 'компл', 'ООО «Привод»', (current_date + 14)::date),
  ('Фрезеровка корпусных деталей, 5 осей', 'Партия корпусов из алюминия Д16Т, допуск ±0,05 мм.', 'Механообработка', 'Д16Т', 200, 'шт', 'АО «Урал-Штамп»', (current_date + 21)::date),
  ('Токарные работы: валы и шейки', 'Валы из стали 45, закалка ТВЧ, шлифовка шеек.', 'Механообработка', 'Сталь 45', 120, 'шт', 'ООО «Точмаш-Сервис»', (current_date + 10)::date),
  ('Лазерная резка листа 4 мм', 'Раскрой листов 09Г2С по карте раскроя, кромка без заусенцев.', 'Лазерная резка', '09Г2С', 60, 'лист', 'ООО «ЛазерПро-Юг»', (current_date + 7)::date)
) as v(title, description, category, material, qty, unit, customer, deadline)
where not exists (select 1 from public.tenders);
-- <<<<<<<<<< 0002_supplier.sql <<<<<<<<<<

-- >>>>>>>>>> 0003_app_auth.sql >>>>>>>>>>
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
-- <<<<<<<<<< 0003_app_auth.sql <<<<<<<<<<

-- >>>>>>>>>> 0004_admin.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0004_admin.sql
-- Админ-функции: управление пользователями и ролями (только role='admin').
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Зависит от 0003_app_auth.sql (app_users, app_sessions).
-- ============================================================

-- ---------- Проверка «админ по токену» ----------
create or replace function public.is_admin(p_token uuid)
returns boolean
language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.app_sessions s
    join public.app_users u on u.id = s.user_id
    where s.token = p_token and s.expires_at > now() and u.active and u.role = 'admin'
  );
$$;

-- ---------- Список пользователей ----------
drop function if exists public.admin_list_users(uuid);
create function public.admin_list_users(p_token uuid)
returns table (id uuid, login text, full_name text, role text, active boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select u.id, u.login, u.full_name, u.role, u.active, u.created_at
    from public.app_users u
    order by u.created_at;
end $$;

-- ---------- Создать пользователя ----------
create or replace function public.admin_create_user(
  p_token uuid, p_login text, p_password text, p_full_name text, p_role text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if not public.is_admin(p_token) then return query select false, 'Доступ запрещён'; return; end if;
  if coalesce(trim(p_login), '') = '' then return query select false, 'Укажите логин'; return; end if;
  if length(coalesce(p_password, '')) < 4 then return query select false, 'Пароль — минимум 4 символа'; return; end if;
  if exists (select 1 from public.app_users where lower(login) = lower(trim(p_login))) then
    return query select false, 'Логин уже занят'; return;
  end if;

  insert into public.app_users (login, password_hash, full_name, role)
  values (
    lower(trim(p_login)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    nullif(trim(p_full_name), ''),
    coalesce(nullif(trim(p_role), ''), 'supplier')
  );
  return query select true, 'Пользователь создан';
end $$;

-- ---------- Изменить роль / активность / имя ----------
create or replace function public.admin_update_user(
  p_token uuid, p_user_id uuid, p_role text, p_active boolean, p_full_name text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare caller uuid;
begin
  if not public.is_admin(p_token) then return query select false, 'Доступ запрещён'; return; end if;
  select u.id into caller from public.app_sessions s
    join public.app_users u on u.id = s.user_id
    where s.token = p_token and s.expires_at > now();
  if caller is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_user_id = caller and (p_active is false or (p_role is not null and p_role <> 'admin')) then
    return query select false, 'Нельзя менять свою роль/доступ'; return;
  end if;

  update public.app_users
     set role = coalesce(p_role, role),
         active = coalesce(p_active, active),
         full_name = coalesce(p_full_name, full_name)
   where id = p_user_id;
  return query select true, 'Сохранено';
end $$;

-- ---------- Сбросить пароль ----------
create or replace function public.admin_reset_password(
  p_token uuid, p_user_id uuid, p_password text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if not public.is_admin(p_token) then return query select false, 'Доступ запрещён'; return; end if;
  if length(coalesce(p_password, '')) < 4 then return query select false, 'Пароль — минимум 4 символа'; return; end if;
  update public.app_users
     set password_hash = extensions.crypt(p_password, extensions.gen_salt('bf'))
   where id = p_user_id;
  return query select true, 'Пароль изменён';
end $$;

-- ---------- Удалить пользователя ----------
create or replace function public.admin_delete_user(p_token uuid, p_user_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare caller uuid;
begin
  if not public.is_admin(p_token) then return query select false, 'Доступ запрещён'; return; end if;
  select u.id into caller from public.app_sessions s
    join public.app_users u on u.id = s.user_id
    where s.token = p_token and s.expires_at > now();
  if p_user_id = caller then return query select false, 'Нельзя удалить себя'; return; end if;
  delete from public.app_users where id = p_user_id;
  return query select true, 'Пользователь удалён';
end $$;

grant execute on function public.is_admin(uuid) to anon, authenticated;
grant execute on function public.admin_list_users(uuid) to anon, authenticated;
grant execute on function public.admin_create_user(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_update_user(uuid, uuid, text, boolean, text) to anon, authenticated;
grant execute on function public.admin_reset_password(uuid, uuid, text) to anon, authenticated;
grant execute on function public.admin_delete_user(uuid, uuid) to anon, authenticated;
-- <<<<<<<<<< 0004_admin.sql <<<<<<<<<<

-- >>>>>>>>>> 0005_core.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0005_core.sql  (v1.1 — права, журнал, доступ)
-- Журнал действий: app_events; last_login; обновлённые app_login/app_me/admin_list_users.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Зависит от 0001..0004.
-- ============================================================

-- ---------- Журнал действий ----------
create table if not exists public.app_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.app_users (id) on delete set null,
  login      text,
  action     text not null,
  detail     text,
  created_at timestamptz not null default now()
);
create index if not exists app_events_created_idx on public.app_events (created_at desc);
alter table public.app_events enable row level security;

-- ---------- Последний вход ----------
alter table public.app_users add column if not exists last_login_at timestamptz;

-- ---------- Запись события по токену ----------
create or replace function public.app_log_event(p_token uuid, p_action text, p_detail text)
returns void
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text;
begin
  select u.id, u.login into uid, ulogin
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now();
  if uid is null then return; end if;
  insert into public.app_events (user_id, login, action, detail)
  values (uid, ulogin, left(coalesce(p_action, ''), 120), left(coalesce(p_detail, ''), 500));
end $$;

-- ---------- Мои события ----------
create or replace function public.app_my_events(p_token uuid, p_limit integer default 20)
returns table (action text, detail text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.user_id into uid from public.app_sessions s
   where s.token = p_token and s.expires_at > now();
  if uid is null then return; end if;
  return query select e.action, e.detail, e.created_at
   from public.app_events e
   where e.user_id = uid
   order by e.created_at desc
   limit greatest(1, least(coalesce(p_limit, 20), 100));
end $$;

-- ---------- Журнал для админа ----------
create or replace function public.admin_list_events(p_token uuid, p_limit integer default 100)
returns table (id uuid, login text, action text, detail text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select e.id, e.login, e.action, e.detail, e.created_at
   from public.app_events e
   order by e.created_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 500));
end $$;

-- ---------- app_login: last_login + событие ----------
create or replace function public.app_login(p_login text, p_password text)
returns table (token uuid, user_id uuid, login text, full_name text, role text)
language plpgsql security definer set search_path = public, extensions
as $$
declare u public.app_users; tk uuid;
begin
  select * into u from public.app_users au
   where lower(au.login) = lower(trim(p_login)) and au.active limit 1;
  if u.id is null then return; end if;
  if u.password_hash <> extensions.crypt(p_password, u.password_hash) then return; end if;

  update public.app_users set last_login_at = now() where id = u.id;
  insert into public.app_events (user_id, login, action, detail) values (u.id, u.login, 'Вход', 'успешный вход');

  insert into public.app_sessions (user_id) values (u.id) returning app_sessions.token into tk;
  return query select tk, u.id, u.login, u.full_name, u.role;
end $$;

-- ---------- app_me: + last_login_at (меняется тип возврата → пересоздаём) ----------
drop function if exists public.app_me(uuid);
create function public.app_me(p_token uuid)
returns table (user_id uuid, login text, full_name text, role text, last_login_at timestamptz)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.full_name, u.role, u.last_login_at
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

-- ---------- admin_list_users: + last_login_at ----------
drop function if exists public.admin_list_users(uuid);
create function public.admin_list_users(p_token uuid)
returns table (id uuid, login text, full_name text, role text, active boolean, created_at timestamptz, last_login_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select u.id, u.login, u.full_name, u.role, u.active, u.created_at, u.last_login_at
    from public.app_users u order by u.created_at;
end $$;

grant execute on function public.app_log_event(uuid, text, text)   to anon, authenticated;
grant execute on function public.app_my_events(uuid, integer)      to anon, authenticated;
grant execute on function public.admin_list_events(uuid, integer)  to anon, authenticated;
grant execute on function public.app_login(text, text)             to anon, authenticated;
grant execute on function public.app_me(uuid)                      to anon, authenticated;
grant execute on function public.admin_list_users(uuid)            to anon, authenticated;
-- <<<<<<<<<< 0005_core.sql <<<<<<<<<<

-- >>>>>>>>>> 0006_orders.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0006_orders.sql  (v1.2 — единый приём заявок + уведомления)
-- ВАЖНО: public.orders НЕ трогаем (проект «гравировка»). Наши таблицы — app_*.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.  Зависит от 0001..0005.
-- ============================================================

-- ---------- Заявки/заказы (из любых модулей и сервисов) ----------
create sequence if not exists public.app_order_seq;

create table if not exists public.app_orders (
  id           uuid primary key default gen_random_uuid(),
  number       text unique not null,
  title        text not null,
  description  text,
  source       text,                    -- модуль/сервис-источник (eco:A1, supplier, manual …)
  customer     text,
  contact      text,
  status       text not null default 'new',   -- new | in_progress | done | cancelled
  priority     text not null default 'normal',-- low | normal | high
  created_by   uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_orders_created_idx on public.app_orders (created_at desc);

create table if not exists public.app_order_items (
  id       uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.app_orders (id) on delete cascade,
  name     text not null,
  qty      numeric default 1,
  unit     text,
  price    numeric
);
create index if not exists app_order_items_order_idx on public.app_order_items (order_id);

create table if not exists public.app_order_history (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.app_orders (id) on delete cascade,
  status     text not null,
  comment    text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_order_history_order_idx on public.app_order_history (order_id);

-- ---------- Уведомления (адресные) ----------
create table if not exists public.app_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users (id) on delete cascade,
  title      text not null,
  body       text,
  link       text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists app_notifications_user_idx on public.app_notifications (user_id, created_at desc);

alter table public.app_orders        enable row level security;
alter table public.app_order_items   enable row level security;
alter table public.app_order_history enable row level security;
alter table public.app_notifications enable row level security;

-- ---------- Внутренние помощники ----------
create or replace function public.app_session_user(p_token uuid)
returns table (uid uuid, ulogin text, urole text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.role
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

create or replace function public.app_notif_send(p_user uuid, p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  values (p_user, left(p_title, 200), left(coalesce(p_body, ''), 500), p_link);
$$;

create or replace function public.app_notif_roles(p_roles text[], p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  select u.id, left(p_title, 200), left(coalesce(p_body, ''), 500), p_link
  from public.app_users u
  where u.active and u.role = any(p_roles);
$$;

-- ---------- Создать заявку ----------
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, contact, priority, status, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          nullif(trim(p_customer), ''), nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles(array['admin', 'manager', 'owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');

  return query select oid, onum;
end $$;

-- ---------- Список заявок ----------
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole in ('admin', 'manager', 'owner') then
    return query select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
      from public.app_orders o order by o.created_at desc;
  else
    return query select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
      from public.app_orders o where o.created_by = uid order by o.created_at desc;
  end if;
end $$;

-- ---------- Одна заявка + позиции + история ----------
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; owner uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  select o.created_by into owner from public.app_orders o where o.id = p_id;
  if owner is null then return; end if;
  if not (urole in ('admin','manager','owner') or owner = uid) then raise exception 'Доступ запрещён'; end if;
  return query select o.id, o.number, o.title, o.description, o.source, o.customer, o.contact,
    o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o where o.id = p_id;
end $$;

create or replace function public.app_order_history_list(p_token uuid, p_id uuid)
returns table (status text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  return query select h.status, h.comment, h.by_login, h.created_at
    from public.app_order_history h where h.order_id = p_id order by h.created_at;
end $$;

-- ---------- Сменить статус ----------
create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; owner uuid; onum text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  select o.created_by, o.number into owner, onum from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole in ('admin','manager','owner') or owner = uid) then return query select false, 'Доступ запрещён'; return; end if;

  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment), ''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment, ''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- Уведомления: список/счётчик/прочитано ----------
create or replace function public.app_notif_list(p_token uuid, p_limit integer default 20)
returns table (id uuid, title text, body text, link text, read_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  return query select n.id, n.title, n.body, n.link, n.read_at, n.created_at
    from public.app_notifications n where n.user_id = uid
    order by n.created_at desc limit greatest(1, least(coalesce(p_limit,20),100));
end $$;

create or replace function public.app_notif_unread(p_token uuid)
returns integer language plpgsql security definer set search_path = public
as $$
declare uid uuid; c integer;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return 0; end if;
  select count(*) into c from public.app_notifications n where n.user_id = uid and n.read_at is null;
  return c;
end $$;

create or replace function public.app_notif_mark_read(p_token uuid, p_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  update public.app_notifications set read_at = now() where id = p_id and user_id = uid;
end $$;

create or replace function public.app_notif_mark_all(p_token uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  update public.app_notifications set read_at = now() where user_id = uid and read_at is null;
end $$;

-- ---------- Уведомление о новом КП (переписываем supplier_submit_bid) ----------
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin uuid; uname text; ttitle text;
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

  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/supplier/index.html');

  return query select true, 'Предложение сохранено';
end $$;

grant execute on function public.app_order_create(uuid,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_order_list(uuid)                              to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid)                          to anon, authenticated;
grant execute on function public.app_order_history_list(uuid,uuid)                 to anon, authenticated;
grant execute on function public.app_order_set_status(uuid,uuid,text,text)         to anon, authenticated;
grant execute on function public.app_notif_list(uuid,integer)                      to anon, authenticated;
grant execute on function public.app_notif_unread(uuid)                            to anon, authenticated;
grant execute on function public.app_notif_mark_read(uuid,uuid)                    to anon, authenticated;
grant execute on function public.app_notif_mark_all(uuid)                         to anon, authenticated;
-- <<<<<<<<<< 0006_orders.sql <<<<<<<<<<

-- >>>>>>>>>> 0007_production.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0007_production.sql  (v1.3 — производство: наряды и операции)
-- Роли доступа: admin | owner | manager (расширим на master/operator позже).
-- Зависит от 0001..0006. public.orders НЕ трогаем.
-- ============================================================

create sequence if not exists public.app_naryad_seq;

-- ---------- Рабочие центры ----------
create table if not exists public.app_work_centers (
  id         uuid primary key default gen_random_uuid(),
  code       text unique,
  name       text not null,
  kind       text,                     -- Фрезерный | Токарный | Лазер | Сборка …
  cost_hour  numeric default 0,        -- стоимость нормочаса, ₽
  active     boolean not null default true
);

-- ---------- Нормы операций (заготовки для наряда) ----------
create table if not exists public.app_norms (
  id           uuid primary key default gen_random_uuid(),
  operation    text not null,
  machine_kind text,
  setup_min    numeric default 0,      -- подготовительно-заключительное, мин
  unit_min     numeric default 0,      -- на единицу, мин
  rate_hour    numeric default 0,      -- стоимость нормочаса, ₽
  note         text
);

-- ---------- Наряды ----------
create table if not exists public.app_naryads (
  id           uuid primary key default gen_random_uuid(),
  number       text unique not null,
  order_id     uuid references public.app_orders (id) on delete set null,
  title        text not null,
  wc_id        uuid references public.app_work_centers (id) on delete set null,
  assignee     text,                   -- логин исполнителя
  status       text not null default 'open',  -- open | in_progress | closed
  plan_hours   numeric default 0,
  fact_hours   numeric default 0,
  due_date     date,
  created_by   uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_naryads_created_idx on public.app_naryads (created_at desc);
create index if not exists app_naryads_order_idx on public.app_naryads (order_id);

-- ---------- Операции наряда ----------
create table if not exists public.app_naryad_ops (
  id         uuid primary key default gen_random_uuid(),
  naryad_id  uuid not null references public.app_naryads (id) on delete cascade,
  seq        integer default 0,
  operation  text not null,
  worker     text,
  plan_hours numeric default 0,
  fact_hours numeric default 0,
  done       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists app_naryad_ops_idx on public.app_naryad_ops (naryad_id);

alter table public.app_work_centers enable row level security;
alter table public.app_norms        enable row level security;
alter table public.app_naryads      enable row level security;
alter table public.app_naryad_ops   enable row level security;

-- ---------- Доступ к производству ----------
create or replace function public.app_production_allowed(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.app_session_user(p_token) s
    where s.urole in ('admin','owner','manager')
  );
$$;

-- ---------- Справочники ----------
create or replace function public.app_wc_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, cost_hour numeric, active boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select w.id, w.code, w.name, w.kind, w.cost_hour, w.active from public.app_work_centers w order by w.name;
end $$;

create or replace function public.app_norms_list(p_token uuid)
returns table (id uuid, operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n order by n.operation;
end $$;

-- ---------- Наряды: список ----------
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select n.id, n.number, n.title, o.number, w.name, n.assignee, n.status,
           n.plan_hours, n.fact_hours, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    order by n.created_at desc;
end $$;

-- ---------- Создать наряд ----------
create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, created_by, created_login)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee), ''), 'open', uid, ulogin)
  returning app_naryads.id into nid;

  perform public.app_notif_roles(array['admin','manager','owner'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u where lower(u.login) = lower(trim(p_assignee)) and u.active limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

-- ---------- Наряд: карточка + операции ----------
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id;
end $$;

create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select op.id, op.seq, op.operation, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op where op.naryad_id = p_id order by op.seq, op.created_at;
end $$;

-- ---------- Добавить операцию ----------
create or replace function public.app_naryad_add_op(
  p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare seqn integer; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id;
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  if coalesce(trim(p_operation),'') = '' then return query select false,'Укажите операцию'; return; end if;

  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours)
  values (p_naryad_id, seqn, trim(p_operation), nullif(trim(p_worker),''), coalesce(p_plan_hours,0));

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

-- ---------- Отметить операцию выполненной ----------
create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select op.naryad_id into nid from public.app_naryad_ops op where op.id = p_op_id;
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;
  return query select true,'Обновлено';
end $$;

-- ---------- Закрыть наряд ----------
create or replace function public.app_naryad_close(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; nnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  select n.number into nnum from public.app_naryads n where n.id = p_id;
  if nnum is null then return query select false,'Наряд не найден'; return; end if;
  update public.app_naryads n set status = 'closed', updated_at = now(),
    fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = p_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Наряд ' || nnum || ' закрыт', 'Закрыл: ' || coalesce(ulogin,''), 'apps/production/index.html');
  return query select true,'Наряд закрыт';
end $$;

grant execute on function public.app_production_allowed(uuid) to anon, authenticated;
grant execute on function public.app_wc_list(uuid) to anon, authenticated;
grant execute on function public.app_norms_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_create(uuid,uuid,text,uuid,text,date) to anon, authenticated;
grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_ops(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_add_op(uuid,uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_naryad_op_done(uuid,uuid,numeric,boolean) to anon, authenticated;
grant execute on function public.app_naryad_close(uuid,uuid) to anon, authenticated;

-- ---------- Демо-данные ----------
insert into public.app_work_centers (code, name, kind, cost_hour)
select v.code, v.name, v.kind, v.cost_hour from (values
  ('WC-01','Фрезерный ЧПУ DMU-50','Фрезерный', 3500),
  ('WC-02','Токарный с ЧПУ','Токарный', 3000),
  ('WC-03','Лазерный комплекс','Лазер', 4200),
  ('WC-04','Слесарная/сборка','Сборка', 1800)
) as v(code,name,kind,cost_hour)
where not exists (select 1 from public.app_work_centers);

insert into public.app_norms (operation, machine_kind, setup_min, unit_min, rate_hour)
select v.operation, v.machine_kind, v.setup_min, v.unit_min, v.rate_hour from (values
  ('Фрезеровка черновая','Фрезерный', 20, 12, 3500),
  ('Фрезеровка чистовая','Фрезерный', 15, 8, 3500),
  ('Токарная обработка','Токарный', 18, 10, 3000),
  ('Лазерная резка','Лазер', 10, 3, 4200),
  ('Слесарная доводка','Сборка', 5, 15, 1800)
) as v(operation,machine_kind,setup_min,unit_min,rate_hour)
where not exists (select 1 from public.app_norms);
-- <<<<<<<<<< 0007_production.sql <<<<<<<<<<

-- >>>>>>>>>> 0008_procurement.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0008_procurement.sql  (v1.4 — закупки и поставщики)
-- Аккредитация поставщика, публикация закупок, КП, выбор победителя.
-- Зависит от 0001..0007. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Профиль поставщика (аккредитация) ----------
create table if not exists public.app_supplier_profiles (
  id          uuid primary key default gen_random_uuid(),
  app_user_id uuid unique not null references public.app_users (id) on delete cascade,
  company     text,
  inn         text,
  contact     text,
  phone       text,
  email       text,
  status      text not null default 'pending',  -- pending | approved | rejected
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.app_supplier_profiles enable row level security;

-- ---------- Закупки: поля победителя ----------
alter table public.tenders add column if not exists awarded_bid_id uuid references public.bids (id) on delete set null;
alter table public.tenders add column if not exists closed_at timestamptz;

-- ---------- Мой профиль поставщика ----------
create or replace function public.app_supplier_profile_get(p_token uuid)
returns table (company text, inn text, contact text, phone text, email text, status text, note text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  return query select p.company, p.inn, p.contact, p.phone, p.email, p.status, p.note, p.updated_at
    from public.app_supplier_profiles p where p.app_user_id = uid;
end $$;

create or replace function public.app_supplier_profile_save(
  p_token uuid, p_company text, p_inn text, p_contact text, p_phone text, p_email text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if coalesce(trim(p_company), '') = '' then return query select false, 'Укажите организацию'; return; end if;

  insert into public.app_supplier_profiles (app_user_id, company, inn, contact, phone, email, status)
  values (uid, trim(p_company), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''), nullif(trim(p_email),''), 'pending')
  on conflict (app_user_id) do update
    set company = excluded.company, inn = excluded.inn, contact = excluded.contact,
        phone = excluded.phone, email = excluded.email, status = 'pending', updated_at = now();

  perform public.app_notif_roles(array['admin','manager','owner'], 'Аккредитация: ' || trim(p_company),
          'Заявка от ' || coalesce(ulogin,''), 'apps/procurement/index.html');
  return query select true, 'Заявка на аккредитацию отправлена';
end $$;

-- ---------- Публикация закупки (закупщик) ----------
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;

  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status, created_by)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, 'open', uid)
  returning tenders.id into tid;

  perform public.app_notif_roles(array['supplier'], 'Новая закупка: ' || trim(p_title),
          coalesce(nullif(trim(p_customer),''), '') , 'apps/supplier/index.html');
  return query select tid, 'Закупка опубликована';
end $$;

-- ---------- Закупки для закупщика (с числом КП) ----------
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select t.id, t.title, t.category, t.customer, t.deadline, t.status,
           (select count(*) from public.bids b where b.tender_id = t.id), t.awarded_bid_id, t.created_at
    from public.tenders t order by t.created_at desc;
end $$;

create or replace function public.app_bids_for_tender(p_token uuid, p_tender_id uuid)
returns table (id uuid, supplier_name text, price numeric, term_days integer, comment text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select b.id, b.supplier_name, b.price, b.term_days, b.comment, b.status, b.created_at
    from public.bids b where b.tender_id = p_tender_id order by b.price asc, b.created_at;
end $$;

-- ---------- Выбор победителя ----------
create or replace function public.app_tender_award(p_token uuid, p_tender_id uuid, p_bid_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ttitle text; win_user uuid; win_name text; sup record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  if ttitle is null then return query select false,'Закупка не найдена'; return; end if;
  select b.app_user_id, b.supplier_name into win_user, win_name from public.bids b where b.id = p_bid_id and b.tender_id = p_tender_id;
  if win_user is null then return query select false,'Предложение не найдено'; return; end if;

  update public.bids set status = case when id = p_bid_id then 'accepted' else 'rejected' end where tender_id = p_tender_id;
  update public.tenders set status = 'awarded', awarded_bid_id = p_bid_id, closed_at = now() where id = p_tender_id;

  for sup in select b.app_user_id from public.bids b where b.tender_id = p_tender_id and b.app_user_id is not null loop
    if sup.app_user_id = win_user then
      perform public.app_notif_send(sup.app_user_id, 'Вы выбраны: ' || ttitle, 'Ваше КП принято', 'apps/supplier/index.html');
    else
      perform public.app_notif_send(sup.app_user_id, 'Закупка ' || ttitle || ': победитель определён', 'Ваше КП отклонено', 'apps/supplier/index.html');
    end if;
  end loop;
  return query select true, 'Победитель: ' || coalesce(win_name,'—');
end $$;

-- ---------- Смена статуса закупки ----------
create or replace function public.app_tender_set_status(p_token uuid, p_tender_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  update public.tenders set status = p_status, closed_at = case when p_status in ('closed','awarded') then now() else closed_at end
   where id = p_tender_id;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- Аккредитация учитывается при подаче КП ----------
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; uname text; ttitle text; pstatus text;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  select p.status into pstatus from public.app_supplier_profiles p where p.app_user_id = uid;
  if pstatus = 'rejected' then return query select false, 'Аккредитация отклонена — подача КП недоступна'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/procurement/index.html');
  return query select true, 'Предложение сохранено';
end $$;

grant execute on function public.app_supplier_profile_get(uuid) to anon, authenticated;
grant execute on function public.app_supplier_profile_save(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date) to anon, authenticated;
grant execute on function public.app_tender_list_full(uuid) to anon, authenticated;
grant execute on function public.app_bids_for_tender(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tender_award(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_tender_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.supplier_submit_bid(uuid,uuid,numeric,integer,text) to anon, authenticated;
-- <<<<<<<<<< 0008_procurement.sql <<<<<<<<<<

-- >>>>>>>>>> 0009_tenancy.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0009_tenancy.sql  (v1.4.1 — мультитенантность данных)
-- Изоляция по организации (tenant_id): каждый видит только данные своего тенанта.
-- admin (платформа) — видит всё. Поставщики — внешние (витрина + свои КП).
-- Зависит от 0001..0008. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Демо-тенанты ----------
insert into public.tenants (id, name, slug, plan, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'ООО «3Д Металлообработка Пресс»', '3dmp', 'business', 'active')
on conflict (id) do nothing;
insert into public.tenants (id, name, slug, plan, status) values
  ('bbbbbbbb-0000-0000-0000-000000000002', 'ООО «Клиент-2»', 'client2', 'business', 'active')
on conflict (id) do nothing;

-- ---------- Тенант у пользователей ----------
alter table public.app_users add column if not exists tenant_id uuid references public.tenants (id);
update public.app_users set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;

-- Второй пользователь другого тенанта (для проверки изоляции)
insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values ('client2', extensions.crypt('client2', extensions.gen_salt('bf')), 'Заказчик Клиент-2', 'owner',
        'bbbbbbbb-0000-0000-0000-000000000002')
on conflict (login) do update set tenant_id = 'bbbbbbbb-0000-0000-0000-000000000002', role = 'owner';

-- ---------- tenant_id в бизнес-таблицах ----------
alter table public.app_orders        add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_naryads       add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_work_centers  add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_norms         add column if not exists tenant_id uuid references public.tenants (id);
alter table public.tenders           add column if not exists tenant_id uuid references public.tenants (id);

update public.app_orders       set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_naryads      set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_work_centers set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_norms        set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.tenders          set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;

create index if not exists app_orders_tenant_idx   on public.app_orders (tenant_id);
create index if not exists app_naryads_tenant_idx  on public.app_naryads (tenant_id);
create index if not exists tenders_tenant_idx      on public.tenders (tenant_id);

-- ---------- Хелперы тенанта ----------
create or replace function public.app_my_tenant(p_token uuid)
returns uuid language sql security definer set search_path = public
as $$
  select u.tenant_id from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

create or replace function public.app_is_platform_admin(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (select 1 from public.app_session_user(p_token) s where s.urole = 'admin');
$$;

-- Уведомления в рамках тенанта
create or replace function public.app_notif_roles_t(p_tenant uuid, p_roles text[], p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  select u.id, left(p_title,200), left(coalesce(p_body,''),500), p_link
  from public.app_users u
  where u.active and u.role = any(p_roles) and (p_tenant is null or u.tenant_id = p_tenant);
$$;

-- ============================================================
--  ЗАЯВКИ (app_orders) — изоляция по тенанту
-- ============================================================
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, contact, priority, status, created_by, created_login, tenant_id)
  values (onum, trim(p_title), nullif(trim(p_description),''), nullif(trim(p_source),''), nullif(trim(p_customer),''),
          nullif(trim(p_contact),''), coalesce(nullif(trim(p_priority),''),'normal'), 'new', uid, ulogin, ten)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.contact,
           o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

create or replace function public.app_order_history_list(p_token uuid, p_id uuid)
returns table (status text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select h.status, h.comment, h.by_login, h.created_at
    from public.app_order_history h join public.app_orders o on o.id = h.order_id
    where h.order_id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))
    order by h.created_at;
end $$;

create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; owner uuid; onum text; oten uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select o.created_by, o.number, o.tenant_id into owner, onum, oten from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole = 'admin' or (oten = ten and (urole in ('owner','manager') or owner = uid))) then
    return query select false, 'Доступ запрещён'; return;
  end if;
  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment),''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment,''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ============================================================
--  ЗАКУПКИ (tenders/bids) — витрина открыта поставщикам, управление — по тенанту
-- ============================================================
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; tid uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;
  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status, created_by, tenant_id)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, 'open', uid, ten)
  returning tenders.id into tid;
  return query select tid, 'Закупка опубликована';
end $$;

create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.category, t.customer, t.deadline, t.status,
           (select count(*) from public.bids b where b.tender_id = t.id), t.awarded_bid_id, t.created_at
    from public.tenders t
    where (urole = 'admin' or t.tenant_id = ten)
    order by t.created_at desc;
end $$;

create or replace function public.app_bids_for_tender(p_token uuid, p_tender_id uuid)
returns table (id uuid, supplier_name text, price numeric, term_days integer, comment text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (urole = 'admin' or exists (select 1 from public.tenders t where t.id = p_tender_id and t.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select b.id, b.supplier_name, b.price, b.term_days, b.comment, b.status, b.created_at
    from public.bids b where b.tender_id = p_tender_id order by b.price asc, b.created_at;
end $$;

create or replace function public.app_tender_award(p_token uuid, p_tender_id uuid, p_bid_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; ttitle text; win_user uuid; win_name text; sup record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.title into ttitle from public.tenders t
    where t.id = p_tender_id and (urole = 'admin' or t.tenant_id = ten);
  if ttitle is null then return query select false,'Закупка не найдена'; return; end if;
  select b.app_user_id, b.supplier_name into win_user, win_name from public.bids b where b.id = p_bid_id and b.tender_id = p_tender_id;
  if win_user is null then return query select false,'Предложение не найдено'; return; end if;

  update public.bids set status = case when id = p_bid_id then 'accepted' else 'rejected' end where tender_id = p_tender_id;
  update public.tenders set status = 'awarded', awarded_bid_id = p_bid_id, closed_at = now() where id = p_tender_id;

  for sup in select b.app_user_id from public.bids b where b.tender_id = p_tender_id and b.app_user_id is not null loop
    if sup.app_user_id = win_user then
      perform public.app_notif_send(sup.app_user_id, 'Вы выбраны: ' || ttitle, 'Ваше КП принято', 'apps/supplier/index.html');
    else
      perform public.app_notif_send(sup.app_user_id, 'Закупка ' || ttitle || ': победитель определён', 'Ваше КП отклонено', 'apps/supplier/index.html');
    end if;
  end loop;
  return query select true, 'Победитель: ' || coalesce(win_name,'—');
end $$;

create or replace function public.app_tender_set_status(p_token uuid, p_tender_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.tenders set status = p_status,
         closed_at = case when p_status in ('closed','awarded') then now() else closed_at end
   where id = p_tender_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Статус обновлён';
end $$;

-- supplier_submit_bid: уведомляем закупщиков тенанта закупки
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; uname text; ttitle text; pstatus text; tten uuid;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  select p.status into pstatus from public.app_supplier_profiles p where p.app_user_id = uid;
  if pstatus = 'rejected' then return query select false, 'Аккредитация отклонена — подача КП недоступна'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  select t.title, t.tenant_id into ttitle, tten from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles_t(tten, array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/procurement/index.html');
  return query select true, 'Предложение сохранено';
end $$;

-- ============================================================
--  ПРОИЗВОДСТВО — изоляция по тенанту
-- ============================================================
create or replace function public.app_wc_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, cost_hour numeric, active boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select w.id, w.code, w.name, w.kind, w.cost_hour, w.active from public.app_work_centers w
    where (urole = 'admin' or w.tenant_id = ten) order by w.name;
end $$;

create or replace function public.app_norms_list(p_token uuid)
returns table (id uuid, operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n
    where (urole = 'admin' or n.tenant_id = ten) order by n.operation;
end $$;

create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, o.number, w.name, n.assignee, n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by n.created_at desc;
end $$;

create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;
  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, created_by, created_login, tenant_id)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee),''), 'open', uid, ulogin, ten)
  returning app_naryads.id into nid;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u
      where lower(u.login) = lower(trim(p_assignee)) and u.active and (u.tenant_id = ten) limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select op.id, op.seq, op.operation, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.naryad_id = p_id and (urole = 'admin' or n.tenant_id = ten)
    order by op.seq, op.created_at;
end $$;

create or replace function public.app_naryad_add_op(
  p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare seqn integer; nid uuid; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  if coalesce(trim(p_operation),'') = '' then return query select false,'Укажите операцию'; return; end if;
  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours)
  values (p_naryad_id, seqn, trim(p_operation), nullif(trim(p_worker),''), coalesce(p_plan_hours,0));
  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare nid uuid; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select op.naryad_id into nid from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.id = p_op_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;
  return query select true,'Обновлено';
end $$;

create or replace function public.app_naryad_close(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; nnum text; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.number into nnum from public.app_naryads n where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
  if nnum is null then return query select false,'Наряд не найден'; return; end if;
  update public.app_naryads n set status = 'closed', updated_at = now(),
    fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = p_id;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Наряд ' || nnum || ' закрыт', 'Закрыл: ' || coalesce(ulogin,''), 'apps/production/index.html');
  return query select true,'Наряд закрыт';
end $$;

-- ---------- app_me: + tenant ----------
drop function if exists public.app_me(uuid);
create function public.app_me(p_token uuid)
returns table (user_id uuid, login text, full_name text, role text, last_login_at timestamptz, tenant_id uuid, tenant_name text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.full_name, u.role, u.last_login_at, u.tenant_id, t.name
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  left join public.tenants t on t.id = u.tenant_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;
grant execute on function public.app_me(uuid) to anon, authenticated;

-- ---------- Привязка демо-закупок к тенанту A ----------
update public.tenders set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
-- <<<<<<<<<< 0009_tenancy.sql <<<<<<<<<<

-- >>>>>>>>>> 0010_warehouse.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0010_warehouse.sql  (v1.5 — склад и BOM)
-- Материалы, движения (приход/расход), спецификации изделия. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0009. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Материалы ----------
create table if not exists public.app_materials (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text,
  name       text not null,
  unit       text,
  price      numeric default 0,
  qty        numeric not null default 0,
  min_qty    numeric not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists app_materials_tenant_idx on public.app_materials (tenant_id);

-- ---------- Движения склада ----------
create table if not exists public.app_stock_moves (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  material_id uuid not null references public.app_materials (id) on delete cascade,
  kind        text not null,               -- in | out
  qty         numeric not null,
  price       numeric default 0,
  note        text,
  source      text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_stock_moves_mat_idx on public.app_stock_moves (material_id, created_at desc);

-- ---------- Спецификации (BOM) ----------
create table if not exists public.app_bom (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  order_id    uuid references public.app_orders (id) on delete set null,
  product     text not null,
  version     text default '1',
  note        text,
  created_by  uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_bom_tenant_idx on public.app_bom (tenant_id);

create table if not exists public.app_bom_lines (
  id          uuid primary key default gen_random_uuid(),
  bom_id      uuid not null references public.app_bom (id) on delete cascade,
  seq         integer default 0,
  item_type   text not null default 'material',  -- material | operation
  material_id uuid references public.app_materials (id) on delete set null,
  name        text not null,
  qty         numeric default 0,
  unit        text,
  norm_hours  numeric default 0
);
create index if not exists app_bom_lines_bom_idx on public.app_bom_lines (bom_id);

alter table public.app_materials   enable row level security;
alter table public.app_stock_moves enable row level security;
alter table public.app_bom         enable row level security;
alter table public.app_bom_lines   enable row level security;

-- ---------- Материалы: список ----------
create or replace function public.app_material_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric, low boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty, (m.qty < m.min_qty) as low
    from public.app_materials m where (urole = 'admin' or m.tenant_id = ten) and m.active order by m.name;
end $$;

-- ---------- Материал: создать/изменить ----------
create or replace function public.app_material_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_unit text, p_price numeric, p_min_qty numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_materials (tenant_id, code, name, unit, price, min_qty)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_unit),''), coalesce(p_price,0), coalesce(p_min_qty,0));
  else
    update public.app_materials set code = nullif(trim(p_code),''), name = trim(p_name), unit = nullif(trim(p_unit),''),
      price = coalesce(p_price,0), min_qty = coalesce(p_min_qty,0), updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Движение (приход/расход) ----------
create or replace function public.app_stock_move(
  p_token uuid, p_material_id uuid, p_kind text, p_qty numeric, p_price numeric, p_note text, p_source text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; m public.app_materials; newqty numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into m from public.app_materials where id = p_material_id and (urole = 'admin' or tenant_id = ten);
  if m.id is null then return query select false,'Материал не найден'; return; end if;
  if p_kind not in ('in','out') then return query select false,'Неверный тип движения'; return; end if;
  if coalesce(p_qty,0) <= 0 then return query select false,'Количество должно быть > 0'; return; end if;

  newqty := case when p_kind = 'in' then m.qty + p_qty else m.qty - p_qty end;
  if newqty < 0 then return query select false,'Недостаточно на складе'; return; end if;

  insert into public.app_stock_moves (tenant_id, material_id, kind, qty, price, note, source, by_login)
  values (m.tenant_id, m.id, p_kind, p_qty, coalesce(p_price,0), nullif(trim(p_note),''), nullif(trim(p_source),''), ulogin);
  update public.app_materials set qty = newqty, updated_at = now() where id = m.id;

  if newqty < m.min_qty then
    perform public.app_notif_roles_t(m.tenant_id, array['admin','manager','owner'],
      'Низкий остаток: ' || m.name, 'Остаток ' || newqty || ' ' || coalesce(m.unit,'') || ' (мин ' || m.min_qty || ')', 'apps/warehouse/index.html');
  end if;
  return query select true,'Движение проведено';
end $$;

-- ---------- История движений ----------
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.kind, v.qty, v.price, v.note, v.by_login, v.created_at
    from public.app_stock_moves v join public.app_materials m on m.id = v.material_id
    where v.material_id = p_material_id and (urole = 'admin' or m.tenant_id = ten)
    order by v.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

-- ---------- BOM: список ----------
create or replace function public.app_bom_list(p_token uuid)
returns table (id uuid, product text, version text, order_number text, lines_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.product, b.version, o.number,
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id), b.created_at
    from public.app_bom b left join public.app_orders o on o.id = b.order_id
    where (urole = 'admin' or b.tenant_id = ten)
    order by b.created_at desc;
end $$;

create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, name text, qty numeric, unit text, norm_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.seq, l.item_type, l.name, l.qty, l.unit, l.norm_hours
    from public.app_bom_lines l join public.app_bom b on b.id = l.bom_id
    where l.bom_id = p_bom_id and (urole = 'admin' or b.tenant_id = ten)
    order by l.seq, l.id;
end $$;

-- ---------- BOM: сохранить (шапка + позиции) ----------
create or replace function public.app_bom_save(
  p_token uuid, p_id uuid, p_order_id uuid, p_product text, p_version text, p_lines jsonb
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; bid uuid; ln jsonb; i integer := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;

  if p_id is null then
    insert into public.app_bom (tenant_id, order_id, product, version, created_by, created_login)
    values (ten, p_order_id, trim(p_product), coalesce(nullif(trim(p_version),''),'1'), uid, ulogin)
    returning app_bom.id into bid;
  else
    update public.app_bom set order_id = p_order_id, product = trim(p_product),
      version = coalesce(nullif(trim(p_version),''),'1'), updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten)
     returning app_bom.id into bid;
    delete from public.app_bom_lines where bom_id = bid;
  end if;

  if p_lines is not null then
    for ln in select * from jsonb_array_elements(p_lines) loop
      i := i + 1;
      insert into public.app_bom_lines (bom_id, seq, item_type, material_id, name, qty, unit, norm_hours)
      values (bid, i,
              coalesce(nullif(ln->>'item_type',''),'material'),
              nullif(ln->>'material_id','')::uuid,
              coalesce(nullif(ln->>'name',''),'—'),
              coalesce((ln->>'qty')::numeric,0),
              nullif(ln->>'unit',''),
              coalesce((ln->>'norm_hours')::numeric,0));
    end loop;
  end if;
  return query select bid, 'Спецификация сохранена';
end $$;

grant execute on function public.app_material_list(uuid) to anon, authenticated;
grant execute on function public.app_material_save(uuid,uuid,text,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_stock_moves_list(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_bom_list(uuid) to anon, authenticated;
grant execute on function public.app_bom_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_bom_save(uuid,uuid,uuid,text,text,jsonb) to anon, authenticated;

-- ---------- Демо-материалы (тенант A) ----------
insert into public.app_materials (tenant_id, code, name, unit, price, qty, min_qty)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.unit, v.price, v.qty, v.min_qty
from (values
  ('М-40Х','Сталь 40Х, круг', 'кг', 120, 500, 100),
  ('М-45','Сталь 45, круг', 'кг', 95, 800, 150),
  ('М-Д16Т','Алюминий Д16Т, лист', 'кг', 480, 120, 60),
  ('М-09Г2С','Сталь 09Г2С, лист 4 мм', 'лист', 5200, 40, 10)
) as v(code,name,unit,price,qty,min_qty)
where not exists (select 1 from public.app_materials where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0010_warehouse.sql <<<<<<<<<<

-- >>>>>>>>>> 0011_planning.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0011_planning.sql  (v1.6 — планирование)
-- План-даты нарядов, диаграмма Ганта, загрузка рабочих центров.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0010.
-- ============================================================

alter table public.app_naryads add column if not exists plan_start date;
alter table public.app_naryads add column if not exists plan_end date;

-- демо: проставить план-даты существующим нарядам
update public.app_naryads set plan_start = created_at::date, plan_end = (created_at::date + 3)
 where plan_start is null;

create index if not exists app_naryads_plan_idx on public.app_naryads (plan_start, plan_end);

-- ---------- Гант: наряды с план-датами ----------
create or replace function public.app_schedule(p_token uuid)
returns table (id uuid, number text, title text, wc_name text, assignee text, status text,
               plan_start date, plan_end date, due_date date, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, w.name, n.assignee, n.status,
           n.plan_start, n.plan_end, n.due_date, n.plan_hours, n.fact_hours
    from public.app_naryads n
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by coalesce(n.plan_start, n.created_at::date), n.created_at;
end $$;

-- ---------- Загрузка рабочих центров ----------
create or replace function public.app_capacity(p_token uuid)
returns table (wc_id uuid, wc_name text, kind text, cost_hour numeric,
               active_naryads bigint, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.name, w.kind, w.cost_hour,
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress')),
           coalesce((select sum(n.plan_hours) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress')), 0),
           coalesce((select sum(n.fact_hours) from public.app_naryads n where n.wc_id = w.id), 0)
    from public.app_work_centers w
    where (urole = 'admin' or w.tenant_id = ten)
    order by w.name;
end $$;

-- ---------- Назначить план-даты наряду ----------
create or replace function public.app_naryad_schedule(p_token uuid, p_id uuid, p_start date, p_end date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_naryads set plan_start = p_start, plan_end = p_end, updated_at = now()
   where id = p_id
     and (urole = 'admin' or tenant_id = ten)
     and (p_end is null or p_start is null or p_end >= p_start);
  return query select true,'Сроки обновлены';
end $$;

grant execute on function public.app_schedule(uuid) to anon, authenticated;
grant execute on function public.app_capacity(uuid) to anon, authenticated;
grant execute on function public.app_naryad_schedule(uuid,uuid,date,date) to anon, authenticated;
-- <<<<<<<<<< 0011_planning.sql <<<<<<<<<<

-- >>>>>>>>>> 0012_quality.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0012_quality.sql  (v1.7 — качество и паспорт изделия)
-- ОТК-чек-листы, дефекты, паспорт изделия. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0011. public.orders НЕ трогаем.
-- ============================================================

create sequence if not exists public.app_qc_seq;
create sequence if not exists public.app_passport_seq;

-- ---------- Чек-листы ОТК ----------
create table if not exists public.app_qc_checks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  order_id      uuid references public.app_orders (id) on delete set null,
  product       text,
  status        text not null default 'draft',   -- draft | passed | failed
  inspector     text,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  checked_at    timestamptz
);
create index if not exists app_qc_tenant_idx on public.app_qc_checks (tenant_id, created_at desc);

create table if not exists public.app_qc_lines (
  id       uuid primary key default gen_random_uuid(),
  check_id uuid not null references public.app_qc_checks (id) on delete cascade,
  name     text not null,
  norm     text,
  value    text,
  result   text not null default 'ok'     -- ok | no
);
create index if not exists app_qc_lines_idx on public.app_qc_lines (check_id);

-- ---------- Дефекты ----------
create table if not exists public.app_defects (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  check_id   uuid references public.app_qc_checks (id) on delete set null,
  title      text not null,
  qty        numeric default 1,
  severity   text not null default 'minor',   -- minor | major | critical
  status     text not null default 'open',    -- open | resolved
  note       text,
  by_login   text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists app_defects_tenant_idx on public.app_defects (tenant_id, created_at desc);

-- ---------- Паспорт изделия ----------
create table if not exists public.app_passports (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  product       text not null,
  qc_check_id   uuid references public.app_qc_checks (id) on delete set null,
  data          jsonb default '{}'::jsonb,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_passports_tenant_idx on public.app_passports (tenant_id, created_at desc);

alter table public.app_qc_checks enable row level security;
alter table public.app_qc_lines  enable row level security;
alter table public.app_defects   enable row level security;
alter table public.app_passports enable row level security;

-- ---------- ОТК: список ----------
create or replace function public.app_qc_list(p_token uuid)
returns table (id uuid, number text, product text, status text, inspector text, naryad_number text,
               order_number text, lines_count bigint, defects_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.number, c.product, c.status, c.inspector, n.number, o.number,
           (select count(*) from public.app_qc_lines l where l.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id),
           c.created_at
    from public.app_qc_checks c
    left join public.app_naryads n on n.id = c.naryad_id
    left join public.app_orders o on o.id = c.order_id
    where (urole = 'admin' or c.tenant_id = ten)
    order by c.created_at desc;
end $$;

-- ---------- ОТК: создать ----------
create or replace function public.app_qc_create(p_token uuid, p_naryad_id uuid, p_order_id uuid, p_product text, p_inspector text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; cid uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  cnum := 'QCK-' || lpad(nextval('public.app_qc_seq')::text, 5, '0');
  insert into public.app_qc_checks (tenant_id, number, naryad_id, order_id, product, inspector, created_by, created_login)
  values (ten, cnum, p_naryad_id, p_order_id, nullif(trim(p_product),''), nullif(trim(p_inspector),''), uid, ulogin)
  returning app_qc_checks.id into cid;
  return query select cid, cnum;
end $$;

-- ---------- ОТК: позиции ----------
create or replace function public.app_qc_add_line(p_token uuid, p_check_id uuid, p_name text, p_norm text, p_value text, p_result text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.id into cid from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cid is null then return query select false,'Чек-лист не найден'; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите параметр'; return; end if;
  insert into public.app_qc_lines (check_id, name, norm, value, result)
  values (cid, trim(p_name), nullif(trim(p_norm),''), nullif(trim(p_value),''), coalesce(nullif(trim(p_result),''),'ok'));
  return query select true,'Позиция добавлена';
end $$;

create or replace function public.app_qc_lines_list(p_token uuid, p_check_id uuid)
returns table (id uuid, name text, norm text, value text, result text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.name, l.norm, l.value, l.result
    from public.app_qc_lines l join public.app_qc_checks c on c.id = l.check_id
    where l.check_id = p_check_id and (urole='admin' or c.tenant_id = ten) order by l.id;
end $$;

-- ---------- ОТК: статус (passed/failed) ----------
create or replace function public.app_qc_set_status(p_token uuid, p_check_id uuid, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.number into cnum from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cnum is null then return query select false,'Чек-лист не найден'; return; end if;
  update public.app_qc_checks set status = p_status, note = nullif(trim(p_note),''), checked_at = now() where id = p_check_id;
  if p_status = 'failed' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'ОТК: брак по ' || cnum, coalesce(p_note,''), 'apps/qc/index.html');
  end if;
  return query select true, case when p_status = 'passed' then 'Принято' else 'Зафиксирован брак' end;
end $$;

-- ---------- Дефекты ----------
create or replace function public.app_defect_list(p_token uuid)
returns table (id uuid, title text, qty numeric, severity text, status text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.title, d.qty, d.severity, d.status, d.note, d.by_login, d.created_at
    from public.app_defects d where (urole='admin' or d.tenant_id = ten) order by d.created_at desc;
end $$;

create or replace function public.app_defect_add(p_token uuid, p_check_id uuid, p_title text, p_qty numeric, p_severity text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then return query select false,'Опишите дефект'; return; end if;
  insert into public.app_defects (tenant_id, check_id, title, qty, severity, note, by_login)
  values (ten, p_check_id, trim(p_title), coalesce(p_qty,1), coalesce(nullif(trim(p_severity),''),'minor'), nullif(trim(p_note),''), ulogin);
  if p_severity = 'critical' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Критический дефект', trim(p_title), 'apps/qc/index.html');
  end if;
  return query select true,'Дефект зарегистрирован';
end $$;

create or replace function public.app_defect_resolve(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_defects set status='resolved', note = coalesce(nullif(trim(p_note),''), note), resolved_at = now()
   where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Дефект закрыт';
end $$;

-- ---------- Паспорт изделия ----------
create or replace function public.app_passport_create(p_token uuid, p_order_id uuid, p_product text, p_qc_check_id uuid, p_data jsonb)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; pid uuid; pnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;
  pnum := 'PAS-' || lpad(nextval('public.app_passport_seq')::text, 5, '0');
  insert into public.app_passports (tenant_id, number, order_id, product, qc_check_id, data, created_by, created_login)
  values (ten, pnum, p_order_id, trim(p_product), p_qc_check_id, coalesce(p_data,'{}'::jsonb), uid, ulogin)
  returning app_passports.id into pid;
  return query select pid, pnum;
end $$;

create or replace function public.app_passport_list(p_token uuid)
returns table (id uuid, number text, product text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.number, p.product, o.number, p.created_at
    from public.app_passports p left join public.app_orders o on o.id = p.order_id
    where (urole='admin' or p.tenant_id = ten) order by p.created_at desc;
end $$;

create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, order_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.number, p.product, o.number, p.data, p.created_login, p.created_at
    from public.app_passports p left join public.app_orders o on o.id = p.order_id
    where p.id = p_id and (urole='admin' or p.tenant_id = ten);
end $$;

grant execute on function public.app_qc_list(uuid) to anon, authenticated;
grant execute on function public.app_qc_create(uuid,uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_qc_add_line(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_qc_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_qc_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_defect_list(uuid) to anon, authenticated;
grant execute on function public.app_defect_add(uuid,uuid,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_defect_resolve(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_passport_create(uuid,uuid,text,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_passport_list(uuid) to anon, authenticated;
grant execute on function public.app_passport_get(uuid,uuid) to anon, authenticated;
-- <<<<<<<<<< 0012_quality.sql <<<<<<<<<<

-- >>>>>>>>>> 0013_economics.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0013_economics.sql  (v1.8 — экономика)
-- Себестоимость заявки, нормочас, сводные KPI. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0012.
-- ============================================================

-- ---------- Ставки (справочник) ----------
create table if not exists public.app_cost_rates (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  kind       text not null default 'machine',  -- machine | labor | overhead
  name       text not null,
  rate_hour  numeric not null default 0,
  note       text
);
alter table public.app_cost_rates enable row level security;

-- Сумма заказа (для маржи, необязательно)
alter table public.app_orders add column if not exists amount numeric;

-- ---------- Ставки: список ----------
create or replace function public.app_cost_rates_list(p_token uuid)
returns table (id uuid, kind text, name text, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.kind, r.name, r.rate_hour from public.app_cost_rates r
    where (urole='admin' or r.tenant_id = ten) order by r.kind, r.name;
end $$;

-- ---------- Себестоимость заявки ----------
create or replace function public.app_order_cost(p_token uuid, p_order_id uuid)
returns table (plan_hours numeric, fact_hours numeric, work_cost numeric,
               material_cost numeric, overhead numeric, total numeric, amount numeric, margin numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; oten uuid; amt numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.tenant_id, o.amount into oten, amt from public.app_orders o where o.id = p_order_id;
  if oten is null or not (urole='admin' or oten = ten) then raise exception 'Доступ запрещён'; end if;

  return query
  with w as (
    select coalesce(sum(coalesce(nullif(n.fact_hours,0), n.plan_hours)),0) as ph,
           coalesce(sum(n.fact_hours),0) as fh,
           coalesce(sum(coalesce(nullif(n.fact_hours,0), n.plan_hours) * coalesce(wc.cost_hour,0)),0) as wcost
    from public.app_naryads n left join public.app_work_centers wc on wc.id = n.wc_id
    where n.order_id = p_order_id
  ), m as (
    select coalesce(sum(l.qty * coalesce(mat.price,0)),0) as mcost
    from public.app_bom b
    join public.app_bom_lines l on l.bom_id = b.id and l.item_type = 'material'
    left join public.app_materials mat on mat.id = l.material_id
    where b.order_id = p_order_id
  )
  select w.ph, w.fh, w.wcost, m.mcost,
         round((w.wcost + m.mcost) * 0.15, 2) as overhead,
         round((w.wcost + m.mcost) * 1.15, 2) as total,
         amt,
         case when amt is not null then round(amt - (w.wcost + m.mcost) * 1.15, 2) else null end as margin
  from w, m;
end $$;

-- ---------- Сводные KPI ----------
create or replace function public.app_economics(p_token uuid)
returns table (orders_total bigint, orders_open bigint, naryads_open bigint, naryads_closed bigint,
               plan_hours numeric, fact_hours numeric, defects_open bigint, low_stock bigint, avg_rate numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_orders o where (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_orders o where o.status in ('new','in_progress') and (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_naryads n where n.status in ('open','in_progress') and (urole='admin' or n.tenant_id=ten)),
    (select count(*) from public.app_naryads n where n.status='closed' and (urole='admin' or n.tenant_id=ten)),
    (select coalesce(sum(n.plan_hours),0) from public.app_naryads n where (urole='admin' or n.tenant_id=ten)),
    (select coalesce(sum(n.fact_hours),0) from public.app_naryads n where (urole='admin' or n.tenant_id=ten)),
    (select count(*) from public.app_defects d where d.status='open' and (urole='admin' or d.tenant_id=ten)),
    (select count(*) from public.app_materials m where m.qty < m.min_qty and (urole='admin' or m.tenant_id=ten)),
    (select coalesce(round(avg(w.cost_hour)),0) from public.app_work_centers w where (urole='admin' or w.tenant_id=ten));
end $$;

grant execute on function public.app_cost_rates_list(uuid) to anon, authenticated;
grant execute on function public.app_order_cost(uuid,uuid) to anon, authenticated;
grant execute on function public.app_economics(uuid) to anon, authenticated;

-- ---------- Демо-ставки ----------
insert into public.app_cost_rates (tenant_id, kind, name, rate_hour)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.kind, v.name, v.rate_hour
from (values
  ('machine','Фрезерный ЧПУ', 3500::numeric),
  ('machine','Токарный ЧПУ', 3000::numeric),
  ('machine','Лазер', 4200::numeric),
  ('labor','Слесарь/сборщик', 1800::numeric),
  ('overhead','Накладные, %', 15::numeric)
) as v(kind,name,rate_hour)
where not exists (select 1 from public.app_cost_rates where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0013_economics.sql <<<<<<<<<<

-- >>>>>>>>>> 0014_platform.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0014_platform.sql  (v2.0 — SaaS-платформа)
-- Управление организацией: пользователи тенанта, тарифы, лимиты, feature flags.
-- Зависит от 0001..0013.
-- ============================================================

-- ---------- Тарифы ----------
create table if not exists public.app_plans (
  code       text primary key,
  name       text not null,
  price      numeric not null default 0,
  max_users  integer,
  features   jsonb not null default '{}'::jsonb,
  sort       integer default 0
);
alter table public.app_plans enable row level security;

insert into public.app_plans (code, name, price, max_users, features, sort) values
  ('start',    'Старт',         9900,  5,  '{"modules":["orders","dashboard"]}'::jsonb, 1),
  ('business', 'Бизнес',       19900, 25,  '{"modules":["orders","production","procurement","warehouse","bom","planning","qc","passport","economics","reports"]}'::jsonb, 2),
  ('corp',     'Корпоративный',39900, null,'{"modules":["*"]}'::jsonb, 3)
on conflict (code) do update set name=excluded.name, price=excluded.price, max_users=excluded.max_users, features=excluded.features, sort=excluded.sort;

-- ---------- Флаги тенанта ----------
alter table public.tenants add column if not exists features jsonb not null default '{}'::jsonb;

-- ---------- Хелперы ----------
create or replace function public.app_is_owner(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (select 1 from public.app_session_user(p_token) s where s.urole in ('owner','admin'));
$$;

-- ---------- Инфо об организации ----------
create or replace function public.app_tenant_info(p_token uuid)
returns table (id uuid, name text, plan text, plan_name text, max_users integer,
               users_count bigint, features jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if ten is null then return; end if;
  return query
    select t.id, t.name, t.plan, p.name, p.max_users,
           (select count(*) from public.app_users u2 where u2.tenant_id = t.id),
           t.features, t.created_at
    from public.tenants t
    left join public.app_plans p on p.code = t.plan
    where t.id = ten;
end $$;

-- ---------- Пользователи тенанта ----------
create or replace function public.app_tenant_users(p_token uuid)
returns table (id uuid, login text, full_name text, role text, active boolean, last_login_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  select u.tenant_id, s.urole into ten, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if urole not in ('owner','manager','admin') then raise exception 'Доступ запрещён'; end if;
  return query select u.id, u.login, u.full_name, u.role, u.active, u.last_login_at, u.created_at
    from public.app_users u where u.tenant_id = ten order by u.created_at;
end $$;

create or replace function public.app_tenant_user_create(p_token uuid, p_login text, p_password text, p_full_name text, p_role text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
declare ten uuid; cnt bigint; mx integer;
begin
  if not public.app_is_owner(p_token) then return query select false,'Только владелец организации может добавлять пользователей'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_login),'') = '' then return query select false,'Укажите логин'; return; end if;
  if length(coalesce(p_password,'')) < 4 then return query select false,'Пароль — минимум 4 символа'; return; end if;
  if exists (select 1 from public.app_users where lower(login) = lower(trim(p_login))) then return query select false,'Логин уже занят'; return; end if;

  select count(*) into cnt from public.app_users u where u.tenant_id = ten;
  select p.max_users into mx from public.tenants t left join public.app_plans p on p.code = t.plan where t.id = ten;
  if mx is not null and cnt >= mx then return query select false,'Достигнут лимит пользователей тарифа'; return; end if;

  insert into public.app_users (login, password_hash, full_name, role, tenant_id)
  values (lower(trim(p_login)), extensions.crypt(p_password, extensions.gen_salt('bf')),
          nullif(trim(p_full_name),''), coalesce(nullif(trim(p_role),''),'manager'), ten);
  return query select true,'Пользователь добавлен';
end $$;

create or replace function public.app_tenant_user_update(p_token uuid, p_user_id uuid, p_role text, p_active boolean, p_full_name text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; caller uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id, s.uid into ten, caller from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_user_id = caller and (p_active is false or (p_role is not null and p_role <> 'owner')) then
    return query select false,'Нельзя менять свою роль/доступ'; return;
  end if;
  update public.app_users set role = coalesce(p_role, role), active = coalesce(p_active, active), full_name = coalesce(p_full_name, full_name)
   where id = p_user_id and tenant_id = ten;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_tenant_user_reset(p_token uuid, p_user_id uuid, p_password text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  if length(coalesce(p_password,'')) < 4 then return query select false,'Пароль — минимум 4 символа'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.app_users set password_hash = extensions.crypt(p_password, extensions.gen_salt('bf'))
   where id = p_user_id and tenant_id = ten;
  return query select true,'Пароль изменён';
end $$;

-- ---------- Тарифы и смена ----------
create or replace function public.app_plans_list(p_token uuid)
returns table (code text, name text, price numeric, max_users integer, features jsonb)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_is_owner(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select p.code, p.name, p.price, p.max_users, p.features from public.app_plans p order by p.sort;
end $$;

create or replace function public.app_tenant_set_plan(p_token uuid, p_plan text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if not exists (select 1 from public.app_plans where code = p_plan) then return query select false,'Тариф не найден'; return; end if;
  update public.tenants set plan = p_plan where id = ten;
  return query select true,'Тариф изменён';
end $$;

-- ---------- Feature flags ----------
create or replace function public.app_tenant_flags(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare ten uuid; f jsonb;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select t.features into f from public.tenants t where t.id = ten;
  return coalesce(f, '{}'::jsonb);
end $$;

create or replace function public.app_tenant_set_flag(p_token uuid, p_module text, p_enabled boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.tenants
     set features = jsonb_set(coalesce(features,'{}'::jsonb), array[p_module], to_jsonb(coalesce(p_enabled,false)), true)
   where id = ten;
  return query select true,'Флаг обновлён';
end $$;

grant execute on function public.app_is_owner(uuid) to anon, authenticated;
grant execute on function public.app_tenant_info(uuid) to anon, authenticated;
grant execute on function public.app_tenant_users(uuid) to anon, authenticated;
grant execute on function public.app_tenant_user_create(uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_tenant_user_update(uuid,uuid,text,boolean,text) to anon, authenticated;
grant execute on function public.app_tenant_user_reset(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_plans_list(uuid) to anon, authenticated;
grant execute on function public.app_tenant_set_plan(uuid,text) to anon, authenticated;
grant execute on function public.app_tenant_flags(uuid) to anon, authenticated;
grant execute on function public.app_tenant_set_flag(uuid,text,boolean) to anon, authenticated;
-- <<<<<<<<<< 0014_platform.sql <<<<<<<<<<

-- >>>>>>>>>> 0015_finance.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0015_finance.sql  (v2.2 — финансы)
-- Счета, платежи, взаиморасчёты (дебиторка). Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0014.
-- ============================================================

create sequence if not exists public.app_invoice_seq;

create table if not exists public.app_invoices (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  customer      text,
  amount        numeric not null default 0,
  status        text not null default 'draft',   -- draft | sent | paid | overdue | cancelled
  due_date      date,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  paid_at       timestamptz
);
create index if not exists app_invoices_tenant_idx on public.app_invoices (tenant_id, created_at desc);

create table if not exists public.app_payments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  invoice_id  uuid not null references public.app_invoices (id) on delete cascade,
  amount      numeric not null,
  method      text not null default 'bank',   -- cash | bank | card
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_payments_invoice_idx on public.app_payments (invoice_id, created_at desc);

alter table public.app_invoices enable row level security;
alter table public.app_payments enable row level security;

-- ---------- Счета: список с оплаченной суммой ----------
create or replace function public.app_invoice_list(p_token uuid)
returns table (id uuid, number text, customer text, order_number text, amount numeric, paid numeric,
               status text, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, o.number, i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.created_at
    from public.app_invoices i left join public.app_orders o on o.id = i.order_id
    where (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

create or replace function public.app_invoice_create(p_token uuid, p_order_id uuid, p_customer text, p_amount numeric, p_due_date date, p_note text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; iid uuid; inum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, amount, status, due_date, note, created_by, created_login)
  values (ten, inum, p_order_id, nullif(trim(p_customer),''), p_amount, 'draft', p_due_date, nullif(trim(p_note),''), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum;
end $$;

create or replace function public.app_invoice_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_invoices set status = p_status, paid_at = case when p_status='paid' then now() else paid_at end
   where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус счёта обновлён';
end $$;

-- ---------- Платежи ----------
create or replace function public.app_payment_add(p_token uuid, p_invoice_id uuid, p_amount numeric, p_method text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; inv public.app_invoices; paid numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into inv from public.app_invoices where id = p_invoice_id and (urole='admin' or tenant_id = ten);
  if inv.id is null then return query select false,'Счёт не найден'; return; end if;
  if coalesce(p_amount,0) <= 0 then return query select false,'Сумма платежа должна быть > 0'; return; end if;

  insert into public.app_payments (tenant_id, invoice_id, amount, method, note, by_login)
  values (inv.tenant_id, inv.id, p_amount, coalesce(nullif(trim(p_method),''),'bank'), nullif(trim(p_note),''), ulogin);

  select coalesce(sum(p.amount),0) into paid from public.app_payments p where p.invoice_id = inv.id;
  if paid >= inv.amount then
    update public.app_invoices set status='paid', paid_at = now() where id = inv.id;
    perform public.app_notif_roles_t(inv.tenant_id, array['admin','manager','owner'], 'Счёт ' || inv.number || ' оплачен',
            to_char(paid,'FM999G999G999G999') || ' ₽', 'apps/finance/index.html');
  end if;
  return query select true,'Платёж добавлен';
end $$;

create or replace function public.app_payment_list(p_token uuid, p_invoice_id uuid)
returns table (id uuid, amount numeric, method text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.amount, p.method, p.note, p.by_login, p.created_at
    from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
    where p.invoice_id = p_invoice_id and (urole='admin' or i.tenant_id = ten)
    order by p.created_at desc;
end $$;

-- ---------- KPI финансов ----------
create or replace function public.app_finance_kpi(p_token uuid)
returns table (invoices_total bigint, sum_total numeric, sum_paid numeric, receivable numeric, overdue bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_invoices i where (urole='admin' or i.tenant_id=ten)),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.status <> 'cancelled'),
    (select coalesce(sum(p.amount),0) from public.app_payments p join public.app_invoices i on i.id=p.invoice_id where (urole='admin' or i.tenant_id=ten)),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.status in ('sent','overdue')),
    (select count(*) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.due_date < current_date and i.status in ('sent','overdue'));
end $$;

grant execute on function public.app_invoice_list(uuid) to anon, authenticated;
grant execute on function public.app_invoice_create(uuid,uuid,text,numeric,date,text) to anon, authenticated;
grant execute on function public.app_invoice_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_payment_add(uuid,uuid,numeric,text,text) to anon, authenticated;
grant execute on function public.app_payment_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_finance_kpi(uuid) to anon, authenticated;

-- ---------- Демо-счёт ----------
insert into public.app_invoices (tenant_id, number, customer, amount, status, due_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'INV-DEMO1', 'ООО «Привод»', 184000, 'sent', (current_date + 10), 'owner'
where not exists (select 1 from public.app_invoices where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0015_finance.sql <<<<<<<<<<

-- >>>>>>>>>> 0016_hr.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0016_hr.sql  (v2.3 — кадры и смены)
-- Сотрудники, смены/табель, обучение. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0015.
-- ============================================================

create table if not exists public.app_employees (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  app_user_id uuid references public.app_users (id) on delete set null,
  full_name   text not null,
  job    text,
  dept        text,
  phone       text,
  hired_at    date,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_employees_tenant_idx on public.app_employees (tenant_id);

create table if not exists public.app_shifts (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  employee_id uuid not null references public.app_employees (id) on delete cascade,
  shift_date  date not null,
  kind        text not null default 'day',   -- day | night | off | vacation | sick
  hours       numeric default 8,
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_shifts_idx on public.app_shifts (tenant_id, shift_date desc);

create table if not exists public.app_trainings (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  employee_id uuid references public.app_employees (id) on delete cascade,
  title       text not null,
  status      text not null default 'planned',  -- planned | passed
  train_date  date,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_trainings_idx on public.app_trainings (tenant_id, created_at desc);

alter table public.app_employees enable row level security;
alter table public.app_shifts    enable row level security;
alter table public.app_trainings enable row level security;

-- ---------- Сотрудники ----------
create or replace function public.app_employees_list(p_token uuid)
returns table (id uuid, full_name text, job text, dept text, phone text, active boolean, shifts_month bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.full_name, e.job, e.dept, e.phone, e.active,
    (select count(*) from public.app_shifts sh where sh.employee_id = e.id and date_trunc('month', sh.shift_date) = date_trunc('month', current_date))
    from public.app_employees e where (urole='admin' or e.tenant_id = ten) and e.active order by e.full_name;
end $$;

create or replace function public.app_employee_save(p_token uuid, p_id uuid, p_full_name text, p_position text, p_dept text, p_phone text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_full_name),'') = '' then return query select false,'Укажите ФИО'; return; end if;
  if p_id is null then
    insert into public.app_employees (tenant_id, full_name, job, dept, phone)
    values (ten, trim(p_full_name), nullif(trim(p_position),''), nullif(trim(p_dept),''), nullif(trim(p_phone),''));
  else
    update public.app_employees set full_name=trim(p_full_name), job=nullif(trim(p_position),''),
      dept=nullif(trim(p_dept),''), phone=nullif(trim(p_phone),'')
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Смены ----------
create or replace function public.app_shifts_list(p_token uuid, p_from date, p_to date)
returns table (id uuid, employee_id uuid, employee text, shift_date date, kind text, hours numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select sh.id, sh.employee_id, e.full_name, sh.shift_date, sh.kind, sh.hours, sh.note
    from public.app_shifts sh join public.app_employees e on e.id = sh.employee_id
    where (urole='admin' or sh.tenant_id = ten)
      and (p_from is null or sh.shift_date >= p_from) and (p_to is null or sh.shift_date <= p_to)
    order by sh.shift_date desc, e.full_name;
end $$;

create or replace function public.app_shift_add(p_token uuid, p_employee_id uuid, p_date date, p_kind text, p_hours numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select e.id into eid from public.app_employees e where e.id = p_employee_id and (ten is null or e.tenant_id = ten);
  if eid is null then return query select false,'Сотрудник не найден'; return; end if;
  if p_date is null then return query select false,'Укажите дату'; return; end if;
  insert into public.app_shifts (tenant_id, employee_id, shift_date, kind, hours, note, by_login)
  values (ten, eid, p_date, coalesce(nullif(trim(p_kind),''),'day'), coalesce(p_hours,8), nullif(trim(p_note),''), ulogin);
  return query select true,'Смена добавлена';
end $$;

create or replace function public.app_shift_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_shifts where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Смена удалена';
end $$;

-- ---------- Обучение ----------
create or replace function public.app_training_list(p_token uuid)
returns table (id uuid, employee text, title text, status text, train_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, e.full_name, t.title, t.status, t.train_date, t.created_at
    from public.app_trainings t join public.app_employees e on e.id = t.employee_id
    where (urole='admin' or t.tenant_id = ten) order by t.created_at desc;
end $$;

create or replace function public.app_training_add(p_token uuid, p_employee_id uuid, p_title text, p_status text, p_date date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; eid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  select e.id into eid from public.app_employees e where e.id = p_employee_id and (ten is null or e.tenant_id = ten);
  if eid is null then return query select false,'Сотрудник не найден'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему обучения'; return; end if;
  insert into public.app_trainings (tenant_id, employee_id, title, status, train_date, note)
  values (ten, eid, trim(p_title), coalesce(nullif(trim(p_status),''),'planned'), p_date, nullif(trim(p_note),''));
  return query select true,'Обучение добавлено';
end $$;

create or replace function public.app_training_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_trainings set status = p_status where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус обновлён';
end $$;

-- ---------- KPI кадров ----------
create or replace function public.app_hr_kpi(p_token uuid)
returns table (employees bigint, shifts_month bigint, hours_month numeric, trainings_planned bigint, trainings_passed bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_employees e where e.active and (urole='admin' or e.tenant_id=ten)),
    (select count(*) from public.app_shifts sh where (urole='admin' or sh.tenant_id=ten) and date_trunc('month', sh.shift_date)=date_trunc('month', current_date)),
    (select coalesce(sum(sh.hours),0) from public.app_shifts sh where (urole='admin' or sh.tenant_id=ten) and date_trunc('month', sh.shift_date)=date_trunc('month', current_date)),
    (select count(*) from public.app_trainings t where t.status='planned' and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_trainings t where t.status='passed' and (urole='admin' or t.tenant_id=ten));
end $$;

grant execute on function public.app_employees_list(uuid) to anon, authenticated;
grant execute on function public.app_employee_save(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_shifts_list(uuid,date,date) to anon, authenticated;
grant execute on function public.app_shift_add(uuid,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_shift_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_training_list(uuid) to anon, authenticated;
grant execute on function public.app_training_add(uuid,uuid,text,text,date,text) to anon, authenticated;
grant execute on function public.app_training_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_hr_kpi(uuid) to anon, authenticated;

-- ---------- Демо-сотрудники ----------
insert into public.app_employees (tenant_id, full_name, job, dept)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.full_name, v.job, v.dept
from (values
  ('Кузнецов А.П.','Начальник цеха','Механообработка'),
  ('Орлов Д.В.','Мастер','Механообработка'),
  ('Петров В.С.','Оператор ЧПУ','Механообработка')
) as v(full_name,job,dept)
where not exists (select 1 from public.app_employees where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0016_hr.sql <<<<<<<<<<

-- >>>>>>>>>> 0017_docs.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0017_docs.sql  (v2.4 — документооборот)
-- Документы (КП/договоры/техкарты/акты), версии. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0016.
-- ============================================================

create sequence if not exists public.app_doc_seq;

create table if not exists public.app_documents (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  doc_type      text not null default 'kp',     -- kp | contract | techcard | act | other
  number        text unique not null,
  title         text not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  counterparty  text,
  amount        numeric,
  status        text not null default 'draft',  -- draft | active | archived
  version       integer not null default 1,
  content       text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_documents_tenant_idx on public.app_documents (tenant_id, created_at desc);

create table if not exists public.app_document_versions (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.app_documents (id) on delete cascade,
  version     integer not null,
  title       text,
  content     text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_doc_versions_idx on public.app_document_versions (document_id, version desc);

alter table public.app_documents         enable row level security;
alter table public.app_document_versions enable row level security;

-- ---------- Список ----------
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, amount numeric, status text, version integer, order_number text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.doc_type, d.number, d.title, d.counterparty, d.amount, d.status, d.version, o.number, d.updated_at
    from public.app_documents d left join public.app_orders o on o.id = d.order_id
    where (urole='admin' or d.tenant_id = ten) and (p_type is null or p_type = '' or d.doc_type = p_type)
    order by d.updated_at desc;
end $$;

create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, counterparty text, amount numeric, status text, version integer, content text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.order_id, d.counterparty, d.amount, d.status, d.version, d.content, d.created_login, d.created_at, d.updated_at
    from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
end $$;

-- ---------- Создание ----------
create or replace function public.app_doc_create(p_token uuid, p_doc_type text, p_title text, p_order_id uuid, p_counterparty text, p_amount numeric, p_content text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; did uuid; dnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название документа'; end if;
  dnum := 'DOC-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, amount, content, created_by, created_login)
  values (ten, coalesce(nullif(trim(p_doc_type),''),'kp'), dnum, trim(p_title), p_order_id, nullif(trim(p_counterparty),''), p_amount, p_content, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, trim(p_title), p_content, ulogin);
  return query select did, dnum;
end $$;

-- ---------- Обновление (новая версия) ----------
create or replace function public.app_doc_update(p_token uuid, p_id uuid, p_title text, p_counterparty text, p_amount numeric, p_content text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; v integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.version into v from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if v is null then return query select false,'Документ не найден'; return; end if;
  v := v + 1;
  update public.app_documents set title = coalesce(nullif(trim(p_title),''), title), counterparty = coalesce(nullif(trim(p_counterparty),''), counterparty),
    amount = coalesce(p_amount, amount), content = coalesce(p_content, content), version = v, updated_at = now()
   where id = p_id;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (p_id, v, coalesce(nullif(trim(p_title),''),'—'), p_content, ulogin);
  return query select true,'Сохранено (версия ' || v || ')';
end $$;

create or replace function public.app_doc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_documents set status = p_status, updated_at = now() where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_doc_versions(p_token uuid, p_id uuid)
returns table (version integer, title text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.version, v.title, v.by_login, v.created_at
    from public.app_document_versions v join public.app_documents d on d.id = v.document_id
    where v.document_id = p_id and (urole='admin' or d.tenant_id = ten) order by v.version desc;
end $$;

grant execute on function public.app_doc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_doc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_create(uuid,text,text,uuid,text,numeric,text) to anon, authenticated;
grant execute on function public.app_doc_update(uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_doc_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_versions(uuid,uuid) to anon, authenticated;
-- <<<<<<<<<< 0017_docs.sql <<<<<<<<<<

-- >>>>>>>>>> 0018_api.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0018_api.sql  (v3.0 — Public API и вебхуки)
-- API-ключи организации и публичное чтение данных по ключу; вебхуки (регистрация).
-- Зависит от 0001..0017.
-- ============================================================

create table if not exists public.app_api_keys (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  name         text not null,
  api_key      uuid unique not null default gen_random_uuid(),
  active       boolean not null default true,
  created_by   uuid references public.app_users (id) on delete set null,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);
alter table public.app_api_keys enable row level security;

create table if not exists public.app_webhooks (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  url        text not null,
  event      text not null default '*',   -- order.created | bid.created | * …
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.app_webhooks enable row level security;

-- ---------- Ключи ----------
create or replace function public.app_api_key_list(p_token uuid)
returns table (id uuid, name text, api_key uuid, active boolean, created_at timestamptz, last_used_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  select u.tenant_id, s.urole into ten, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if urole not in ('owner','manager','admin') then raise exception 'Доступ запрещён'; end if;
  return query select k.id, k.name, k.api_key, k.active, k.created_at, k.last_used_at
    from public.app_api_keys k where k.tenant_id = ten order by k.created_at desc;
end $$;

create or replace function public.app_api_key_create(p_token uuid, p_name text)
returns table (id uuid, api_key uuid)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; kid uuid; kkey uuid; uid uuid;
begin
  if not public.app_is_owner(p_token) then raise exception 'Только владелец может создавать ключи'; end if;
  select u.tenant_id, s.uid into ten, uid from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  insert into public.app_api_keys (tenant_id, name, created_by) values (ten, coalesce(nullif(trim(p_name),''),'API-ключ'), uid)
  returning app_api_keys.id, app_api_keys.api_key into kid, kkey;
  return query select kid, kkey;
end $$;

create or replace function public.app_api_key_revoke(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.app_api_keys set active = false where id = p_id and tenant_id = ten;
  return query select true,'Ключ отозван';
end $$;

-- ---------- Вебхуки ----------
create or replace function public.app_webhook_list(p_token uuid)
returns table (id uuid, url text, event text, active boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  select u.tenant_id, s.urole into ten, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if urole not in ('owner','manager','admin') then raise exception 'Доступ запрещён'; end if;
  return query select w.id, w.url, w.event, w.active, w.created_at from public.app_webhooks w where w.tenant_id = ten order by w.created_at desc;
end $$;

create or replace function public.app_webhook_add(p_token uuid, p_url text, p_event text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_url),'') = '' then return query select false,'Укажите URL'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  insert into public.app_webhooks (tenant_id, url, event) values (ten, trim(p_url), coalesce(nullif(trim(p_event),''),'*'));
  return query select true,'Вебхук добавлен';
end $$;

create or replace function public.app_webhook_toggle(p_token uuid, p_id uuid, p_active boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.app_webhooks set active = p_active where id = p_id and tenant_id = ten;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_webhook_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  delete from public.app_webhooks where id = p_id and tenant_id = ten;
  return query select true,'Вебхук удалён';
end $$;

-- ============================================================
--  Публичное чтение по API-ключу (внешние интеграции)
-- ============================================================
create or replace function public.api_tenant_of(p_key uuid)
returns uuid language sql security definer set search_path = public
as $$
  select k.tenant_id from public.app_api_keys k where k.api_key = p_key and k.active;
$$;

create or replace function public.api_touch(p_key uuid)
returns void language sql security definer set search_path = public
as $$ update public.app_api_keys set last_used_at = now() where api_key = p_key and active; $$;

create or replace function public.api_orders(p_key uuid)
returns table (number text, title text, customer text, status text, priority text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select o.number, o.title, o.customer, o.status, o.priority, o.created_at
    from public.app_orders o where o.tenant_id = ten order by o.created_at desc;
end $$;

create or replace function public.api_tenders(p_key uuid)
returns table (title text, category text, customer text, status text, bids_count bigint)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select t.title, t.category, t.customer, t.status,
    (select count(*) from public.bids b where b.tender_id = t.id)
    from public.tenders t where t.tenant_id = ten order by t.created_at desc;
end $$;

create or replace function public.api_stock(p_key uuid)
returns table (name text, unit text, qty numeric, min_qty numeric)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select m.name, m.unit, m.qty, m.min_qty from public.app_materials m where m.tenant_id = ten order by m.name;
end $$;

grant execute on function public.app_api_key_list(uuid) to anon, authenticated;
grant execute on function public.app_api_key_create(uuid,text) to anon, authenticated;
grant execute on function public.app_api_key_revoke(uuid,uuid) to anon, authenticated;
grant execute on function public.app_webhook_list(uuid) to anon, authenticated;
grant execute on function public.app_webhook_add(uuid,text,text) to anon, authenticated;
grant execute on function public.app_webhook_toggle(uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.app_webhook_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.api_orders(uuid) to anon, authenticated;
grant execute on function public.api_tenders(uuid) to anon, authenticated;
grant execute on function public.api_stock(uuid) to anon, authenticated;
-- <<<<<<<<<< 0018_api.sql <<<<<<<<<<

-- >>>>>>>>>> 0019_bi.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0019_bi.sql  (v4.0 — аналитика/BI)
-- Агрегаты для дашбордов (платежи по месяцам, счета/заявки/наряды по статусам).
-- Изоляция по tenant. Зависит от 0001..0018.
-- ============================================================

create or replace function public.app_bi(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; res jsonb;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  select jsonb_build_object(
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object('m', t.m, 'sum', t.s) order by t.m)
      from (
        select to_char(date_trunc('month', p.created_at), 'YYYY-MM') as m, sum(p.amount) as s
        from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
        where (urole='admin' or i.tenant_id = ten) and p.created_at >= now() - interval '6 months'
        group by 1
      ) t), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt, 'sum', t.s))
      from (
        select status, count(*) as cnt, coalesce(sum(amount),0) as s
        from public.app_invoices where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (
        select status, count(*) as cnt from public.app_orders where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb),
    'naryads', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (
        select status, count(*) as cnt from public.app_naryads where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb)
  ) into res;

  return res;
end $$;

grant execute on function public.app_bi(uuid) to anon, authenticated;
-- <<<<<<<<<< 0019_bi.sql <<<<<<<<<<

-- >>>>>>>>>> 0020_platform_admin.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0020_platform_admin.sql  (v5.0 — мультизавод/платформа)
-- Платформенный админ управляет всеми организациями (тенантами); брендирование.
-- Зависит от 0001..0019.
-- ============================================================

alter table public.tenants add column if not exists brand jsonb not null default '{}'::jsonb;

-- ---------- Список всех организаций (только platform admin) ----------
create or replace function public.app_platform_tenants(p_token uuid)
returns table (id uuid, name text, plan text, plan_name text, status text,
               users_count bigint, orders_count bigint, brand jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_is_platform_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select t.id, t.name, t.plan, p.name, t.status,
           (select count(*) from public.app_users u where u.tenant_id = t.id),
           (select count(*) from public.app_orders o where o.tenant_id = t.id),
           t.brand, t.created_at
    from public.tenants t left join public.app_plans p on p.code = t.plan
    order by t.created_at;
end $$;

-- ---------- Создать организацию (+ владелец) ----------
create or replace function public.app_platform_tenant_create(
  p_token uuid, p_name text, p_plan text, p_owner_login text, p_owner_password text, p_owner_name text
) returns table (ok boolean, message text, tenant_id uuid)
language plpgsql security definer set search_path = public, extensions
as $$
declare tid uuid;
begin
  if not public.app_is_platform_admin(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название организации', null::uuid; return; end if;
  if coalesce(trim(p_owner_login),'') = '' then return query select false,'Укажите логин владельца', null::uuid; return; end if;
  if exists (select 1 from public.app_users where lower(login) = lower(trim(p_owner_login))) then
    return query select false,'Логин уже занят', null::uuid; return;
  end if;
  insert into public.tenants (name, slug, plan, status)
  values (trim(p_name), lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')), coalesce(nullif(trim(p_plan),''),'business'), 'active')
  returning tenants.id into tid;
  insert into public.app_users (login, password_hash, full_name, role, tenant_id)
  values (lower(trim(p_owner_login)), extensions.crypt(coalesce(nullif(p_owner_password,''),'changeme'), extensions.gen_salt('bf')),
          nullif(trim(p_owner_name),''), 'owner', tid);
  return query select true, 'Организация создана', tid;
end $$;

-- ---------- Изменить план/статус/бренд ----------
create or replace function public.app_platform_tenant_update(
  p_token uuid, p_tenant_id uuid, p_plan text, p_status text, p_brand jsonb
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_is_platform_admin(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if p_plan is not null and not exists (select 1 from public.app_plans where code = p_plan) then
    return query select false,'Тариф не найден'; return;
  end if;
  update public.tenants
     set plan = coalesce(p_plan, plan),
         status = coalesce(p_status, status),
         brand = coalesce(p_brand, brand)
   where id = p_tenant_id;
  return query select true,'Сохранено';
end $$;

-- ---------- Брендирование своей организации (owner/admin) ----------
create or replace function public.app_tenant_set_brand(p_token uuid, p_brand jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.tenants set brand = coalesce(p_brand, '{}'::jsonb) where id = ten;
  return query select true,'Бренд сохранён';
end $$;

grant execute on function public.app_platform_tenants(uuid) to anon, authenticated;
grant execute on function public.app_platform_tenant_create(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_platform_tenant_update(uuid,uuid,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_tenant_set_brand(uuid,jsonb) to anon, authenticated;
-- <<<<<<<<<< 0020_platform_admin.sql <<<<<<<<<<

-- >>>>>>>>>> 0021_mes.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0021_mes.sql  (v6.0 — MES-ядро, диспетчеризация)
-- Оперативные задания по рабочим центрам (канбан производства).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0020.
-- ============================================================

create sequence if not exists public.app_mes_seq;

create table if not exists public.app_mes_tasks (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text unique not null,
  wc_id        uuid references public.app_work_centers (id) on delete set null,
  naryad_id    uuid references public.app_naryads (id) on delete set null,
  title        text not null,
  status       text not null default 'queued',  -- queued | running | paused | done
  priority     text not null default 'normal',  -- low | normal | high
  operator     text,
  started_at   timestamptz,
  finished_at  timestamptz,
  note         text,
  created_by   uuid references public.app_users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_mes_tenant_idx on public.app_mes_tasks (tenant_id, created_at desc);

alter table public.app_mes_tasks enable row level security;

-- ---------- Доска ----------
create or replace function public.app_mes_board(p_token uuid)
returns table (id uuid, number text, title text, wc_name text, naryad_number text, status text, priority text,
               operator text, started_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select m.id, m.number, m.title, w.name, n.number, m.status, m.priority, m.operator, m.started_at, m.created_at
    from public.app_mes_tasks m
    left join public.app_work_centers w on w.id = m.wc_id
    left join public.app_naryads n on n.id = m.naryad_id
    where (urole='admin' or m.tenant_id = ten)
    order by case m.status when 'running' then 0 when 'paused' then 1 when 'queued' then 2 else 3 end,
             case m.priority when 'high' then 0 when 'normal' then 1 else 2 end, m.created_at;
end $$;

-- ---------- Создать задание ----------
create or replace function public.app_mes_create(p_token uuid, p_wc_id uuid, p_naryad_id uuid, p_title text, p_priority text, p_operator text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ten uuid; mid uuid; mnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите задание'; end if;
  mnum := 'MES-' || lpad(nextval('public.app_mes_seq')::text, 5, '0');
  insert into public.app_mes_tasks (tenant_id, number, wc_id, naryad_id, title, priority, operator, created_by)
  values (ten, mnum, p_wc_id, p_naryad_id, trim(p_title), coalesce(nullif(trim(p_priority),''),'normal'), nullif(trim(p_operator),''), uid)
  returning app_mes_tasks.id into mid;
  return query select mid, mnum;
end $$;

-- ---------- Сменить статус ----------
create or replace function public.app_mes_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; mnum text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select m.number into mnum from public.app_mes_tasks m where m.id = p_id and (urole='admin' or m.tenant_id = ten);
  if mnum is null then return query select false,'Задание не найдено'; return; end if;

  update public.app_mes_tasks set status = p_status,
    started_at = case when p_status='running' and started_at is null then now() else started_at end,
    finished_at = case when p_status='done' then now() else finished_at end,
    updated_at = now()
   where id = p_id;

  if p_status = 'done' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Задание ' || mnum || ' выполнено', 'Выполнил: ' || coalesce(ulogin,''), 'apps/mes/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

create or replace function public.app_mes_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_mes_tasks where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Задание удалено';
end $$;

-- ---------- KPI ----------
create or replace function public.app_mes_kpi(p_token uuid)
returns table (queued bigint, running bigint, paused bigint, done bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_mes_tasks m where m.status='queued' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='running' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='paused' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='done' and (urole='admin' or m.tenant_id=ten));
end $$;

grant execute on function public.app_mes_board(uuid) to anon, authenticated;
grant execute on function public.app_mes_create(uuid,uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_mes_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_mes_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mes_kpi(uuid) to anon, authenticated;
-- <<<<<<<<<< 0021_mes.sql <<<<<<<<<<

-- >>>>>>>>>> 0022_quality_system.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0022_quality_system.sql  (v7.0 — качество/СМК)
-- Средства измерений (поверка) и трассируемость. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0021.
-- ============================================================

create table if not exists public.app_measuring_tools (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  serial        text,
  tool_type     text,
  location      text,
  last_verified date,
  next_verified date,
  created_at    timestamptz not null default now()
);
create index if not exists app_tools_tenant_idx on public.app_measuring_tools (tenant_id);

create table if not exists public.app_traceability (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  item        text not null,
  serial      text,
  order_id    uuid references public.app_orders (id) on delete set null,
  passport_id uuid references public.app_passports (id) on delete set null,
  material    text,
  operator    text,
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_trace_tenant_idx on public.app_traceability (tenant_id, created_at desc);

alter table public.app_measuring_tools enable row level security;
alter table public.app_traceability    enable row level security;

-- ---------- Средства измерений ----------
create or replace function public.app_tools_list(p_token uuid)
returns table (id uuid, name text, serial text, tool_type text, location text,
               last_verified date, next_verified date, status text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.name, t.serial, t.tool_type, t.location, t.last_verified, t.next_verified,
      case when t.next_verified is null then 'none'
           when t.next_verified < current_date then 'expired'
           when t.next_verified < current_date + 30 then 'due'
           else 'ok' end
    from public.app_measuring_tools t
    where (urole='admin' or t.tenant_id = ten)
    order by case when t.next_verified is null then 1 else 0 end, t.next_verified;
end $$;

create or replace function public.app_tool_save(p_token uuid, p_id uuid, p_name text, p_serial text, p_tool_type text, p_location text, p_last date, p_next date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_measuring_tools (tenant_id, name, serial, tool_type, location, last_verified, next_verified)
    values (ten, trim(p_name), nullif(trim(p_serial),''), nullif(trim(p_tool_type),''), nullif(trim(p_location),''), p_last, p_next);
  else
    update public.app_measuring_tools set name=trim(p_name), serial=nullif(trim(p_serial),''), tool_type=nullif(trim(p_tool_type),''),
      location=nullif(trim(p_location),''), last_verified=p_last, next_verified=p_next
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_tool_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_measuring_tools where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Удалено';
end $$;

-- ---------- Трассируемость ----------
create or replace function public.app_trace_list(p_token uuid)
returns table (id uuid, item text, serial text, order_number text, material text, operator text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select tr.id, tr.item, tr.serial, o.number, tr.material, tr.operator, tr.by_login, tr.created_at
    from public.app_traceability tr left join public.app_orders o on o.id = tr.order_id
    where (urole='admin' or tr.tenant_id = ten) order by tr.created_at desc;
end $$;

create or replace function public.app_trace_add(p_token uuid, p_item text, p_serial text, p_order_id uuid, p_passport_id uuid, p_material text, p_operator text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_item),'') = '' then return query select false,'Укажите изделие/партию'; return; end if;
  insert into public.app_traceability (tenant_id, item, serial, order_id, passport_id, material, operator, note, by_login)
  values (ten, trim(p_item), nullif(trim(p_serial),''), p_order_id, p_passport_id, nullif(trim(p_material),''), nullif(trim(p_operator),''), nullif(trim(p_note),''), ulogin);
  return query select true,'Запись добавлена';
end $$;

-- ---------- KPI ----------
create or replace function public.app_quality_kpi(p_token uuid)
returns table (tools bigint, expired bigint, due bigint, trace_records bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_measuring_tools t where (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_measuring_tools t where t.next_verified < current_date and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_measuring_tools t where t.next_verified >= current_date and t.next_verified < current_date+30 and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_traceability tr where (urole='admin' or tr.tenant_id=ten));
end $$;

grant execute on function public.app_tools_list(uuid) to anon, authenticated;
grant execute on function public.app_tool_save(uuid,uuid,text,text,text,text,date,date) to anon, authenticated;
grant execute on function public.app_tool_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_trace_list(uuid) to anon, authenticated;
grant execute on function public.app_trace_add(uuid,text,text,uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_quality_kpi(uuid) to anon, authenticated;

-- ---------- Демо-СИ ----------
insert into public.app_measuring_tools (tenant_id, name, serial, tool_type, location, last_verified, next_verified)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.serial, v.tool_type, v.location, (current_date - 300), (current_date + v.plus)
from (values
  ('Штангенциркуль ШЦ-125','SN-001','Штангенциркуль','ОТК', 20),
  ('Микрометр МК-25','SN-002','Микрометр','ОТК', -5),
  ('КИМ-стойка','SN-003','КИМ','Цех', 120)
) as v(name,serial,tool_type,location,plus)
where not exists (select 1 from public.app_measuring_tools where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0022_quality_system.sql <<<<<<<<<<

-- >>>>>>>>>> 0023_assistant.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0023_assistant.sql  (v8.0 — ИИ-помощник)
-- База знаний и правиловой подбор технологии (без внешних API).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0022.
-- ============================================================

create table if not exists public.app_knowledge (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  category   text,
  question   text not null,
  answer     text not null,
  tags       text,
  created_at timestamptz not null default now()
);
create index if not exists app_kb_tenant_idx on public.app_knowledge (tenant_id);

create table if not exists public.app_tech_rules (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  material       text,          -- 'Сталь 40Х' | 'алюминий' | '*' (любой)
  feature        text,          -- 'отверстие' | 'паз' | 'резьба' | 'плоскость' | '*'
  recommendation text not null,
  note           text
);
create index if not exists app_tech_tenant_idx on public.app_tech_rules (tenant_id);

alter table public.app_knowledge enable row level security;
alter table public.app_tech_rules enable row level security;

-- ---------- База знаний ----------
create or replace function public.app_kb_list(p_token uuid)
returns table (id uuid, category text, question text, answer text, tags text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select k.id, k.category, k.question, k.answer, k.tags, k.created_at
    from public.app_knowledge k where (urole='admin' or k.tenant_id = ten) order by k.created_at desc;
end $$;

create or replace function public.app_kb_add(p_token uuid, p_category text, p_question text, p_answer text, p_tags text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_question),'') = '' or coalesce(trim(p_answer),'') = '' then
    return query select false,'Заполните вопрос и ответ'; return;
  end if;
  insert into public.app_knowledge (tenant_id, category, question, answer, tags)
  values (ten, nullif(trim(p_category),''), trim(p_question), trim(p_answer), nullif(trim(p_tags),''));
  return query select true,'Запись добавлена';
end $$;

-- простой «поиск» по базе знаний
create or replace function public.app_kb_search(p_token uuid, p_query text)
returns table (id uuid, category text, question text, answer text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  q := '%' || coalesce(trim(p_query),'') || '%';
  return query select k.id, k.category, k.question, k.answer
    from public.app_knowledge k
    where (urole='admin' or k.tenant_id = ten)
      and (k.question ilike q or k.answer ilike q or coalesce(k.tags,'') ilike q)
    order by k.created_at desc limit 20;
end $$;

-- ---------- Подбор технологии ----------
create or replace function public.app_tech_recommend(p_token uuid, p_material text, p_feature text)
returns table (recommendation text, note text, matched_material text, matched_feature text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.recommendation, r.note, r.material, r.feature
    from public.app_tech_rules r
    where (urole='admin' or r.tenant_id = ten)
      and (r.material is null or r.material = '*' or p_material ilike '%' || r.material || '%')
      and (r.feature is null or r.feature = '*' or p_feature = r.feature)
    order by (case when r.material = '*' or r.material is null then 1 else 0 end) + (case when r.feature='*' or r.feature is null then 1 else 0 end),
             r.recommendation
    limit 5;
end $$;

grant execute on function public.app_kb_list(uuid) to anon, authenticated;
grant execute on function public.app_kb_add(uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_kb_search(uuid,text) to anon, authenticated;
grant execute on function public.app_tech_recommend(uuid,text,text) to anon, authenticated;

-- ---------- Демо: база знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Обработка','Какую подачу выбрать для фрезерования алюминия Д16Т?','Для Д16Т используйте повышенную частоту вращения и охлаждение; подача на зуб 0.05–0.12 мм, СОЖ обязательна.','алюминий фрезеровка подача'),
  ('Обработка','Допуск на отверстие 12H7?','Поле H7 для Ø12: +0.000 / +0.018 мм. Контроль калибром или КИМ.','отверстие допуск H7'),
  ('Оснастка','Материал формообразующих для серийной пресс-формы?','Сталь 40Х с закалкой либо Х12МФ для повышенной стойкости.','пресс-форма сталь стойкость'),
  ('Качество','Периодичность поверки штангенциркуля?','Ежегодно (по графику поверки). Просрочку контролируем в разделе Качество/СМК.','поверка СИ штангенциркуль')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- Демо: правила подбора ----------
insert into public.app_tech_rules (tenant_id, material, feature, recommendation, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.material, v.feature, v.recommendation, v.note
from (values
  ('Сталь 40Х','отверстие','Сверление + развёртывание под H7','При закалке — после термообработки шлифовка'),
  ('Сталь 40Х','паз','Фрезерование концевой фрезой, черновой + чистовой проход','СОЖ, контроль размера 12H7'),
  ('алюминий','отверстие','Сверление на высоких оборотах, зенковка','Охлаждение обязательно, риск наростов'),
  ('*','резьба','Метрическая резьба по ГОСТ 24705, контроль калибром','Для серии — резьбофреза'),
  ('*','плоскость','Торцевое фрезерование или шлифовка','Шероховатость по требованию чертежа')
) as v(material,feature,recommendation,note)
where not exists (select 1 from public.app_tech_rules where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
-- <<<<<<<<<< 0023_assistant.sql <<<<<<<<<<

-- >>>>>>>>>> 0024_masterdata.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0024_masterdata.sql  (функциональная модель: справочники)
-- Связная модель: оборудование ↔ операции ↔ материалы ↔ шаблоны техпроцессов.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0023.
-- ============================================================

-- ---------- Оборудование ----------
create table if not exists public.app_equipment (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  model       text,
  kind        text not null default 'frezerny', -- frezerny|tokarny|lazer|sverlilny|shlifovalny|edm|sborka
  axis        integer,
  max_x       numeric, max_y numeric, max_z numeric,
  accuracy    numeric,
  power       numeric,
  cost_hour   numeric default 0,
  dept        text,
  wc_id       uuid references public.app_work_centers (id) on delete set null,
  status      text not null default 'active',   -- active|maintenance|off
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_equipment_tenant_idx on public.app_equipment (tenant_id, kind);
alter table public.app_equipment enable row level security;

-- ---------- Материалы: расширение свойств ----------
alter table public.app_materials add column if not exists material_group text;  -- сталь|алюминий|латунь|титан|пластик
alter table public.app_materials add column if not exists grade text;          -- марка
alter table public.app_materials add column if not exists standard text;       -- ГОСТ/ТУ
alter table public.app_materials add column if not exists density numeric;     -- кг/дм³

-- ---------- Операции (справочник) ----------
create table if not exists public.app_operations (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  kind        text not null default 'frezerny', -- тип оборудования (совместимость)
  setup_min   numeric default 0,
  unit_min    numeric default 0,
  base_rate   numeric default 0,
  unit        text default 'шт',
  description text,
  created_at  timestamptz not null default now()
);
create index if not exists app_operations_tenant_idx on public.app_operations (tenant_id, kind);
alter table public.app_operations enable row level security;

-- ---------- Шаблоны техпроцессов ----------
create table if not exists public.app_process_templates (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  code         text,
  name         text not null,
  product_type text,
  material_id  uuid references public.app_materials (id) on delete set null,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_process_tpl_tenant_idx on public.app_process_templates (tenant_id);
alter table public.app_process_templates enable row level security;

create table if not exists public.app_process_steps (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references public.app_process_templates (id) on delete cascade,
  seq          integer default 0,
  operation_id uuid references public.app_operations (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  material_id  uuid references public.app_materials (id) on delete set null,
  plan_min     numeric default 0,
  note         text
);
create index if not exists app_process_steps_tpl_idx on public.app_process_steps (template_id, seq);
alter table public.app_process_steps enable row level security;

-- ============================================================
--  RPC
-- ============================================================
create or replace function public.app_equipment_list(p_token uuid)
returns table (id uuid, code text, name text, model text, kind text, axis integer, max_x numeric, max_y numeric, max_z numeric,
               accuracy numeric, cost_hour numeric, dept text, status text, wc_name text, ops_count bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.model, e.kind, e.axis, e.max_x, e.max_y, e.max_z, e.accuracy, e.cost_hour, e.dept, e.status,
           w.name,
           (select count(*) from public.app_operations o where o.kind = e.kind and (urole='admin' or o.tenant_id = ten))
    from public.app_equipment e left join public.app_work_centers w on w.id = e.wc_id
    where (urole='admin' or e.tenant_id = ten)
    order by e.kind, e.name;
end $$;

create or replace function public.app_equipment_save(p_token uuid, p_id uuid, p_code text, p_name text, p_model text, p_kind text,
  p_axis integer, p_max_x numeric, p_max_y numeric, p_max_z numeric, p_accuracy numeric, p_cost_hour numeric, p_dept text, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_equipment (tenant_id, code, name, model, kind, axis, max_x, max_y, max_z, accuracy, cost_hour, dept, status)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_model),''), coalesce(nullif(trim(p_kind),''),'frezerny'),
            p_axis, p_max_x, p_max_y, p_max_z, p_accuracy, coalesce(p_cost_hour,0), nullif(trim(p_dept),''), coalesce(nullif(trim(p_status),''),'active'));
  else
    update public.app_equipment set code=nullif(trim(p_code),''), name=trim(p_name), model=nullif(trim(p_model),''),
      kind=coalesce(nullif(trim(p_kind),''),kind), axis=p_axis, max_x=p_max_x, max_y=p_max_y, max_z=p_max_z, accuracy=p_accuracy,
      cost_hour=coalesce(p_cost_hour,0), dept=nullif(trim(p_dept),''), status=coalesce(nullif(trim(p_status),''),status)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_operations_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, setup_min numeric, unit_min numeric, base_rate numeric, unit text, equipment_count bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.code, o.name, o.kind, o.setup_min, o.unit_min, o.base_rate, o.unit,
           (select count(*) from public.app_equipment e where e.kind = o.kind and (urole='admin' or e.tenant_id = ten))
    from public.app_operations o where (urole='admin' or o.tenant_id = ten) order by o.kind, o.name;
end $$;

create or replace function public.app_operation_save(p_token uuid, p_id uuid, p_code text, p_name text, p_kind text, p_setup numeric, p_unit_min numeric, p_rate numeric, p_unit text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_operations (tenant_id, code, name, kind, setup_min, unit_min, base_rate, unit)
    values (ten, nullif(trim(p_code),''), trim(p_name), coalesce(nullif(trim(p_kind),''),'frezerny'), coalesce(p_setup,0), coalesce(p_unit_min,0), coalesce(p_rate,0), coalesce(nullif(trim(p_unit),''),'шт'));
  else
    update public.app_operations set code=nullif(trim(p_code),''), name=trim(p_name), kind=coalesce(nullif(trim(p_kind),''),kind),
      setup_min=coalesce(p_setup,0), unit_min=coalesce(p_unit_min,0), base_rate=coalesce(p_rate,0), unit=coalesce(nullif(trim(p_unit),''),unit)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_process_list(p_token uuid)
returns table (id uuid, code text, name text, product_type text, material_name text, steps_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.code, t.name, t.product_type, m.name,
           (select count(*) from public.app_process_steps st where st.template_id = t.id), t.created_at
    from public.app_process_templates t left join public.app_materials m on m.id = t.material_id
    where (urole='admin' or t.tenant_id = ten) order by t.created_at desc;
end $$;

create or replace function public.app_process_get(p_token uuid, p_id uuid)
returns table (id uuid, code text, name text, product_type text, material_name text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, t.code, t.name, t.product_type, m.name, t.note
    from public.app_process_templates t left join public.app_materials m on m.id = t.material_id
    where t.id = p_id and (urole='admin' or t.tenant_id = ten);
end $$;

create or replace function public.app_process_steps_list(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, equipment text, material text, plan_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select st.id, st.seq, o.name, e.name, m.name, st.plan_min, st.note
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    left join public.app_materials m on m.id = st.material_id
    join public.app_process_templates t on t.id = st.template_id
    where st.template_id = p_id and (urole='admin' or t.tenant_id = ten)
    order by st.seq;
end $$;

create or replace function public.app_process_create(p_token uuid, p_code text, p_name text, p_product_type text, p_material_id uuid, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название'; end if;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_product_type),''), p_material_id, nullif(trim(p_note),''))
  returning app_process_templates.id into tid;
  return query select tid, 'Шаблон создан';
end $$;

create or replace function public.app_process_add_step(p_token uuid, p_id uuid, p_operation_id uuid, p_equipment_id uuid, p_material_id uuid, p_plan_min numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; seqn integer; tid uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.id into tid from public.app_process_templates t where t.id = p_id and (ten is null or t.tenant_id = ten);
  if tid is null then return query select false,'Шаблон не найден'; return; end if;
  select coalesce(max(st.seq),0)+1 into seqn from public.app_process_steps st where st.template_id = p_id;
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, material_id, plan_min, note)
  values (p_id, seqn, p_operation_id, p_equipment_id, p_material_id, coalesce(p_plan_min,0), nullif(trim(p_note),''));
  return query select true,'Шаг добавлен';
end $$;

-- расширенный список материалов (с характеристиками)
create or replace function public.app_materials_reg(p_token uuid)
returns table (id uuid, code text, name text, material_group text, grade text, standard text, density numeric, unit text, price numeric, qty numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.material_group, m.grade, m.standard, m.density, m.unit, m.price, m.qty
    from public.app_materials m where (urole='admin' or m.tenant_id = ten) order by m.name;
end $$;

grant execute on function public.app_equipment_list(uuid) to anon, authenticated;
grant execute on function public.app_equipment_save(uuid,uuid,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_operations_list(uuid) to anon, authenticated;
grant execute on function public.app_operation_save(uuid,uuid,text,text,text,numeric,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_process_list(uuid) to anon, authenticated;
grant execute on function public.app_process_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_steps_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_create(uuid,text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.app_process_add_step(uuid,uuid,uuid,uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_materials_reg(uuid) to anon, authenticated;

-- ============================================================
--  Наполнение (связные демо-данные, тенант A)
-- ============================================================
-- Оборудование (с привязкой к рабочим центрам по коду)
insert into public.app_equipment (tenant_id, code, name, model, kind, axis, max_x, max_y, max_z, accuracy, cost_hour, dept, wc_id, status)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.model, v.kind, v.axis, v.mx, v.my, v.mz, v.acc, v.cost, v.dept,
       (select w.id from public.app_work_centers w where w.code = v.wc and w.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' limit 1), 'active'
from (values
  ('EQ-01','Фрезерный ЧПУ DMU-50','DMU-50','frezerny',5,500,400,400,0.01,3500,'Механообработка','WC-01'),
  ('EQ-02','Токарный с ЧПУ Haas ST-20','ST-20','tokarny',2,300,0,500,0.02,3000,'Механообработка','WC-02'),
  ('EQ-03','Лазерный комплекс 3 кВт','FiberCut-3','lazer',2,3000,1500,0,0.1,4200,'Резка','WC-03'),
  ('EQ-04','Слесарная/сборка','Верстак-1','sborka',0,0,0,0,0,1800,'Сборка','WC-04'),
  ('EQ-05','Вертикально-сверлильный','2Н135','sverlilny',1,35,0,0,0.05,1200,'Механообработка',null),
  ('EQ-06','Плоскошлифовальный','3Г71','shlifovalny',3,630,200,320,0.005,2200,'Механообработка',null),
  ('EQ-07','Электроэрозионный','EA-12','edm',3,400,300,300,0.01,3800,'Механообработка',null)
) as v(code,name,model,kind,axis,mx,my,mz,acc,cost,dept,wc)
where not exists (select 1 from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- Материалы: характеристики
update public.app_materials set material_group='сталь', grade='40Х', standard='ГОСТ 4543-2016', density=7.85 where code='М-40Х' and material_group is null;
update public.app_materials set material_group='сталь', grade='45', standard='ГОСТ 1050-2013', density=7.85 where code='М-45' and material_group is null;
update public.app_materials set material_group='алюминий', grade='Д16Т', standard='ГОСТ 4784-2019', density=2.78 where code='М-Д16Т' and material_group is null;
update public.app_materials set material_group='сталь', grade='09Г2С', standard='ГОСТ 19281-2014', density=7.85 where code='М-09Г2С' and material_group is null;

-- Операции
insert into public.app_operations (tenant_id, code, name, kind, setup_min, unit_min, base_rate, unit, description)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.kind, v.setup, v.unit_min, v.rate, v.unit, v.descr
from (values
  ('OP-01','Фрезеровка черновая','frezerny',20,12,3500,'шт','Снятие основного припуска'),
  ('OP-02','Фрезеровка чистовая','frezerny',15,8,3500,'шт','По допуску чертежа'),
  ('OP-03','Токарная черновая','tokarny',18,10,3000,'шт','Обдирка'),
  ('OP-04','Токарная чистовая','tokarny',15,7,3000,'шт','Чистовой проход'),
  ('OP-05','Сверление','sverlilny',5,3,1200,'отв','По разметке/ЧПУ'),
  ('OP-06','Лазерная резка','lazer',10,3,4200,'лист','Контурный раскрой'),
  ('OP-07','Плоское шлифование','shlifovalny',12,6,2200,'шт','Достижение точности'),
  ('OP-08','Электроэрозия','edm',25,15,3800,'шт','Каналы/фасонные полости'),
  ('OP-09','Слесарная доводка','sborka',5,15,1800,'шт','Зачистка, пригонка'),
  ('OP-10','Сборка узла','sborka',10,25,1800,'шт','Финальная сборка')
) as v(code,name,kind,setup,unit_min,rate,unit,descr)
where not exists (select 1 from public.app_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- Шаблоны техпроцессов + шаги
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        t1 uuid; t2 uuid; t3 uuid;
        m40 uuid; m45 uuid; m09 uuid;
begin
  if exists (select 1 from public.app_process_templates where tenant_id = ten) then return; end if;
  select id into m40 from public.app_materials where tenant_id=ten and code='М-40Х';
  select id into m45 from public.app_materials where tenant_id=ten and code='М-45';
  select id into m09 from public.app_materials where tenant_id=ten and code='М-09Г2С';

  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-01', 'Кронштейн', 'корпусная деталь', m40, 'Типовой маршрут корпусных деталей') returning id into t1;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-02', 'Вал', 'тел вращения', m45, 'Токарный маршрут') returning id into t2;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-03', 'Листовая деталь', 'плоская деталь', m09, 'Лазерный раскрой') returning id into t3;

  -- Шаги: операция + рекомендованное оборудование (по kind)
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 1, o.id, e.id, 45 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-01' and e.code='EQ-01';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 2, o.id, e.id, 40 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-02' and e.code='EQ-01';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 3, o.id, e.id, 25 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-05' and e.code='EQ-05';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 4, o.id, e.id, 30 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-09' and e.code='EQ-04';

  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 1, o.id, e.id, 35 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-03' and e.code='EQ-02';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 2, o.id, e.id, 30 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-04' and e.code='EQ-02';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 3, o.id, e.id, 25 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-07' and e.code='EQ-06';

  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t3, 1, o.id, e.id, 12 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-06' and e.code='EQ-03';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t3, 2, o.id, e.id, 20 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-09' and e.code='EQ-04';
end $$;
-- <<<<<<<<<< 0024_masterdata.sql <<<<<<<<<<

-- >>>>>>>>>> 0025_routes.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0025_routes.sql  (v9.0 — маршруты по техпроцессу)
-- Связь: шаблон техпроцесса → маршрут изготовления → нормирование → себестоимость.
-- Нормирование: app_norms связывается с операциями (operation_id).
-- Себестоимость: работы (нормо-часы × ставка) + материал + накладные 15% (как в 0013).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0024.
-- ============================================================

-- ---------- Связь нормирования с операциями ----------
alter table public.app_norms add column if not exists operation_id uuid references public.app_operations (id) on delete set null;
create index if not exists app_norms_op_idx on public.app_norms (operation_id);

update public.app_norms n set operation_id = o.id
  from public.app_operations o
  where n.operation_id is null
    and n.tenant_id = o.tenant_id
    and lower(trim(o.name)) = lower(trim(n.operation));

-- ---------- Маршруты изготовления ----------
create sequence if not exists public.app_route_seq;

create table if not exists public.app_routes (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  name          text not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  template_id   uuid references public.app_process_templates (id) on delete set null,
  material_id   uuid references public.app_materials (id) on delete set null,
  qty           numeric not null default 1,
  mat_qty       numeric not null default 0,       -- норма расхода материала на изделие
  status        text not null default 'draft',    -- draft | active | done
  work_cost     numeric not null default 0,
  material_cost numeric not null default 0,
  overhead      numeric not null default 0,
  total_min     numeric not null default 0,
  total_cost    numeric not null default 0,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_routes_tenant_idx on public.app_routes (tenant_id, created_at desc);
create index if not exists app_routes_order_idx  on public.app_routes (order_id);
alter table public.app_routes enable row level security;

create table if not exists public.app_route_steps (
  id           uuid primary key default gen_random_uuid(),
  route_id     uuid not null references public.app_routes (id) on delete cascade,
  seq          integer default 0,
  operation_id uuid references public.app_operations (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  norm_id      uuid references public.app_norms (id) on delete set null,
  setup_min    numeric not null default 0,
  unit_min     numeric not null default 0,
  qty          numeric not null default 1,
  plan_min     numeric not null default 0,
  rate_hour    numeric not null default 0,
  cost         numeric not null default 0,
  note         text
);
create index if not exists app_route_steps_idx on public.app_route_steps (route_id, seq);
alter table public.app_route_steps enable row level security;

-- ============================================================
--  RPC
-- ============================================================

-- Расчёт норм по шагам шаблона (нормирование): план-минуты и стоимость работ.
-- Ставка: приоритет — операция, затем связанная норма, затем нормочас оборудования.
create or replace function public.app_route_calc(p_token uuid, p_id uuid, p_qty numeric)
returns table (seq integer, operation text, equipment text, norm_source text,
               setup_min numeric, unit_min numeric, qty numeric, plan_min numeric, rate_hour numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_process_templates t where t.id = p_id and (urole='admin' or t.tenant_id = ten)) then
    raise exception 'Шаблон не найден';
  end if;
  q := greatest(coalesce(p_qty,1), 0);
  return query
    select st.seq, o.name, e.name,
           case when o.id is null then 'шаблон'
                when exists (select 1 from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten)) then 'норма'
                else 'операция' end,
           coalesce(o.setup_min, 0),
           coalesce(nullif(o.unit_min,0), st.plan_min, 0),
           q,
           coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                    e.cost_hour, 0),
           round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
                 * coalesce(nullif(o.base_rate,0),
                            (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                            e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = p_id
    order by st.seq;
end $$;

-- Итоговый расчёт себестоимости по шаблону: работы + материал + накладные.
create or replace function public.app_route_cost(p_token uuid, p_id uuid, p_qty numeric, p_material_id uuid, p_mat_qty numeric)
returns table (step_count bigint, total_min numeric, work_cost numeric, material_cost numeric, overhead numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q numeric; mq numeric; price numeric; rwork numeric; rmin numeric; rcnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_process_templates t where t.id = p_id and (urole='admin' or t.tenant_id = ten)) then
    raise exception 'Шаблон не найден';
  end if;
  q := greatest(coalesce(p_qty,1), 0);

  with rs as (
    select coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q as pm,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                    e.cost_hour, 0) as rt
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = p_id
  )
  select count(*), coalesce(sum(pm),0), coalesce(sum(round(pm/60.0*rt,2)),0)
    into rcnt, rmin, rwork from rs;

  price := 0;
  if p_material_id is not null then
    select m.price into price from public.app_materials m where m.id = p_material_id and (urole='admin' or m.tenant_id = ten);
  end if;
  mq := coalesce(p_mat_qty, 0);

  step_count := rcnt;
  total_min := rmin;
  work_cost := rwork;
  material_cost := round(coalesce(price,0) * mq * q, 2);
  overhead := round((work_cost + material_cost) * 0.15, 2);
  total := round((work_cost + material_cost) * 1.15, 2);
  return next;
end $$;

-- Создать маршрут из шаблона техпроцесса (со снимком норм и расчётом).
create or replace function public.app_route_from_tpl(p_token uuid, p_id uuid, p_order_id uuid, p_qty numeric,
  p_material_id uuid, p_mat_qty numeric, p_name text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; uid uuid; ulogin text; q numeric; rid uuid; rnum text; tname text; tmat uuid;
        vcnt bigint; vmin numeric; vwork numeric; vmat numeric; vovh numeric; vtot numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name, t.material_id into tname, tmat from public.app_process_templates t
    where t.id = p_id and (urole='admin' or t.tenant_id = ten);
  if tname is null then raise exception 'Шаблон не найден'; end if;
  q := greatest(coalesce(p_qty,1), 0);

  select c.step_count, c.total_min, c.work_cost, c.material_cost, c.overhead, c.total
    into vcnt, vmin, vwork, vmat, vovh, vtot
    from public.app_route_cost(p_token, p_id, q, coalesce(p_material_id, tmat), p_mat_qty) c;

  rnum := 'MR-' || lpad(nextval('public.app_route_seq')::text, 5, '0');
  insert into public.app_routes (tenant_id, number, name, order_id, template_id, material_id, qty, mat_qty,
      status, work_cost, material_cost, overhead, total_min, total_cost, note, created_by, created_login)
  values (ten, rnum, coalesce(nullif(trim(p_name),''), tname || ' ×' || q), p_order_id, p_id,
      coalesce(p_material_id, tmat), q, coalesce(p_mat_qty,0), 'draft', vwork, vmat, vovh, vmin, vtot,
      nullif(trim(p_note),''), uid, ulogin)
  returning app_routes.id into rid;

  insert into public.app_route_steps (route_id, seq, operation_id, equipment_id, norm_id, setup_min, unit_min, qty, plan_min, rate_hour, cost)
  select rid, st.seq, st.operation_id, st.equipment_id,
         (select n.id from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
         coalesce(o.setup_min, 0),
         coalesce(nullif(o.unit_min,0), st.plan_min, 0),
         q,
         coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
         coalesce(nullif(o.base_rate,0),
                  (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                  e.cost_hour, 0),
         round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
               * coalesce(nullif(o.base_rate,0),
                          (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                          e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
   where st.template_id = p_id;

  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Маршрут ' || rnum,
    coalesce(nullif(trim(p_name),''), tname), 'apps/registry/index.html');
  return query select rid, rnum, 'Маршрут создан';
end $$;

-- Список маршрутов.
create or replace function public.app_route_list(p_token uuid)
returns table (id uuid, number text, name text, template_name text, order_number text, qty numeric, status text,
               step_count bigint, total_min numeric, work_cost numeric, material_cost numeric, overhead numeric,
               total_cost numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.name, t.name, o.number, r.qty, r.status,
           (select count(*) from public.app_route_steps st where st.route_id = r.id),
           r.total_min, r.work_cost, r.material_cost, r.overhead, r.total_cost, r.created_at
    from public.app_routes r
    left join public.app_process_templates t on t.id = r.template_id
    left join public.app_orders o on o.id = r.order_id
    where (urole='admin' or r.tenant_id = ten)
    order by r.created_at desc;
end $$;

-- Карточка маршрута.
create or replace function public.app_route_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, name text, template_name text, order_id uuid, order_number text,
               material_name text, qty numeric, mat_qty numeric, status text,
               total_min numeric, work_cost numeric, material_cost numeric, overhead numeric, total_cost numeric,
               note text, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.name, t.name, r.order_id, o.number, m.name, r.qty, r.mat_qty, r.status,
           r.total_min, r.work_cost, r.material_cost, r.overhead, r.total_cost, r.note, r.created_login, r.created_at
    from public.app_routes r
    left join public.app_process_templates t on t.id = r.template_id
    left join public.app_orders o on o.id = r.order_id
    left join public.app_materials m on m.id = r.material_id
    where r.id = p_id and (urole='admin' or r.tenant_id = ten);
end $$;

-- Шаги маршрута (снимок норм).
create or replace function public.app_route_steps_list(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, equipment text, norm_source text,
               setup_min numeric, unit_min numeric, qty numeric, plan_min numeric, rate_hour numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select st.id, st.seq, o.name, e.name,
           case when st.norm_id is not null then 'норма' else 'операция' end,
           st.setup_min, st.unit_min, st.qty, st.plan_min, st.rate_hour, st.cost
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    join public.app_routes r on r.id = st.route_id
    where st.route_id = p_id and (urole='admin' or r.tenant_id = ten)
    order by st.seq;
end $$;

-- Смена статуса маршрута.
create or replace function public.app_route_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; rnum text; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := case when p_status in ('draft','active','done') then p_status else null end;
  if st is null then return query select false,'Недопустимый статус'; return; end if;
  select r.number into rnum from public.app_routes r where r.id = p_id and (urole='admin' or r.tenant_id = ten);
  if rnum is null then return query select false,'Маршрут не найден'; return; end if;
  update public.app_routes r set status = st where r.id = p_id;
  if st = 'done' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Маршрут ' || rnum || ' завершён', '', 'apps/registry/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

-- Себестоимость маршрутов заказа (связь маршрут → заказ → экономика).
create or replace function public.app_order_routes_cost(p_token uuid, p_order_id uuid)
returns table (route_count bigint, total_min numeric, work_cost numeric, material_cost numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; oten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.tenant_id into oten from public.app_orders o where o.id = p_order_id;
  if oten is null or not (urole='admin' or oten = ten) then raise exception 'Доступ запрещён'; end if;
  return query
    select count(*), coalesce(sum(r.total_min),0), coalesce(sum(r.work_cost),0),
           coalesce(sum(r.material_cost),0), coalesce(sum(r.total_cost),0)
    from public.app_routes r where r.order_id = p_order_id;
end $$;

grant execute on function public.app_route_calc(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_route_cost(uuid,uuid,numeric,uuid,numeric) to anon, authenticated;
grant execute on function public.app_route_from_tpl(uuid,uuid,uuid,numeric,uuid,numeric,text,text) to anon, authenticated;
grant execute on function public.app_route_list(uuid) to anon, authenticated;
grant execute on function public.app_route_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_steps_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_order_routes_cost(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо-данные (тенант A): маршрут из техпроцесса TP-01 «Кронштейн», 10 шт.
-- ============================================================
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        tpl uuid; mat uuid; ord uuid; rid uuid;
        q numeric := 10; mq numeric := 12.5; price numeric := 0;
        vcnt bigint; vmin numeric; vwork numeric; vmat numeric; vovh numeric; vtot numeric;
begin
  if exists (select 1 from public.app_routes where tenant_id = ten) then return; end if;
  select t.id, t.material_id into tpl, mat
    from public.app_process_templates t
    where t.tenant_id = ten and t.code = 'TP-01' limit 1;
  if tpl is null then return; end if;
  select id into ord from public.app_orders where tenant_id = ten order by created_at limit 1;
  select coalesce(m.price,0) into price from public.app_materials m where m.id = mat;

  with rs as (
    select coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q as pm,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and n.tenant_id = ten order by n.id limit 1),
                    e.cost_hour, 0) as rt
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = tpl
  )
  select count(*), coalesce(sum(pm),0), coalesce(sum(round(pm/60.0*rt,2)),0)
    into vcnt, vmin, vwork from rs;
  vmat := round(price * mq * q, 2);
  vovh := round((vwork + vmat) * 0.15, 2);
  vtot := round((vwork + vmat) * 1.15, 2);

  insert into public.app_routes (tenant_id, number, name, order_id, template_id, material_id, qty, mat_qty,
      status, work_cost, material_cost, overhead, total_min, total_cost, note, created_login)
  values (ten, 'MR-' || lpad(nextval('public.app_route_seq')::text, 5, '0'), 'Кронштейн ×' || q, ord, tpl, mat, q, mq,
      'active', vwork, vmat, vovh, vmin, vtot, 'Демо-маршрут по TP-01', 'owner')
  returning id into rid;

  insert into public.app_route_steps (route_id, seq, operation_id, equipment_id, norm_id, setup_min, unit_min, qty, plan_min, rate_hour, cost)
  select rid, st.seq, st.operation_id, st.equipment_id,
         (select n.id from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
         coalesce(o.setup_min, 0),
         coalesce(nullif(o.unit_min,0), st.plan_min, 0),
         q,
         coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
         coalesce(nullif(o.base_rate,0),
                  (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
                  e.cost_hour, 0),
         round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
               * coalesce(nullif(o.base_rate,0),
                          (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
                          e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
   where st.template_id = tpl;
end $$;
-- <<<<<<<<<< 0025_routes.sql <<<<<<<<<<

-- >>>>>>>>>> 0026_naryad_route.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0026_naryad_route.sql  (v9.1 — маршрут → наряд)
-- Перенос маршрута в наряд: автогенерация операций наряда из шагов маршрута
-- (нормо-минуты → план-часы), связь наряд ↔ маршрут ↔ заявка.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0025.
-- ============================================================

-- ---------- Связь наряда с маршрутом ----------
alter table public.app_naryads   add column if not exists route_id uuid references public.app_routes (id) on delete set null;
alter table public.app_naryad_ops add column if not exists operation_id  uuid references public.app_operations (id) on delete set null;
alter table public.app_naryad_ops add column if not exists route_step_id uuid references public.app_route_steps (id) on delete set null;
create index if not exists app_naryads_route_idx on public.app_naryads (route_id);

-- ---------- Карточка наряда + маршрут ----------
drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz,
               route_id uuid, route_number text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at,
    n.route_id, r.number
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    left join public.app_routes r on r.id = n.route_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

-- ---------- Создать наряд из маршрута (операции из шагов) ----------
create or replace function public.app_naryad_from_route(p_token uuid, p_route_id uuid, p_wc_id uuid, p_assignee text, p_due_date date)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; uid uuid; ulogin text; rid uuid; rnum text; rname text; rorder uuid;
        target uuid; dwc uuid; nid uuid; nnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r.id, r.number, r.name, r.order_id into rid, rnum, rname, rorder
    from public.app_routes r where r.id = p_route_id and (urole='admin' or r.tenant_id = ten);
  if rid is null then raise exception 'Маршрут не найден'; end if;
  if exists (select 1 from public.app_naryads n where n.route_id = rid and n.status <> 'closed') then
    raise exception 'По маршруту уже есть активный наряд';
  end if;

  dwc := p_wc_id;
  if dwc is null then
    select e.wc_id into dwc
      from public.app_route_steps st join public.app_equipment e on e.id = st.equipment_id
      where st.route_id = rid and e.wc_id is not null order by st.seq limit 1;
  end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, route_id, tenant_id, title, wc_id, assignee, status, created_by, created_login)
  values (nnum, rorder, rid, ten, coalesce(rname, 'Маршрут') || ' · ' || rnum, dwc, nullif(trim(p_assignee),''), 'open', uid, ulogin)
  returning app_naryads.id into nid;

  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours, operation_id, route_step_id)
  select nid, st.seq, coalesce(o.name, 'Операция ' || st.seq), nullif(trim(p_assignee),''),
         round(st.plan_min / 60.0, 2), st.operation_id, st.id
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    where st.route_id = rid
    order by st.seq;

  update public.app_naryads n
     set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
         status = 'in_progress', updated_at = now()
   where n.id = nid;
  update public.app_routes r set status = 'active' where r.id = rid and r.status = 'draft';

  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Наряд ' || nnum || ' по маршруту ' || rnum, rname, 'apps/production/index.html');
  if nullif(trim(p_assignee),'') is not null then
    select u.id into target from public.app_users u
      where lower(u.login) = lower(trim(p_assignee)) and u.active and u.tenant_id = ten limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, rname, 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum, 'Наряд создан по маршруту';
end $$;

-- ---------- Наряды маршрута ----------
create or replace function public.app_route_naryads(p_token uuid, p_route_id uuid)
returns table (id uuid, number text, title text, status text, assignee text, plan_hours numeric, fact_hours numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.status, n.assignee, n.plan_hours, n.fact_hours, n.created_at
    from public.app_naryads n join public.app_routes r on r.id = n.route_id
    where n.route_id = p_route_id and (urole='admin' or r.tenant_id = ten)
    order by n.created_at desc;
end $$;

grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_from_route(uuid,uuid,uuid,text,date) to anon, authenticated;
grant execute on function public.app_route_naryads(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо (тенант A): наряд по демо-маршруту MR-00001
-- ============================================================
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        rid uuid; rorder uuid; rname text; rnum text; nid uuid; nnum text; dwc uuid;
begin
  select r.id, r.order_id, r.name, r.number into rid, rorder, rname, rnum
    from public.app_routes r where r.tenant_id = ten and r.number = 'MR-00001' limit 1;
  if rid is null then return; end if;
  if exists (select 1 from public.app_naryads where route_id = rid) then return; end if;

  select e.wc_id into dwc
    from public.app_route_steps st join public.app_equipment e on e.id = st.equipment_id
    where st.route_id = rid and e.wc_id is not null order by st.seq limit 1;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, route_id, tenant_id, title, wc_id, status, created_login)
  values (nnum, rorder, rid, ten, rname || ' · ' || rnum, dwc, 'in_progress', 'owner')
  returning id into nid;

  insert into public.app_naryad_ops (naryad_id, seq, operation, plan_hours, operation_id, route_step_id)
  select nid, st.seq, coalesce(o.name, 'Операция ' || st.seq), round(st.plan_min / 60.0, 2), st.operation_id, st.id
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    where st.route_id = rid order by st.seq;

  update public.app_naryads n
     set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = nid;
end $$;
-- <<<<<<<<<< 0026_naryad_route.sql <<<<<<<<<<

-- >>>>>>>>>> 0027_orders_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0027_orders_ref.sql  (v11.0 — переработка «Заявки» как эталон)
-- Заказчики (CRM), расширение заявки: срок, исполнитель, сумма, заказчик.
-- Позиции заявки, связи заявки с документами/нарядами/счетами/маршрутами.
-- Наполнение базы знаний (app_knowledge). Изоляция по tenant. Зависит от 0001..0026.
-- ============================================================

-- ---------- Заказчики (CRM) ----------
create table if not exists public.app_customers (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  name           text not null,
  inn            text,
  contact_person text,
  phone          text,
  email          text,
  address        text,
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists app_customers_tenant_idx on public.app_customers (tenant_id, name);
alter table public.app_customers enable row level security;

-- ---------- Расширение заявки ----------
alter table public.app_orders add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_orders add column if not exists due_date    date;
alter table public.app_orders add column if not exists assignee    text;
alter table public.app_orders add column if not exists amount      numeric;
create index if not exists app_orders_customer_idx on public.app_orders (customer_id);

-- ============================================================
--  CRM: RPC
-- ============================================================
create or replace function public.app_customer_list(p_token uuid)
returns table (id uuid, name text, inn text, contact_person text, phone text, email text, address text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.name, c.inn, c.contact_person, c.phone, c.email, c.address, c.note
    from public.app_customers c where (urole='admin' or c.tenant_id = ten) order by c.name;
end $$;

create or replace function public.app_customer_save(p_token uuid, p_id uuid, p_name text, p_inn text,
  p_contact_person text, p_phone text, p_email text, p_address text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название заказчика'; end if;
  if p_id is null then
    insert into public.app_customers (tenant_id, name, inn, contact_person, phone, email, address, note)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact_person),''),
            nullif(trim(p_phone),''), nullif(trim(p_email),''), nullif(trim(p_address),''), nullif(trim(p_note),''))
    returning app_customers.id into cid;
  else
    update public.app_customers set name=trim(p_name), inn=nullif(trim(p_inn),''), contact_person=nullif(trim(p_contact_person),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), address=nullif(trim(p_address),''), note=nullif(trim(p_note),'')
     where id=p_id and (ten is null or tenant_id=ten) returning app_customers.id into cid;
  end if;
  return query select cid, 'Заказчик сохранён';
end $$;

-- ============================================================
--  Заявки: RPC (переработка)
-- ============================================================
drop function if exists public.app_order_create(uuid,text,text,text,text,text,text);
drop function if exists public.app_order_list(uuid);
drop function if exists public.app_order_get(uuid,uuid);

-- Создать заявку (расширенная).
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null, p_amount numeric default null
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid; cname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, customer_id, contact, priority,
                                 status, due_date, assignee, amount, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  if nullif(trim(p_assignee),'') is not null then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Назначена заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  end if;

  return query select oid, onum;
end $$;

-- Список заявок (расширенный).
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

-- Одна заявка (расширенная).
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.customer_id, c.name,
           o.contact, o.status, o.priority, o.due_date, o.assignee, o.amount,
           o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

-- Изменить заявку.
create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; cname text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_id and (urole='admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки'; return; end if;

  cname := null;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  update public.app_orders set title = trim(p_title), description = nullif(trim(p_description),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), customer_id = p_customer_id,
    customer = coalesce(cname, customer), contact = nullif(trim(p_contact),''), due_date = p_due_date,
    assignee = nullif(trim(p_assignee),''), amount = p_amount, updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

-- ---------- Позиции заявки ----------
create or replace function public.app_order_items_list(p_token uuid, p_order_id uuid)
returns table (id uuid, name text, qty numeric, unit text, price numeric, amount numeric)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select i.id, i.name, i.qty, i.unit, i.price, round(coalesce(i.qty,0)*coalesce(i.price,0),2)
    from public.app_order_items i where i.order_id = p_order_id order by i.id;
end $$;

create or replace function public.app_order_item_add(p_token uuid, p_order_id uuid, p_name text, p_qty numeric, p_unit text, p_price numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; total numeric;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id = ten)) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование позиции'; return; end if;
  insert into public.app_order_items (order_id, name, qty, unit, price)
  values (p_order_id, trim(p_name), coalesce(p_qty,1), nullif(trim(p_unit),''), p_price);
  select coalesce(sum(coalesce(i.qty,0)*coalesce(i.price,0)),0) into total from public.app_order_items i where i.order_id = p_order_id;
  update public.app_orders o set amount = case when coalesce(o.amount,0) = 0 then total else o.amount end, updated_at = now() where o.id = p_order_id;
  return query select true,'Позиция добавлена';
end $$;

create or replace function public.app_order_item_remove(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; oid uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select i.order_id into oid from public.app_order_items i join public.app_orders o on o.id = i.order_id
    where i.id = p_id and (urole='admin' or o.tenant_id = ten);
  if oid is null then return query select false,'Позиция не найдена'; return; end if;
  delete from public.app_order_items where id = p_id;
  return query select true,'Позиция удалена';
end $$;

-- ---------- Связи заявки ----------
create or replace function public.app_order_docs(p_token uuid, p_order_id uuid)
returns table (id uuid, doc_type text, number text, title text, status text, amount numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.status, d.amount, d.created_at
    from public.app_documents d where d.order_id = p_order_id and (urole='admin' or d.tenant_id = ten)
    order by d.created_at desc;
end $$;

create or replace function public.app_order_naryads(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, title text, status text, plan_hours numeric, fact_hours numeric, route_number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.status, n.plan_hours, n.fact_hours, r.number
    from public.app_naryads n left join public.app_routes r on r.id = n.route_id
    where n.order_id = p_order_id and (urole='admin' or n.tenant_id = ten)
    order by n.created_at desc;
end $$;

create or replace function public.app_order_invoices(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, amount numeric, status text, due_date date)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select i.id, i.number, i.amount, i.status, i.due_date
    from public.app_invoices i where i.order_id = p_order_id and (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

create or replace function public.app_order_routes(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, name text, status text, total_min numeric, total_cost numeric)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.number, r.name, r.status, r.total_min, r.total_cost
    from public.app_routes r where r.order_id = p_order_id and (urole='admin' or r.tenant_id = ten)
    order by r.created_at desc;
end $$;

grant execute on function public.app_customer_list(uuid) to anon, authenticated;
grant execute on function public.app_customer_save(uuid,uuid,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric) to anon, authenticated;
grant execute on function public.app_order_list(uuid) to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric) to anon, authenticated;
grant execute on function public.app_order_items_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_item_add(uuid,uuid,text,numeric,text,numeric) to anon, authenticated;
grant execute on function public.app_order_item_remove(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_docs(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_naryads(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_invoices(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_routes(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо-заказчики (тенант A)
-- ============================================================
insert into public.app_customers (tenant_id, name, inn, contact_person, phone, email, address)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.inn, v.cp, v.phone, v.email, v.addr
from (values
  ('ООО «ТехноМаш»', '7701234567', 'Иванов И.И.', '+7 495 111-22-33', 'zakaz@technomash.ru', 'г. Москва, ул. Заводская, 1'),
  ('АО «АвиаДеталь»', '7809876543', 'Петрова А.С.', '+7 812 222-33-44', 'sales@aviadetal.ru', 'г. Санкт-Петербург, пр. Металлистов, 10'),
  ('ООО «ЭнергоРемонт»', '5022334455', 'Сидоров П.П.', '+7 916 555-66-77', 'info@energoremont.ru', 'г. Подольск, ул. Ремонтная, 5')
) as v(name,inn,cp,phone,email,addr)
where not exists (select 1 from public.app_customers where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001');

-- ============================================================
--  База знаний: описания модуля «Заявки» (тенант A)
-- ============================================================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Заявки','Как создать заявку и что заполнить?',
   'Откройте модуль «Заявки» → «Новая заявка». Обязательно: тема. Рекомендуется: заказчик (из CRM), источник, срок, приоритет, исполнитель, сумма и описание. Заявка получает номер REQ-NNNNN и попадает в общий список; ответственным приходит уведомление.',
   'заявка создать требования поля'),
  ('Заявки','Что такое заказчик в CRM и как он связан с заявкой?',
   'Заказчик (модуль «Заявки», блок CRM) — карточка контрагента: название, ИНН, контактное лицо, телефон, e-mail, адрес. При создании заявки выбирается заказчик; заявка хранит и ссылку на карточку, и имя. Это основа для КП, договора и счёта.',
   'заказчик CRM контрагент связь'),
  ('Заявки','Как заявка связана с КП, договором, счётом и нарядом?',
   'Карточка заявки показывает связанные сущности: документы (КП/договор/акт, модуль «Документы»), счета (модуль «Финансы»), наряды и маршруты (модули «Производство» и «Справочники»). Связь по заявке: документ/счёт/наряд создаются с указанием заявки. Это единый сквозной поток: заявка → КП → договор → наряд → счёт → оплата.',
   'заявка связи КП договор счет наряд маршрут поток'),
  ('Заявки','Приоритеты и сроки заявок',
   'Приоритет: низкий / обычный / высокий. Срок (план-дата) задаётся вручную и используется планированием и нарядами. Просрочку смотрите фильтрами и в KPI. Для срочных заказов ставьте высокий приоритет — он виден мастеру и в диспетчерской.',
   'приоритет срок дедлайн планирование'),
  ('Система','Роли и доступ в модуле «Заявки»',
   'Директор/владелец и администратор видят все заявки организации; начальник цеха, мастер, технолог, снабженец, экономист — видят заявки организации; рядовой пользователь — только свои созданные. Все данные изолированы по организации (tenant).',
   'роли доступ права заявки организация')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Заявки');
-- <<<<<<<<<< 0027_orders_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0028_orders_sla.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0028_orders_sla.sql  (v11.1 — типы заказов и SLA)
-- Тип заказа (единичный/серийный/оснастка/инжиниринг) и уведомления о просрочке.
-- Изоляция по tenant. Зависит от 0001..0027.
-- ============================================================

alter table public.app_orders add column if not exists order_type text not null default 'single'; -- single|batch|tooling|engineering
alter table public.app_orders add column if not exists overdue_notified_at timestamptz;

-- ---------- Создать заявку (с типом) ----------
drop function if exists public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric);
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null,
  p_amount numeric default null, p_order_type text default 'single'
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid; cname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, customer_id, contact, priority,
                                 status, due_date, assignee, amount, order_type, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, coalesce(nullif(trim(p_order_type),''),'single'), ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

-- ---------- Список заявок (с типом) ----------
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.order_type, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

-- ---------- Одна заявка (с типом) ----------
drop function if exists public.app_order_get(uuid,uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.customer_id, c.name,
           o.contact, o.status, o.priority, o.due_date, o.assignee, o.amount, o.order_type,
           o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

-- ---------- Изменить заявку (с типом) ----------
drop function if exists public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric);
create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric, p_order_type text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; cname text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_id and (urole='admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки'; return; end if;

  cname := null;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  update public.app_orders set title = trim(p_title), description = nullif(trim(p_description),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), customer_id = p_customer_id,
    customer = coalesce(cname, customer), contact = nullif(trim(p_contact),''), due_date = p_due_date,
    assignee = nullif(trim(p_assignee),''), amount = p_amount,
    order_type = coalesce(nullif(trim(p_order_type),''), order_type), updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

-- ---------- SLA: уведомления о просрочке (однократно на заявку) ----------
create or replace function public.app_order_sla_check(p_token uuid)
returns table (notified bigint)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; n bigint;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select 0::bigint; return; end if;
  ten := public.app_my_tenant(p_token);
  with ov as (
    update public.app_orders o
       set overdue_notified_at = now()
     where (urole = 'admin' or o.tenant_id = ten)
       and o.due_date is not null and o.due_date < current_date
       and o.status not in ('done','cancelled')
       and o.overdue_notified_at is null
    returning o.number, o.title, o.tenant_id
  ), ins as (
    insert into public.app_notifications (user_id, title, body, link)
    select u.id, 'Просрочена заявка ' || ov.number, ov.title, 'apps/orders/index.html'
    from ov join public.app_users u
      on u.active and u.role in ('admin','manager','owner') and (ov.tenant_id is null or u.tenant_id = ov.tenant_id)
    returning 1
  )
  select count(*) into n from ins;
  return query select n;
end $$;

grant execute on function public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_order_list(uuid) to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_order_sla_check(uuid) to anon, authenticated;

-- ---------- База знаний: типы заказов и SLA ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Заявки','Типы заказов: какие бывают и зачем поле «Тип»?',
   'Тип заказа уточняет характер работы и влияет на маршрут и планирование: «Единичный/штучный» — разовые детали; «Серийный/партия» — повторяемые партии, выгодны типовые техпроцессы; «Оснастка/штамп/пресс-форма» — изготовление оснастки (длинный цикл, проектирование); «Инжиниринг/НИОКР» — реверс-инжиниринг, конструкторские работы. Тип отображается бейджем в списке и карточке.',
   'тип заказа единичный серийный оснастка инжиниринг НИОКР'),
  ('Заявки','Как работает напоминание о просрочке (SLA)?',
   'Если у заявки задан срок и он прошёл, а статус не «Выполнена» и не «Отменена», система один раз создаёт уведомление о просрочке ответственным (директор, начальник цеха, менеджер). Повторно по одной заявке не уведомляет. Просроченные видно фильтром «Просрочены» и в KPI. Двигайте срок или закрывайте заявку, чтобы убрать просрочку.',
   'SLA просрочка срок уведомление напоминание')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Типы заказов: какие бывают и зачем поле «Тип»?');
-- <<<<<<<<<< 0028_orders_sla.sql <<<<<<<<<<

-- >>>>>>>>>> 0029_roles.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0029_roles.sql  (v12.0 — роли предприятия и матрица прав, P8)
-- 8 ролей предприятия + существующие. Матрица «роль × модуль» (просмотр/правка).
-- Изоляция по tenant. Зависит от 0001..0028.
-- ============================================================

-- ---------- Роли ----------
create or replace function public.app_staff_roles()
returns text[] language sql immutable
as $$ select array['admin','owner','manager','director','chief','master','technologist','operator','supply','qc','economist']::text[] $$;

create or replace function public.app_role_is_staff(p_role text)
returns boolean language sql immutable
as $$ select coalesce(p_role, '') = any (public.app_staff_roles()) $$;

-- Расширяем доступ к производственным/учётным RPC на все роли предприятия.
create or replace function public.app_production_allowed(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.app_session_user(p_token) s
    where public.app_role_is_staff(s.urole)
  );
$$;

-- ---------- Заявки: доступ по ролям предприятия ----------
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.order_type, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or public.app_role_is_staff(urole) or o.created_by = uid)
    order by o.created_at desc;
end $$;

create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.customer_id, c.name,
           o.contact, o.status, o.priority, o.due_date, o.assignee, o.amount, o.order_type,
           o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (public.app_role_is_staff(urole) or o.created_by = uid)));
end $$;

create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; owner uuid; onum text; oten uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select o.created_by, o.number, o.tenant_id into owner, onum, oten from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole = 'admin' or (oten = ten and (public.app_role_is_staff(urole) or owner = uid))) then
    return query select false, 'Доступ запрещён'; return;
  end if;
  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment),''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment,''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- Матрица прав: роль × модуль ----------
create table if not exists public.app_role_permissions (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  role       text not null,
  module_id  text not null,
  can_view   boolean not null default true,
  can_edit   boolean not null default false,
  unique (tenant_id, role, module_id)
);
create index if not exists app_role_perms_idx on public.app_role_permissions (tenant_id, role);
alter table public.app_role_permissions enable row level security;

create or replace function public.app_roles_list(p_token uuid)
returns table (role text, users_count bigint, view_count bigint, edit_count bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.role,
           (select count(*) from public.app_users u where u.role = r.role and (urole='admin' or u.tenant_id = ten)),
           (select count(*) from public.app_role_permissions p where p.role = r.role and p.can_view and (ten is null or p.tenant_id = ten)),
           (select count(*) from public.app_role_permissions p where p.role = r.role and p.can_edit and (ten is null or p.tenant_id = ten))
    from unnest(public.app_staff_roles()) as r(role)
    order by r.role;
end $$;

create or replace function public.app_role_matrix(p_token uuid)
returns table (role text, module_id text, can_view boolean, can_edit boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.role, p.module_id, p.can_view, p.can_edit
    from public.app_role_permissions p
    where (urole='admin' or p.tenant_id = ten)
    order by p.role, p.module_id;
end $$;

create or replace function public.app_role_perm_set(p_token uuid, p_role text, p_module text, p_view boolean, p_edit boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return query select false,'Сессия недействительна'; return; end if;
  if urole not in ('admin','owner') then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not public.app_role_is_staff(p_role) then return query select false,'Неизвестная роль'; return; end if;
  if coalesce(trim(p_module),'') = '' then return query select false,'Не указан модуль'; return; end if;

  insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit)
  values (ten, p_role, p_module, coalesce(p_view,false), coalesce(p_edit,false))
  on conflict (tenant_id, role, module_id) do update set can_view = excluded.can_view, can_edit = excluded.can_edit;
  return query select true,'Сохранено';
end $$;

grant execute on function public.app_staff_roles() to anon, authenticated;
grant execute on function public.app_role_is_staff(text) to anon, authenticated;
grant execute on function public.app_roles_list(uuid) to anon, authenticated;
grant execute on function public.app_role_matrix(uuid) to anon, authenticated;
grant execute on function public.app_role_perm_set(uuid,text,text,boolean,boolean) to anon, authenticated;

-- ============================================================
--  Демо-пользователи ролей (тенант A). Пароль = логин.
-- ============================================================
insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values
  ('director',      extensions.crypt('director',      extensions.gen_salt('bf')), 'Директор',              'director',      'aaaaaaaa-0000-0000-0000-000000000001'),
  ('chief',         extensions.crypt('chief',         extensions.gen_salt('bf')), 'Начальник цеха',        'chief',         'aaaaaaaa-0000-0000-0000-000000000001'),
  ('master',        extensions.crypt('master',        extensions.gen_salt('bf')), 'Мастер смены',          'master',        'aaaaaaaa-0000-0000-0000-000000000001'),
  ('technologist',  extensions.crypt('technologist',  extensions.gen_salt('bf')), 'Технолог',              'technologist',  'aaaaaaaa-0000-0000-0000-000000000001'),
  ('operator',      extensions.crypt('operator',      extensions.gen_salt('bf')), 'Оператор ЧПУ',          'operator',      'aaaaaaaa-0000-0000-0000-000000000001'),
  ('supply',        extensions.crypt('supply',        extensions.gen_salt('bf')), 'Снабженец',             'supply',        'aaaaaaaa-0000-0000-0000-000000000001'),
  ('otk',           extensions.crypt('otk',           extensions.gen_salt('bf')), 'Контролёр ОТК',         'qc',            'aaaaaaaa-0000-0000-0000-000000000001'),
  ('economist',     extensions.crypt('economist',     extensions.gen_salt('bf')), 'Экономист',             'economist',     'aaaaaaaa-0000-0000-0000-000000000001')
on conflict (login) do update set role = excluded.role, tenant_id = excluded.tenant_id, full_name = excluded.full_name;

-- ============================================================
--  Демо-матрица (тенант A)
-- ============================================================
-- Владелец, админ, директор — все модули (правка у всех трёх; платформенные скроются по каталогу).
insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit)
select 'aaaaaaaa-0000-0000-0000-000000000001', r.role, m.module_id, true, true
from (values ('owner'),('admin'),('director')) as r(role)
cross join (values
  ('auth'),('panel'),('dashboard'),('guide'),('modules'),('eco'),('orders'),('supplier'),('procurement'),('docs'),
  ('registry'),('bom'),('assistant'),('production'),('mes'),('planning'),('warehouse'),('qc'),('passport'),('quality'),
  ('economics'),('finance'),('bi'),('reports'),('hr'),('org'),('platform'),('admin'),('diagnostics'),('api'),('roles')
) as m(module_id)
where not exists (select 1 from public.app_role_permissions where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and role = r.role and module_id = m.module_id);

-- Остальные роли — по функциям.
insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.role, v.module_id, v.can_view, v.can_edit
from (values
  ('chief','orders',true,false),('chief','dashboard',true,false),('chief','panel',true,false),('chief','production',true,true),('chief','planning',true,true),('chief','mes',true,true),('chief','warehouse',true,true),('chief','registry',true,false),('chief','qc',true,false),('chief','hr',true,false),('chief','reports',true,false),
  ('master','orders',true,false),('master','dashboard',true,false),('master','panel',true,false),('master','production',true,true),('master','mes',true,true),('master','planning',true,false),('master','warehouse',true,false),('master','registry',true,false),('master','qc',true,false),
  ('technologist','orders',true,false),('technologist','dashboard',true,false),('technologist','panel',true,false),('technologist','registry',true,true),('technologist','bom',true,true),('technologist','assistant',true,true),('technologist','production',true,false),('technologist','docs',true,true),('technologist','planning',true,false),('technologist','economics',true,false),
  ('operator','dashboard',true,false),('operator','panel',true,false),('operator','production',true,false),('operator','mes',true,true),('operator','passport',true,true),('operator','qc',true,false),('operator','registry',true,false),
  ('supply','orders',true,false),('supply','dashboard',true,false),('supply','panel',true,false),('supply','procurement',true,true),('supply','supplier',true,true),('supply','warehouse',true,true),('supply','registry',true,false),('supply','docs',true,false),
  ('qc','dashboard',true,false),('qc','panel',true,false),('qc','qc',true,true),('qc','quality',true,true),('qc','passport',true,true),('qc','registry',true,false),('qc','production',true,false),
  ('economist','orders',true,false),('economist','dashboard',true,false),('economist','panel',true,false),('economist','economics',true,true),('economist','finance',true,true),('economist','bi',true,true),('economist','reports',true,true),('economist','registry',true,false)
) as v(role,module_id,can_view,can_edit)
where not exists (select 1 from public.app_role_permissions where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and role = v.role and module_id = v.module_id);

-- ============================================================
--  База знаний: роли
-- ============================================================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Роли','Какие роли есть в системе?',
   'Сотрудники: директор, начальник цеха/участка, мастер/бригадир, технолог/инженер, оператор ЧПУ, снабженец, ОТК/метролог, экономист/бухгалтер. Административные: владелец организации (owner) и администратор платформы. Внешний пользователь — поставщик.',
   'роли директор начальник мастер технолог оператор снабженец ОТК экономист'),
  ('Роли','Что такое матрица прав (роль × модуль)?',
   'Матрица задаёт для каждой роли, какие модули доступны (просмотр) и где можно изменять данные (правка). Настраивается в модуле «Роли и права» (владелец/администратор). Например: оператор ЧПУ видит наряд и MES, ОТК — контроль и паспорта, экономист — финансы и экономику.',
   'матрица права роль модуль просмотр правка доступ')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Какие роли есть в системе?');
-- <<<<<<<<<< 0029_roles.sql <<<<<<<<<<

-- >>>>>>>>>> 0030_docs_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0030_docs_ref.sql  (v13.0 — переработка «Документы»)
-- КП/договор/техкарта/акт: CRM-заказчик, срок действия, исполнитель, подписание.
-- Номера по типу: KP-/DOG-/TC-/ACT-. Связь с заявкой. Версии. База знаний.
-- Изоляция по tenant. Зависит от 0001..0029.
-- ============================================================

alter table public.app_documents add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_documents add column if not exists valid_until date;
alter table public.app_documents add column if not exists assignee    text;
alter table public.app_documents add column if not exists signed_at   timestamptz;
create index if not exists app_documents_customer_idx on public.app_documents (customer_id);

-- ---------- Список ----------
drop function if exists public.app_doc_list(uuid,text);
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, customer_id uuid, customer_name text,
               amount numeric, status text, version integer, order_id uuid, order_number text,
               valid_until date, assignee text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.doc_type, d.number, d.title, d.counterparty, d.customer_id, c.name,
           d.amount, d.status, d.version, d.order_id, o.number, d.valid_until, d.assignee, d.updated_at
    from public.app_documents d
    left join public.app_orders o on o.id = d.order_id
    left join public.app_customers c on c.id = d.customer_id
    where (urole='admin' or d.tenant_id = ten) and (p_type is null or p_type = '' or d.doc_type = p_type)
    order by d.updated_at desc;
end $$;

-- ---------- Один документ ----------
drop function if exists public.app_doc_get(uuid,uuid);
create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, order_number text,
               counterparty text, customer_id uuid, customer_name text, amount numeric, status text, version integer,
               valid_until date, assignee text, signed_at timestamptz, content text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.order_id, o.number, d.counterparty,
    d.customer_id, c.name, d.amount, d.status, d.version, d.valid_until, d.assignee, d.signed_at, d.content,
    d.created_login, d.created_at, d.updated_at
    from public.app_documents d
    left join public.app_orders o on o.id = d.order_id
    left join public.app_customers c on c.id = d.customer_id
    where d.id = p_id and (urole='admin' or d.tenant_id = ten);
end $$;

-- ---------- Создание (номер по типу) ----------
drop function if exists public.app_doc_create(uuid,text,text,uuid,text,numeric,text);
create or replace function public.app_doc_create(p_token uuid, p_doc_type text, p_title text, p_order_id uuid,
  p_counterparty text, p_amount numeric, p_content text,
  p_customer_id uuid default null, p_valid_until date default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; did uuid; dnum text; prefix text; dtype text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название документа'; end if;
  dtype := coalesce(nullif(trim(p_doc_type),''),'kp');
  prefix := case dtype when 'kp' then 'KP' when 'contract' then 'DOG' when 'techcard' then 'TC' when 'act' then 'ACT' else 'DOC' end;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, customer_id, amount,
                                    valid_until, assignee, content, created_by, created_login)
  values (ten, dtype, dnum, trim(p_title), p_order_id, coalesce(cname, nullif(trim(p_counterparty),'')),
          p_customer_id, p_amount, p_valid_until, nullif(trim(p_assignee),''), p_content, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, trim(p_title), p_content, ulogin);
  return query select did, dnum;
end $$;

-- ---------- Обновление (новая версия) ----------
drop function if exists public.app_doc_update(uuid,uuid,text,text,numeric,text);
create or replace function public.app_doc_update(p_token uuid, p_id uuid, p_title text, p_counterparty text, p_amount numeric, p_content text,
  p_customer_id uuid default null, p_valid_until date default null, p_assignee text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; v integer; cname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.version into v from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if v is null then return query select false,'Документ не найден'; return; end if;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  v := v + 1;
  update public.app_documents set title = coalesce(nullif(trim(p_title),''), title),
    counterparty = coalesce(cname, nullif(trim(p_counterparty),''), counterparty),
    customer_id = coalesce(p_customer_id, customer_id),
    amount = coalesce(p_amount, amount), valid_until = coalesce(p_valid_until, valid_until),
    assignee = coalesce(nullif(trim(p_assignee),''), assignee),
    content = coalesce(p_content, content), version = v, updated_at = now()
   where id = p_id;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (p_id, v, coalesce(nullif(trim(p_title),''),'—'), p_content, ulogin);
  return query select true,'Сохранено (версия ' || v || ')';
end $$;

-- ---------- Статус (с подписанием и уведомлением) ----------
create or replace function public.app_doc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; dnum text; dtype text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.number, d.doc_type into dnum, dtype from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if dnum is null then return query select false,'Документ не найден'; return; end if;
  update public.app_documents set status = p_status,
    signed_at = case when p_status = 'active' and dtype = 'contract' and signed_at is null then now() else signed_at end,
    updated_at = now()
   where id = p_id;
  if p_status = 'active' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director'], 'Документ ' || dnum || ' в работе', 'Подготовил: ' || coalesce(ulogin,''), 'apps/docs/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_doc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_doc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_create(uuid,text,text,uuid,text,numeric,text,uuid,date,text) to anon, authenticated;
grant execute on function public.app_doc_update(uuid,uuid,text,text,numeric,text,uuid,date,text) to anon, authenticated;
grant execute on function public.app_doc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо: КП по первой заявке тенанта A ----------
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        oid uuid; ocust uuid; dnum text; did uuid;
begin
  select o.id, o.customer_id into oid, ocust from public.app_orders o where o.tenant_id = ten order by o.created_at limit 1;
  if oid is null then return; end if;
  if exists (select 1 from public.app_documents where tenant_id = ten and order_id = oid) then return; end if;
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, created_login)
  values (ten, 'kp', dnum, 'Коммерческое предложение', oid, ocust, 39167.09, current_date + 30, 'draft',
          'Предложение по заявке. Срок действия — 30 дней.', 'owner')
  returning id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Коммерческое предложение', 'Предложение по заявке.', 'owner');
end $$;

-- ---------- База знаний: документы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Документы','Какие документы и как нумеруются?',
   'Типы: КП (коммерческое предложение) → номер KP-NNNNN; договор → DOG-NNNNN; техкарта → TC-NNNNN; акт → ACT-NNNNN. У каждого документа есть версии (v1, v2…): каждая правка создаёт новую версию, историю видно в карточке.',
   'документ КП договор техкарта акт номер версии'),
  ('Документы','Как документы связаны с заявкой и заказчиком?',
   'Документ создаётся с указанием заявки (заказ) и заказчика из CRM. В карточке заявки виден блок «Документы», в карточке документа — номер заявки. Связка: заявка → КП → договор → акт; далее счёт (Финансы) и наряд (Производство).',
   'документ заявка заказчик CRM связь КП договор акт'),
  ('Документы','Срок действия КП и подписание договора',
   'У КП указывается срок действия (valid_until) — до какой даты предложение актуально. У договора при переводе в статус «В работе» фиксируется дата подписания (signed_at) и уходит уведомление. Статусы: черновик → в работе → архив.',
   'КП срок действия договор подписание статус')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Документы');
-- <<<<<<<<<< 0030_docs_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0031_finance_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0031_finance_ref.sql  (v14.0 — переработка «Финансы»)
-- Счета и оплаты: CRM-заказчик, связь с договором (документ), исполнитель,
-- остаток, просрочка. Карточка счёта. База знаний. Изоляция по tenant.
-- Зависит от 0001..0030.
-- ============================================================

alter table public.app_invoices add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_invoices add column if not exists document_id uuid references public.app_documents (id) on delete set null;
alter table public.app_invoices add column if not exists assignee text;
create index if not exists app_invoices_customer_idx on public.app_invoices (customer_id);

-- ---------- Список счетов (расширенный) ----------
drop function if exists public.app_invoice_list(uuid);
create or replace function public.app_invoice_list(p_token uuid)
returns table (id uuid, number text, customer text, customer_id uuid, customer_name text,
               order_id uuid, order_number text, document_id uuid, document_number text,
               amount numeric, paid numeric, balance numeric, status text, due_date date, assignee text,
               is_overdue boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, i.customer_id, c.name, i.order_id, o.number, i.document_id, d.number,
           i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.assignee,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue')),
           i.created_at
    from public.app_invoices i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_customers c on c.id = i.customer_id
    left join public.app_documents d on d.id = i.document_id
    where (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

-- ---------- Карточка счёта ----------
create or replace function public.app_invoice_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, customer text, customer_id uuid, customer_name text,
               order_id uuid, order_number text, document_id uuid, document_number text,
               amount numeric, paid numeric, balance numeric, status text, due_date date, assignee text,
               is_overdue boolean, note text, created_login text, created_at timestamptz, paid_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, i.customer_id, c.name, i.order_id, o.number, i.document_id, d.number,
           i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.assignee,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue')),
           i.note, i.created_login, i.created_at, i.paid_at
    from public.app_invoices i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_customers c on c.id = i.customer_id
    left join public.app_documents d on d.id = i.document_id
    where i.id = p_id and (urole='admin' or i.tenant_id = ten);
end $$;

-- ---------- Создание счёта ----------
drop function if exists public.app_invoice_create(uuid,uuid,text,numeric,date,text);
create or replace function public.app_invoice_create(p_token uuid, p_order_id uuid, p_customer text, p_amount numeric, p_due_date date, p_note text,
  p_customer_id uuid default null, p_document_id uuid default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; iid uuid; inum text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, customer_id, document_id, amount, status, due_date, assignee, note, created_by, created_login)
  values (ten, inum, p_order_id, coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, p_document_id, p_amount, 'draft',
          p_due_date, nullif(trim(p_assignee),''), nullif(trim(p_note),''), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum;
end $$;

-- ---------- Статус счёта (с уведомлением) ----------
create or replace function public.app_invoice_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; inum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select i.number into inum from public.app_invoices i where i.id = p_id and (urole='admin' or i.tenant_id = ten);
  if inum is null then return query select false,'Счёт не найден'; return; end if;
  update public.app_invoices set status = p_status, paid_at = case when p_status='paid' then now() else paid_at end where id = p_id;
  if p_status = 'sent' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','economist'], 'Счёт ' || inum || ' выставлен', 'Отправил: ' || coalesce(ulogin,''), 'apps/finance/index.html');
  end if;
  return query select true,'Статус счёта обновлён';
end $$;

grant execute on function public.app_invoice_list(uuid) to anon, authenticated;
grant execute on function public.app_invoice_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_invoice_create(uuid,uuid,text,numeric,date,text,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_invoice_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: финансы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Финансы','Как выставить счёт и связать с заявкой/договором?',
   'В модуле «Финансы» нажмите «Новый счёт»: выберите заявку и заказчика (CRM), укажите сумму, срок и (при наличии) договор. Счёт получит номер INV-NNNNN. В карточке заявки и документа он появится в связях. Статус: черновик → отправлен → оплачен.',
   'счет выставление заявка договор CRM INV'),
  ('Финансы','Как учитываются частичные оплаты и дебиторка?',
   'Каждый платёж (наличные/банк/карта) уменьшает остаток счёта. Остаток = сумма − оплачено. Когда оплачено не меньше суммы, счёт автоматически становится «Оплачен». Дебиторка — это счета со статусом «Отправлен/Просрочен»; просрочка — если срок прошёл, а оплата не полная.',
   'оплата частичная дебиторка остаток просрочка'),
  ('Финансы','Что видно в KPI финансов?',
   'Плитки: количество счетов, сумма выставлено, оплачено, дебиторка (к взысканию) и число просроченных. Эти показатели — основа аналитики (модуль «Аналитика») и отчётов.',
   'KPI финансы дебиторка выставлено оплачено')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Финансы');
-- <<<<<<<<<< 0031_finance_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0032_procurement_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0032_procurement_ref.sql  (v15.0 — переработка «Закупки»)
-- Закупки: связь с заявкой (потребность), исполнитель, лучшая цена, карточка.
-- Витрина поставщика и подача КП — как есть. База знаний. Tenant-изоляция.
-- Зависит от 0001..0031.
-- ============================================================

alter table public.tenders add column if not exists order_id uuid references public.app_orders (id) on delete set null;
alter table public.tenders add column if not exists assignee text;
create index if not exists tenders_order_idx on public.tenders (order_id);

-- ---------- Создание закупки ----------
drop function if exists public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date);
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date,
  p_order_id uuid default null, p_assignee text default null
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; tid uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;
  -- created_by в tenders ссылается на auth.users, поэтому не заполняем его app-пользователем.
  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, assignee, status, tenant_id)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, p_order_id, nullif(trim(p_assignee),''), 'open', ten)
  returning tenders.id into tid;
  return query select tid, 'Закупка опубликована';
end $$;

-- ---------- Список закупок (расширенный) ----------
drop function if exists public.app_tender_list_full(uuid);
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, description text, category text, material text, qty numeric, unit text,
               customer text, deadline date, status text, order_id uuid, order_number text, assignee text,
               bids_count bigint, best_price numeric, awarded_bid_id uuid, created_at timestamptz, closed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.description, t.category, t.material, t.qty, t.unit,
           t.customer, t.deadline, t.status, t.order_id, o.number, t.assignee,
           (select count(*) from public.bids b where b.tender_id = t.id),
           (select min(b.price) from public.bids b where b.tender_id = t.id),
           t.awarded_bid_id, t.created_at, t.closed_at
    from public.tenders t left join public.app_orders o on o.id = t.order_id
    where (urole = 'admin' or t.tenant_id = ten)
    order by t.created_at desc;
end $$;

-- ---------- Карточка закупки ----------
create or replace function public.app_tender_get(p_token uuid, p_id uuid)
returns table (id uuid, title text, description text, category text, material text, qty numeric, unit text,
               customer text, deadline date, status text, order_id uuid, order_number text, assignee text,
               bids_count bigint, best_price numeric, awarded_bid_id uuid, created_at timestamptz, closed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.description, t.category, t.material, t.qty, t.unit,
           t.customer, t.deadline, t.status, t.order_id, o.number, t.assignee,
           (select count(*) from public.bids b where b.tender_id = t.id),
           (select min(b.price) from public.bids b where b.tender_id = t.id),
           t.awarded_bid_id, t.created_at, t.closed_at
    from public.tenders t left join public.app_orders o on o.id = t.order_id
    where t.id = p_id and (urole = 'admin' or t.tenant_id = ten);
end $$;

grant execute on function public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date,uuid,text) to anon, authenticated;
grant execute on function public.app_tender_list_full(uuid) to anon, authenticated;
grant execute on function public.app_tender_get(uuid,uuid) to anon, authenticated;

-- ---------- Демо: закупка по заявке (тенант A) ----------
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, status, tenant_id)
select 'Закупка: сталь 40Х, круг Ø80', 'Металлопрокат для изготовления кронштейна.',
       'Металлопрокат', 'Сталь 40Х, круг', 125, 'кг', null, (current_date + 14), o.id, 'open',
       'aaaaaaaa-0000-0000-0000-000000000001'
from public.app_orders o
where o.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.tenders t where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and t.order_id is not null)
order by o.created_at limit 1;

-- ---------- База знаний: закупки ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Закупки','Как работает закупка от потребности до победителя?',
   'Закупщик создаёт закупку (можно из потребности по заявке): категория, материал, количество, срок подачи. Закупка публикуется в витрине портала поставщиков. Поставщики подают КП (цена, срок, комментарий). Закупщик сравнивает предложения (лучшая цена подсвечена) и выбирает победителя — статус «Победитель», остальные получают уведомление.',
   'закупка потребность заявка КП поставщик победитель'),
  ('Закупки','Что видит поставщик и как подать КП?',
   'Поставщик входит в «Портал поставщика», видит открытые закупки с фильтрами и поиском, открывает карточку и подаёт КП (цена, срок, комментарий); КП можно изменить до выбора победителя. Раздел «Мои КП» показывает статус: Подано/Принято/Отклонено. Требуется аккредитация.',
   'поставщик портал КП подача аккредитация'),
  ('Закупки','KPI и статусы закупок',
   'Статусы: Открыта → Победитель → Закрыта. KPI: сколько открыто, определено победителей, закрыто, и сколько КП подано. Лучшая цена по закупке видна сразу в списке.',
   'KPI закупки статус открыта победитель закрыта')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Закупки');
-- <<<<<<<<<< 0032_procurement_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0033_production_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0033_production_ref.sql  (v16.0 — переработка «Производство»)
-- Наряды: приоритет, план-даты, прогресс операций, связи маршрут/заявка/центр.
-- Операции наряда — из справочника операций. База знаний. Tenant-изоляция.
-- Зависит от 0001..0032.
-- ============================================================

alter table public.app_naryads add column if not exists priority   text not null default 'normal'; -- low|normal|high
alter table public.app_naryads add column if not exists start_date date;
alter table public.app_naryads add column if not exists note       text;

-- ---------- Список нарядов (расширенный) ----------
drop function if exists public.app_naryad_list(uuid);
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text,
               wc_name text, assignee text, status text, priority text, plan_hours numeric, fact_hours numeric,
               ops_total bigint, ops_done bigint, start_date date, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.order_id, o.number, n.route_id, r.number, w.name, n.assignee, n.status,
           n.priority, n.plan_hours, n.fact_hours,
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id),
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id and op.done),
           n.start_date, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by n.created_at desc;
end $$;

-- ---------- Создать наряд ----------
drop function if exists public.app_naryad_create(uuid,uuid,text,uuid,text,date);
create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date,
  p_priority text default 'normal', p_start_date date default null
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, priority, start_date, due_date, tenant_id, created_by, created_login)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee), ''), 'open',
          coalesce(nullif(trim(p_priority),''),'normal'), p_start_date, p_due_date, ten, uid, ulogin)
  returning app_naryads.id into nid;

  perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u where lower(u.login) = lower(trim(p_assignee)) and u.active and u.tenant_id = ten limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

-- ---------- Изменить наряд ----------
create or replace function public.app_naryad_update(p_token uuid, p_id uuid, p_assignee text, p_priority text,
  p_wc_id uuid, p_start_date date, p_due_date date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_naryads n where n.id = p_id and (urole='admin' or n.tenant_id = ten)) then
    return query select false,'Наряд не найден'; return;
  end if;
  update public.app_naryads set assignee = nullif(trim(p_assignee),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), wc_id = p_wc_id,
    start_date = p_start_date, due_date = p_due_date, note = nullif(trim(p_note),''), updated_at = now()
   where id = p_id;
  return query select true,'Наряд обновлён';
end $$;

-- ---------- Карточка наряда (с новыми полями) ----------
drop function if exists public.app_naryad_get(uuid,uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text,
               wc_id uuid, wc_name text, assignee text, status text, priority text,
               plan_hours numeric, fact_hours numeric, start_date date, due_date date, note text,
               created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, n.route_id, r.number,
    n.wc_id, w.name, n.assignee, n.status, n.priority,
    n.plan_hours, n.fact_hours, n.start_date, n.due_date, n.note, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

-- ---------- Операции наряда (с связью на операцию/шаг маршрута) ----------
drop function if exists public.app_naryad_ops(uuid,uuid);
create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, operation_id uuid, route_step_id uuid, worker text,
               plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_naryads n where n.id = p_id and (urole='admin' or n.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select op.id, op.seq, op.operation, op.operation_id, op.route_step_id, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op where op.naryad_id = p_id order by op.seq, op.created_at;
end $$;

drop function if exists public.app_naryad_add_op(uuid,uuid,text,text,numeric);
create or replace function public.app_naryad_add_op(p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric,
  p_operation_id uuid default null, p_route_step_id uuid default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare seqn integer; nid uuid; urole text; ten uuid; oname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id and (urole='admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  oname := nullif(trim(p_operation),'');
  if oname is null and p_operation_id is not null then
    select o.name into oname from public.app_operations o where o.id = p_operation_id;
  end if;
  if oname is null then return query select false,'Укажите операцию'; return; end if;

  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, operation_id, route_step_id, worker, plan_hours)
  values (p_naryad_id, seqn, oname, p_operation_id, p_route_step_id, nullif(trim(p_worker),''), coalesce(p_plan_hours,0));

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

-- ---------- Отметить операцию выполненной ----------
create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare nid uuid; nnum text; left_c integer; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select op.naryad_id into nid from public.app_naryad_ops op where op.id = p_op_id;
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;

  select n.number, n.tenant_id into nnum, ten from public.app_naryads n where n.id = nid;
  select count(*) into left_c from public.app_naryad_ops op where op.naryad_id = nid and not op.done;
  if left_c = 0 then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'], 'Наряд ' || nnum || ': все операции выполнены', 'Можно закрывать', 'apps/production/index.html');
  end if;
  return query select true,'Обновлено';
end $$;

grant execute on function public.app_naryad_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_create(uuid,uuid,text,uuid,text,date,text,date) to anon, authenticated;
grant execute on function public.app_naryad_update(uuid,uuid,text,text,uuid,date,date,text) to anon, authenticated;
grant execute on function public.app_naryad_ops(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_add_op(uuid,uuid,text,text,numeric,uuid,uuid) to anon, authenticated;

-- ---------- База знаний: производство ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Как создать наряд и операции?',
   'В «Производстве» → «Новый наряд»: укажите заявку, название, рабочий центр, исполнителя, приоритет, план-даты. Можно создать наряд сразу из маршрута (кнопка в «Справочниках» → «Маршруты») — тогда операции и нормо-часы появятся автоматически. Операции можно добавлять и вручную, выбирая из справочника операций.',
   'наряд операции маршрут справочник создать'),
  ('Производство','Как учитывать факт и закрывать наряд?',
   'По каждой операции вносится факт часов и отметка «выполнено». Факт суммируется в наряде. Когда все операции выполнены — приходит уведомление «можно закрывать»; наряд закрывается кнопкой «Закрыть». План/факт часов — основа экономики и MES.',
   'факт часы закрыть наряд операции выполнение'),
  ('Производство','Приоритет и план-даты наряда',
   'Приоритет (низкий/обычный/высокий) и план-даты (старт/срок) используются планированием и диспетчерской: по ним строится Гант и очередь работ. Срок наряда связан со сроком заявки.',
   'приоритет план-даты срок старт планирование')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Производство');
-- <<<<<<<<<< 0033_production_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0034_mes_ops.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0034_mes_ops.sql  (v16.1 — MES на операциях нарядов)
-- Диспетчерская работаем поверх операций нарядов (единый источник):
-- статус операции (очередь/работа/пауза/готово), факт, привязка к РЦ.
-- Tenant-изоляция. Зависит от 0001..0033.
-- ============================================================

alter table public.app_naryad_ops add column if not exists mes_status  text not null default 'queue'; -- queue|work|paused|done
alter table public.app_naryad_ops add column if not exists started_at  timestamptz;
alter table public.app_naryad_ops add column if not exists finished_at timestamptz;
create index if not exists app_naryad_ops_mes_idx on public.app_naryad_ops (mes_status);

update public.app_naryad_ops set mes_status = 'done' where done and mes_status <> 'done';

-- ---------- Доска диспетчера ----------
create or replace function public.app_mes_ops_board(p_token uuid, p_wc_id uuid default null)
returns table (op_id uuid, naryad_id uuid, naryad_number text, naryad_title text, wc_id uuid, wc_name text,
               seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric,
               mes_status text, priority text, due_date date, assignee text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select op.id, n.id, n.number, n.title, n.wc_id, w.name, op.seq, op.operation, coalesce(op.worker, n.assignee),
           op.plan_hours, op.fact_hours, op.mes_status, n.priority, n.due_date, n.assignee
    from public.app_naryad_ops op
    join public.app_naryads n on n.id = op.naryad_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
      and (p_wc_id is null or n.wc_id = p_wc_id)
    order by case op.mes_status when 'work' then 0 when 'paused' then 1 when 'queue' then 2 else 3 end,
             case n.priority when 'high' then 0 when 'normal' then 1 else 2 end, n.due_date nulls last, op.seq;
end $$;

-- ---------- Сменить статус операции ----------
create or replace function public.app_mes_ops_set_status(p_token uuid, p_op_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; nid uuid; nnum text; st text; left_c integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := case when p_status in ('queue','work','paused','done') then p_status else null end;
  if st is null then return query select false,'Недопустимый статус'; return; end if;
  select op.naryad_id, n.number into nid, nnum
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.id = p_op_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Операция не найдена'; return; end if;

  update public.app_naryad_ops set mes_status = st,
    done = (st = 'done'),
    started_at = case when st = 'work' and started_at is null then now() else started_at end,
    finished_at = case when st = 'done' then coalesce(finished_at, now()) else null end
   where id = p_op_id;

  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' and st = 'work' then 'in_progress' else n.status end,
    updated_at = now()
   where n.id = nid;

  if st = 'done' then
    select count(*) into left_c from public.app_naryad_ops op where op.naryad_id = nid and not op.done;
    perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'],
      case when left_c = 0 then 'Наряд ' || nnum || ': все операции выполнены' else 'Операция выполнена (' || nnum || ')' end,
      'Изменил: ' || coalesce(ulogin,''), 'apps/production/index.html');
  end if;
  return query select true,'Статус операции обновлён';
end $$;

grant execute on function public.app_mes_ops_board(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mes_ops_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: MES ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Диспетчерская','Что показывает MES-доска и как ей пользоваться?',
   'Диспетчерская показывает операции нарядов по рабочим центрам в четырёх колонках: «В очереди», «В работе», «Пауза», «Выполнено». Переталкивайте операции кнопками: Запустить → Пауза/Продолжить → Готово. Готово автоматически ставит факт и, когда все операции наряда выполнены, уведомляет о готовности к закрытию. Источник данных — операции нарядов (модуль «Производство»).',
   'MES диспетчерская канбан операция очередь работа пауза готово'),
  ('Диспетчерская','Связь MES с нарядами и рабочими центрами',
   'Каждая карточка — операция конкретного наряда: номер наряда, операция, рабочий центр, исполнитель, план/факт часов, приоритет и срок. Фильтр по рабочему центру показывает только его загрузку. Итог прозрачен: MES и «Производство» — один источник (операции наряда).',
   'MES наряд операция рабочий центр фильтр загрузка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Диспетчерская');
-- <<<<<<<<<< 0034_mes_ops.sql <<<<<<<<<<

-- >>>>>>>>>> 0035_planning_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0035_planning_ref.sql  (v17.0 — переработка «Планирование»)
-- Гант и загрузка центров: связи маршрут/заявка/приоритет, прогресс операций,
-- коррекция бага app_capacity (несуществующий wc.tenant_id). База знаний.
-- Зависит от 0001..0034.
-- ============================================================

-- ---------- Гант: наряды с план-датами (расширено) ----------
drop function if exists public.app_schedule(uuid);
create or replace function public.app_schedule(p_token uuid)
returns table (id uuid, number text, title text, wc_id uuid, wc_name text, assignee text, status text, priority text,
               route_number text, order_number text, ops_total bigint, ops_done bigint,
               plan_start date, plan_end date, due_date date, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.wc_id, w.name, n.assignee, n.status, n.priority,
           r.number, o.number,
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id),
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id and op.done),
           n.plan_start, n.plan_end, n.due_date, n.plan_hours, n.fact_hours
    from public.app_naryads n
    left join public.app_work_centers w on w.id = n.wc_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_orders o on o.id = n.order_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by coalesce(n.plan_start, n.created_at::date), n.created_at;
end $$;

-- ---------- Загрузка рабочих центров (фикс бага wc.tenant_id) ----------
drop function if exists public.app_capacity(uuid);
create or replace function public.app_capacity(p_token uuid)
returns table (wc_id uuid, wc_name text, kind text, cost_hour numeric,
               active_naryads bigint, plan_hours numeric, fact_hours numeric, ops_open bigint, overdue bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.name, w.kind, w.cost_hour,
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten)),
           coalesce((select sum(n.plan_hours) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten)), 0),
           coalesce((select sum(n.fact_hours) from public.app_naryads n where n.wc_id = w.id and (urole='admin' or n.tenant_id = ten)), 0),
           (select count(*) from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
              where n.wc_id = w.id and not op.done and (urole='admin' or n.tenant_id = ten)),
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.due_date is not null and n.due_date < current_date and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten))
    from public.app_work_centers w
    order by w.name;
end $$;

grant execute on function public.app_schedule(uuid) to anon, authenticated;
grant execute on function public.app_capacity(uuid) to anon, authenticated;

-- ---------- База знаний: планирование ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Планирование','Как планировать сроки нарядов (Гант)?',
   'В «Планировании» на вкладке «Гант» задайте план-старт и план-финиш наряда в таблице ниже диаграммы. Полосы показывают длительность, цвет — статус наряда (открыт/в работе/закрыт); видно маршрут, заявку и прогресс операций. Даты используются диспетчерской и напоминаниями.',
   'планирование гант сроки план-старт план-финиш наряд'),
  ('Планирование','Как читать загрузку рабочих центров?',
   'Вкладка «Загрузка» показывает по каждому центру: активные наряды, план и факт нормо-часов, открытые операции и просроченные наряды. Полоса — относительная загрузка. Так видно «узкие места» и куда перераспределить работы.',
   'загрузка рабочий центр нормочасы операции просрочка узкое место')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Планирование');
-- <<<<<<<<<< 0035_planning_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0036_warehouse_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0036_warehouse_ref.sql  (v18.0 — переработка «Склад»)
-- Движения со связью заявка/наряд, стоимость запаса, список нехватки,
-- связка «нехватка → закупка». База знаний. Tenant-изоляция.
-- Зависит от 0001..0035.
-- ============================================================

alter table public.app_stock_moves add column if not exists order_id  uuid references public.app_orders (id) on delete set null;
alter table public.app_stock_moves add column if not exists naryad_id uuid references public.app_naryads (id) on delete set null;
create index if not exists app_stock_moves_order_idx on public.app_stock_moves (order_id);

-- ---------- Материалы: список (со стоимостью запаса) ----------
drop function if exists public.app_material_list(uuid);
create or replace function public.app_material_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric,
               stock_value numeric, low boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty,
    round(coalesce(m.qty,0) * coalesce(m.price,0), 2), (m.qty < m.min_qty)
    from public.app_materials m where (urole = 'admin' or m.tenant_id = ten) and m.active order by m.name;
end $$;

-- ---------- Нехватка (ниже минимума) ----------
create or replace function public.app_stock_low(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric, deficit numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty, round(m.min_qty - m.qty, 2)
    from public.app_materials m
    where (urole = 'admin' or m.tenant_id = ten) and m.active and m.qty < m.min_qty
    order by (m.qty - m.min_qty);
end $$;

-- ---------- Движение (приход/расход) со связью ----------
drop function if exists public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text);
create or replace function public.app_stock_move(
  p_token uuid, p_material_id uuid, p_kind text, p_qty numeric, p_price numeric, p_note text, p_source text,
  p_order_id uuid default null, p_naryad_id uuid default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; m public.app_materials; newqty numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into m from public.app_materials where id = p_material_id and (urole = 'admin' or tenant_id = ten);
  if m.id is null then return query select false,'Материал не найден'; return; end if;
  if p_kind not in ('in','out') then return query select false,'Неверный тип движения'; return; end if;
  if coalesce(p_qty,0) <= 0 then return query select false,'Количество должно быть > 0'; return; end if;

  newqty := case when p_kind = 'in' then m.qty + p_qty else m.qty - p_qty end;
  if newqty < 0 then return query select false,'Недостаточно на складе'; return; end if;

  insert into public.app_stock_moves (tenant_id, material_id, kind, qty, price, note, source, order_id, naryad_id, by_login)
  values (m.tenant_id, m.id, p_kind, p_qty, coalesce(p_price,0), nullif(trim(p_note),''), nullif(trim(p_source),''),
          p_order_id, p_naryad_id, ulogin);
  update public.app_materials set qty = newqty, updated_at = now() where id = m.id;

  if newqty < m.min_qty then
    perform public.app_notif_roles_t(m.tenant_id, array['admin','manager','owner','supply','director'],
      'Низкий остаток: ' || m.name, 'Остаток ' || newqty || ' ' || coalesce(m.unit,'') || ' (мин ' || m.min_qty || ')', 'apps/warehouse/index.html');
  end if;
  return query select true,'Движение проведено';
end $$;

-- ---------- История движений (со связями) ----------
drop function if exists public.app_stock_moves_list(uuid,uuid,integer);
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, source text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.kind, v.qty, v.price, v.note, v.source,
    v.order_id, o.number, v.naryad_id, n.number, v.by_login, v.created_at
    from public.app_stock_moves v
    join public.app_materials m on m.id = v.material_id
    left join public.app_orders o on o.id = v.order_id
    left join public.app_naryads n on n.id = v.naryad_id
    where v.material_id = p_material_id and (urole = 'admin' or m.tenant_id = ten)
    order by v.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

grant execute on function public.app_material_list(uuid) to anon, authenticated;
grant execute on function public.app_stock_low(uuid) to anon, authenticated;
grant execute on function public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text,uuid,uuid) to anon, authenticated;
grant execute on function public.app_stock_moves_list(uuid,uuid,integer) to anon, authenticated;

-- ---------- База знаний: склад ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','Как вести приход и расход материалов?',
   'В «Складе» откройте материал и проведите движение: приход или расход, количество, при необходимости заявку/наряд и комментарий. Остаток пересчитывается автоматически; при уходе ниже минимума приходит уведомление снабжению и руководству. Стоимость запаса = остаток × цена.',
   'склад приход расход остаток минимум стоимость'),
  ('Склад','Что делать при нехватке материала?',
   'Позиции ниже минимума показаны в блоке «Нехватка». По такой позиции нажмите «Создать закупку» — откроется предзаполненная закупка в снабжении (материал и рекомендуемое количество). Так замыкается цепочка: склад → закупка → приход.',
   'нехватка закупка снабжение материал минимум')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Склад');
-- <<<<<<<<<< 0036_warehouse_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0037_qc_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0037_qc_ref.sql  (v19.0 — переработка «ОТК»)
-- ОТК: количество (всего/годных), связь с нарядом/заявкой, трассируемость.
-- База знаний. Tenant-изоляция. Зависит от 0001..0036.
-- ============================================================

alter table public.app_qc_checks add column if not exists qty_total numeric;
alter table public.app_qc_checks add column if not exists qty_good  numeric;

-- ---------- ОТК: список (расширенный) ----------
drop function if exists public.app_qc_list(uuid);
create or replace function public.app_qc_list(p_token uuid)
returns table (id uuid, number text, product text, status text, inspector text,
               naryad_id uuid, naryad_number text, order_id uuid, order_number text,
               qty_total numeric, qty_good numeric, lines_count bigint, defects_count bigint, open_defects bigint,
               checked_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.number, c.product, c.status, c.inspector, c.naryad_id, n.number, c.order_id, o.number,
           c.qty_total, c.qty_good,
           (select count(*) from public.app_qc_lines l where l.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id and d.status <> 'resolved'),
           c.checked_at, c.created_at
    from public.app_qc_checks c
    left join public.app_naryads n on n.id = c.naryad_id
    left join public.app_orders o on o.id = c.order_id
    where (urole = 'admin' or c.tenant_id = ten)
    order by c.created_at desc;
end $$;

-- ---------- ОТК: создать ----------
drop function if exists public.app_qc_create(uuid,uuid,uuid,text,text);
create or replace function public.app_qc_create(p_token uuid, p_naryad_id uuid, p_order_id uuid, p_product text, p_inspector text,
  p_qty_total numeric default null, p_qty_good numeric default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; cid uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  cnum := 'QCK-' || lpad(nextval('public.app_qc_seq')::text, 5, '0');
  insert into public.app_qc_checks (tenant_id, number, naryad_id, order_id, product, inspector, qty_total, qty_good, created_by, created_login)
  values (ten, cnum, p_naryad_id, p_order_id, nullif(trim(p_product),''), nullif(trim(p_inspector),''), p_qty_total, p_qty_good, uid, ulogin)
  returning app_qc_checks.id into cid;
  return query select cid, cnum;
end $$;

-- ---------- ОТК: статус ----------
create or replace function public.app_qc_set_status(p_token uuid, p_check_id uuid, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.number into cnum from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cnum is null then return query select false,'Чек-лист не найден'; return; end if;
  update public.app_qc_checks set status = p_status, note = nullif(trim(p_note),''), checked_at = now() where id = p_check_id;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master','qc'],
    case when p_status='passed' then 'ОТК: годен ' || cnum when p_status='failed' then 'ОТК: брак по ' || cnum else 'ОТК ' || cnum end,
    coalesce(nullif(trim(p_note),''),''), 'apps/qc/index.html');
  return query select true, case when p_status = 'passed' then 'Принято' when p_status='failed' then 'Зафиксирован брак' else 'Сохранено' end;
end $$;

-- ---------- Трассируемость по чек-листу ----------
create or replace function public.app_qc_trace(p_token uuid, p_check_id uuid)
returns table (kind text, title text, detail text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; c record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c0.* into c from public.app_qc_checks c0 where c0.id = p_check_id and (urole='admin' or c0.tenant_id = ten);
  if c.id is null then raise exception 'Чек-лист не найден'; end if;

  return query
  -- заявка
  select 'Заявка'::text as kind, o.number as title, o.title as detail, o.created_at as ts
    from public.app_orders o where o.id = c.order_id
  union all
  -- наряд
  select 'Наряд'::text, n.number, n.title, n.created_at
    from public.app_naryads n where n.id = c.naryad_id
  union all
  -- операции наряда
  select 'Операция'::text, op.seq || '. ' || op.operation,
         'план ' || coalesce(op.plan_hours,0) || ' ч · факт ' || coalesce(op.fact_hours,0) || ' ч' || case when op.done then ' · выполнено' else '' end,
         n.created_at
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.naryad_id = c.naryad_id
  union all
  -- расход материалов по заявке
  select 'Материал'::text, coalesce(m.name,'—'),
         case when v.kind='out' then 'расход ' else 'приход ' end || coalesce(v.qty,0) || ' ' || coalesce(m.unit,''),
         v.created_at
    from public.app_stock_moves v left join public.app_materials m on m.id = v.material_id
    where v.order_id = c.order_id
  union all
  -- дефекты чек-листа
  select 'Дефект'::text, d.title,
         d.severity || ' · ' || case when d.status='resolved' then 'закрыт' else 'открыт' end,
         d.created_at
    from public.app_defects d where d.check_id = c.id
  order by ts;
end $$;

grant execute on function public.app_qc_list(uuid) to anon, authenticated;
grant execute on function public.app_qc_create(uuid,uuid,uuid,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_qc_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_qc_trace(uuid,uuid) to anon, authenticated;

-- ---------- База знаний: ОТК ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ОТК','Как провести контроль (чек-лист)?',
   'В «ОТК» создайте чек-лист: наряд, изделие, контролёр, количество (всего/годных). Добавьте позиции (параметр/норма/факт/результат) и дефекты. Итог: «Годен» или «Брак». При браке и критических дефектах приходят уведомления.',
   'ОТК чек-лист контроль дефект годен брак'),
  ('ОТК','Что такое трассируемость изделия?',
   'В карточке чек-листа блок «Трассируемость» собирает всю цепочку: заявка → наряд → операции наряда → расход материалов → дефекты. Это основа СМК и паспорта изделия: видно, из чего и как сделано изделие и какие были замечания.',
   'трассируемость СМК паспорт материалы операции дефекты')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='ОТК');
-- <<<<<<<<<< 0037_qc_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0038_passport_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0038_passport_ref.sql  (v20.0 — переработка «Паспорт изделия»)
-- Серийный номер, количество, связи наряд/ОТК/заявка, статус. QR-метка (UI).
-- База знаний. Tenant-изоляция. Зависит от 0001..0037.
-- ============================================================

alter table public.app_passports add column if not exists naryad_id uuid references public.app_naryads (id) on delete set null;
alter table public.app_passports add column if not exists serial    text;
alter table public.app_passports add column if not exists qty       numeric;
alter table public.app_passports add column if not exists status    text not null default 'active'; -- active | archived
create index if not exists app_passports_naryad_idx on public.app_passports (naryad_id);

-- ---------- Список паспортов (расширенный) ----------
drop function if exists public.app_passport_list(uuid);
create or replace function public.app_passport_list(p_token uuid)
returns table (id uuid, number text, product text, serial text, qty numeric, status text,
               order_id uuid, order_number text, qc_check_id uuid, qc_number text, naryad_number text,
               created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.number, p.product, p.serial, p.qty, p.status, p.order_id, o.number, p.qc_check_id, c.number, n.number,
           p.created_login, p.created_at
    from public.app_passports p
    left join public.app_orders o on o.id = p.order_id
    left join public.app_qc_checks c on c.id = p.qc_check_id
    left join public.app_naryads n on n.id = p.naryad_id
    where (urole='admin' or p.tenant_id = ten)
    order by p.created_at desc;
end $$;

-- ---------- Карточка паспорта (расширенная) ----------
drop function if exists public.app_passport_get(uuid,uuid);
create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, serial text, qty numeric, status text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               qc_check_id uuid, qc_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.number, p.product, p.serial, p.qty, p.status, p.order_id, o.number, p.naryad_id, n.number,
           p.qc_check_id, c.number, p.data, p.created_login, p.created_at
    from public.app_passports p
    left join public.app_orders o on o.id = p.order_id
    left join public.app_naryads n on n.id = p.naryad_id
    left join public.app_qc_checks c on c.id = p.qc_check_id
    where p.id = p_id and (urole='admin' or p.tenant_id = ten);
end $$;

-- ---------- Создать паспорт ----------
drop function if exists public.app_passport_create(uuid,uuid,text,uuid,jsonb);
create or replace function public.app_passport_create(p_token uuid, p_order_id uuid, p_product text, p_qc_check_id uuid, p_data jsonb,
  p_naryad_id uuid default null, p_serial text default null, p_qty numeric default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; pid uuid; pnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;
  pnum := 'PAS-' || lpad(nextval('public.app_passport_seq')::text, 5, '0');
  insert into public.app_passports (tenant_id, number, order_id, product, qc_check_id, data, naryad_id, serial, qty, created_by, created_login)
  values (ten, pnum, p_order_id, trim(p_product), p_qc_check_id, coalesce(p_data,'{}'::jsonb), p_naryad_id, nullif(trim(p_serial),''), p_qty, uid, ulogin)
  returning app_passports.id into pid;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner','qc','master'], 'Паспорт ' || pnum, trim(p_product), 'apps/passport/index.html');
  return query select pid, pnum;
end $$;

grant execute on function public.app_passport_list(uuid) to anon, authenticated;
grant execute on function public.app_passport_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_passport_create(uuid,uuid,text,uuid,jsonb,uuid,text,numeric) to anon, authenticated;

-- ---------- База знаний: паспорт ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Паспорт','Что такое паспорт изделия и зачем QR?',
   'Паспорт — цифровой документ изделия: номер, изделие, серийный номер, количество, связи с заявкой, нарядом и чек-листом ОТК, а также данные (материал, примечания). QR-метка на карточке ведёт на страницу паспорта — при сканировании открывается вся история изделия.',
   'паспорт изделие QR серийный номер история'),
  ('Паспорт','Как связаны паспорт, ОТК и трассируемость?',
   'Если у паспорта указан чек-лист ОТК, в карточке доступна трассируемость: заявка → наряд → операции → материалы → дефекты. Так паспорт опирается на реальные данные, а не на ручной ввод, и подтверждает качество изделия.',
   'паспорт ОТК трассируемость качество связь')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Паспорт');
-- <<<<<<<<<< 0038_passport_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0039_bom_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0039_bom_ref.sql  (v21.0 — переработка «Спецификации/BOM»)
-- Спецификация из техпроцесса, себестоимость по BOM, связи с операциями/материалами.
-- База знаний. Tenant-изоляция. Зависит от 0001..0038.
-- ============================================================

alter table public.app_bom add column if not exists product_code text;
alter table public.app_bom add column if not exists qty numeric;
alter table public.app_bom add column if not exists status text not null default 'draft'; -- draft | active
alter table public.app_bom add column if not exists source_template_id uuid references public.app_process_templates (id) on delete set null;
alter table public.app_bom_lines add column if not exists operation_id uuid references public.app_operations (id) on delete set null;

-- ---------- Список спецификаций ----------
drop function if exists public.app_bom_list(uuid);
create or replace function public.app_bom_list(p_token uuid)
returns table (id uuid, product text, product_code text, version text, status text, qty numeric,
               order_id uuid, order_number text, source_template_id uuid,
               lines_count bigint, materials_count bigint, norm_hours_sum numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.product, b.product_code, b.version, b.status, b.qty, b.order_id, o.number, b.source_template_id,
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id),
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id and l.item_type='material'),
           coalesce((select sum(l.norm_hours) from public.app_bom_lines l where l.bom_id = b.id),0),
           b.created_at
    from public.app_bom b left join public.app_orders o on o.id = b.order_id
    where (urole='admin' or b.tenant_id = ten)
    order by b.created_at desc;
end $$;

-- ---------- Позиции спецификации (с себестоимостью позиции) ----------
drop function if exists public.app_bom_lines_list(uuid,uuid);
create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, material_id uuid, operation_id uuid, name text,
               qty numeric, unit text, norm_hours numeric, price numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.seq, l.item_type, l.material_id, l.operation_id, l.name, l.qty, l.unit, l.norm_hours,
           case when l.item_type='material' then coalesce(m.price,0) else coalesce(op.base_rate,0) end,
           round(case when l.item_type='material' then coalesce(l.qty,0)*coalesce(m.price,0)
                      else coalesce(l.norm_hours,0)*coalesce(op.base_rate,0) end, 2)
    from public.app_bom_lines l
    join public.app_bom b on b.id = l.bom_id
    left join public.app_materials m on m.id = l.material_id
    left join public.app_operations op on op.id = l.operation_id
    where l.bom_id = p_bom_id and (urole='admin' or b.tenant_id = ten)
    order by l.seq, l.id;
end $$;

-- ---------- Сохранить спецификацию ----------
drop function if exists public.app_bom_save(uuid,uuid,uuid,text,text,jsonb);
create or replace function public.app_bom_save(p_token uuid, p_id uuid, p_order_id uuid, p_product text, p_version text, p_lines jsonb,
  p_product_code text default null, p_qty numeric default null)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; bid uuid; ln jsonb; i integer := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;

  if p_id is null then
    insert into public.app_bom (tenant_id, order_id, product, product_code, version, qty, created_by, created_login)
    values (ten, p_order_id, trim(p_product), nullif(trim(p_product_code),''), coalesce(nullif(trim(p_version),''),'1'), p_qty, uid, ulogin)
    returning app_bom.id into bid;
  else
    update public.app_bom set order_id = p_order_id, product = trim(p_product),
      product_code = nullif(trim(p_product_code),''), version = coalesce(nullif(trim(p_version),''),'1'),
      qty = p_qty, updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten)
     returning app_bom.id into bid;
    delete from public.app_bom_lines where bom_id = bid;
  end if;

  if p_lines is not null then
    for ln in select * from jsonb_array_elements(p_lines) loop
      i := i + 1;
      insert into public.app_bom_lines (bom_id, seq, item_type, material_id, operation_id, name, qty, unit, norm_hours)
      values (bid, i,
              coalesce(nullif(ln->>'item_type',''),'material'),
              nullif(ln->>'material_id','')::uuid,
              nullif(ln->>'operation_id','')::uuid,
              coalesce(nullif(ln->>'name',''),'—'),
              coalesce((ln->>'qty')::numeric,0),
              nullif(ln->>'unit',''),
              coalesce((ln->>'norm_hours')::numeric,0));
    end loop;
  end if;
  return query select bid, 'Спецификация сохранена';
end $$;

-- ---------- Себестоимость по спецификации ----------
create or replace function public.app_bom_cost(p_token uuid, p_bom_id uuid, p_qty numeric default 1)
returns table (materials_cost numeric, work_cost numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; mc numeric; wc numeric; k numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_bom b where b.id = p_bom_id and (urole='admin' or b.tenant_id = ten)) then
    raise exception 'Спецификация не найдена';
  end if;
  k := greatest(coalesce(p_qty,1), 1);
  select coalesce(sum(coalesce(l.qty,0)*coalesce(m.price,0)),0) into mc
    from public.app_bom_lines l left join public.app_materials m on m.id = l.material_id
    where l.bom_id = p_bom_id and l.item_type='material';
  select coalesce(sum(coalesce(l.norm_hours,0)*coalesce(op.base_rate,0)),0) into wc
    from public.app_bom_lines l left join public.app_operations op on op.id = l.operation_id
    where l.bom_id = p_bom_id and l.item_type='operation';
  materials_cost := round(mc * k, 2);
  work_cost := round(wc * k, 2);
  total := round((materials_cost + work_cost) * 1.15, 2); -- +15% накладные (как в экономике)
  return next;
end $$;

-- ---------- Создать спецификацию из техпроцесса ----------
create or replace function public.app_bom_from_template(p_token uuid, p_template_id uuid, p_order_id uuid, p_product text, p_qty numeric default 1)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; bid uuid; tname text; tmat uuid; matname text; munit text; i integer := 0; st record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name, t.material_id into tname, tmat from public.app_process_templates t
    where t.id = p_template_id and (uid is not null);
  if tname is null then raise exception 'Техпроцесс не найден'; end if;

  insert into public.app_bom (tenant_id, order_id, product, version, qty, source_template_id, created_by, created_login)
  values (ten, p_order_id, coalesce(nullif(trim(p_product),''), tname), '1', greatest(coalesce(p_qty,1),1), p_template_id, uid, ulogin)
  returning app_bom.id into bid;

  if tmat is not null then
    select m.name, m.unit into matname, munit from public.app_materials m where m.id = tmat;
    i := i + 1;
    insert into public.app_bom_lines (bom_id, seq, item_type, material_id, name, qty, unit, norm_hours)
    values (bid, i, 'material', tmat, coalesce(matname, tname), greatest(coalesce(p_qty,1),1), munit, 0);
  end if;

  for st in select st0.operation_id, st0.plan_min, o.name as opname
            from public.app_process_steps st0 left join public.app_operations o on o.id = st0.operation_id
            where st0.template_id = p_template_id order by st0.seq loop
    i := i + 1;
    insert into public.app_bom_lines (bom_id, seq, item_type, operation_id, name, qty, unit, norm_hours)
    values (bid, i, 'operation', st.operation_id, coalesce(st.opname, 'Операция '||i), 0, 'н/ч', round(coalesce(st.plan_min,0)/60.0, 2));
  end loop;

  return query select bid, 'Спецификация создана из техпроцесса';
end $$;

grant execute on function public.app_bom_list(uuid) to anon, authenticated;
grant execute on function public.app_bom_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_bom_save(uuid,uuid,uuid,text,text,jsonb,text,numeric) to anon, authenticated;
grant execute on function public.app_bom_cost(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_bom_from_template(uuid,uuid,uuid,text,numeric) to anon, authenticated;

-- ---------- База знаний: спецификации ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Спецификации','Что такое спецификация (BOM) и как её создать из техпроцесса?',
   'Спецификация — состав изделия: материалы (с количеством) и операции (с нормо-часами). Нажмите «Создать из техпроцесса» и выберите шаблон — материалы и операции подтянутся автоматически из «Справочников». Позиции можно добавить и вручную.',
   'спецификация BOM техпроцесс материалы операции состав'),
  ('Спецификации','Как считается себестоимость по спецификации?',
   'В карточке спецификации показывается расчёт: материалы (кол-во × цена) + работы (нормо-часы × ставка операции) + 15% накладные = итого. Укажите количество изделий — расчёт умножается. Это основа экономики заказа.',
   'себестоимость BOM материалы работы накладные экономика')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Спецификации');
-- <<<<<<<<<< 0039_bom_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0040_hr_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0040_hr_ref.sql  (v22.0 — переработка «Кадры/HR»)
-- Сотрудник ↔ пользователь системы (логин/роль), дата приёма, расширенные списки.
-- База знаний. Tenant-изоляция. Зависит от 0001..0039.
-- ============================================================

alter table public.app_employees add column if not exists user_login text;
alter table public.app_employees add column if not exists role       text;
alter table public.app_employees add column if not exists email      text;

-- ---------- Список сотрудников (расширенный) ----------
drop function if exists public.app_employees_list(uuid);
create or replace function public.app_employees_list(p_token uuid)
returns table (id uuid, full_name text, job text, dept text, phone text, email text, hired_at date,
               active boolean, user_login text, role text, shifts_month bigint, trainings_open bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.full_name, e.job, e.dept, e.phone, e.email, e.hired_at, e.active, e.user_login, e.role,
    (select count(*) from public.app_shifts sh where sh.employee_id = e.id and date_trunc('month', sh.shift_date) = date_trunc('month', current_date)),
    (select count(*) from public.app_trainings tr where tr.employee_id = e.id and tr.status <> 'passed')
    from public.app_employees e where (urole='admin' or e.tenant_id = ten) order by e.active desc, e.full_name;
end $$;

-- ---------- Сохранить сотрудника ----------
drop function if exists public.app_employee_save(uuid,uuid,text,text,text,text);
create or replace function public.app_employee_save(p_token uuid, p_id uuid, p_full_name text, p_position text, p_dept text, p_phone text,
  p_email text default null, p_hired_at date default null, p_user_login text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_full_name),'') = '' then return query select false,'Укажите ФИО'; return; end if;
  if p_id is null then
    insert into public.app_employees (tenant_id, full_name, job, dept, phone, email, hired_at, user_login, role)
    values (ten, trim(p_full_name), nullif(trim(p_position),''), nullif(trim(p_dept),''), nullif(trim(p_phone),''),
            nullif(trim(p_email),''), coalesce(p_hired_at, current_date), nullif(trim(p_user_login),''),
            (select u.role from public.app_users u where lower(u.login)=lower(trim(p_user_login)) and u.tenant_id = ten limit 1));
  else
    update public.app_employees set full_name=trim(p_full_name), job=nullif(trim(p_position),''),
      dept=nullif(trim(p_dept),''), phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''),
      hired_at=coalesce(p_hired_at, hired_at), user_login=nullif(trim(p_user_login),''),
      role=(select u.role from public.app_users u where lower(u.login)=lower(trim(p_user_login)) and u.tenant_id = ten limit 1)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Привязать сотрудника к пользователю системы ----------
create or replace function public.app_employee_link_user(p_token uuid, p_employee_id uuid, p_login text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; uid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select u.id into uid from public.app_users u where lower(u.login)=lower(trim(p_login)) and u.tenant_id = ten limit 1;
  if uid is null then return query select false,'Пользователь не найден в организации'; return; end if;
  update public.app_employees e set app_user_id = uid, user_login = (select u.login from public.app_users u where u.id = uid),
    role = (select u.role from public.app_users u where u.id = uid)
   where e.id = p_employee_id and (urole='admin' or e.tenant_id = ten);
  if not found then return query select false,'Сотрудник не найден'; return; end if;
  return query select true,'Сотрудник связан с пользователем';
end $$;

grant execute on function public.app_employees_list(uuid) to anon, authenticated;
grant execute on function public.app_employee_save(uuid,uuid,text,text,text,text,text,date,text) to anon, authenticated;
grant execute on function public.app_employee_link_user(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: кадры ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кадры','Сотрудник и пользователь системы — в чём разница?',
   'Сотрудник — это кадровая запись (ФИО, должность, подразделение, телефон, дата приёма). Пользователь — учётная запись для входа (логин/пароль/роль). Свяжите их: в карточке сотрудника укажите логин пользователя — и роль/логин подтянутся автоматически. Так видно, кто за что отвечает и кто в системе.',
   'кадры сотрудник пользователь логин роль связь'),
  ('Кадры','Табель смен и обучение',
   'Вкладка «Смены» — табель по дням (дневная/ночная/выходной/отпуск/больничный) с часами. Вкладка «Обучение» — план и отметка прохождения. KPI кадров: сотрудники, смены и часы за месяц, обучение (план/пройдено).',
   'табель смены обучение часы KPI кадры')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Кадры');
-- <<<<<<<<<< 0040_hr_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0041_org_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0041_org_ref.sql  (v23.0 — переработка «Организация»)
-- Инфо об организации (+ бренд, статус), чтение бренда, роли предприятия в пользователях.
-- База знаний. Зависит от 0001..0040.
-- ============================================================

-- ---------- Инфо об организации (расширенное) ----------
drop function if exists public.app_tenant_info(uuid);
create or replace function public.app_tenant_info(p_token uuid)
returns table (id uuid, name text, plan text, plan_name text, max_users integer,
               users_count bigint, features jsonb, brand jsonb, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if ten is null then return; end if;
  return query
    select t.id, t.name, t.plan, p.name, p.max_users,
           (select count(*) from public.app_users u2 where u2.tenant_id = t.id),
           t.features, t.brand, t.status, t.created_at
    from public.tenants t
    left join public.app_plans p on p.code = t.plan
    where t.id = ten;
end $$;

-- ---------- Бренд организации ----------
create or replace function public.app_tenant_brand(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare ten uuid; b jsonb;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select t.brand into b from public.tenants t where t.id = ten;
  return coalesce(b, '{}'::jsonb);
end $$;

-- ---------- Сводка по модулям (вкл/выкл) ----------
create or replace function public.app_tenant_modules(p_token uuid, p_modules text[])
returns table (module_id text, enabled boolean)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; f jsonb;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select t.features into f from public.tenants t where t.id = ten;
  f := coalesce(f, '{}'::jsonb);
  return query select m.module_id, coalesce((f->>m.module_id)::boolean, true) from unnest(p_modules) as m(module_id);
end $$;

grant execute on function public.app_tenant_info(uuid) to anon, authenticated;
grant execute on function public.app_tenant_brand(uuid) to anon, authenticated;
grant execute on function public.app_tenant_modules(uuid,text[]) to anon, authenticated;

-- ---------- База знаний: организация ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Организация','Как управлять пользователями и ролями организации?',
   'В «Организации» (админ-панель клиента) на вкладке «Пользователи» владелец добавляет сотрудников (логин/пароль/роль), меняет роль, включает/выключает доступ и сбрасывает пароль. Доступны все роли предприятия: директор, начальник цеха, мастер, технолог, оператор ЧПУ, снабженец, ОТК, экономист (+ менеджер, поставщик). Точные права по модулям — в модуле «Роли и права».',
   'организация пользователи роли владелец доступ клиент'),
  ('Организация','Что такое модули (feature flags) и тариф?',
   'Вкладка «Модули» включает/выключает приложения для организации (кроме платформенных). Вкладка «Тариф» — план (Старт/Бизнес/Корпоративный) с ценой и лимитом пользователей. Вкладка «Бренд» — название, цвет и логотип для white-label. Всё изолировано по организации.',
   'модули feature flags тариф бренд white-label организация')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Организация');
-- <<<<<<<<<< 0041_org_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0042_econ_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0042_econ_ref.sql  (v24.0 — переработка «Экономика»)
-- Себестоимость по факту: работы (факт-часы операций × ставка), материалы
-- (расход со склада по заявке, иначе BOM), накладные, маржа. Свод по заявкам.
-- Исправлен баг app_economics (wc.tenant_id). База знаний. Зависит от 0001..0041.
-- ============================================================

-- ---------- Себестоимость заявки (по факту) ----------
drop function if exists public.app_order_cost(uuid,uuid);
create or replace function public.app_order_cost(p_token uuid, p_order_id uuid)
returns table (plan_hours numeric, fact_hours numeric, work_cost numeric,
               material_cost numeric, overhead numeric, total numeric, amount numeric,
               margin numeric, margin_pct numeric, materials_from_moves boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; oten uuid; amt numeric; ph numeric; fh numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.tenant_id, o.amount into oten, amt from public.app_orders o where o.id = p_order_id;
  if oten is null or not (urole='admin' or oten = ten) then raise exception 'Доступ запрещён'; end if;

  select coalesce(sum(n.plan_hours),0), coalesce(sum(n.fact_hours),0) into ph, fh
    from public.app_naryads n where n.order_id = p_order_id;

  return query
  with ops as (
    select coalesce(nullif(op.fact_hours,0), op.plan_hours, 0) as h,
           coalesce(nullif(o.base_rate,0), wc.cost_hour, 0) as rate
    from public.app_naryad_ops op
    join public.app_naryads n on n.id = op.naryad_id
    left join public.app_operations o on o.id = op.operation_id
    left join public.app_work_centers wc on wc.id = n.wc_id
    where n.order_id = p_order_id
  ), w as (
    select coalesce(sum(h),0) as wh, coalesce(sum(h*rate),0) as wcost from ops
  ), mv as (
    select coalesce(sum(v.qty * coalesce(m.price,0)),0) as mcost, count(*) as cnt
    from public.app_stock_moves v left join public.app_materials m on m.id = v.material_id
    where v.order_id = p_order_id and v.kind = 'out'
  ), bom as (
    select coalesce(sum(l.qty * coalesce(mat.price,0)),0) as mcost
    from public.app_bom b join public.app_bom_lines l on l.bom_id = b.id and l.item_type='material'
    left join public.app_materials mat on mat.id = l.material_id
    where b.order_id = p_order_id
  )
  select ph, fh, round(w.wcost,2),
         round(case when mv.cnt > 0 then mv.mcost else bom.mcost end, 2),
         round((w.wcost + case when mv.cnt > 0 then mv.mcost else bom.mcost end) * 0.15, 2),
         round((w.wcost + case when mv.cnt > 0 then mv.mcost else bom.mcost end) * 1.15, 2),
         amt,
         case when amt is not null then round(amt - (w.wcost + case when mv.cnt > 0 then mv.mcost else bom.mcost end) * 1.15, 2) else null end,
         case when amt is not null and amt <> 0 then round((amt - (w.wcost + case when mv.cnt > 0 then mv.mcost else bom.mcost end) * 1.15) / amt * 100, 1) else null end,
         (mv.cnt > 0)
  from w, mv, bom;
end $$;

-- ---------- Экономика по заявкам (таблица) ----------
create or replace function public.app_economics_orders(p_token uuid)
returns table (id uuid, number text, title text, status text, amount numeric,
               work_cost numeric, material_cost numeric, total numeric, margin numeric, margin_pct numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.status, o.amount,
           c.work_cost, c.material_cost, c.total, c.margin, c.margin_pct, c.fact_hours
    from public.app_orders o,
         lateral public.app_order_cost(p_token, o.id) c
    where (urole='admin' or o.tenant_id = ten)
    order by (c.margin is null), c.margin desc, o.created_at desc;
end $$;

-- ---------- Сводные KPI (фикс wc.tenant_id) ----------
drop function if exists public.app_economics(uuid);
create or replace function public.app_economics(p_token uuid)
returns table (orders_total bigint, orders_open bigint, naryads_open bigint, naryads_closed bigint,
               plan_hours numeric, fact_hours numeric, defects_open bigint, low_stock bigint, avg_rate numeric,
               orders_amount_sum numeric, cost_total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; amt numeric; cost numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  select coalesce(sum(o.amount),0) into amt from public.app_orders o
    where (urole='admin' or o.tenant_id=ten) and o.status <> 'cancelled';
  select coalesce(sum(c.total),0) into cost from public.app_orders o, lateral public.app_order_cost(p_token, o.id) c
    where (urole='admin' or o.tenant_id=ten) and o.status <> 'cancelled';

  return query select
    (select count(*) from public.app_orders o where (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_orders o where o.status in ('new','in_progress') and (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_naryads n where n.status in ('open','in_progress') and (urole='admin' or n.tenant_id=ten)),
    (select count(*) from public.app_naryads n where n.status='closed' and (urole='admin' or n.tenant_id=ten)),
    (select coalesce(sum(n.plan_hours),0) from public.app_naryads n where (urole='admin' or n.tenant_id=ten)),
    (select coalesce(sum(n.fact_hours),0) from public.app_naryads n where (urole='admin' or n.tenant_id=ten)),
    (select count(*) from public.app_defects d where d.status='open' and (urole='admin' or d.tenant_id=ten)),
    (select count(*) from public.app_materials m where m.qty < m.min_qty and (urole='admin' or m.tenant_id=ten)),
    (select coalesce(round(avg(w.cost_hour)),0) from public.app_work_centers w),
    amt, round(cost,2);
end $$;

grant execute on function public.app_order_cost(uuid,uuid) to anon, authenticated;
grant execute on function public.app_economics_orders(uuid) to anon, authenticated;
grant execute on function public.app_economics(uuid) to anon, authenticated;

-- ---------- База знаний: экономика ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Как считается себестоимость заявки по факту?',
   'Себестоимость заявки = работы + материалы + накладные. Работы: факт-часы операций наряда × ставка операции (или нормочас центра). Материалы: расход со склада по заявке (если движений нет — берётся из спецификации). Накладные — 15%. Итого = (работы + материалы) × 1.15. Если задана сумма заказа, считается маржа и маржа %.',
   'экономика себестоимость факт работы материалы накладные маржа'),
  ('Экономика','Где смотреть прибыльность по заявкам?',
   'В «Экономике» таблица заявок показывает сумму, себестоимость, маржу и маржу % — отсортировано по марже. Ниже — загрузка центров (план/факт часов, ставки). Так видно, какие заказы прибыльны, а какие убыточны.',
   'экономика маржа прибыль заявки KPI центры')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Экономика');
-- <<<<<<<<<< 0042_econ_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0043_bi_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0043_bi_ref.sql  (v25.0 — переработка «Аналитика/BI»)
-- Обогащённые агрегаты: оплаты, счета, заявки (статус/тип), наряды, производство
-- план/факт, качество, закупки, склад, экономика. База знаний. Зависит от 0001..0042.
-- ============================================================

create or replace function public.app_bi(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; res jsonb;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  select jsonb_build_object(
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object('m', t.m, 'sum', t.s) order by t.m)
      from (select to_char(date_trunc('month', p.created_at), 'YYYY-MM') as m, sum(p.amount) as s
            from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
            where (urole='admin' or i.tenant_id = ten) and p.created_at >= now() - interval '6 months'
            group by 1) t), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt, 'sum', t.s))
      from (select status, count(*) cnt, coalesce(sum(amount),0) s from public.app_invoices where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_orders where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'orders_type', coalesce((
      select jsonb_agg(jsonb_build_object('type', t.ot, 'count', t.cnt))
      from (select coalesce(order_type,'single') ot, count(*) cnt from public.app_orders where (urole='admin' or tenant_id=ten) group by 1) t), '[]'::jsonb),
    'naryads', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_naryads where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'production', coalesce((
      select jsonb_agg(jsonb_build_object('wc', t.wc, 'plan', t.plan, 'fact', t.fact) order by t.wc)
      from (select w.name wc, coalesce(sum(n.plan_hours),0) plan, coalesce(sum(n.fact_hours),0) fact
            from public.app_naryads n left join public.app_work_centers w on w.id = n.wc_id
            where (urole='admin' or n.tenant_id=ten) group by w.name) t), '[]'::jsonb),
    'quality', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_qc_checks where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'procurement', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.tenders where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'warehouse', jsonb_build_object(
      'low', (select count(*) from public.app_materials m where m.qty < m.min_qty and (urole='admin' or m.tenant_id=ten)),
      'stock_value', (select coalesce(round(sum(m.qty*m.price),2),0) from public.app_materials m where (urole='admin' or m.tenant_id=ten))),
    'economics', jsonb_build_object(
      'amount', (select coalesce(sum(o.amount),0) from public.app_orders o where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'),
      'cost', (select coalesce(round(sum(c.total),2),0) from public.app_orders o, lateral public.app_order_cost(p_token, o.id) c where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'),
      'margin', (select coalesce(round(sum(c.margin),2),0) from public.app_orders o, lateral public.app_order_cost(p_token, o.id) c where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'))
  ) into res;

  return res;
end $$;

grant execute on function public.app_bi(uuid) to anon, authenticated;

-- ---------- База знаний: аналитика ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Аналитика','Что показывает аналитика (BI)?',
   'Аналитика собирает данные всех модулей в дашборд: оплаты по месяцам, счета по статусам, заявки (по статусам и типам), наряды, производство (план/факт по центрам), качество (годен/брак), закупки, склад (стоимость запаса, нехватка) и экономику (сумма/себестоимость/маржа).',
   'аналитика BI дашборд графики KPI свод'),
  ('Отчёты','Как выгрузить отчёт в PDF/DOC/CSV/JSON?',
   'В «Отчётах» выберите набор данных (заявки, наряды, закупки, склад, паспорта, счета, экономика, ОТК), задайте заголовок и период, затем выгрузите: CSV/JSON — данные, DOC/PDF — оформленный отчёт с шапкой, KPI и подписью. Есть сводный отчёт KPI за период.',
   'отчёты экспорт PDF DOC CSV JSON печать сводный')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Аналитика');
-- <<<<<<<<<< 0043_bi_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0044_quality_ref.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0044_quality_ref.sql  (v26.0 — переработка «СМК/метрология»)
-- Поверка СИ как действие (+уведомления), срок до поверки, трассируемость с паспортом.
-- База знаний. Зависит от 0001..0043.
-- ============================================================

alter table public.app_measuring_tools add column if not exists note text;

-- ---------- СИ: список (расширенный) ----------
drop function if exists public.app_tools_list(uuid);
create or replace function public.app_tools_list(p_token uuid)
returns table (id uuid, name text, serial text, tool_type text, location text,
               last_verified date, next_verified date, days_left integer, status text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.name, t.serial, t.tool_type, t.location, t.last_verified, t.next_verified,
      case when t.next_verified is null then null else (t.next_verified - current_date) end,
      case when t.next_verified is null then 'none'
           when t.next_verified < current_date then 'expired'
           when t.next_verified < current_date + 30 then 'due'
           else 'ok' end,
      t.note
    from public.app_measuring_tools t
    where (urole='admin' or t.tenant_id = ten)
    order by case when t.next_verified is null then 1 else 0 end, t.next_verified;
end $$;

-- ---------- Поверка СИ (действие) ----------
create or replace function public.app_tool_verify(p_token uuid, p_id uuid, p_date date, p_next date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; tname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name into tname from public.app_measuring_tools t where t.id = p_id and (urole='admin' or t.tenant_id = ten);
  if tname is null then return query select false,'СИ не найдено'; return; end if;
  if coalesce(p_date, current_date) is null then return query select false,'Укажите дату поверки'; return; end if;
  update public.app_measuring_tools set last_verified = coalesce(p_date, current_date), next_verified = p_next where id = p_id;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','qc','chief'], 'Поверка СИ: ' || tname,
    'Поверено ' || coalesce(p_date, current_date)::text || case when p_next is not null then ', следующая ' || p_next::text else '' end,
    'apps/quality/index.html');
  return query select true,'Поверка зарегистрирована';
end $$;

-- ---------- Трассируемость (с паспортом/примечанием) ----------
drop function if exists public.app_trace_list(uuid);
create or replace function public.app_trace_list(p_token uuid)
returns table (id uuid, item text, serial text, order_id uuid, order_number text, passport_id uuid, passport_number text,
               material text, operator text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select tr.id, tr.item, tr.serial, tr.order_id, o.number, tr.passport_id, p.number,
    tr.material, tr.operator, tr.note, tr.by_login, tr.created_at
    from public.app_traceability tr
    left join public.app_orders o on o.id = tr.order_id
    left join public.app_passports p on p.id = tr.passport_id
    where (urole='admin' or tr.tenant_id = ten) order by tr.created_at desc;
end $$;

-- app_trace_add: привязка паспорта уже есть в подписи (0022), оставляем.

grant execute on function public.app_tools_list(uuid) to anon, authenticated;
grant execute on function public.app_tool_verify(uuid,uuid,date,date) to anon, authenticated;
grant execute on function public.app_trace_list(uuid) to anon, authenticated;

-- ---------- База знаний: СМК ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('СМК','Как вести средства измерений и поверку?',
   'В «Качестве» (СМК) вкладка «Средства измерений»: карточки СИ со статусом — «в норме», «истекает» (≤30 дней), «просрочено». При проведении поверки укажите дату и следующую дату — запись обновится, а ответственным уйдёт уведомление. Просроченные СИ нельзя использовать по СМК.',
   'СМК СИ средства измерений поверка просрочено уведомление'),
  ('СМК','Что такое трассируемость в СМК?',
   'Трассируемость связывает изделие/партию с заявкой, паспортом, материалом и оператором: кто, из чего и когда сделал. Записи ведите на вкладке «Трассируемость» (можно из паспорта изделия). Это доказательная база для СМК и претензионной работы.',
   'трассируемость СМК изделие паспорт материал оператор партия')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='СМК');
-- <<<<<<<<<< 0044_quality_ref.sql <<<<<<<<<<

-- >>>>>>>>>> 0045_links.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0045_links.sql  (v27.0 — связки данных)
-- Авто-КП и авто-счёт из заявки, наряд из спецификации (BOM), списание материалов.
-- База знаний. Tenant-изоляция. Зависит от 0001..0044.
-- ============================================================

-- ---------- Авто-КП из заявки ----------
create or replace function public.app_order_create_quote(p_token uuid, p_order_id uuid, p_valid_days integer default 30)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; o record; amt numeric; did uuid; dnum text; vd date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o0.* into o from public.app_orders o0 where o0.id = p_order_id;
  if o.id is null then raise exception 'Заявка не найдена'; end if;

  amt := o.amount;
  if amt is null then
    select c.total into amt from public.app_bom b, lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) c
      where b.order_id = p_order_id limit 1;
  end if;
  vd := current_date + greatest(coalesce(p_valid_days,30),1);
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, created_by, created_login)
  values (ten, 'kp', dnum, 'КП по заявке ' || o.number, p_order_id, o.customer_id, amt, vd, 'draft',
          'Коммерческое предложение по заявке ' || o.number || '.', uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'КП по заявке ' || o.number, 'Коммерческое предложение.', ulogin);
  return query select did, dnum, 'КП создано';
end $$;

-- ---------- Авто-счёт из заявки/договора ----------
create or replace function public.app_order_create_invoice(p_token uuid, p_order_id uuid, p_due_days integer default 14)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; o record; amt numeric; inum text; iid uuid; did_link uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o0.* into o from public.app_orders o0 where o0.id = p_order_id;
  if o.id is null then raise exception 'Заявка не найдена'; end if;

  amt := o.amount;
  if amt is null or amt = 0 then
    select c.total into amt from public.app_bom b, lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) c
      where b.order_id = p_order_id limit 1;
  end if;
  if amt is null or amt = 0 then raise exception 'Не удалось определить сумму — укажите сумму заявки или спецификацию'; end if;

  select d.id into did_link from public.app_documents d
    where d.order_id = p_order_id and d.doc_type = 'contract' order by d.created_at desc limit 1;

  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, customer_id, document_id, amount, status, due_date, created_by, created_login)
  values (ten, inum, p_order_id, o.customer, o.customer_id, did_link, amt, 'draft', current_date + greatest(coalesce(p_due_days,14),1), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum, 'Счёт создан по заявке';
end $$;

-- ---------- Наряд из спецификации (BOM) ----------
create or replace function public.app_naryad_from_bom(p_token uuid, p_bom_id uuid, p_wc_id uuid, p_assignee text, p_due_date date)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; b record; nid uuid; nnum text; i integer := 0; ln record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id;
  if b.id is null then raise exception 'Спецификация не найдена'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, priority, start_date, due_date, tenant_id, created_by, created_login)
  values (nnum, b.order_id, coalesce(b.product,'Наряд по спецификации'), p_wc_id, nullif(trim(p_assignee),''), 'open', 'normal', current_date, p_due_date, ten, uid, ulogin)
  returning app_naryads.id into nid;

  for ln in select * from public.app_bom_lines where bom_id = p_bom_id and item_type = 'operation' order by seq loop
    i := i + 1;
    insert into public.app_naryad_ops (naryad_id, seq, operation, operation_id, worker, plan_hours)
    values (nid, i, coalesce(ln.name,'Операция'), ln.operation_id, nullif(trim(p_assignee),''), coalesce(ln.norm_hours,0));
  end loop;

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = 'in_progress' where n.id = nid;
  return query select nid, nnum, 'Наряд создан по спецификации';
end $$;

-- ---------- Списание материалов по спецификации ----------
create or replace function public.app_bom_writeoff(p_token uuid, p_bom_id uuid, p_order_id uuid, p_qty numeric default 1)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare b record; ln record; rec record; cnt integer := 0; k numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id;
  if b.id is null then return query select false,'Спецификация не найдена'; return; end if;
  k := greatest(coalesce(p_qty,1),1);

  for ln in select * from public.app_bom_lines where bom_id = p_bom_id and item_type='material' and material_id is not null order by seq loop
    for rec in select * from public.app_stock_move(p_token, ln.material_id, 'out', coalesce(ln.qty,0)*k, 0, 'Списание по спецификации', 'bom', p_order_id, null) loop
      if rec.ok then cnt := cnt + 1; end if;
    end loop;
  end loop;
  return query select true, 'Списано позиций: ' || cnt;
end $$;

grant execute on function public.app_order_create_quote(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_order_create_invoice(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_naryad_from_bom(uuid,uuid,uuid,text,date) to anon, authenticated;
grant execute on function public.app_bom_writeoff(uuid,uuid,uuid,numeric) to anon, authenticated;

-- ---------- База знаний: связки ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Связки','Как быстро создать КП и счёт из заявки?',
   'В карточке заявки есть кнопки «Создать КП» и «Создать счёт»: КП создаётся на сумму заявки (или из спецификации), с сроком действия; счёт — со сроком оплаты и привязкой к договору, если он есть. Так замыкается цепочка: заявка → КП → договор → счёт → оплата без ручного переноса.',
   'связки КП счёт заявка авто договор оплата'),
  ('Связки','Как перейти от спецификации к производству и складу?',
   'В карточке спецификации (BOM) есть кнопки «Создать наряд» (операции и нормо-часы переносятся в наряд) и «Списать материалы» (расход материалов по спецификации со склада, с проверкой остатков). Это единый поток: BOM → наряд → склад → себестоимость.',
   'связки BOM наряд склад списание материалы производство')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Связки');
-- <<<<<<<<<< 0045_links.sql <<<<<<<<<<

-- >>>>>>>>>> 0046_files.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0046_files.sql  (v28.0 — боевой режим: вложения/файлы)
-- Единое хранилище вложений к сущностям (заявка/документ/ОТК/паспорт/наряд/закупка).
-- Файлы в БД (bytea), доступ через RPC с tenant-изоляцией. База знаний.
-- Зависит от 0001..0045.
-- ============================================================

create table if not exists public.app_attachments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  entity_type text not null,      -- order | document | qc | passport | naryad | tender
  entity_id   uuid,
  name        text not null,
  mime        text,
  size        integer,
  data        bytea,
  uploaded_by text,
  created_at  timestamptz not null default now()
);
create index if not exists app_attachments_entity_idx on public.app_attachments (entity_type, entity_id);
create index if not exists app_attachments_tenant_idx on public.app_attachments (tenant_id, created_at desc);
alter table public.app_attachments enable row level security;

-- ---------- Загрузить вложение (base64) ----------
create or replace function public.app_attachment_add(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_data text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; ten uuid; aid uuid; bytes bytea; allowed text[] := array['order','document','qc','passport','naryad','tender'];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (p_entity_type = any(allowed)) then raise exception 'Неизвестный тип сущности'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите имя файла'; end if;
  begin
    bytes := decode(p_data, 'base64');
  exception when others then raise exception 'Некорректные данные файла'; end;
  if octet_length(bytes) > 8388608 then raise exception 'Файл больше 8 МБ'; end if;

  insert into public.app_attachments (tenant_id, entity_type, entity_id, name, mime, size, data, uploaded_by)
  values (ten, p_entity_type, p_entity_id, trim(p_name), nullif(trim(p_mime),''), octet_length(bytes), bytes, ulogin)
  returning app_attachments.id into aid;
  return query select aid, trim(p_name);
end $$;

-- ---------- Список вложений (метаданные) ----------
create or replace function public.app_attachment_list(p_token uuid, p_entity_type text, p_entity_id uuid)
returns table (id uuid, name text, mime text, size integer, uploaded_by text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.name, a.mime, a.size, a.uploaded_by, a.created_at
    from public.app_attachments a
    where a.entity_type = p_entity_type and a.entity_id = p_entity_id and (urole='admin' or a.tenant_id = ten)
    order by a.created_at desc;
end $$;

-- ---------- Получить вложение (base64) ----------
create or replace function public.app_attachment_get(p_token uuid, p_id uuid)
returns table (id uuid, name text, mime text, size integer, data text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.name, a.mime, a.size, encode(a.data, 'base64')
    from public.app_attachments a
    where a.id = p_id and (urole='admin' or a.tenant_id = ten);
end $$;

-- ---------- Удалить вложение ----------
create or replace function public.app_attachment_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_attachments where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Файл удалён';
end $$;

grant execute on function public.app_attachment_add(uuid,text,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_attachment_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_attachment_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_attachment_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний: файлы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Файлы','Как прикрепить файл к заявке/документу/ОТК?',
   'В карточке заявки, документа, чек-листа ОТК, паспорта, наряда или закупки есть блок «Файлы»: нажмите «Прикрепить», выберите файл (чертёж, КП, PDF, фото) — до 8 МБ. Скачивание и удаление — там же. Файлы изолированы по организации.',
   'файлы вложения чертежи КП PDF фото заявка документ ОТК')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Файлы');
-- <<<<<<<<<< 0046_files.sql <<<<<<<<<<

-- >>>>>>>>>> 0047_platform_apps.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0047_platform_apps.sql  (v29.0 — платформенные модули)
-- admin_list_users: + организация и последний вход. База знаний (API/Платформа/Админ).
-- Зависит от 0001..0046.
-- ============================================================

drop function if exists public.admin_list_users(uuid);
create or replace function public.admin_list_users(p_token uuid)
returns table (id uuid, login text, full_name text, role text, active boolean,
               tenant_name text, last_login_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select u.id, u.login, u.full_name, u.role, u.active, t.name, u.last_login_at, u.created_at
    from public.app_users u left join public.tenants t on t.id = u.tenant_id
    order by u.created_at;
end $$;

grant execute on function public.admin_list_users(uuid) to anon, authenticated;

-- ---------- База знаний: платформа ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Как работает Public API и вебхуки?',
   'В модуле «API и интеграции» владелец создаёт API-ключи организации. По ключу внешние системы читают данные через публичные функции: api_orders (заявки), api_tenders (закупки), api_stock (склад) — POST на /rest/v1/rpc/<функция> с параметром p_key. Вебхуки регистрируют URL, куда сервис шлёт события (заявка создана, новое КП, наряд закрыт).',
   'API ключи вебхуки интеграция 1С api_orders api_stock'),
  ('Платформа','Что делает администратор платформы?',
   'Администратор платформы: создаёт и ведёт организации (тариф, статус), управляет всеми пользователями и ролями сервиса, смотрит журнал действий. Клиенты администрируют свою организацию сами в «Админ-панели клиента» (сотрудники/роли/модули/бренд).',
   'платформа админ организации тенанты журнал роли SaaS')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Платформа');
-- <<<<<<<<<< 0047_platform_apps.sql <<<<<<<<<<

-- >>>>>>>>>> 0048_permissions.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0048_permissions.sql  (v30.0 — серверная матрица прав)
-- app_can(module, action): серверная проверка прав по матрице app_role_permissions.
-- Правило: admin/owner — всё; иначе по строке матрицы; если строки нет — просмотр разрешён, правка запрещена.
-- Внедрение в модуль «Заявки» (create/update/status). База знаний. Зависит от 0001..0047.
-- ============================================================

-- ---------- Сидирование роли manager (широкие права для совместимости) ----------
insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'manager', m.module_id, true, true
from (values
  ('panel'),('dashboard'),('guide'),('modules'),('eco'),('orders'),('supplier'),('procurement'),('docs'),
  ('registry'),('bom'),('assistant'),('production'),('mes'),('planning'),('warehouse'),('qc'),('passport'),('quality'),
  ('economics'),('finance'),('bi'),('reports'),('hr'),('org'),('api')
) as m(module_id)
where not exists (
  select 1 from public.app_role_permissions
  where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and role='manager' and module_id = m.module_id
);

-- ---------- Проверка прав ----------
create or replace function public.app_can(p_token uuid, p_module text, p_action text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare urole text; ten uuid; vw boolean; ed boolean;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return false; end if;
  if urole in ('admin','owner') then return true; end if;
  ten := public.app_my_tenant(p_token);
  select p.can_view, p.can_edit into vw, ed
    from public.app_role_permissions p
    where p.role = urole and p.module_id = p_module and (p.tenant_id = ten or p.tenant_id is null)
    limit 1;
  if found then
    return case when lower(coalesce(p_action,'view')) = 'edit' then ed else vw end;
  end if;
  -- строки нет: просмотр разрешён, правка — нет
  return lower(coalesce(p_action,'view')) <> 'edit';
end $$;

create or replace function public.app_can_view(p_token uuid, p_module text)
returns boolean language sql stable as $$ select public.app_can(p_token, p_module, 'view') $$;

create or replace function public.app_can_edit(p_token uuid, p_module text)
returns boolean language sql stable as $$ select public.app_can(p_token, p_module, 'edit') $$;

-- ---------- Права текущего пользователя (для UI) ----------
create or replace function public.app_my_permissions(p_token uuid)
returns table (module_id text, can_view boolean, can_edit boolean)
language plpgsql stable security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return; end if;
  ten := public.app_my_tenant(p_token);
  if urole in ('admin','owner') then
    return query select distinct p.module_id, true, true
      from public.app_role_permissions p where p.tenant_id = ten;
    return;
  end if;
  return query select p.module_id, p.can_view, p.can_edit
    from public.app_role_permissions p
    where p.role = urole and (p.tenant_id = ten or p.tenant_id is null);
end $$;

grant execute on function public.app_can(uuid,text,text) to anon, authenticated;
grant execute on function public.app_can_view(uuid,text) to anon, authenticated;
grant execute on function public.app_can_edit(uuid,text) to anon, authenticated;
grant execute on function public.app_my_permissions(uuid) to anon, authenticated;

-- ============================================================
--  Внедрение в модуль «Заявки»
-- ============================================================
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null,
  p_amount numeric default null, p_order_type text default 'single'
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid; cname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if not public.app_can(p_token, 'orders', 'edit') then raise exception 'Недостаточно прав'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, customer_id, contact, priority,
                                 status, due_date, assignee, amount, order_type, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, coalesce(nullif(trim(p_order_type),''),'single'), ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric, p_order_type text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; cname text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'orders', 'edit') then return query select false,'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_id and (urole='admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки'; return; end if;

  cname := null;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  update public.app_orders set title = trim(p_title), description = nullif(trim(p_description),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), customer_id = p_customer_id,
    customer = coalesce(cname, customer), contact = nullif(trim(p_contact),''), due_date = p_due_date,
    assignee = nullif(trim(p_assignee),''), amount = p_amount,
    order_type = coalesce(nullif(trim(p_order_type),''), order_type), updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; owner uuid; onum text; oten uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'orders', 'edit') then return query select false, 'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select o.created_by, o.number, o.tenant_id into owner, onum, oten from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole = 'admin' or (oten = ten and (public.app_role_is_staff(urole) or owner = uid))) then
    return query select false, 'Доступ запрещён'; return;
  end if;
  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment),''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment,''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- База знаний: права ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Роли','Как работает серверная проверка прав (app_can)?',
   'Права проверяются на сервере: функция app_can(модуль, действие) смотрит матрицу app_role_permissions. Владелец и администратор имеют все права; остальные — по строке матрицы. Если строки нет — просмотр разрешён, правка запрещена. Мутирующие операции модулей (например, создание/изменение заявки) выполняются только при праве «правка» на модуль.',
   'права app_can матрица роль модуль правка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как работает серверная проверка прав (app_can)?');
-- <<<<<<<<<< 0048_permissions.sql <<<<<<<<<<

-- >>>>>>>>>> 0049_ref_materials.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0049_ref_materials.sql  (v31.0 — справочник марок материалов)
-- Глобальный справочник марок (tenant_id null — общий для всех организаций):
-- группа, марка, ГОСТ, плотность, σв, твёрдость HB, цена, применение.
-- База знаний. Зависит от 0001..0048.
-- ============================================================

create table if not exists public.app_ref_material_grades (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  group_code text not null,      -- steel|tool_steel|stainless|aluminum|bronze|brass|copper|cast_iron|plastic|titanium
  grade      text not null,
  standard   text,
  density    numeric,
  tensile    numeric,            -- σв, МПа
  hardness   numeric,            -- HB (или HRC для инструментальных)
  price      numeric,            -- ₽/кг
  note       text,
  created_at timestamptz not null default now(),
  unique (tenant_id, group_code, grade)
);
create index if not exists app_ref_mat_grades_idx on public.app_ref_material_grades (group_code, grade);
alter table public.app_ref_material_grades enable row level security;

-- ---------- Список ----------
create or replace function public.app_ref_material_list(p_token uuid, p_group text default null, p_q text default null)
returns table (id uuid, group_code text, grade text, standard text, density numeric, tensile numeric,
               hardness numeric, price numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  qq := lower(coalesce(trim(p_q),''));
  return query
    select g.id, g.group_code, g.grade, g.standard, g.density, g.tensile, g.hardness, g.price, g.note
    from public.app_ref_material_grades g
    where (g.tenant_id is null or g.tenant_id = ten or urole='admin')
      and (p_group is null or p_group = '' or g.group_code = p_group)
      and (qq = '' or lower(g.grade) like '%'||qq||'%' or lower(coalesce(g.standard,'')) like '%'||qq||'%' or lower(coalesce(g.note,'')) like '%'||qq||'%')
    order by g.group_code, g.grade;
end $$;

-- ---------- Добавить/изменить (admin/owner/manager/technologist) ----------
create or replace function public.app_ref_material_save(p_token uuid, p_id uuid, p_group text, p_grade text,
  p_standard text, p_density numeric, p_tensile numeric, p_hardness numeric, p_price numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; gid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','technologist') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_grade),'') = '' then return query select false,'Укажите марку'; return; end if;

  if p_id is null then
    insert into public.app_ref_material_grades (tenant_id, group_code, grade, standard, density, tensile, hardness, price, note)
    values (null, coalesce(nullif(trim(p_group),''),'steel'), trim(p_grade), nullif(trim(p_standard),''),
            p_density, p_tensile, p_hardness, p_price, nullif(trim(p_note),''))
    returning app_ref_material_grades.id into gid;
  else
    update public.app_ref_material_grades set group_code = coalesce(nullif(trim(p_group),''), group_code),
      grade = trim(p_grade), standard = nullif(trim(p_standard),''), density = p_density, tensile = p_tensile,
      hardness = p_hardness, price = p_price, note = nullif(trim(p_note),'')
     where id = p_id and (tenant_id is null and urole in ('admin','owner') or tenant_id = ten)
     returning app_ref_material_grades.id into gid;
    if gid is null then return query select false,'Запись не найдена или нет прав'; return; end if;
  end if;
  return query select true,'Сохранено';
end $$;

grant execute on function public.app_ref_material_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_material_save(uuid,uuid,text,text,text,numeric,numeric,numeric,numeric,text) to anon, authenticated;

-- ---------- Наполнение (глобальный справочник) ----------
insert into public.app_ref_material_grades (tenant_id, group_code, grade, standard, density, tensile, hardness, price, note)
select null, v.group_code, v.grade, v.standard, v.density, v.tensile, v.hardness, v.price, v.note
from (values
  ('steel','Сталь 20','ГОСТ 1050-2013',7.85,410,120,65,'Конструкционная, цементуемая'),
  ('steel','Сталь 45','ГОСТ 1050-2013',7.85,780,197,70,'Конструкционная улучшаемая'),
  ('steel','Сталь 3 (Ст3)','ГОСТ 380-2005',7.85,370,120,60,'Обычного качества'),
  ('steel','09Г2С','ГОСТ 19281-2014',7.85,490,150,75,'Низколегированная, конструкции'),
  ('steel','40Х','ГОСТ 4543-2016',7.82,980,217,85,'Легированная, валы/шестерни'),
  ('steel','40ХН','ГОСТ 4543-2016',7.82,1080,240,95,'Повышенная прочность'),
  ('steel','65Г','ГОСТ 14959-2016',7.85,1000,250,90,'Пружинная/рессорная'),
  ('tool_steel','У8','ГОСТ 1435-99',7.85,900,187,120,'Инструментальная углеродистая (HRC 60)'),
  ('tool_steel','У10','ГОСТ 1435-99',7.85,1000,200,125,'Инструментальная (HRC 62)'),
  ('tool_steel','9ХС','ГОСТ 5950-2000',7.8,1100,220,260,'Инструментальная легированная'),
  ('tool_steel','Х12МФ','ГОСТ 5950-2000',7.7,1100,230,320,'Штамповая холодной штамповки'),
  ('tool_steel','5ХНМ','ГОСТ 5950-2000',7.8,1200,240,300,'Штамповая горячей штамповки'),
  ('tool_steel','Р6М5','ГОСТ 19265-73',8.2,2000,255,750,'Быстрорежущая (HRC 63-65)'),
  ('stainless','12Х18Н10Т','ГОСТ 5632-2014',7.9,550,180,420,'Нержавеющая, пищевая/химстойкая'),
  ('stainless','20Х13','ГОСТ 5632-2014',7.7,650,200,300,'Нержавеющая, валы/лопатки'),
  ('bearing','ШХ15','ГОСТ 801-78',7.81,1200,210,180,'Подшипниковая'),
  ('aluminum','Д16Т','ГОСТ 4784-2019',2.78,440,120,450,'Авиаль, высокопрочная'),
  ('aluminum','АМг6','ГОСТ 4784-2019',2.64,340,95,420,'Алюминиево-магниевый сплав'),
  ('aluminum','АД31','ГОСТ 4784-2019',2.70,200,60,380,'Авиаль, профили'),
  ('bronze','БрАЖ9-4','ГОСТ 18175-78',7.5,550,120,950,'Бронза, втулки/направляющие'),
  ('brass','ЛС59-1','ГОСТ 15527-2004',8.5,470,130,800,'Латунь свинцовистая'),
  ('copper','М1','ГОСТ 859-2014',8.9,220,45,900,'Медь, электроды ЭЭО'),
  ('cast_iron','СЧ20','ГОСТ 1412-85',7.2,200,200,90,'Серый чугун'),
  ('cast_iron','ВЧ50','ГОСТ 7293-85',7.1,500,187,140,'Высокопрочный чугун'),
  ('plastic','ПА6 (полиамид)','—',1.14,80,null,550,'Втулки, зубчатки'),
  ('plastic','POM (полиацеталь)','—',1.41,70,null,700,'Точные детали, скольжение'),
  ('plastic','PTFE (фторопласт)','—',2.2,25,null,1200,'Химстойкие уплотнения'),
  ('titanium','ВТ6','ГОСТ 19807-91',4.43,950,230,3500,'Титановый сплав (Ti-6Al-4V)')
) as v(group_code, grade, standard, density, tensile, hardness, price, note)
where not exists (select 1 from public.app_ref_material_grades where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Материалы','Что содержит справочник марок материалов?',
   'Справочник марок (Справочники → вкладка «Марки»): группа, марка, ГОСТ, плотность, предел прочности σв, твёрдость HB/HRC, цена ₽/кг и применение. Используется в спецификациях (BOM), расчёте массы, себестоимости и подборе режимов резания.',
   'материалы марки справочник ГОСТ плотность прочность HB цена BOM'),
  ('Материалы','Как выбирать марку для штампов и оснастки?',
   'Для холодной штамповки — Х12МФ, для горячей — 5ХНМ, для режущего инструмента — Р6М5/У10, для направляющих и втулок — БрАЖ9-4/ШХ15, для электродов ЭЭО — М1. Плотность и прочность берутся из справочника для расчёта массы и нагружения.',
   'выбор марки штамп оснастка Х12МФ 5ХНМ Р6М5 электроды')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что содержит справочник марок материалов?');
-- <<<<<<<<<< 0049_ref_materials.sql <<<<<<<<<<

-- >>>>>>>>>> 0050_ref_tech.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0050_ref_tech.sql  (v31.1 — технические справочники, пакет 1)
-- Режимы резания, режущий инструмент, каталог оборудования (по данным предприятия).
-- Глобальные справочники (tenant_id null). База знаний. Зависит от 0001..0049.
-- ============================================================

-- ---------- Режимы резания ----------
create table if not exists public.app_ref_cutting (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  material_group text not null,
  operation text not null,
  tool_type text,
  tool_material text,
  vc numeric, feed numeric, ap numeric, ae numeric,
  cooling text, note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_cutting_idx on public.app_ref_cutting (material_group, operation);
alter table public.app_ref_cutting enable row level security;

-- ---------- Режущий инструмент ----------
create table if not exists public.app_ref_tools (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  tool_type text not null,
  designation text,
  material text,
  coating text,
  diameter numeric,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_tools_idx on public.app_ref_tools (tool_type);
alter table public.app_ref_tools enable row level security;

-- ---------- Каталог оборудования ----------
create table if not exists public.app_ref_machines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  manufacturer text,
  model text not null,
  kind text,
  axes integer,
  max_x numeric, max_y numeric, max_z numeric,
  spindle_rpm integer, spindle_kw numeric,
  accuracy numeric, price numeric, note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_machines_idx on public.app_ref_machines (kind);
alter table public.app_ref_machines enable row level security;

-- ---------- RPC ----------
create or replace function public.app_ref_cutting_list(p_token uuid, p_group text default null, p_q text default null)
returns table (id uuid, material_group text, operation text, tool_type text, tool_material text,
               vc numeric, feed numeric, ap numeric, ae numeric, cooling text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select c.id, c.material_group, c.operation, c.tool_type, c.tool_material, c.vc, c.feed, c.ap, c.ae, c.cooling, c.note
    from public.app_ref_cutting c
    where (c.tenant_id is null or c.tenant_id = ten)
      and (p_group is null or p_group='' or c.material_group = p_group)
      and (qq='' or lower(c.operation) like '%'||qq||'%' or lower(coalesce(c.tool_type,'')) like '%'||qq||'%' or lower(coalesce(c.note,'')) like '%'||qq||'%')
    order by c.material_group, c.operation;
end $$;

create or replace function public.app_ref_tools_list(p_token uuid, p_q text default null)
returns table (id uuid, tool_type text, designation text, material text, coating text, diameter numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.tool_type, t.designation, t.material, t.coating, t.diameter, t.note
    from public.app_ref_tools t
    where (t.tenant_id is null or t.tenant_id = ten)
      and (qq='' or lower(t.tool_type) like '%'||qq||'%' or lower(coalesce(t.designation,'')) like '%'||qq||'%' or lower(coalesce(t.material,'')) like '%'||qq||'%')
    order by t.tool_type, t.diameter;
end $$;

create or replace function public.app_ref_machines_list(p_token uuid, p_q text default null)
returns table (id uuid, manufacturer text, model text, kind text, axes integer, max_x numeric, max_y numeric, max_z numeric,
               spindle_rpm integer, spindle_kw numeric, accuracy numeric, price numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select m.id, m.manufacturer, m.model, m.kind, m.axes, m.max_x, m.max_y, m.max_z, m.spindle_rpm, m.spindle_kw, m.accuracy, m.price, m.note
    from public.app_ref_machines m
    where (m.tenant_id is null or m.tenant_id = ten)
      and (qq='' or lower(m.model) like '%'||qq||'%' or lower(coalesce(m.manufacturer,'')) like '%'||qq||'%' or lower(coalesce(m.kind,'')) like '%'||qq||'%')
    order by m.kind, m.model;
end $$;

grant execute on function public.app_ref_cutting_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_tools_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_machines_list(uuid,text) to anon, authenticated;

-- ---------- Наполнение: режимы резания ----------
insert into public.app_ref_cutting (tenant_id, material_group, operation, tool_type, tool_material, vc, feed, ap, ae, cooling, note)
select null, v.mg, v.op, v.tt, v.tm, v.vc, v.feed, v.ap, v.ae, v.cool, v.note
from (values
  ('steel','Фрезерование','Концевая фреза','твердосплав',120,0.05,2,10,'СОЖ эмульсия','Черновая, сталь конструкционная'),
  ('steel','Фрезерование','Концевая фреза','твердосплав+TIAIN',200,0.03,0.5,10,'СОЖ эмульсия','Чистовая'),
  ('steel','Точение','Резец проходной','твердосплав',180,0.25,2,null,'СОЖ эмульсия','Черновая'),
  ('steel','Точение','Резец проходной','твердосплав',260,0.10,0.5,null,'СОЖ эмульсия','Чистовая'),
  ('steel','Сверление','Сверло спиральное','HSS-Co',25,0.15,null,null,'СОЖ эмульсия',''),
  ('steel','Сверление','Сверло спиральное','твердосплав',70,0.20,null,null,'СОЖ эмульсия',''),
  ('tool_steel','Фрезерование','Концевая фреза','твердосплав+TIAIN',80,0.04,1,8,'СОЖ эмульсия','HRC до 32'),
  ('tool_steel','Фрезерование','Концевая фреза','твердосплав+ALCRN',50,0.03,0.5,6,'СОЖ эмульсия','HRC 32-45'),
  ('tool_steel','ЭЭО проволочная','Проволока латунная',null,null,null,null,null,'диэлектрик','Ø0.25 мм, HRC>45'),
  ('tool_steel','Шлифование','Круг шлифовальный','электрокорунд',30,null,0.02,null,'СОЖ','Плоское/круглое'),
  ('stainless','Точение','Резец проходной','твердосплав',90,0.15,1.5,null,'СОЖ эмульсия','Нержавейка, склонность к наклёпу'),
  ('stainless','Фрезерование','Концевая фреза','твердосплав',70,0.04,1,8,'СОЖ эмульсия',''),
  ('aluminum','Фрезерование','Концевая фреза','твердосплав',300,0.10,3,12,'СОЖ эмульсия/туман','Высокие обороты'),
  ('aluminum','Точение','Резец проходной','твердосплав',400,0.30,2,null,'СОЖ эмульсия',''),
  ('aluminum','Сверление','Сверло спиральное','HSS',60,0.20,null,null,'СОЖ эмульсия',''),
  ('cast_iron','Фрезерование','Торцевая фреза','твердосплав',150,0.15,2,30,'без СОЖ/туман',''),
  ('cast_iron','Точение','Резец проходной','твердосплав',120,0.25,2,null,'без СОЖ',''),
  ('bronze','Точение','Резец проходной','твердосплав',200,0.20,1.5,null,'СОЖ эмульсия','Втулки/направляющие'),
  ('plastic','Фрезерование','Концевая фреза','HSS',300,0.15,3,15,'без СОЖ','Охлаждение воздухом')
) as v(mg, op, tt, tm, vc, feed, ap, ae, cool, note)
where not exists (select 1 from public.app_ref_cutting where tenant_id is null);

-- ---------- Наполнение: инструмент ----------
insert into public.app_ref_tools (tenant_id, tool_type, designation, material, coating, diameter, note)
select null, v.tool_type, v.designation, v.material, v.coating, v.diameter, v.note
from (values
  ('Концевая фреза','ФК 10×20×75','твердосплав','TIAIN',10,'4 зуба'),
  ('Концевая фреза','ФК 6×20×60','твердосплав','ALCRN',6,'4 зуба'),
  ('Концевая фреза','ФК 12×30×80','твердосплав','TIAIN',12,'4 зуба'),
  ('Торцевая фреза','ФТ 63','твердосплав','TIAIN',63,'5 пластин'),
  ('Сверло','Ø8.5 HSS-Co','HSS-Co','—',8.5,'под М10'),
  ('Сверло','Ø10.2 HSS-Co','HSS-Co','—',10.2,'под М12'),
  ('Метчик','М10×1.5','HSS','—',10,'машинный'),
  ('Метчик','М12×1.75','HSS','—',12,'машинный'),
  ('Развёртка','Ø12 H7','HSS','—',12,'ручная/машинная'),
  ('Резец','DCGT 11T3','твердосплав','TIAIN',null,'точение чист.'),
  ('Резец','CNMG 120408','твердосплав','CVD',null,'точение черн.'),
  ('Проволока ЭЭО','Ø0.25 латунь','латунь','—',0.25,'проволочно-вырезной'),
  ('Электрод ЭЭО','медь М1 Ø10','медь','—',10,'прошивной'),
  ('Круг шлифовальный','ПП 250×25','электрокорунд','—',250,'плоское шлифование')
) as v(tool_type, designation, material, coating, diameter, note)
where not exists (select 1 from public.app_ref_tools where tenant_id is null);

-- ---------- Наполнение: оборудование ----------
insert into public.app_ref_machines (tenant_id, manufacturer, model, kind, axes, max_x, max_y, max_z, spindle_rpm, spindle_kw, accuracy, price, note)
select null, v.man, v.model, v.kind, v.ax, v.x, v.y, v.z, v.rpm, v.kw, v.acc, v.price, v.note
from (values
  ('Feeler','FTC-350Xl','Токарный ЧПУ',2,350,0,500,4000,15,0.010,4500000,'Токарная обработка'),
  ('Focus','Focus Turn','Токарный ЧПУ',2,300,0,450,4500,11,0.010,3200000,'Токарная обработка'),
  ('Chevalier','QP2440','Фрезерный ЧПУ',3,1000,500,500,8000,7.5,0.010,3500000,'Фрезерная обработка'),
  ('Pinnacle','SV-65','Фрезерный ЧПУ',3,1270,635,610,8000,11,0.010,4200000,'Фрезерная обработка'),
  ('Chevalier','QP2440-L','Фрезерный ЧПУ',3,1200,600,600,8000,11,0.008,4600000,'Фрезерная, длинные детали'),
  ('Chevalier','QP5x-400','Фрезерный ЧПУ',3,800,500,400,10000,7.5,0.008,3800000,'Прецизионная фрезерная'),
  ('Chevalier','SMART B-1224 II','Плоскошлифовальный',2,600,300,0,3000,5.5,0.005,2800000,'Плоское шлифование'),
  ('WASINO','GLS-130AN','Круглошлифовальный',2,300,0,500,2000,7.5,0.005,3900000,'Круглое шлифование'),
  ('Overbeck','400RU','Внутришлифовальный',2,200,0,300,4000,5.5,0.003,4200000,'Внутреннее шлифование'),
  ('FCL','FCL-1220','Шлифовальный',2,500,250,0,3000,5.5,0.005,2200000,'Шлифование'),
  ('Mitsubishi','FA10-VS','ЭЭО проволочно-вырезной',5,400,320,250,0,0,0.005,5200000,'Проволочная ЭЭО'),
  ('Mitsubishi','BA-8','ЭЭО прошивной',2,400,300,300,0,0,0.005,4800000,'Прошивная ЭЭО'),
  ('Sodick','Aa300','ЭЭО прошивной',2,300,250,250,0,0,0.004,4400000,'Прошивная ЭЭО'),
  ('Sodick','A325','ЭЭО прошивной',2,350,300,300,0,0,0.004,4900000,'Прошивная ЭЭО'),
  ('INGERSOLL','Gantry 500','ЭЭО/обрабатывающий',3,500,400,400,0,0,0.005,6500000,'Крупногабаритная ЭЭО')
) as v(man, model, kind, ax, x, y, z, rpm, kw, acc, price, note)
where not exists (select 1 from public.app_ref_machines where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Режимы резания','Что содержит справочник режимов резания?',
   'Таблица «материал × операция → инструмент, Vc (м/мин), подача, глубина, СОЖ». Используется для подбора режимов, расчёта времени обработки и стоимости. Значения — стартовые, уточняются по каталогам инструмента.',
   'режимы резания Vc подача глубина СОЖ материал операция'),
  ('Инструмент','Каталог режущего инструмента',
   'Фрезы, свёрла, метчики, развёртки, резцы, проволока/электроды ЭЭО, шлифкруги — с материалом (HSS/HSS-Co/твердосплав), покрытием (TIAIN/ALCRN) и диаметром. Основа для заявок на закупку и карт наладки.',
   'инструмент фрезы сверла метчики резцы ЭЭО покрытие'),
  ('Оборудование','Каталог станков предприятия',
   'Реальные модели: Feeler FTC-350Xl, Chevalier QP2440/QP2440-L/QP5x-400/SMART B-1224 II, Pinnacle SV-65, WASINO GLS-130AN, Overbeck 400RU, Mitsubishi FA10-VS/BA-8, Sodick Aa300/A325, INGERSOLL Gantry 500. Хода, шпиндель, точность, стоимость — для подбора оборудования под операцию.',
   'оборудование станки Feeler Chevalier Pinnacle WASINO Overbeck Mitsubishi Sodick')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что содержит справочник режимов резания?');
-- <<<<<<<<<< 0050_ref_tech.sql <<<<<<<<<<

-- >>>>>>>>>> 0051_ref_norms.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0051_ref_norms.sql  (v31.2 — технические справочники, пакет 2)
-- Посадки ISO 286, крепёж/стандартные изделия, термообработка/покрытия, СОЖ/смазки,
-- реестр процессов предприятия (АД/ПР/ВСП). Глобальные справочники. База знаний.
-- Зависит от 0001..0050.
-- ============================================================

-- ---------- Посадки ISO 286 ----------
create table if not exists public.app_ref_fits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  nominal numeric not null,
  designation text not null,
  kind text,                -- clearance | transition | interference
  hole_dev text, shaft_dev text,
  clearance_max numeric, clearance_min numeric,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_fits_idx on public.app_ref_fits (kind);
alter table public.app_ref_fits enable row level security;

-- ---------- Крепёж / стандартные изделия ----------
create table if not exists public.app_ref_fasteners (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  standard text,
  size text,
  material text, coating text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_fasteners enable row level security;

-- ---------- Термообработка / покрытия ----------
create table if not exists public.app_ref_heat (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  material_group text,
  hardness text, depth text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_heat enable row level security;

-- ---------- СОЖ / смазки ----------
create table if not exists public.app_ref_fluids (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  name text,
  purpose text, concentration text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_fluids enable row level security;

-- ---------- Реестр процессов ----------
create table if not exists public.app_ref_processes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null,
  name text not null,
  category text,            -- Административный | Производственный | Вспомогательный
  stages text, inputs text, outputs text, executors text, tools text, time_norm text,
  sort integer default 0,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_processes_idx on public.app_ref_processes (category, sort);
alter table public.app_ref_processes enable row level security;

-- ---------- RPC ----------
create or replace function public.app_ref_fits_list(p_token uuid, p_kind text default null, p_q text default null)
returns table (id uuid, nominal numeric, designation text, kind text, hole_dev text, shaft_dev text, clearance_max numeric, clearance_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.nominal, f.designation, f.kind, f.hole_dev, f.shaft_dev, f.clearance_max, f.clearance_min, f.note
    from public.app_ref_fits f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (p_kind is null or p_kind='' or f.kind = p_kind)
      and (qq='' or lower(f.designation) like '%'||qq||'%')
    order by f.nominal, f.designation;
end $$;

create or replace function public.app_ref_fasteners_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, standard text, size text, material text, coating text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.kind, f.standard, f.size, f.material, f.coating, f.note
    from public.app_ref_fasteners f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (qq='' or lower(f.kind) like '%'||qq||'%' or lower(coalesce(f.standard,'')) like '%'||qq||'%' or lower(coalesce(f.size,'')) like '%'||qq||'%')
    order by f.kind, f.size;
end $$;

create or replace function public.app_ref_heat_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, material_group text, hardness text, depth text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select h.id, h.kind, h.material_group, h.hardness, h.depth, h.note
    from public.app_ref_heat h
    where (h.tenant_id is null or h.tenant_id = ten)
      and (qq='' or lower(h.kind) like '%'||qq||'%' or lower(coalesce(h.material_group,'')) like '%'||qq||'%')
    order by h.kind;
end $$;

create or replace function public.app_ref_fluids_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, name text, purpose text, concentration text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.kind, f.name, f.purpose, f.concentration, f.note
    from public.app_ref_fluids f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (qq='' or lower(f.kind) like '%'||qq||'%' or lower(coalesce(f.name,'')) like '%'||qq||'%')
    order by f.kind, f.name;
end $$;

create or replace function public.app_ref_processes_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, code text, name text, category text, stages text, inputs text, outputs text, executors text, tools text, time_norm text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select p.id, p.code, p.name, p.category, p.stages, p.inputs, p.outputs, p.executors, p.tools, p.time_norm
    from public.app_ref_processes p
    where (p.tenant_id is null or p.tenant_id = ten)
      and (p_category is null or p_category='' or p.category = p_category)
      and (qq='' or lower(p.code) like '%'||qq||'%' or lower(p.name) like '%'||qq||'%' or lower(coalesce(p.executors,'')) like '%'||qq||'%')
    order by p.sort, p.code;
end $$;

grant execute on function public.app_ref_fits_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_fasteners_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_heat_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_fluids_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_processes_list(uuid,text,text) to anon, authenticated;

-- ---------- Наполнение: посадки (пример Ø20) ----------
insert into public.app_ref_fits (tenant_id, nominal, designation, kind, hole_dev, shaft_dev, clearance_max, clearance_min, note)
select null, v.n, v.d, v.k, v.hd, v.sd, v.cmax, v.cmin, v.note
from (values
  (20,'H7/h6','clearance','+0.021/0','0/-0.013',0.034,0.013,'Плотная, центрирование'),
  (20,'H7/g6','clearance','+0.021/0','-0.007/-0.020',0.041,0.007,'Скользящая, смазка'),
  (20,'H7/f7','clearance','+0.021/0','-0.020/-0.041',0.062,0.020,'Ходовая'),
  (20,'H7/e8','clearance','+0.021/0','-0.040/-0.073',0.094,0.040,'Легкоходовая'),
  (20,'H8/d9','clearance','+0.033/0','-0.065/-0.117',0.150,0.065,'Свободная'),
  (20,'H7/k6','transition','+0.021/0','+0.015/+0.002',0.019,-0.015,'Напряжённая'),
  (20,'H7/n6','transition','+0.021/0','+0.028/+0.015',0.006,-0.028,'Плотная переходная'),
  (20,'H7/p6','interference','+0.021/0','+0.035/+0.022',-0.001,-0.035,'Прессовая лёгкая'),
  (20,'H7/s6','interference','+0.021/0','+0.048/+0.035',-0.014,-0.048,'Прессовая'),
  (20,'H11/h11','clearance','+0.130/0','0/-0.130',0.260,0.000,'Грубая')
) as v(n, d, k, hd, sd, cmax, cmin, note)
where not exists (select 1 from public.app_ref_fits where tenant_id is null);

-- ---------- Наполнение: крепёж ----------
insert into public.app_ref_fasteners (tenant_id, kind, standard, size, material, coating, note)
select null, v.kind, v.std, v.size, v.mat, v.coat, v.note
from (values
  ('Болт','ГОСТ 7798-70','М8×30','сталь 8.8','цинк','крепёж общий'),
  ('Болт','ГОСТ 7798-70','М10×40','сталь 8.8','цинк',''),
  ('Гайка','ГОСТ 5915-70','М8','сталь 8','цинк',''),
  ('Гайка','ГОСТ 5915-70','М10','сталь 8','цинк',''),
  ('Шайба','ГОСТ 11371-78','8','сталь','цинк',''),
  ('Винт','ГОСТ 17473-80','М6×20','сталь','оксид','с полукруглой головкой'),
  ('Шпилька','ГОСТ 22032-76','М10×60','сталь 8.8','цинк',''),
  ('Шпонка призматическая','ГОСТ 23360-78','6×6×20','сталь 45','—',''),
  ('Штифт цилиндрический','ГОСТ 3128-70','Ø6×30','сталь','—','фиксация'),
  ('Подшипник','ГОСТ 3478-2012','6204','подшипниковая сталь','—','20×47×14'),
  ('Подшипник','ГОСТ 3478-2012','6205','подшипниковая сталь','—','25×52×15'),
  ('Пружина сжатия','ГОСТ 13764-86','—','65Г','—','по каталогу'),
  ('Кольцо стопорное','ГОСТ 13940-86','Ø20','пружинная сталь','—','')
) as v(kind, std, size, mat, coat, note)
where not exists (select 1 from public.app_ref_fasteners where tenant_id is null);

-- ---------- Наполнение: термообработка/покрытия ----------
insert into public.app_ref_heat (tenant_id, kind, material_group, hardness, depth, note)
select null, v.kind, v.mg, v.hard, v.depth, v.note
from (values
  ('Отжиг','углеродистые/легированные стали','—','—','снятие напряжений, снижение твёрдости'),
  ('Нормализация','конструкционные стали','HB 170-220','—','структурная подготовка'),
  ('Закалка','инструментальные стали','HRC 58-63','—','нагрев + охлаждение'),
  ('Отпуск','инструментальные стали','HRC по назначению','—','после закалки'),
  ('Улучшение','конструкционные стали','HB 220-280','—','закалка + высокий отпуск'),
  ('Цементация','стали 20/20Х','HRC 56-62','0.8-1.2 мм','науглероживание поверхности'),
  ('Азотирование','легированные стали','HV 700-1000','0.2-0.5 мм','высокая поверхностная твёрдость'),
  ('ТВЧ','стали 45/40Х','HRC 50-56','1-3 мм','поверхностная закалка'),
  ('Гальваника (цинк)','любые','—','8-12 мкм','антикоррозия'),
  ('Оксидирование','любые','—','1-3 мкм','декоративно-защитное')
) as v(kind, mg, hard, depth, note)
where not exists (select 1 from public.app_ref_heat where tenant_id is null);

-- ---------- Наполнение: СОЖ/смазки ----------
insert into public.app_ref_fluids (tenant_id, kind, name, purpose, concentration, note)
select null, v.kind, v.name, v.purpose, v.conc, v.note
from (values
  ('СОЖ эмульсия','СОЖ эмульсионная','Точение/фрезерование/сверление', '5-10%','разбавление водой'),
  ('СОЖ синтетическая','СОЖ синтетическая','Высокие скорости, чистота','3-8%','биостойкая'),
  ('СОЖ полусинтетическая','СОЖ полусинтетика','Универсально','5-10%','баланс свойств'),
  ('СОЖ масляная','Масло СОЖ','Резьбонарезание, тяжёлые режимы','—','масляный туман'),
  ('Диэлектрик ЭЭО','Диэлектрик','Проволочная/прошивная ЭЭО','—','деионизованная вода/масло'),
  ('Масло','И-20А','Гидравлика, смазка','—',''),
  ('Масло','ИГСП','Направляющие','—',''),
  ('Смазка','Литол-24','Подшипники, узлы','—',''),
  ('Смазка','Циатим-201','Точные узлы','—','')
) as v(kind, name, purpose, conc, note)
where not exists (select 1 from public.app_ref_fluids where tenant_id is null);

-- ---------- Наполнение: реестр процессов ----------
insert into public.app_ref_processes (tenant_id, code, name, category, stages, inputs, outputs, executors, tools, time_norm, sort)
select null, v.code, v.name, v.cat, v.stages, v.inp, v.out, v.exec, v.tools, v.tn, v.srt
from (values
  ('АД.01','Прием заявок','Административный','Получение заявки → проверка КД → анализ → уточнение → запуск обработки','Первичные данные, чертежи (pdf/jpeg), 3D (.step/.x_t/.m3d), ТЗ','Заявка с комплектом документации','Менеджер/секретарь','ПК, e-mail','150 мин + 4К',1),
  ('АД.05','Обработка запросов на выполнение работ','Административный','Анализ → направление на производство → ТЭО → утверждение','Запрос','ТЭО, КП','Менеджер, начальник производства, гендиректор','ПК, e-mail','90 мин + 2К',2),
  ('АД.02','Выставление ТКП, счёта, договора, спецификации, калькуляции','Административный','Подготовка ТКП → отправка → оформление документов → архив','ТЭО','ТКП, счёт, договор, спецификация, калькуляция','Менеджер, бухгалтерия','ПК, e-mail','135 мин + 5К',3),
  ('АД.03','Подписание договоров','Административный','Проект → согласование → подпись → распоряжение о старте','Заявка, ТКП','Подписанный договор','Менеджер, юрист, гендиректор','ПК','145 мин + 4К',4),
  ('АД.06','Запуск заказов в работу','Административный','Старт (оплата/договор) → СХД → распоряжение → задания','Подписанный договор/оплата','Распоряжение, задания','Ответственный, начальник производства','e-mail','145 мин + 4К',5),
  ('АД.04','Обратная связь и рекламации','Административный','Опрос → ответ → анализ → корректирующие действия','Отгруженная продукция','Отзыв/рекламация, статистика','Менеджер','ПК','100 мин + 3К',6),
  ('АД.07','Кадровые документы, ОТ, воинский учёт','Административный','Запрос данных → согласия → досье','—','Досье, документы','Уполномоченный, кадры','ПК','140 мин + 4К',7),
  ('ПР.21','Внесение заказа в MES, сохранение на сервере','Производственный','Внесение данных в MES/СХД','Данные заказа','Заказ в MES','Менеджер','MES, ПК','—',8),
  ('ПР.01','Технологический расчёт: материалы и трудоёмкость','Производственный','Анализ → технология → время → ТЭО','Заявка','ТЭО, перечень материалов','Технолог, начальник производства','ПК','210 мин + 4К',9),
  ('ПР.02','Конструкторская разработка','Производственный','Модель в сборке → КД деталей → утверждение','Заявка','Конструкторская документация','Главный конструктор','CAD','—',10),
  ('ПР.03','Разработка управляющей программы (УП)','Производственный','Проверка → согласование технологии → написание → апробация','Комплект КД','УП, карта наладки','Инженер-программист','CAM','275 мин + 2Х',11),
  ('ПР.04','Закупка материалов и инструмента','Производственный','Перечень → анализ поставщиков → счета → приёмка → закрытие','Задание на закупку','Материалы/инструмент','Снабженец, бухгалтерия','e-mail, ЭДО','320 мин + 9К',12),
  ('ПР.05','Наладка станка','Производственный','Установка оснастки → привязка → пробный прогон','Задание, УП','Налаженный станок','Оператор ЧПУ','Станок','R',13),
  ('ПР.06','Заготовительная операция','Производственный','Резка/правка заготовок','Материал','Заготовки','Заготовитель','Отрезной станок','R',14),
  ('ПР.07','Токарная обработка','Производственный','Точение по УП/чертежу','Заготовка','Деталь после точения','Оператор ЧПУ','Feeler/Focus','R',15),
  ('ПР.08','Фрезерная обработка','Производственный','Фрезерование по УП','Заготовка','Деталь после фрезеровки','Оператор ЧПУ','Chevalier/Pinnacle','R',16),
  ('ПР.09','Шлифование','Производственный','Плоское/круглое/внутреннее шлифование','Деталь','Деталь после шлифования','Оператор','Chevalier/WASINO/Overbeck','R',17),
  ('ПР.10','Проволочная ЭЭО','Производственный','Вырезка контура проволокой','Деталь','Контур вырезан','Оператор ЭЭО','Mitsubishi FA10-VS','R',18),
  ('ПР.11','Прошивная ЭЭО','Производственный','Прошивка электродом','Деталь, электрод','Полость/отверстие','Оператор ЭЭО','Mitsubishi BA-8/Sodick','R',19),
  ('ПР.13','Гравирование','Производственный','Подготовка → гравирование → контроль','Деталь, задание','Маркировка выполнена','Оператор','Гравировальная установка','R',20),
  ('ПР.15','Вулканизация','Производственный','Подготовка → вулканизация','Деталь/резина','Соединение','Оператор','Вулканизатор','R',21),
  ('ПР.16','Термообработка','Производственный','Передача → обработка → контроль твёрдости','Деталь','Термообработанная деталь','Внешняя организация','Печь','R',22),
  ('ПР.12','Слесарная обработка','Производственный','Доводка, пригонка, сборка','Деталь','Деталь/узел','Слесарь','Верстак','R',23),
  ('ПР.14','Сборочная операция','Производственный','Сборка узла/штампа → примерка','Детали','Собранный узел/штамп','Слесарь-сборщик','—','R',24),
  ('ПР.22','Составление отчётов о работе','Производственный','Сбор данных → отчёт','Данные','Отчёт','Все сотрудники','ПК','—',25),
  ('ПР.24','Формирование отгрузочных документов','Производственный','Комплектование → отгрузочные документы','Готовая продукция','Отгрузочные документы','Ответственный','ПК','R',26),
  ('ПР.25','Маркировка и упаковка продукции','Производственный','Упаковка → маркировка (этикетки/бирки)','Продукция','Упакованная маркированная продукция','Упаковщик','Тара, этикетки','R',27),
  ('ПР.17','Обслуживание','Производственный','ППР, ТО оборудования','Оборудование','Работоспособное оборудование','Операторы, сервис','—','R',28),
  ('ПР.18','Сервис','Производственный','Выезд/поддержка','Заявка','Обслуженный клиент','Сервисный инженер','—','R',29),
  ('ПР.19','Ремонт','Производственный','Диагностика → ремонт','Неисправность','Отремонтированное оборудование','Сервисный инженер','—','R',30),
  ('ПР.20','Парко-хозяйственная деятельность (ПХД)','Производственный','Хозработы','—','—','Операторы','—','R',31),
  ('ПР.23','Служебная переписка','Производственный','Переписка по работе','—','—','Все сотрудники','e-mail','—',32),
  ('ВСП.01','Прием/отправка писем по e-mail','Вспомогательный','Обработка почты','—','—','Все сотрудники','e-mail','—',33),
  ('ВСП.02','Прием корреспонденции и грузов (СДЭК, Деловые линии)','Вспомогательный','Приём груза','Груз','Полученный груз','Ответственный','ТК','К',34),
  ('ВСП.03','Отправка корреспонденции и грузов','Вспомогательный','Упаковка → отправка ТК','Груз','Отправление','Ответственный','ТК','К',35)
) as v(code, name, cat, stages, inp, out, exec, tools, tn, srt)
where not exists (select 1 from public.app_ref_processes where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Посадки ISO 286','Как пользоваться справочником посадок?',
   'Таблица посадок ISO 286 (пример Ø20): тип (зазор/переход/натяг), отклонения отверстия и вала, макс/мин зазор. Используется в КД и ОТК для выбора и контроля посадок.',
   'посадки ISO 286 зазор натяг отклонения квалитет'),
  ('Крепёж','Стандартные изделия',
   'Крепёж по ГОСТ: болты, гайки, шайбы, винты, шпильки, шпонки, штифты, подшипники, пружины, стопорные кольца — с материалом и покрытием. Для спецификаций и закупок.',
   'крепёж ГОСТ болт гайка шайба шпонка подшипник'),
  ('Термообработка','Виды термообработки и покрытий',
   'Отжиг, нормализация, закалка, отпуск, улучшение, цементация, азотирование, ТВЧ, гальваника, оксидирование — с твёрдостью и глубиной. Термообработка на предприятии выполняется сторонней организацией.',
   'термообработка закалка цементация азотирование ТВЧ покрытие'),
  ('СОЖ','СОЖ и смазки',
   'СОЖ (эмульсия/синтетика/полусинтетика/масляная), диэлектрик для ЭЭО, масла И-20А/ИГСП, смазки Литол-24/Циатим-201 — назначение и концентрация.',
   'СОЖ масло смазка диэлектрик эмульсия'),
  ('Процессы','Реестр процессов предприятия',
   'Процессы АД (административные), ПР (производственные) и ВСП (вспомогательные) с этапами, входами/выходами, исполнителями, инструментами и нормой времени (K/W/F/R/X). Основа регламентов и матрицы ответственности.',
   'процессы АД ПР ВСП этапы исполнители регламент')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как пользоваться справочником посадок?');
-- <<<<<<<<<< 0051_ref_norms.sql <<<<<<<<<<

-- >>>>>>>>>> 0052_maintenance.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0052_maintenance.sql  (v32.0 — прототип B15 → продукт «ТОиР»)
-- Обслуживание и ремонт оборудования: планы ТО/ППР, регистрация работ, история, KPI.
-- Связь: оборудование (app_equipment), реестр процессов ПР.17/ПР.19. База знаний.
-- Зависит от 0001..0051.
-- ============================================================

create table if not exists public.app_mnt_plans (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  kind          text not null default 'to1',   -- to1|to2|to3|ppr|repair|service
  title         text,
  period_days   integer,
  last_done     date,
  next_due      date,
  responsible   text,
  active        boolean not null default true,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists app_mnt_plans_idx on public.app_mnt_plans (tenant_id, next_due);
alter table public.app_mnt_plans enable row level security;

create table if not exists public.app_mnt_log (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  plan_id      uuid references public.app_mnt_plans (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  kind         text,
  work_date    date not null default current_date,
  executor     text,
  cost         numeric default 0,
  works        text,
  replaced     text,
  status       text not null default 'done',   -- done|planned
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_mnt_log_idx on public.app_mnt_log (tenant_id, work_date desc);
alter table public.app_mnt_log enable row level security;

-- ---------- KPI ----------
create or replace function public.app_mnt_kpi(p_token uuid)
returns table (plans_total bigint, due bigint, overdue bigint, done_month bigint, cost_month numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active),
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active and p.next_due is not null and p.next_due between current_date and current_date+30),
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active and p.next_due is not null and p.next_due < current_date),
    (select count(*) from public.app_mnt_log l where (urole='admin' or l.tenant_id=ten) and l.work_date >= date_trunc('month', current_date)),
    (select coalesce(sum(l.cost),0) from public.app_mnt_log l where (urole='admin' or l.tenant_id=ten) and l.work_date >= date_trunc('month', current_date));
end $$;

-- ---------- Планы ----------
create or replace function public.app_mnt_plans_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment_id uuid, equipment text, kind text, title text, period_days integer,
               last_done date, next_due date, days_left integer, status text, responsible text, active boolean, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, p.equipment_id, e.name, p.kind, p.title, p.period_days, p.last_done, p.next_due,
      case when p.next_due is null then null else (p.next_due - current_date) end,
      case when p.next_due is null then 'none'
           when p.next_due < current_date then 'overdue'
           when p.next_due < current_date + 30 then 'due'
           else 'ok' end,
      p.responsible, p.active, p.note
    from public.app_mnt_plans p left join public.app_equipment e on e.id = p.equipment_id
    where (urole='admin' or p.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(p.title,'')) like '%'||qq||'%' or lower(coalesce(p.responsible,'')) like '%'||qq||'%')
    order by (p.next_due is null), p.next_due;
end $$;

create or replace function public.app_mnt_plan_save(p_token uuid, p_id uuid, p_equipment_id uuid, p_kind text, p_title text,
  p_period_days integer, p_last_done date, p_next_due date, p_responsible text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; nd date;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief') then return query select false,'Недостаточно прав'; return; end if;
  nd := coalesce(p_next_due, case when p_last_done is not null and p_period_days is not null then p_last_done + p_period_days else null end);
  if p_id is null then
    insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, last_done, next_due, responsible, note)
    values (ten, p_equipment_id, coalesce(nullif(trim(p_kind),''),'to1'), nullif(trim(p_title),''), p_period_days, p_last_done, nd, nullif(trim(p_responsible),''), nullif(trim(p_note),''));
  else
    update public.app_mnt_plans set equipment_id=p_equipment_id, kind=coalesce(nullif(trim(p_kind),''),kind),
      title=nullif(trim(p_title),''), period_days=p_period_days, last_done=p_last_done, next_due=nd,
      responsible=nullif(trim(p_responsible),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Регистрация выполнения (ТО/ремонт) ----------
create or replace function public.app_mnt_register(p_token uuid, p_plan_id uuid, p_equipment_id uuid, p_kind text,
  p_date date, p_executor text, p_cost numeric, p_works text, p_replaced text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; eid uuid; nd date; pd integer; k text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','operator','supply') then return query select false,'Недостаточно прав'; return; end if;

  eid := p_equipment_id; k := p_kind;
  if p_plan_id is not null then
    select p.equipment_id, coalesce(k, p.kind), p.period_days into eid, k, pd
      from public.app_mnt_plans p where p.id = p_plan_id and (urole='admin' or p.tenant_id=ten);
    if eid is null and pd is null then return query select false,'План не найден'; return; end if;
    nd := case when pd is not null then coalesce(p_date,current_date) + pd else null end;
    update public.app_mnt_plans p set last_done = coalesce(p_date, current_date), next_due = nd where p.id = p_plan_id;
  end if;

  insert into public.app_mnt_log (tenant_id, plan_id, equipment_id, kind, work_date, executor, cost, works, replaced, status, note, created_login)
  values (ten, p_plan_id, eid, k, coalesce(p_date,current_date), nullif(trim(p_executor),''), coalesce(p_cost,0),
          nullif(trim(p_works),''), nullif(trim(p_replaced),''), 'done', nullif(trim(p_note),''), ulogin);

  perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief'], 'ТОиР: выполнено', coalesce(p_works,'Работы по обслуживанию'), 'apps/maintenance/index.html');
  return query select true,'Работа зарегистрирована';
end $$;

-- ---------- История ----------
create or replace function public.app_mnt_log_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment text, kind text, work_date date, executor text, cost numeric, works text, replaced text, note text, created_login text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select l.id, e.name, l.kind, l.work_date, l.executor, l.cost, l.works, l.replaced, l.note, l.created_login
    from public.app_mnt_log l left join public.app_equipment e on e.id = l.equipment_id
    where (urole='admin' or l.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(l.works,'')) like '%'||qq||'%' or lower(coalesce(l.executor,'')) like '%'||qq||'%')
    order by l.work_date desc, l.created_at desc;
end $$;

grant execute on function public.app_mnt_kpi(uuid) to anon, authenticated;
grant execute on function public.app_mnt_plans_list(uuid,text) to anon, authenticated;
grant execute on function public.app_mnt_plan_save(uuid,uuid,uuid,text,text,integer,date,date,text,text) to anon, authenticated;
grant execute on function public.app_mnt_register(uuid,uuid,uuid,text,date,text,numeric,text,text,text) to anon, authenticated;
grant execute on function public.app_mnt_log_list(uuid,text) to anon, authenticated;

-- ---------- Демо-планы (тенант A) ----------
insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, last_done, next_due, responsible, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.id, v.kind, v.title, v.period, current_date - v.ago, current_date - v.ago + v.period, 'master', v.note
from public.app_equipment e
join (values
  ('frezerny','to1','ТО-1 фрезерного ЧПУ',30,20,'Ежемесячное ТО'),
  ('tokarny','to2','ТО-2 токарного',90,80,'Квартальное ТО'),
  ('shlifovalny','ppr','ППР шлифовального',180,200,'Просрочено — планировать ППР'),
  ('edm','to1','ТО-1 ЭЭО',30,25,'Проверка диэлектрика')
) as v(kind_eq, kind, title, period, ago, note) on e.kind = v.kind_eq
where not exists (select 1 from public.app_mnt_plans where tenant_id='aaaaaaaa-0000-0000-0000-000000000001')
limit 4;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ТОиР','Как вести обслуживание и ремонт оборудования?',
   'Модуль «Обслуживание и ремонт»: планы ТО/ППР по оборудованию (период, ответственный, следующая дата), регистрация выполненных работ (дата, исполнитель, стоимость, что сделано, что заменено) и история. KPI: всего планов, «истекает» (≤30 дней), «просрочено», выполнено за месяц и суммарные затраты.',
   'ТОиР обслуживание ремонт ППР ТО план оборудование история'),
  ('ТОиР','Связь с процессами и MES',
   'Обслуживание соответствует процессам ПР.17 (обслуживание) и ПР.19 (ремонт). Работы по ТО снижают простои, что отражается в OEE (диспетчерская/аналитика). Просроченные ППР выделяются отдельно — планируйте их заранее.',
   'ТОиР процесс ПР.17 ПР.19 простои OEE ППР')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести обслуживание и ремонт оборудования?');
-- <<<<<<<<<< 0052_maintenance.sql <<<<<<<<<<

