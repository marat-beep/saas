-- 3DMP Service · apply_all.sql — единая схема (0001..0010), идемпотентно.

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
