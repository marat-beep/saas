-- 3DMP Service · apply_all.sql — единая схема (0001..0005), идемпотентно.
-- Логины: admin/admin, owner/Owner12345, manager/Manager12345, supplier/Supplier12345.

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
create or replace function public.app_me(p_token uuid)
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
  ('admin',    extensions.crypt('admin',         extensions.gen_salt('bf')), 'Администратор',     'admin'),
  ('owner',    extensions.crypt('Owner12345',    extensions.gen_salt('bf')), 'Собственник 3DMP', 'owner'),
  ('manager',  extensions.crypt('Manager12345',  extensions.gen_salt('bf')), 'Менеджер закупок',  'manager'),
  ('supplier', extensions.crypt('Supplier12345', extensions.gen_salt('bf')), 'Поставщик Демо',    'supplier')
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
create or replace function public.admin_list_users(p_token uuid)
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
