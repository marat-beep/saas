-- 3DMP Service · apply_all.sql — единая схема (0001..0099), идемпотентно.

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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  update public.app_notifications set read_at = now() where id = p_id and user_id = uid;
end $$;

create or replace function public.app_notif_mark_all(p_token uuid)
returns void language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_production_allowed(uuid);
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
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select w.id, w.code, w.name, w.kind, w.cost_hour, w.active from public.app_work_centers w order by w.name;
end $$;

create or replace function public.app_norms_list(p_token uuid)
returns table (id uuid, operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n order by n.operation;
end $$;

-- ---------- Наряды: список ----------
drop function if exists public.app_naryad_list(uuid);
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id;
end $$;

drop function if exists public.app_naryad_ops(uuid, uuid);
create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_tender_list_full(uuid);
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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

drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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

drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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

drop function if exists public.app_tender_list_full(uuid);
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n
    where (urole = 'admin' or n.tenant_id = ten) order by n.operation;
end $$;

drop function if exists public.app_naryad_list(uuid);
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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

drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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

drop function if exists public.app_naryad_ops(uuid, uuid);
create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_material_list(uuid);
create or replace function public.app_material_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric, low boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_stock_moves_list(uuid, uuid, integer);
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_bom_list(uuid);
create or replace function public.app_bom_list(p_token uuid)
returns table (id uuid, product text, version text, order_number text, lines_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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

drop function if exists public.app_bom_lines_list(uuid, uuid);
create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, name text, qty numeric, unit text, norm_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_schedule(uuid);
create or replace function public.app_schedule(p_token uuid)
returns table (id uuid, number text, title text, wc_name text, assignee text, status text,
               plan_start date, plan_end date, due_date date, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_capacity(uuid);
create or replace function public.app_capacity(p_token uuid)
returns table (wc_id uuid, wc_name text, kind text, cost_hour numeric,
               active_naryads bigint, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_qc_list(uuid);
create or replace function public.app_qc_list(p_token uuid)
returns table (id uuid, number text, product text, status text, inspector text, naryad_number text,
               order_number text, lines_count bigint, defects_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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

drop function if exists public.app_passport_list(uuid);
create or replace function public.app_passport_list(p_token uuid)
returns table (id uuid, number text, product text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.number, p.product, o.number, p.created_at
    from public.app_passports p left join public.app_orders o on o.id = p.order_id
    where (urole='admin' or p.tenant_id = ten) order by p.created_at desc;
end $$;

drop function if exists public.app_passport_get(uuid, uuid);
create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, order_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.kind, r.name, r.rate_hour from public.app_cost_rates r
    where (urole='admin' or r.tenant_id = ten) order by r.kind, r.name;
end $$;

-- ---------- Себестоимость заявки ----------
drop function if exists public.app_order_cost(uuid, uuid);
create or replace function public.app_order_cost(p_token uuid, p_order_id uuid)
returns table (plan_hours numeric, fact_hours numeric, work_cost numeric,
               material_cost numeric, overhead numeric, total numeric, amount numeric, margin numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_economics(uuid);
create or replace function public.app_economics(p_token uuid)
returns table (orders_total bigint, orders_open bigint, naryads_open bigint, naryads_closed bigint,
               plan_hours numeric, fact_hours numeric, defects_open bigint, low_stock bigint, avg_rate numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_tenant_info(uuid);
create or replace function public.app_tenant_info(p_token uuid)
returns table (id uuid, name text, plan text, plan_name text, max_users integer,
               users_count bigint, features jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
begin
  if not public.app_is_owner(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select p.code, p.name, p.price, p.max_users, p.features from public.app_plans p order by p.sort;
end $$;

create or replace function public.app_tenant_set_plan(p_token uuid, p_plan text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_invoice_list(uuid);
create or replace function public.app_invoice_list(p_token uuid)
returns table (id uuid, number text, customer text, order_number text, amount numeric, paid numeric,
               status text, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_employees_list(uuid);
create or replace function public.app_employees_list(p_token uuid)
returns table (id uuid, full_name text, job text, dept text, phone text, active boolean, shifts_month bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_doc_list(uuid, text);
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, amount numeric, status text, version integer, order_number text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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

drop function if exists public.app_doc_get(uuid, uuid);
create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, counterparty text, amount numeric, status text, version integer, content text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_tools_list(uuid);
create or replace function public.app_tools_list(p_token uuid)
returns table (id uuid, name text, serial text, tool_type text, location text,
               last_verified date, next_verified date, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_measuring_tools where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Удалено';
end $$;

-- ---------- Трассируемость ----------
drop function if exists public.app_trace_list(uuid);
create or replace function public.app_trace_list(p_token uuid)
returns table (id uuid, item text, serial text, order_number text, material text, operator text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_production_allowed(uuid);
create or replace function public.app_production_allowed(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.app_session_user(p_token) s
    where public.app_role_is_staff(s.urole)
  );
$$;

-- ---------- Заявки: доступ по ролям предприятия ----------
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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

drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_doc_list(uuid, text);
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, customer_id uuid, customer_name text,
               amount numeric, status text, version integer, order_id uuid, order_number text,
               valid_until date, assignee text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_doc_get(uuid, uuid);
create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, order_number text,
               counterparty text, customer_id uuid, customer_name text, amount numeric, status text, version integer,
               valid_until date, assignee text, signed_at timestamptz, content text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text,
               wc_id uuid, wc_name text, assignee text, status text, priority text,
               plan_hours numeric, fact_hours numeric, start_date date, due_date date, note text,
               created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
drop function if exists public.app_naryad_ops(uuid, uuid);
create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, operation_id uuid, route_step_id uuid, worker text,
               plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_stock_moves_list(uuid, uuid, integer);
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, source text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_passport_get(uuid, uuid);
create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, serial text, qty numeric, status text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               qc_check_id uuid, qc_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_bom_lines_list(uuid, uuid);
create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, material_id uuid, operation_id uuid, name text,
               qty numeric, unit text, norm_hours numeric, price numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
drop function if exists public.app_order_cost(uuid, uuid);
create or replace function public.app_order_cost(p_token uuid, p_order_id uuid)
returns table (plan_hours numeric, fact_hours numeric, work_cost numeric,
               material_cost numeric, overhead numeric, total numeric, amount numeric,
               margin numeric, margin_pct numeric, materials_from_moves boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
#variable_conflict use_column
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
-- >>>>>>>>>> 0053_tooling.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0053_tooling.sql  (v33.0 — прототипы B13/B19 → «Инструмент и стойкость»)
-- Учёт режущего инструмента: ресурс/наработка, заточки, износ, связь с оборудованием.
-- База знаний. Зависит от 0001..0052.
-- ============================================================

create table if not exists public.app_tool_life (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  code          text,
  name          text not null,
  tool_type     text,
  material      text,
  coating       text,
  diameter      numeric,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  resource_min  numeric default 0,     -- ресурс (стойкость), минут
  used_min      numeric default 0,      -- текущая наработка
  wears         integer default 0,      -- число заточек
  max_wears     integer default 3,      -- допустимое число заточек
  status        text not null default 'ok', -- ok|worn|scrapped
  location      text,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists app_tool_life_idx on public.app_tool_life (tenant_id, status);
alter table public.app_tool_life enable row level security;

-- ---------- KPI ----------
create or replace function public.app_tool_kpi(p_token uuid)
returns table (tools_total bigint, worn bigint, scrapped bigint, avg_life numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status<>'scrapped'),
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status='worn'),
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status='scrapped'),
    (select coalesce(round(avg(case when t.resource_min>0 then t.used_min/t.resource_min*100 else 0 end),1),0)
       from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status<>'scrapped');
end $$;

-- ---------- Список ----------
create or replace function public.app_tool_life_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, tool_type text, material text, coating text, diameter numeric,
               equipment text, resource_min numeric, used_min numeric, wears integer, max_wears integer,
               life_pct numeric, status text, location text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.code, t.name, t.tool_type, t.material, t.coating, t.diameter, e.name,
    t.resource_min, t.used_min, t.wears, t.max_wears,
    round(case when t.resource_min>0 then t.used_min/t.resource_min*100 else 0 end, 1),
    t.status, t.location, t.note
    from public.app_tool_life t left join public.app_equipment e on e.id = t.equipment_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(t.name) like '%'||qq||'%' or lower(coalesce(t.code,'')) like '%'||qq||'%' or lower(coalesce(t.tool_type,'')) like '%'||qq||'%' or lower(coalesce(e.name,'')) like '%'||qq||'%')
    order by (t.status='scrapped'), (t.status='worn') desc, t.name;
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_tool_life_save(p_token uuid, p_id uuid, p_code text, p_name text, p_tool_type text,
  p_material text, p_coating text, p_diameter numeric, p_equipment_id uuid, p_resource_min numeric, p_max_wears integer,
  p_location text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','supply','technologist') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_tool_life (tenant_id, code, name, tool_type, material, coating, diameter, equipment_id, resource_min, max_wears, location, note)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_tool_type),''), nullif(trim(p_material),''), nullif(trim(p_coating),''),
            p_diameter, p_equipment_id, coalesce(p_resource_min,0), coalesce(p_max_wears,3), nullif(trim(p_location),''), nullif(trim(p_note),''));
  else
    update public.app_tool_life set code=nullif(trim(p_code),''), name=trim(p_name), tool_type=nullif(trim(p_tool_type),''),
      material=nullif(trim(p_material),''), coating=nullif(trim(p_coating),''), diameter=p_diameter, equipment_id=p_equipment_id,
      resource_min=coalesce(p_resource_min,0), max_wears=coalesce(p_max_wears,3), location=nullif(trim(p_location),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Учёт наработки ----------
create or replace function public.app_tool_life_use(p_token uuid, p_id uuid, p_minutes numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t public.app_tool_life; newused numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_tool_life where id=p_id and (urole='admin' or tenant_id=ten);
  if t.id is null then return query select false,'Инструмент не найден'; return; end if;
  if coalesce(p_minutes,0) <= 0 then return query select false,'Укажите наработку > 0'; return; end if;
  newused := t.used_min + p_minutes;
  update public.app_tool_life set used_min = newused,
    status = case when t.resource_min>0 and newused >= t.resource_min then 'worn' else t.status end
   where id = p_id;
  if t.resource_min>0 and newused >= t.resource_min then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief'], 'Инструмент изношен: '||t.name,
      'Наработка '||round(newused)||' из '||round(t.resource_min)||' мин — требуется заточка/замена', 'apps/tooling/index.html');
  end if;
  return query select true,'Наработка учтена';
end $$;

-- ---------- Заточка ----------
create or replace function public.app_tool_life_resharpen(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t public.app_tool_life; nw integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_tool_life where id=p_id and (urole='admin' or tenant_id=ten);
  if t.id is null then return query select false,'Инструмент не найден'; return; end if;
  nw := t.wears + 1;
  update public.app_tool_life set wears = nw, used_min = 0,
    status = case when nw >= t.max_wears then 'scrapped' else 'ok' end
   where id = p_id;
  if nw >= t.max_wears then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief','supply'], 'Инструмент списан: '||t.name,
      'Ресурс заточек исчерпан ('||nw||'/'||t.max_wears||')', 'apps/tooling/index.html');
    return query select true,'Заточка учтена, ресурс заточек исчерпан — инструмент списан';
  end if;
  return query select true,'Заточка учтена, наработка обнулена';
end $$;

grant execute on function public.app_tool_kpi(uuid) to anon, authenticated;
grant execute on function public.app_tool_life_list(uuid,text) to anon, authenticated;
grant execute on function public.app_tool_life_save(uuid,uuid,text,text,text,text,text,numeric,uuid,numeric,integer,text,text) to anon, authenticated;
grant execute on function public.app_tool_life_use(uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_tool_life_resharpen(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_tool_life (tenant_id, code, name, tool_type, material, coating, diameter, equipment_id, resource_min, used_min, max_wears, status, location)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.tt, v.mat, v.coat, v.dia,
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind=v.eqkind order by name limit 1),
       v.res, v.used, 3, v.st, v.loc
from (values
  ('T-001','Фреза концевая Ø10','Концевая фреза','твердосплав','TIAIN',10,'frezerny',600,180,'ok','инструментальная'),
  ('T-002','Фреза концевая Ø6','Концевая фреза','твердосплав','ALCRN',6,'frezerny',400,360,'ok','инструментальная'),
  ('T-003','Сверло Ø8.5','Сверло','HSS-Co','—',8.5,'sverlilny',240,250,'worn','инструментальная'),
  ('T-004','Метчик М10','Метчик','HSS','—',10,'sverlilny',200,40,'ok','инструментальная'),
  ('T-005','Резец CNMG 120408','Резец','твердосплав','CVD',null,'tokarny',480,120,'ok','инструментальная'),
  ('T-006','Проволока ЭЭО Ø0.25','Проволока','латунь','—',0.25,'edm',3000,3000,'worn','ЭЭО')
) as v(code, name, tt, mat, coat, dia, eqkind, res, used, st, loc)
where not exists (select 1 from public.app_tool_life where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Инструмент','Как вести учёт стойкости инструмента?',
   'Модуль «Инструмент и стойкость»: карточка инструмента (тип, материал, покрытие, Ø, оборудование, ресурс в минутах, допустимое число заточек). Учитывайте наработку — при достижении ресурса инструмент помечается «изношен» и приходит уведомление; после заточки наработка обнуляется, а по исчерпании числа заточек инструмент списывается.',
   'инструмент стойкость наработка ресурс заточка списание'),
  ('Инструмент','Связь с MES и закупками',
   'Наработку инструмента учитывайте при закрытии операций на станке (MES/производство). Списанный инструмент — сигнал снабжению к закупке (реестр инструмента в Справочниках → вкладка «Техданные»).',
   'инструмент MES производство закупка снабжение')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести учёт стойкости инструмента?');
-- <<<<<<<<<< 0053_tooling.sql <<<<<<<<<<
-- >>>>>>>>>> 0054_oee.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0054_oee.sql  (v34.0 — прототип B17 → «OEE-монитор»)
-- Учёт смен по оборудованию: план/работа/простои, годные/всего → OEE (упрощённо).
-- Связь: оборудование, MES, ТОиР, инструмент. База знаний. Зависит от 0001..0053.
-- ============================================================

create table if not exists public.app_oee_log (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  equipment_id   uuid references public.app_equipment (id) on delete set null,
  shift_date     date not null default current_date,
  shift          text,           -- 1|2|night
  planned_min    numeric default 0,
  run_min        numeric default 0,
  downtime_min   numeric default 0,
  downtime_reason text,
  good_qty       numeric default 0,
  total_qty      numeric default 0,
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_oee_log_idx on public.app_oee_log (tenant_id, shift_date desc);
alter table public.app_oee_log enable row level security;

-- ---------- Список ----------
create or replace function public.app_oee_log_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment_id uuid, equipment text, shift_date date, shift text,
               planned_min numeric, run_min numeric, downtime_min numeric, downtime_reason text,
               good_qty numeric, total_qty numeric, availability numeric, quality numeric, oee numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select o.id, o.equipment_id, e.name, o.shift_date, o.shift, o.planned_min, o.run_min, o.downtime_min, o.downtime_reason,
      o.good_qty, o.total_qty,
      round(case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min*100 else 0 end,1),
      round(case when o.total_qty>0 then o.good_qty/o.total_qty*100 else 0 end,1),
      round((case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min else 0 end)
          * (case when o.total_qty>0 then o.good_qty/o.total_qty else 0 end) * 100, 1),
      o.note
    from public.app_oee_log o left join public.app_equipment e on e.id = o.equipment_id
    where (urole='admin' or o.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(o.downtime_reason,'')) like '%'||qq||'%')
    order by o.shift_date desc, e.name;
end $$;

-- ---------- KPI ----------
create or replace function public.app_oee_kpi(p_token uuid)
returns table (records bigint, avg_oee numeric, avg_availability numeric, avg_quality numeric, downtime_total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*),
    coalesce(round(avg((case when planned_min>0 then least(run_min,planned_min)/planned_min else 0 end)
                       * (case when total_qty>0 then good_qty/total_qty else 0 end) * 100),1),0),
    coalesce(round(avg(case when planned_min>0 then least(run_min,planned_min)/planned_min*100 else 0 end),1),0),
    coalesce(round(avg(case when total_qty>0 then good_qty/total_qty*100 else 0 end),1),0),
    coalesce(sum(downtime_min),0)
    from public.app_oee_log where (urole='admin' or tenant_id = ten);
end $$;

-- ---------- OEE по оборудованию ----------
create or replace function public.app_oee_by_equipment(p_token uuid)
returns table (equipment text, records bigint, avg_oee numeric, downtime_total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(e.name,'—'), count(*),
      coalesce(round(avg((case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min else 0 end)
                         * (case when o.total_qty>0 then o.good_qty/o.total_qty else 0 end) * 100),1),0),
      coalesce(sum(o.downtime_min),0)
    from public.app_oee_log o left join public.app_equipment e on e.id = o.equipment_id
    where (urole='admin' or o.tenant_id = ten)
    group by coalesce(e.name,'—')
    order by 3 desc;
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_oee_save(p_token uuid, p_id uuid, p_equipment_id uuid, p_date date, p_shift text,
  p_planned numeric, p_run numeric, p_downtime numeric, p_reason text, p_good numeric, p_total numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','operator') then return query select false,'Недостаточно прав'; return; end if;
  if p_equipment_id is null then return query select false,'Выберите оборудование'; return; end if;
  if coalesce(p_planned,0) <= 0 then return query select false,'Укажите плановое время > 0'; return; end if;
  if p_id is null then
    insert into public.app_oee_log (tenant_id, equipment_id, shift_date, shift, planned_min, run_min, downtime_min, downtime_reason, good_qty, total_qty, note, created_login)
    values (ten, p_equipment_id, coalesce(p_date,current_date), nullif(trim(p_shift),''), p_planned, coalesce(p_run,0), coalesce(p_downtime,0),
            nullif(trim(p_reason),''), coalesce(p_good,0), coalesce(p_total,0), nullif(trim(p_note),''), ulogin);
  else
    update public.app_oee_log set equipment_id=p_equipment_id, shift_date=coalesce(p_date,shift_date), shift=nullif(trim(p_shift),''),
      planned_min=p_planned, run_min=coalesce(p_run,0), downtime_min=coalesce(p_downtime,0), downtime_reason=nullif(trim(p_reason),''),
      good_qty=coalesce(p_good,0), total_qty=coalesce(p_total,0), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

grant execute on function public.app_oee_log_list(uuid,text) to anon, authenticated;
grant execute on function public.app_oee_kpi(uuid) to anon, authenticated;
grant execute on function public.app_oee_by_equipment(uuid) to anon, authenticated;
grant execute on function public.app_oee_save(uuid,uuid,uuid,date,text,numeric,numeric,numeric,text,numeric,numeric,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_oee_log (tenant_id, equipment_id, shift_date, shift, planned_min, run_min, downtime_min, downtime_reason, good_qty, total_qty, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.id, current_date - v.d, v.sh, 480, v.run, v.dt, v.reason, v.good, v.total, 'master'
from public.app_equipment e
join (values
  ('frezerny',1,'1',420,60,'переналадка',95,100),
  ('frezerny',2,'1',400,80,'ожидание материала',90,98),
  ('tokarny',1,'1',440,40,'инструмент',98,100),
  ('edm',1,'1',300,180,'поломка/ремонт',40,50)
) as v(eqkind, d, sh, run, dt, reason, good, total) on e.kind = v.eqkind
where not exists (select 1 from public.app_oee_log where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('OEE','Что такое OEE и как его вести?',
   'OEE — общая эффективность оборудования. Упрощённо: OEE = Доступность × Качество, где Доступность = работа/план, Качество = годные/всего. Ведите по сменам: плановое время, фактическая работа, простои с причиной, годные/всего. В модуле видно средний OEE, доступность, качество, суммарные простои и рейтинг оборудования.',
   'OEE эффективность доступность качество простои смена оборудование'),
  ('OEE','Как снижать простои?',
   'Анализируйте причины простоев (переналадка, ожидание материала, поломка/ремонт, инструмент). Поломки ведут в ТОиР, износ инструмента — в «Инструмент и стойкость», ожидание материала — в склад/закупки. Рейтинг оборудования показывает, где теряется эффективность.',
   'OEE простои причины ТОиР инструмент склад переналадка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что такое OEE и как его вести?');
-- <<<<<<<<<< 0054_oee.sql <<<<<<<<<<
-- >>>>>>>>>> 0055_terminal_kb.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0055_terminal_kb.sql  (v35.0 — база знаний для «Пульт оператора», B22)
-- Зависит от 0001..0054.
-- ============================================================

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Пульт оператора','Как работать в мобильном пульте оператора?',
   'Откройте «Пульт оператора» на телефоне (можно установить как приложение — PWA). Видны операции: свои (фильтр «только мои») и по выбранному рабочему центру. Кнопки: «Запустить» → «Пауза»/«Продолжить» → «Готово». При завершении можно ввести факт часов. Статусы синхронизированы с «Производством» и «Диспетчерской» (MES).',
   'пульт оператора мобильный PWA операции MES запуск пауза готово факт'),
  ('Пульт оператора','Связь с MES, OEE и инструментом',
   'Пульт использует операции нарядов (тот же источник, что MES). Завершение операций влияет на прогресс наряда и на данные для OEE; износ инструмента учитывайте в модуле «Инструмент и стойкость», простои — в «OEE-мониторе».',
   'пульт оператора MES OEE инструмент наряд факт часов')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как работать в мобильном пульте оператора?');
-- <<<<<<<<<< 0055_terminal_kb.sql <<<<<<<<<<
-- >>>>>>>>>> 0056_crm.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0056_crm.sql  (v36.0 — ЭПИК A: CRM / сделки, прототипы B12/A14)
-- Воронка сделок по заказчикам, стадии, суммы/вероятность, связь с заявкой.
-- База знаний. Зависит от 0001..0055.
-- ============================================================

create table if not exists public.app_deals (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  customer_id uuid references public.app_customers (id) on delete set null,
  title       text not null,
  stage       text not null default 'lead', -- lead|qualified|proposal|negotiation|won|lost
  amount      numeric,
  probability integer default 10,
  source      text,
  owner_login text,
  next_action text,
  due_date    date,
  order_id    uuid references public.app_orders (id) on delete set null,
  note        text,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_deals_idx on public.app_deals (tenant_id, stage);
alter table public.app_deals enable row level security;

-- ---------- Список ----------
create or replace function public.app_deal_list(p_token uuid, p_q text default null)
returns table (id uuid, customer_id uuid, customer text, title text, stage text, amount numeric, probability integer,
               weighted numeric, source text, owner_login text, next_action text, due_date date, order_id uuid, order_number text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.customer_id, c.name, d.title, d.stage, d.amount, d.probability,
      round(coalesce(d.amount,0)*coalesce(d.probability,0)/100.0, 2), d.source, d.owner_login, d.next_action, d.due_date, d.order_id, o.number, d.note
    from public.app_deals d
    left join public.app_customers c on c.id = d.customer_id
    left join public.app_orders o on o.id = d.order_id
    where (urole='admin' or d.tenant_id = ten)
      and (qq='' or lower(d.title) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%' or lower(coalesce(d.owner_login,'')) like '%'||qq||'%')
    order by case d.stage when 'negotiation' then 0 when 'proposal' then 1 when 'qualified' then 2 when 'lead' then 3 when 'won' then 4 else 5 end, d.updated_at desc;
end $$;

-- ---------- KPI ----------
create or replace function public.app_deal_kpi(p_token uuid)
returns table (deals_total bigint, open_deals bigint, pipeline numeric, won_sum numeric, won_count bigint, conversion numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*),
    count(*) filter (where stage not in ('won','lost')),
    coalesce(sum(coalesce(amount,0)*coalesce(probability,0)/100.0) filter (where stage not in ('won','lost')),0),
    coalesce(sum(amount) filter (where stage='won'),0),
    count(*) filter (where stage='won'),
    case when count(*) filter (where stage in ('won','lost')) > 0
         then round(100.0 * count(*) filter (where stage='won') / count(*) filter (where stage in ('won','lost')),1) else 0 end
    from public.app_deals where (urole='admin' or tenant_id = ten);
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_deal_save(p_token uuid, p_id uuid, p_customer_id uuid, p_title text, p_stage text,
  p_amount numeric, p_probability integer, p_source text, p_owner text, p_next_action text, p_due_date date, p_order_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите название сделки'; return; end if;
  if p_id is null then
    insert into public.app_deals (tenant_id, customer_id, title, stage, amount, probability, source, owner_login, next_action, due_date, order_id, note, created_login)
    values (ten, p_customer_id, trim(p_title), coalesce(nullif(trim(p_stage),''),'lead'), p_amount, coalesce(p_probability,10),
            nullif(trim(p_source),''), nullif(trim(p_owner),''), nullif(trim(p_next_action),''), p_due_date, p_order_id, nullif(trim(p_note),''), ulogin);
  else
    update public.app_deals set customer_id=p_customer_id, title=trim(p_title), stage=coalesce(nullif(trim(p_stage),''),stage),
      amount=p_amount, probability=coalesce(p_probability,probability), source=nullif(trim(p_source),''), owner_login=nullif(trim(p_owner),''),
      next_action=nullif(trim(p_next_action),''), due_date=p_due_date, order_id=p_order_id, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сделка сохранена';
end $$;

-- ---------- Смена стадии ----------
create or replace function public.app_deal_set_stage(p_token uuid, p_id uuid, p_stage text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_stage not in ('lead','qualified','proposal','negotiation','won','lost') then return query select false,'Неверная стадия'; return; end if;
  select d.title, d.tenant_id into t from public.app_deals d where d.id = p_id and (urole='admin' or d.tenant_id=ten);
  if t.title is null then return query select false,'Сделка не найдена'; return; end if;
  update public.app_deals set stage=p_stage, updated_at=now() where id=p_id;
  if p_stage = 'won' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director'], 'Сделка выиграна: '||t.title, '', 'apps/crm/index.html');
  end if;
  return query select true,'Стадия обновлена';
end $$;

grant execute on function public.app_deal_list(uuid,text) to anon, authenticated;
grant execute on function public.app_deal_kpi(uuid) to anon, authenticated;
grant execute on function public.app_deal_save(uuid,uuid,uuid,text,text,numeric,integer,text,text,text,date,uuid,text) to anon, authenticated;
grant execute on function public.app_deal_set_stage(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_deals (tenant_id, customer_id, title, stage, amount, probability, source, owner_login, next_action, due_date)
select 'aaaaaaaa-0000-0000-0000-000000000001',
       (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
       v.title, v.stage, v.amount, v.prob, 'входящая', 'manager', v.next, current_date + v.days
from (values
  ('Изготовление пресс-формы', 'negotiation', 850000, 60, 'согласовать ТЗ', 5),
  ('Партия штампов (5 шт)', 'proposal', 1200000, 40, 'отправить КП', 3),
  ('Реверс-инжиниринг детали', 'qualified', 180000, 25, 'оценка трудоёмкости', 7),
  ('Кронштейны, серия', 'won', 39167.09, 100, 'выставить счёт', 0)
) as v(title, stage, amount, prob, next, days)
where not exists (select 1 from public.app_deals where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('CRM','Как вести воронку сделок?',
   'Модуль «CRM»: сделки по заказчикам со стадиями (лид → квалифицирован), предложение, переговоры, выиграна/проиграна), суммой и вероятностью. Взвешенная сумма = сумма × вероятность. KPI: сделок, открытых, воронка (взвешенная), выиграно (сумма/число), конверсия. Сделку можно связать с заявкой.',
   'CRM воронка сделки стадии сумма вероятность конверсия'),
  ('CRM','Связь CRM с заявками и ТКП',
   'Сделка ведёт к заявке (модуль «Заявки») и КП/ТКП (модуль «Документы»/реестр ТКП). При выигрыше сделки приходит уведомление. Так продажи связаны с производством и финансами.',
   'CRM заявка ТКП КП сделка связь продажи')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести воронку сделок?');
-- <<<<<<<<<< 0056_crm.sql <<<<<<<<<<
-- >>>>>>>>>> 0057_tkp.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0057_tkp.sql  (v36.1 — ЭПИК A: реестр ТКП)
-- Технико-коммерческие предложения: номер, контрагент, срок, цена, статусы.
-- Связь с заявкой/документом. База знаний. Зависит от 0001..0056.
-- ============================================================

create sequence if not exists public.app_tkp_seq;

create table if not exists public.app_tkp_registry (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text,
  tkp_date     date not null default current_date,
  counterparty text,
  customer_id  uuid references public.app_customers (id) on delete set null,
  subject      text not null,
  valid_until  date,
  price        numeric,
  status       text not null default 'actual',  -- actual|expired|contracted|closed
  order_id     uuid references public.app_orders (id) on delete set null,
  document_id  uuid references public.app_documents (id) on delete set null,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_tkp_idx on public.app_tkp_registry (tenant_id, status);
alter table public.app_tkp_registry enable row level security;

create or replace function public.app_tkp_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, tkp_date date, counterparty text, customer text, subject text, valid_until date,
               price numeric, status text, order_id uuid, order_number text, document_number text, note text, expired boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select t.id, t.number, t.tkp_date, t.counterparty, c.name, t.subject, t.valid_until, t.price, t.status, t.order_id, o.number, d.number, t.note,
      (t.valid_until is not null and t.valid_until < current_date and t.status = 'actual')
    from public.app_tkp_registry t
    left join public.app_customers c on c.id = t.customer_id
    left join public.app_orders o on o.id = t.order_id
    left join public.app_documents d on d.id = t.document_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(coalesce(t.number,'')) like '%'||qq||'%' or lower(t.subject) like '%'||qq||'%' or lower(coalesce(t.counterparty,'')) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%')
    order by t.tkp_date desc, t.created_at desc;
end $$;

create or replace function public.app_tkp_save(p_token uuid, p_id uuid, p_customer_id uuid, p_counterparty text, p_subject text,
  p_valid_until date, p_price numeric, p_order_id uuid, p_document_id uuid, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_subject),'') = '' then raise exception 'Укажите предмет ТКП'; return; end if;
  if p_id is null then
    tnum := 'TKP-' || lpad(nextval('public.app_tkp_seq')::text, 5, '0');
    insert into public.app_tkp_registry (tenant_id, number, counterparty, customer_id, subject, valid_until, price, order_id, document_id, note, created_login)
    values (ten, tnum, nullif(trim(p_counterparty),''), p_customer_id, trim(p_subject), p_valid_until, p_price, p_order_id, p_document_id, nullif(trim(p_note),''), ulogin)
    returning id into tid;
    return query select tid, tnum, 'ТКП добавлено';
  else
    update public.app_tkp_registry set counterparty=nullif(trim(p_counterparty),''), customer_id=p_customer_id, subject=trim(p_subject),
      valid_until=p_valid_until, price=p_price, order_id=p_order_id, document_id=p_document_id, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into tid, tnum;
    return query select tid, tnum, 'ТКП обновлено';
  end if;
end $$;

create or replace function public.app_tkp_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('actual','expired','contracted','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_tkp_registry set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус ТКП обновлён';
end $$;

grant execute on function public.app_tkp_list(uuid,text) to anon, authenticated;
grant execute on function public.app_tkp_save(uuid,uuid,uuid,text,text,date,numeric,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_tkp_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_tkp_registry (tenant_id, number, counterparty, customer_id, subject, valid_until, price, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'TKP-' || lpad(nextval('public.app_tkp_seq')::text, 5, '0'),
       c.name, c.id, v.subject, current_date + v.days, v.price, v.status, 'manager'
from public.app_customers c
join (values ('Изготовление штампа Ш-001', 30, 1000000, 'actual'), ('Оснастка, комплект', -5, 250000, 'expired')) as v(subject, days, price, status)
  on c.name = (select name from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1)
where not exists (select 1 from public.app_tkp_registry where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ТКП','Что такое реестр ТКП?',
   'Реестр технико-коммерческих предложений: номер (TKP-NNNNN), дата, контрагент/заказчик, предмет, срок действия, цена и статус (Актуальное/Истёк срок/Заключён договор/Закрыто). Просроченные по сроку (но ещё «Актуальные») выделяются. ТКП связывается с заявкой и КП.',
   'ТКП реестр предложение срок цена статус контрагент')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что такое реестр ТКП?');
-- <<<<<<<<<< 0057_tkp.sql <<<<<<<<<<
-- >>>>>>>>>> 0058_client.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0058_client.sql  (v36.2 — ЭПИК A: кабинет заказчика, прототип A3)
-- Роль `client` (внешний заказчик): привязка к заказчику + read-проекции
-- (заявки, документы, счета, ТКП). База знаний. Зависит от 0001..0057.
-- ============================================================

create table if not exists public.app_client_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  app_user_id uuid references public.app_users (id) on delete cascade,
  customer_id uuid references public.app_customers (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (app_user_id, customer_id)
);
create index if not exists app_client_links_idx on public.app_client_links (app_user_id);
alter table public.app_client_links enable row level security;

-- ---------- Контекст клиента ----------
create or replace function public.app_client_context(p_token uuid)
returns table (customer_id uuid, customer text, tenant_name text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select l.customer_id, c.name, t.name
    from public.app_client_links l
    join public.app_customers c on c.id = l.customer_id
    left join public.tenants t on t.id = l.tenant_id
    where l.app_user_id = uid;
end $$;

-- ---------- Заявки клиента ----------
create or replace function public.app_client_orders(p_token uuid)
returns table (number text, title text, status text, priority text, due_date date, amount numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select o.number, o.title, o.status, o.priority, o.due_date, o.amount, o.created_at
    from public.app_orders o
    where o.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by o.created_at desc;
end $$;

-- ---------- Документы клиента ----------
create or replace function public.app_client_docs(p_token uuid)
returns table (number text, doc_type text, title text, status text, amount numeric, valid_until date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select d.number, d.doc_type, d.title, d.status, d.amount, d.valid_until, d.created_at
    from public.app_documents d
    where d.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by d.created_at desc;
end $$;

-- ---------- Счета клиента ----------
create or replace function public.app_client_invoices(p_token uuid)
returns table (number text, amount numeric, paid numeric, balance numeric, status text, due_date date, is_overdue boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select i.number, i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue'))
    from public.app_invoices i
    where i.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by i.created_at desc;
end $$;

-- ---------- ТКП клиента ----------
create or replace function public.app_client_tkp(p_token uuid)
returns table (number text, subject text, valid_until date, price numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select t.number, t.subject, t.valid_until, t.price, t.status, t.created_at
    from public.app_tkp_registry t
    where t.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by t.created_at desc;
end $$;

grant execute on function public.app_client_context(uuid) to anon, authenticated;
grant execute on function public.app_client_orders(uuid) to anon, authenticated;
grant execute on function public.app_client_docs(uuid) to anon, authenticated;
grant execute on function public.app_client_invoices(uuid) to anon, authenticated;
grant execute on function public.app_client_tkp(uuid) to anon, authenticated;

-- ---------- Демо: клиентский доступ (тенант A) ----------
insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values ('client', extensions.crypt('client', extensions.gen_salt('bf')), 'Клиент (портал)', 'client', 'aaaaaaaa-0000-0000-0000-000000000001')
on conflict (login) do update set role='client', tenant_id=excluded.tenant_id, full_name=excluded.full_name;

insert into public.app_client_links (tenant_id, app_user_id, customer_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', u.id, c.id
from public.app_users u, public.app_customers c
where u.login='client'
  and c.id = (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1)
  and not exists (select 1 from public.app_client_links where app_user_id=u.id and customer_id=c.id);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кабинет заказчика','Как клиент видит свои заказы?',
   'Внешний заказчик входит под ролью client и видит только свои данные: заявки (статусы, суммы, сроки), документы (КП/договор/акт), счета (оплачено/остаток/просрочка) и ТКП. Доступ привязан к карточке заказчика (CRM) через связку «пользователь ↔ заказчик».',
   'кабинет заказчика client роль заявки документы счета ТКП портал')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как клиент видит свои заказы?');
-- <<<<<<<<<< 0058_client.sql <<<<<<<<<<
-- >>>>>>>>>> 0059_nc.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0059_nc.sql  (v37 — ЭПИК B: реестр УП / прототипы B18/B27)
-- Управляющие программы: заказ, деталь, станок, номер, версия, время, статус, файлы.
-- Расширен список типов вложений (nc и др.). База знаний. Зависит от 0001..0058.
-- ============================================================

create table if not exists public.app_nc_programs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  order_id      uuid references public.app_orders (id) on delete set null,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  detail        text not null,
  program_no    text,
  version       integer not null default 1,
  program_time_min numeric,
  status        text not null default 'draft', -- draft|approved|archive
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_nc_idx on public.app_nc_programs (tenant_id, status);
alter table public.app_nc_programs enable row level security;

-- ---------- Расширить типы вложений ----------
create or replace function public.app_attachment_add(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_data text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; ten uuid; aid uuid; bytes bytea;
        allowed text[] := array['order','document','qc','passport','naryad','tender','nc','issue','service','tkp','deal','client'];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (p_entity_type = any(allowed)) then raise exception 'Неизвестный тип сущности'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите имя файла'; end if;
  begin bytes := decode(p_data, 'base64'); exception when others then raise exception 'Некорректные данные файла'; end;
  if octet_length(bytes) > 8388608 then raise exception 'Файл больше 8 МБ'; end if;
  insert into public.app_attachments (tenant_id, entity_type, entity_id, name, mime, size, data, uploaded_by)
  values (ten, p_entity_type, p_entity_id, trim(p_name), nullif(trim(p_mime),''), octet_length(bytes), bytes, ulogin)
  returning app_attachments.id into aid;
  return query select aid, trim(p_name);
end $$;

-- ---------- RPC ----------
create or replace function public.app_nc_list(p_token uuid, p_q text default null)
returns table (id uuid, order_id uuid, order_number text, equipment_id uuid, equipment text, detail text,
               program_no text, version integer, program_time_min numeric, status text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select n.id, n.order_id, o.number, n.equipment_id, e.name, n.detail, n.program_no, n.version, n.program_time_min, n.status, n.note, n.created_at
    from public.app_nc_programs n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_equipment e on e.id = n.equipment_id
    where (urole='admin' or n.tenant_id = ten)
      and (qq='' or lower(n.detail) like '%'||qq||'%' or lower(coalesce(n.program_no,'')) like '%'||qq||'%' or lower(coalesce(o.number,'')) like '%'||qq||'%')
    order by n.created_at desc;
end $$;

create or replace function public.app_nc_kpi(p_token uuid)
returns table (programs bigint, approved bigint, draft bigint, total_min numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*),
    count(*) filter (where status='approved'),
    count(*) filter (where status='draft'),
    coalesce(sum(program_time_min),0)
    from public.app_nc_programs where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_nc_save(p_token uuid, p_id uuid, p_order_id uuid, p_equipment_id uuid, p_detail text,
  p_program_no text, p_time numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','technologist','master') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_detail),'') = '' then return query select false,'Укажите деталь'; return; end if;
  if p_id is null then
    insert into public.app_nc_programs (tenant_id, order_id, equipment_id, detail, program_no, program_time_min, note, created_login)
    values (ten, p_order_id, p_equipment_id, trim(p_detail), nullif(trim(p_program_no),''), p_time, nullif(trim(p_note),''), ulogin);
  else
    update public.app_nc_programs set order_id=p_order_id, equipment_id=p_equipment_id, detail=trim(p_detail),
      program_no=nullif(trim(p_program_no),''), program_time_min=p_time, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'УП сохранена';
end $$;

create or replace function public.app_nc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('draft','approved','archive') then return query select false,'Неверный статус'; return; end if;
  update public.app_nc_programs set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус УП обновлён';
end $$;

grant execute on function public.app_nc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_nc_kpi(uuid) to anon, authenticated;
grant execute on function public.app_nc_save(uuid,uuid,uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_nc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_nc_programs (tenant_id, order_id, equipment_id, detail, program_no, version, program_time_min, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
       (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind='frezerny' order by name limit 1),
       v.detail, v.pno, 1, v.tm, v.st, 'technologist'
from (values ('Пуансон, Ш-001.01.01','УП010135',480,'approved'), ('Матрица, Ш-001.02.01','УП010136',720,'draft')) as v(detail, pno, tm, st)
where not exists (select 1 from public.app_nc_programs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('УП/NC','Как вести реестр управляющих программ?',
   'Модуль «УП/NC»: программа привязывается к заказу и станку, указывается деталь, номер программы (напр. УП010135), версия, время обработки и статус (черновик/апробирована/архив). Файлы программы прикрепляются к карточке. KPI: программ, апробировано, черновиков, суммарное время.',
   'УП NC управляющая программа реестр версия станок деталь G-код'),
  ('УП/NC','Связь УП с производством',
   'УП выбирается при наладке и выполнении операций (диспетчерская/производство). Время обработки из УП используется для нормирования и плана. Файлы УП хранятся в карточке (до 8 МБ).',
   'УП NC наладка операция нормирование производство файлы')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести реестр управляющих программ?');
-- <<<<<<<<<< 0059_nc.sql <<<<<<<<<<
-- >>>>>>>>>> 0060_issues_service.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0060_issues_service.sql  (v38 — ЭПИК C: эскалация B24 + сервис B29)
-- app_issues (проблемы/эскалация/SLA) и app_service_requests (заявки на сервис/ремонт).
-- База знаний. Зависит от 0001..0059.
-- ============================================================

create table if not exists public.app_issues (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  title        text not null,
  description  text,
  priority     text not null default 'normal', -- low|normal|high|critical
  source       text,
  status       text not null default 'open',   -- open|in_progress|resolved|closed
  assignee     text,
  due_date     date,
  escalated    boolean not null default false,
  escalated_at timestamptz,
  order_id     uuid references public.app_orders (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_issues_idx on public.app_issues (tenant_id, status, priority);
alter table public.app_issues enable row level security;

create sequence if not exists public.app_service_seq;
create table if not exists public.app_service_requests (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  customer_id   uuid references public.app_customers (id) on delete set null,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  title         text not null,
  kind          text not null default 'service', -- service|repair|warranty
  status        text not null default 'new',     -- new|scheduled|in_progress|done|cancelled
  scheduled_date date,
  engineer      text,
  works         text,
  cost          numeric,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_service_idx on public.app_service_requests (tenant_id, status);
alter table public.app_service_requests enable row level security;

-- ---------- Проблемы ----------
create or replace function public.app_issue_list(p_token uuid, p_q text default null)
returns table (id uuid, title text, priority text, status text, assignee text, due_date date, escalated boolean,
               order_number text, equipment text, created_at timestamptz, overdue boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select i.id, i.title, i.priority, i.status, i.assignee, i.due_date, i.escalated, o.number, e.name, i.created_at,
      (i.due_date is not null and i.due_date < current_date and i.status not in ('resolved','closed'))
    from public.app_issues i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_equipment e on e.id = i.equipment_id
    where (urole='admin' or i.tenant_id = ten)
      and (qq='' or lower(i.title) like '%'||qq||'%' or lower(coalesce(i.assignee,'')) like '%'||qq||'%')
    order by (i.status in ('resolved','closed')), case i.priority when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, i.created_at desc;
end $$;

create or replace function public.app_issue_kpi(p_token uuid)
returns table (issues_open bigint, critical bigint, escalated bigint, overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*) filter (where status not in ('resolved','closed')),
    count(*) filter (where priority='critical' and status not in ('resolved','closed')),
    count(*) filter (where escalated and status not in ('resolved','closed')),
    count(*) filter (where due_date is not null and due_date < current_date and status not in ('resolved','closed'))
    from public.app_issues where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_issue_save(p_token uuid, p_id uuid, p_title text, p_description text, p_priority text,
  p_assignee text, p_due_date date, p_order_id uuid, p_equipment_id uuid, p_source text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','qc','supply','technologist','operator') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему'; return; end if;
  if p_id is null then
    insert into public.app_issues (tenant_id, title, description, priority, assignee, due_date, order_id, equipment_id, source, created_login)
    values (ten, trim(p_title), nullif(trim(p_description),''), coalesce(nullif(trim(p_priority),''),'normal'),
            nullif(trim(p_assignee),''), p_due_date, p_order_id, p_equipment_id, nullif(trim(p_source),''), ulogin);
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief'],
      'Новая проблема: '||trim(p_title), coalesce(nullif(trim(p_priority),''),'normal'), 'apps/issues/index.html');
  else
    update public.app_issues set title=trim(p_title), description=nullif(trim(p_description),''),
      priority=coalesce(nullif(trim(p_priority),''),priority), assignee=nullif(trim(p_assignee),''), due_date=p_due_date,
      order_id=p_order_id, equipment_id=p_equipment_id, source=nullif(trim(p_source),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_issue_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('open','in_progress','resolved','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_issues set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_issue_escalate(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select title into t from public.app_issues where id=p_id and (urole='admin' or tenant_id=ten);
  if t is null then return query select false,'Проблема не найдена'; return; end if;
  update public.app_issues set escalated=true, escalated_at=now(), priority='critical', updated_at=now() where id=p_id;
  perform public.app_notif_roles_t(ten, array['admin','owner','director','manager'], 'ЭСКАЛАЦИЯ: '||t, coalesce(p_note,''), 'apps/issues/index.html');
  return query select true,'Проблема эскалирована руководству';
end $$;

-- ---------- Заявки на сервис ----------
create or replace function public.app_service_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, customer text, equipment text, title text, kind text, status text,
               scheduled_date date, engineer text, cost numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.number, c.name, e.name, s.title, s.kind, s.status, s.scheduled_date, s.engineer, s.cost, s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    where (urole='admin' or s.tenant_id = ten)
      and (qq='' or lower(s.title) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%' or lower(coalesce(s.engineer,'')) like '%'||qq||'%')
    order by s.created_at desc;
end $$;

create or replace function public.app_service_kpi(p_token uuid)
returns table (requests bigint, open bigint, done bigint, cost_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status not in ('done','cancelled')),
    count(*) filter (where status='done'), coalesce(sum(cost),0)
    from public.app_service_requests where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_service_save(p_token uuid, p_id uuid, p_customer_id uuid, p_equipment_id uuid,
  p_title text, p_kind text, p_scheduled_date date, p_engineer text, p_works text, p_cost numeric, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid; snum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите тему'; return; end if;
  if p_id is null then
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests (tenant_id, number, customer_id, equipment_id, title, kind, scheduled_date, engineer, works, cost, note, created_login)
    values (ten, snum, p_customer_id, p_equipment_id, trim(p_title), coalesce(nullif(trim(p_kind),''),'service'), p_scheduled_date,
            nullif(trim(p_engineer),''), nullif(trim(p_works),''), p_cost, nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, snum, 'Заявка создана';
  else
    update public.app_service_requests set customer_id=p_customer_id, equipment_id=p_equipment_id, title=trim(p_title),
      kind=coalesce(nullif(trim(p_kind),''),kind), scheduled_date=p_scheduled_date, engineer=nullif(trim(p_engineer),''),
      works=nullif(trim(p_works),''), cost=p_cost, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into sid, snum;
    return query select sid, snum, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_service_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','scheduled','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_service_requests set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_issue_list(uuid,text) to anon, authenticated;
grant execute on function public.app_issue_kpi(uuid) to anon, authenticated;
grant execute on function public.app_issue_save(uuid,uuid,text,text,text,text,date,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_issue_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_issue_escalate(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_service_list(uuid,text) to anon, authenticated;
grant execute on function public.app_service_kpi(uuid) to anon, authenticated;
grant execute on function public.app_service_save(uuid,uuid,uuid,uuid,text,text,date,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_service_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_issues (tenant_id, title, description, priority, status, assignee, due_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.descr, v.pr, v.st, v.asg, current_date + v.days, 'master'
from (values
  ('Простой фрезерного DMU-50 (поломка)', 'Ожидание ремонта шпинделя', 'critical', 'in_progress', 'master', 0),
  ('Задержка материала по заказу', 'Нет стали 40Х на складе', 'high', 'open', 'supply', 2),
  ('Дефект кромки после ЭЭО', 'Задиры на контуре', 'normal', 'open', 'qc', 5)
) as v(title, descr, pr, st, asg, days)
where not exists (select 1 from public.app_issues where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_service_requests (tenant_id, number, customer_id, equipment_id, title, kind, status, scheduled_date, engineer, works, cost, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0'),
       (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind='frezerny' order by name limit 1),
       'Пусконаладка штампа у заказчика', 'service', 'scheduled', current_date + 3, 'service', 'Пробный прогон, подгонка', 25000, 'manager'
where not exists (select 1 from public.app_service_requests where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Проблемы','Как работает эскалация проблем (B24)?',
   'Модуль «Проблемы»: тема, приоритет (низкий/обычный/высокий/критический), исполнитель, срок, статус. Просроченные и критические выделяются. Кнопка «Эскалировать» поднимает приоритет до критического и уведомляет руководство (директор/владелец).',
   'проблемы эскалация приоритет SLA уведомление руководитель'),
  ('Сервис','Заявки на сервис и ремонт (B29)',
   'Модуль «Сервис»: заявки (SRV-NNNNN) с заказчиком, оборудованием, видом (сервис/ремонт/гарантия), датой, инженером, работами и стоимостью. Статусы: новая → запланирована → в работе → выполнена. KPI: заявок, открытых, выполнено, сумма затрат.',
   'сервис ремонт заявка инженер выезд гарантия')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как работает эскалация проблем (B24)?');
-- <<<<<<<<<< 0060_issues_service.sql <<<<<<<<<<
-- >>>>>>>>>> 0061_calendar.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0061_calendar.sql  (v39 — ЭПИК D: производственный календарь, B38)
-- Календарь РФ (праздники/сокращённые) + расчёт рабочих дней. База знаний.
-- Зависит от 0001..0060.
-- ============================================================

create table if not exists public.app_calendar (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  cal_date   date not null,
  kind       text not null default 'holiday', -- holiday|short|work|shift
  name       text,
  note       text,
  created_at timestamptz not null default now(),
  unique (tenant_id, cal_date)
);
create index if not exists app_calendar_idx on public.app_calendar (cal_date);
alter table public.app_calendar enable row level security;

-- ---------- Список ----------
create or replace function public.app_calendar_list(p_token uuid, p_from date default null, p_to date default null)
returns table (id uuid, cal_date date, kind text, name text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.cal_date, c.kind, c.name, c.note
    from public.app_calendar c
    where (c.tenant_id is null or c.tenant_id = ten or urole='admin')
      and (p_from is null or c.cal_date >= p_from) and (p_to is null or c.cal_date <= p_to)
    order by c.cal_date;
end $$;

-- ---------- Добавить/изменить день ----------
create or replace function public.app_calendar_save(p_token uuid, p_date date, p_kind text, p_name text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','hr','chief') then return query select false,'Недостаточно прав'; return; end if;
  if p_date is null then return query select false,'Укажите дату'; return; end if;
  insert into public.app_calendar (tenant_id, cal_date, kind, name)
  values (ten, p_date, coalesce(nullif(trim(p_kind),''),'holiday'), nullif(trim(p_name),''))
  on conflict (tenant_id, cal_date) do update set kind = excluded.kind, name = excluded.name;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_calendar_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','hr','chief') then return query select false,'Недостаточно прав'; return; end if;
  delete from public.app_calendar where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Удалено';
end $$;

-- ---------- Прибавить рабочие дни ----------
create or replace function public.app_calendar_add_days(p_token uuid, p_start date, p_days integer)
returns table (result date)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; d date; left_n integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  d := coalesce(p_start, current_date);
  left_n := greatest(coalesce(p_days,0),0);
  while left_n > 0 loop
    d := d + 1;
    if extract(dow from d) not in (0,6)
       and not exists (select 1 from public.app_calendar c where c.cal_date = d and c.kind in ('holiday') and (c.tenant_id is null or c.tenant_id=ten)) then
      left_n := left_n - 1;
    end if;
  end loop;
  return query select d;
end $$;

grant execute on function public.app_calendar_list(uuid,date,date) to anon, authenticated;
grant execute on function public.app_calendar_save(uuid,date,text,text) to anon, authenticated;
grant execute on function public.app_calendar_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_calendar_add_days(uuid,date,integer) to anon, authenticated;

-- ---------- Наполнение: праздники РФ 2025–2026 (глобально) ----------
insert into public.app_calendar (tenant_id, cal_date, kind, name)
select null, d::date, v.kind, v.name
from (values
  ('2025-01-01','holiday','Новый год'),('2025-01-02','holiday','Новогодние каникулы'),('2025-01-03','holiday','Новогодние каникулы'),
  ('2025-01-06','holiday','Новогодние каникулы'),('2025-01-07','holiday','Рождество'),('2025-01-08','holiday','Новогодние каникулы'),
  ('2025-01-09','work','Рабочий день (перенос)'),('2025-02-23','holiday','День защитника Отечества'),('2025-03-08','holiday','8 Марта'),
  ('2025-05-01','holiday','Праздник Весны и Труда'),('2025-05-09','holiday','День Победы'),('2025-06-12','holiday','День России'),
  ('2025-11-04','holiday','День народного единства'),('2025-03-07','short','Сокращённый день'),('2025-04-30','short','Сокращённый день'),
  ('2025-05-08','short','Сокращённый день'),('2025-06-11','short','Сокращённый день'),('2025-11-03','short','Сокращённый день'),('2025-12-31','short','Сокращённый день'),
  ('2026-01-01','holiday','Новый год'),('2026-01-02','holiday','Новогодние каникулы'),('2026-01-05','holiday','Новогодние каникулы'),
  ('2026-01-06','holiday','Новогодние каникулы'),('2026-01-07','holiday','Рождество'),('2026-01-08','holiday','Новогодние каникулы'),
  ('2026-02-23','holiday','День защитника Отечества'),('2026-03-08','holiday','8 Марта'),('2026-05-01','holiday','Праздник Весны и Труда'),
  ('2026-05-09','holiday','День Победы'),('2026-06-12','holiday','День России'),('2026-11-04','holiday','День народного единства')
) as v(d, kind, name)
where not exists (select 1 from public.app_calendar where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Календарь','Производственный календарь РФ',
   'Модуль «Календарь»: праздничные, сокращённые и рабочие (переносы) дни. Используется для расчёта рабочих дней и сроков: функция «прибавить рабочие дни» учитывает выходные и праздники. Праздники заданы глобально (РФ) и могут дополняться организацией.',
   'календарь праздники рабочие дни переносы срок РФ')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Производственный календарь РФ');
-- <<<<<<<<<< 0061_calendar.sql <<<<<<<<<<
-- >>>>>>>>>> 0062_doc_templates.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0062_doc_templates.sql  (v40 — ЭПИК E: шаблоны документов, B33)
-- Шаблоны документов (КП/договор/акт/техкарта) с подстановкой по заявке.
-- База знаний. Зависит от 0001..0061.
-- ============================================================

create table if not exists public.app_doc_templates (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  doc_type   text not null default 'kp',  -- kp|contract|act|techcard|other
  name       text not null,
  body       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_doc_templates_idx on public.app_doc_templates (tenant_id, doc_type);
alter table public.app_doc_templates enable row level security;

-- ---------- Шаблоны ----------
create or replace function public.app_doc_templates_list(p_token uuid, p_doc_type text default null, p_q text default null)
returns table (id uuid, doc_type text, name text, body text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.doc_type, t.name, t.body, t.active
    from public.app_doc_templates t
    where (t.tenant_id is null or t.tenant_id = ten or urole='admin')
      and (p_doc_type is null or p_doc_type='' or t.doc_type = p_doc_type)
      and (qq='' or lower(t.name) like '%'||qq||'%')
    order by t.doc_type, t.name;
end $$;

create or replace function public.app_doc_template_save(p_token uuid, p_id uuid, p_doc_type text, p_name text, p_body text, p_active boolean)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название шаблона'; return; end if;
  if p_id is null then
    insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
    values (ten, coalesce(nullif(trim(p_doc_type),''),'kp'), trim(p_name), p_body, coalesce(p_active,true))
    returning id into tid;
  else
    update public.app_doc_templates set doc_type=coalesce(nullif(trim(p_doc_type),''),doc_type), name=trim(p_name), body=p_body, active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into tid;
  end if;
  return query select tid, 'Шаблон сохранён';
end $$;

-- ---------- Создать документ из шаблона ----------
create or replace function public.app_doc_from_template(p_token uuid, p_template_id uuid, p_order_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; t record; o record; prefix text; dnum text; did uuid; body text; cust text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_doc_templates where id = p_template_id and (tenant_id is null or tenant_id = ten or urole='admin');
  if t.id is null then raise exception 'Шаблон не найден'; end if;
  if p_order_id is not null then
    select o0.*, c.name as cname into o from public.app_orders o0 left join public.app_customers c on c.id = o0.customer_id where o0.id = p_order_id;
    cust := coalesce(o.cname, o.customer, '');
  end if;
  prefix := case t.doc_type when 'kp' then 'KP' when 'contract' then 'DOG' when 'techcard' then 'TC' when 'act' then 'ACT' else 'DOC' end;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  body := coalesce(t.body,'');
  body := replace(body, '{customer}', coalesce(cust,''));
  body := replace(body, '{order}', coalesce(o.number,''));
  body := replace(body, '{title}', coalesce(o.title,''));
  body := replace(body, '{amount}', coalesce(o.amount::text,''));
  body := replace(body, '{date}', to_char(current_date,'DD.MM.YYYY'));
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, status, content, created_by, created_login)
  values (ten, t.doc_type, dnum, t.name, p_order_id, o.customer_id, o.amount, 'draft', body, 
          (select uid from public.app_session_user(p_token)), ulogin)
  returning id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, t.name, body, ulogin);
  return query select did, dnum, 'Документ создан из шаблона';
end $$;

grant execute on function public.app_doc_templates_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_template_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_doc_from_template(uuid,uuid,uuid) to anon, authenticated;

-- ---------- Демо-шаблоны (тенант A) ----------
insert into public.app_doc_templates (tenant_id, doc_type, name, body)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.t, v.n, v.b
from (values
  ('kp','Коммерческое предложение','Коммерческое предложение № {order} от {date}.
Заказчик: {customer}.
Предмет: {title}.
Стоимость: {amount} ₽. Срок действия — 30 дней.'),
  ('contract','Договор','Договор № {order} от {date}.
Стороны: Исполнитель и {customer}.
Предмет: {title}. Сумма: {amount} ₽.'),
  ('act','Акт выполненных работ','Акт № {order} от {date}.
Заказчик: {customer}. Работы: {title}. Сумма: {amount} ₽. Претензий нет.')
) as v(t, n, b)
where not exists (select 1 from public.app_doc_templates where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Шаблоны','Как использовать шаблоны документов?',
   'В модуле «Шаблоны документов» задаются КП/договор/акт/техкарта с подстановками: {customer}, {order}, {title}, {amount}, {date}. Кнопкой «Создать документ из шаблона» выбирается заявка — документ создаётся в «Документах» с подставленными данными и версией.',
   'шаблоны документы КП договор акт подстановка заявка печать')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как использовать шаблоны документов?');
-- <<<<<<<<<< 0062_doc_templates.sql <<<<<<<<<<
-- >>>>>>>>>> 0063_calc.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0063_calc.sql  (v41 — ЭПИК F: 8 мини-сервисов/калькуляторов)
-- Калькуляторы: масса проката, режимы резания, ISO 286, нормочас ЧПУ,
-- себестоимость детали, децимальные/обозначения, конвертеры, подбор технологии.
-- Сохранение расчётов (app_calc_saves) с привязкой к заявке.
-- База знаний. Зависит от 0001..0062.
-- ============================================================

create table if not exists public.app_calc_saves (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null,   -- mass|cutting|iso|cnc|cost|decimal|convert|tech
  title         text,
  input         jsonb,
  result        jsonb,
  ref           text,
  order_id      uuid references public.app_orders (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_calc_saves_idx on public.app_calc_saves (tenant_id, kind, created_at desc);
alter table public.app_calc_saves enable row level security;

-- ---------- 1. Масса проката ----------
create or replace function public.app_calc_mass(
  p_token uuid, p_profile text, p_a numeric, p_b numeric default 0, p_c numeric default 0,
  p_len numeric default 0, p_density numeric default 7.85, p_qty numeric default 1)
returns table (area_mm2 numeric, volume_mm3 numeric, mass_kg numeric, mass_total_kg numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare a numeric; area numeric; vol numeric; m numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  if coalesce(p_a,0) <= 0 then raise exception 'Укажите размер сечения'; end if;
  area := case lower(coalesce(p_profile,'round'))
    when 'round'  then pi()*p_a*p_a/4
    when 'square' then p_a*p_a
    when 'rect'   then p_a*coalesce(p_b,0)
    when 'pipe'   then pi()*(p_a*p_a - greatest(p_a-2*coalesce(p_c,0),0)^2)/4
    when 'sheet'  then p_a*coalesce(p_b,0)
    when 'hex'    then sqrt(3)/2*p_a*p_a
    else pi()*p_a*p_a/4 end;
  vol := area * coalesce(p_len,0);
  m := vol * coalesce(p_density,7.85) / 1000000.0;
  return query select round(area,2), round(vol,2), round(m,4), round(m*coalesce(p_qty,1),4);
end $$;

-- ---------- 2. Режимы резания ----------
create or replace function public.app_calc_cutting(
  p_token uuid, p_vc numeric, p_d numeric, p_fz numeric, p_z int default 1,
  p_ap numeric default 0, p_ae numeric default 0, p_kc numeric default 2000)
returns table (n_rpm numeric, feed_rev numeric, vf_mm_min numeric, mrr_cm3_min numeric, pc_kw numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare n numeric; vf numeric; mrr numeric; pc numeric; fz numeric; z int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  if coalesce(p_vc,0) <= 0 or coalesce(p_d,0) <= 0 then raise exception 'Укажите Vc и диаметр'; end if;
  fz := coalesce(p_fz,0); z := greatest(coalesce(p_z,1),1);
  n := 1000.0*p_vc/(pi()*p_d);
  vf := fz*z*n;
  mrr := coalesce(p_ap,0)*coalesce(p_ae,0)*vf/1000.0;
  pc := coalesce(p_ap,0)*coalesce(p_ae,0)*vf*coalesce(p_kc,2000)/(60.0*1000000.0);
  return query select round(n,0), round(fz*z,3), round(vf,1), round(mrr,2), round(pc,2);
end $$;

-- ---------- 3. ISO 286 (посадки) ----------
create or replace function public.app_calc_iso(
  p_token uuid, p_nominal numeric, p_hole_es numeric, p_hole_ei numeric,
  p_shaft_es numeric, p_shaft_ei numeric)
returns table (hole_max numeric, hole_min numeric, shaft_max numeric, shaft_min numeric,
               clearance_min numeric, clearance_max numeric, fit text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare hmax numeric; hmin numeric; smax numeric; smin numeric; cmin numeric; cmax numeric; ft text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  hmax := p_nominal + coalesce(p_hole_es,0); hmin := p_nominal + coalesce(p_hole_ei,0);
  smax := p_nominal + coalesce(p_shaft_es,0); smin := p_nominal + coalesce(p_shaft_ei,0);
  cmin := hmin - smax; cmax := hmax - smin;
  ft := case when cmin >= 0 then 'зазор' when cmax <= 0 then 'натяг' else 'переходная' end;
  return query select round(hmax,4), round(hmin,4), round(smax,4), round(smin,4), round(cmin,4), round(cmax,4), ft;
end $$;

-- ---------- 4. Нормочас ЧПУ ----------
create or replace function public.app_calc_cnc(
  p_token uuid, p_machine_price numeric, p_life_years numeric default 7, p_hours_year numeric default 2000,
  p_power_kw numeric default 10, p_energy_price numeric default 6, p_fot_rate numeric default 0,
  p_tools_rate numeric default 0, p_overhead_pct numeric default 15)
returns table (amort numeric, energy numeric, fot numeric, tools numeric, direct numeric, overhead numeric, rate numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare am numeric; en numeric; ft numeric; toc numeric; dr numeric; ov numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  am := case when coalesce(p_life_years,0)*coalesce(p_hours_year,0) > 0
             then coalesce(p_machine_price,0)/(p_life_years*p_hours_year) else 0 end;
  en := coalesce(p_power_kw,0)*coalesce(p_energy_price,0);
  ft := coalesce(p_fot_rate,0); toc := coalesce(p_tools_rate,0);
  dr := am + en + ft + toc;
  ov := dr*coalesce(p_overhead_pct,0)/100.0;
  return query select round(am,2), round(en,2), round(ft,2), round(toc,2), round(dr,2), round(ov,2), round(dr+ov,2);
end $$;

-- ---------- 5. Себестоимость детали ----------
create or replace function public.app_calc_cost(
  p_token uuid, p_material_cost numeric default 0, p_work_hours numeric default 0,
  p_rate numeric default 0, p_overhead_pct numeric default 15, p_qty numeric default 1)
returns table (material numeric, work numeric, overhead numeric, total numeric, per_unit numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare mat numeric; wrk numeric; ov numeric; tot numeric; q numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  mat := coalesce(p_material_cost,0);
  wrk := coalesce(p_work_hours,0)*coalesce(p_rate,0);
  ov := (mat+wrk)*coalesce(p_overhead_pct,0)/100.0;
  tot := mat+wrk+ov;
  q := greatest(coalesce(p_qty,1),1);
  return query select round(mat,2), round(wrk,2), round(ov,2), round(tot,2), round(tot/q,2);
end $$;

-- ---------- 6. Децимальные обозначения ----------
create or replace function public.app_calc_decimal(
  p_token uuid, p_code text, p_doc_number text, p_litera text default null)
returns table (designation text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare code text; num text; lit text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  code := upper(coalesce(nullif(trim(p_code),''),'АБВГ'));
  num  := lpad(regexp_replace(coalesce(p_doc_number,'0'), '\D', '', 'g'), 6, '0');
  lit  := nullif(trim(coalesce(p_litera,'')),'');
  return query select code || '.' || num || coalesce('-'||upper(lit),'');
end $$;

-- ---------- 7. Конвертеры ----------
create or replace function public.app_calc_convert(p_token uuid, p_kind text, p_value numeric)
returns table (result numeric, unit text, formula text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r numeric; u text; f text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  case lower(coalesce(p_kind,''))
    when 'mm_in'   then r := p_value/25.4;          u := 'дюйм'; f := 'мм / 25.4';
    when 'in_mm'   then r := p_value*25.4;          u := 'мм';   f := 'дюйм × 25.4';
    when 'hb_sigma' then r := p_value*3.38;         u := 'МПа';  f := 'HB × 3.38 (σв)';
    when 'sigma_hb' then r := p_value/3.38;         u := 'HB';   f := 'σв / 3.38';
    when 'kg_lb'   then r := p_value*2.20462;       u := 'lb';   f := 'кг × 2.20462';
    when 'lb_kg'   then r := p_value/2.20462;       u := 'кг';   f := 'lb / 2.20462';
    when 'n_kgf'   then r := p_value/9.80665;       u := 'кгс';  f := 'Н / 9.80665';
    when 'kgf_n'   then r := p_value*9.80665;       u := 'Н';    f := 'кгс × 9.80665';
    when 'kw_hp'   then r := p_value*1.34102;       u := 'л.с.'; f := 'кВт × 1.34102';
    when 'hp_kw'   then r := p_value/1.34102;       u := 'кВт';  f := 'л.с. / 1.34102';
    when 'grad_rad' then r := p_value*pi()/180.0;   u := 'рад';  f := 'град × π/180';
    when 'rad_grad' then r := p_value*180.0/pi();   u := 'град'; f := 'рад × 180/π';
    else raise exception 'Неизвестный тип конвертации: %', p_kind;
  end case;
  return query select round(r,6), u, f;
end $$;

-- ---------- 8. Подбор технологии ----------
create or replace function public.app_calc_tech(p_token uuid, p_material text, p_feature text)
returns table (recommendation text, note text, source text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.recommendation, r.note, 'правило'::text
    from public.app_tech_rules r
    where (r.tenant_id is null or r.tenant_id = ten)
      and (r.material is null or r.material = '*' or r.material = p_material or lower(coalesce(r.material,'')) = lower(coalesce(p_material,'')))
      and (r.feature  is null or r.feature  = '*' or r.feature  = p_feature  or lower(coalesce(r.feature,''))  = lower(coalesce(p_feature,'')))
    order by (case when lower(coalesce(r.material,''))=lower(coalesce(p_material,'')) then 0 else 1 end),
             (case when lower(coalesce(r.feature,''))=lower(coalesce(p_feature,'')) then 0 else 1 end)
    limit 5;
  if not found then
    return query
      select k.answer, k.question, 'база знаний'::text
      from public.app_knowledge k
      where (k.tenant_id is null or k.tenant_id = ten)
        and (lower(k.question) like '%'||lower(coalesce(p_material,''))||'%'
          or lower(coalesce(k.tags,'')) like '%'||lower(coalesce(p_feature,''))||'%')
      limit 3;
  end if;
end $$;

-- ---------- Сохранение расчётов ----------
create or replace function public.app_calc_save(p_token uuid, p_kind text, p_title text,
  p_input jsonb, p_result jsonb, p_ref text default null, p_order_id uuid default null)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; cid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_kind),'') = '' then raise exception 'Укажите тип расчёта'; return; end if;
  insert into public.app_calc_saves (tenant_id, kind, title, input, result, ref, order_id, created_login)
  values (ten, lower(trim(p_kind)), nullif(trim(p_title),''), p_input, p_result, nullif(trim(p_ref),''), p_order_id, ulogin)
  returning id into cid;
  return query select cid, 'Расчёт сохранён';
end $$;

create or replace function public.app_calc_list(p_token uuid, p_kind text default null, p_q text default null)
returns table (id uuid, kind text, title text, ref text, order_number text, result jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select c.id, c.kind, c.title, c.ref, o.number, c.result, c.created_at
    from public.app_calc_saves c
    left join public.app_orders o on o.id = c.order_id
    where (urole='admin' or c.tenant_id = ten)
      and (coalesce(p_kind,'')='' or c.kind = p_kind)
      and (qq='' or lower(coalesce(c.title,'')) like '%'||qq||'%' or lower(coalesce(c.ref,'')) like '%'||qq||'%')
    order by c.created_at desc;
end $$;

create or replace function public.app_calc_get(p_token uuid, p_id uuid)
returns table (id uuid, kind text, title text, input jsonb, result jsonb, ref text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.kind, c.title, c.input, c.result, c.ref, c.created_at
    from public.app_calc_saves c
    where c.id = p_id and (urole='admin' or c.tenant_id = ten);
end $$;

create or replace function public.app_calc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_calc_saves where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Расчёт удалён';
end $$;

grant execute on function public.app_calc_mass(uuid,text,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cutting(uuid,numeric,numeric,numeric,int,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_iso(uuid,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cnc(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_cost(uuid,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_calc_decimal(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_calc_convert(uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_calc_tech(uuid,text,text) to anon, authenticated;
grant execute on function public.app_calc_save(uuid,text,text,jsonb,jsonb,text,uuid) to anon, authenticated;
grant execute on function public.app_calc_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_calc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_calc_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Мини-сервисы','Какие калькуляторы есть в системе (B34/A1)?',
   'Модуль «Калькуляторы»: масса проката (круг/квадрат/прямоугольник/труба/лист/шестигранник, плотность, количество), режимы резания (Vc→обороты, минутная подача, MRR, мощность), ISO 286 (посадки: предельные размеры, зазор/натяг), нормочас ЧПУ (амортизация+энергия+ФОТ+расходники+накладные), себестоимость детали (материал+работы+накладные), децимальные обозначения (ГОСТ 2.201), конвертеры (мм↔дюйм, HB↔σв, кг↔lb, Н↔кгс, кВт↔л.с.), подбор технологии (по материалу и признаку). Расчёт можно сохранить и привязать к заявке.',
   'калькуляторы масса проката режимы резания ISO 286 нормочас себестоимость децимальные конвертер подбор технологии')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Какие калькуляторы есть в системе (B34/A1)?');
-- <<<<<<<<<< 0063_calc.sql <<<<<<<<<<
-- >>>>>>>>>> 0064_registries.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0064_registries.sql  (v42 — ЭПИК F: реестры)
-- Реестры: гравирование (заказы на гравировку), поставщики (реестр/аккредитация),
-- ТЭО (технико-экономическое обоснование: статьи и итог, из заявки).
-- База знаний. Зависит от 0001..0063.
-- ============================================================

-- ---------- Гравирование ----------
create sequence if not exists public.app_engraving_seq;
create table if not exists public.app_engraving (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid references public.tenants (id),
  number           text,
  order_id         uuid references public.app_orders (id) on delete set null,
  detail           text,
  machine          text,
  engraving_number text,
  minutes          numeric,
  ship_date        date,
  status           text not null default 'new', -- new|in_progress|done|cancelled
  note             text,
  created_login    text,
  created_at       timestamptz not null default now()
);
create index if not exists app_engraving_idx on public.app_engraving (tenant_id, status, ship_date);
alter table public.app_engraving enable row level security;

-- ---------- Поставщики ----------
create table if not exists public.app_suppliers (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  inn        text,
  contact    text,
  phone      text,
  email      text,
  category   text,   -- металл|инструмент|комплектующие|услуги|прочее
  rating     numeric default 0,
  status     text not null default 'pending', -- pending|accredited|blocked
  note       text,
  created_login text,
  created_at timestamptz not null default now()
);
create index if not exists app_suppliers_idx on public.app_suppliers (tenant_id, status, category);
alter table public.app_suppliers enable row level security;

-- ---------- ТЭО ----------
create sequence if not exists public.app_teo_seq;
create table if not exists public.app_teo (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  order_id      uuid references public.app_orders (id) on delete set null,
  title         text not null,
  status        text not null default 'draft', -- draft|approved|rejected
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_teo_idx on public.app_teo (tenant_id, status);
alter table public.app_teo enable row level security;

create table if not exists public.app_teo_lines (
  id       uuid primary key default gen_random_uuid(),
  teo_id   uuid references public.app_teo (id) on delete cascade,
  kind     text not null default 'other', -- consumables|metal|labor|service|other
  name     text not null,
  qty      numeric default 1,
  price    numeric default 0,
  amount   numeric default 0,
  sort     int default 100
);
create index if not exists app_teo_lines_idx on public.app_teo_lines (teo_id);
alter table public.app_teo_lines enable row level security;

-- ================= Гравирование: RPC =================
create or replace function public.app_engraving_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, order_id uuid, order_number text, detail text, machine text, engraving_number text,
               minutes numeric, ship_date date, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select g.id, g.number, g.order_id, o.number, g.detail, g.machine, g.engraving_number, g.minutes, g.ship_date, g.status, g.created_at
    from public.app_engraving g left join public.app_orders o on o.id = g.order_id
    where (urole='admin' or g.tenant_id = ten)
      and (qq='' or lower(coalesce(g.detail,'')) like '%'||qq||'%' or lower(coalesce(g.engraving_number,'')) like '%'||qq||'%' or lower(coalesce(o.number,'')) like '%'||qq||'%')
    order by (g.status='done'), coalesce(g.ship_date, current_date + 365), g.created_at desc;
end $$;

create or replace function public.app_engraving_kpi(p_token uuid)
returns table (total bigint, queue bigint, done bigint, minutes_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status in ('new','in_progress')),
    count(*) filter (where status='done'), coalesce(sum(minutes),0)
    from public.app_engraving where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_engraving_save(p_token uuid, p_id uuid, p_order_id uuid, p_detail text,
  p_machine text, p_engraving_number text, p_minutes numeric, p_ship_date date, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; gid uuid; gnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_detail),'') = '' and p_order_id is null then raise exception 'Укажите деталь или заявку'; return; end if;
  if p_id is null then
    gnum := 'ENG-' || lpad(nextval('public.app_engraving_seq')::text, 5, '0');
    insert into public.app_engraving (tenant_id, number, order_id, detail, machine, engraving_number, minutes, ship_date, note, created_login)
    values (ten, gnum, p_order_id, nullif(trim(p_detail),''), nullif(trim(p_machine),''), nullif(trim(p_engraving_number),''),
            p_minutes, p_ship_date, nullif(trim(p_note),''), ulogin)
    returning id into gid;
    return query select gid, gnum, 'Заказ на гравирование создан';
  else
    update public.app_engraving set order_id=p_order_id, detail=nullif(trim(p_detail),''), machine=nullif(trim(p_machine),''),
      engraving_number=nullif(trim(p_engraving_number),''), minutes=p_minutes, ship_date=p_ship_date, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into gid, gnum;
    return query select gid, gnum, 'Заказ обновлён';
  end if;
end $$;

create or replace function public.app_engraving_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_engraving set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ================= Поставщики: RPC =================
create or replace function public.app_suppliers_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, name text, inn text, contact text, phone text, email text, category text, rating numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.name, s.inn, s.contact, s.phone, s.email, s.category, s.rating, s.status, s.created_at
    from public.app_suppliers s
    where (urole='admin' or s.tenant_id = ten)
      and (coalesce(p_category,'')='' or s.category = p_category)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(coalesce(s.inn,'')) like '%'||qq||'%' or lower(coalesce(s.contact,'')) like '%'||qq||'%')
    order by (s.status='blocked'), s.rating desc nulls last, s.name;
end $$;

create or replace function public.app_suppliers_kpi(p_token uuid)
returns table (total bigint, accredited bigint, pending bigint, blocked bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='accredited'),
    count(*) filter (where status='pending'), count(*) filter (where status='blocked')
    from public.app_suppliers where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_suppliers_save(p_token uuid, p_id uuid, p_name text, p_inn text, p_contact text,
  p_phone text, p_email text, p_category text, p_rating numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','supply') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите наименование поставщика'; return; end if;
  if p_id is null then
    insert into public.app_suppliers (tenant_id, name, inn, contact, phone, email, category, rating, note, created_login)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''),
            nullif(trim(p_email),''), nullif(trim(p_category),''), coalesce(p_rating,0), nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, 'Поставщик добавлен';
  else
    update public.app_suppliers set name=trim(p_name), inn=nullif(trim(p_inn),''), contact=nullif(trim(p_contact),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), category=nullif(trim(p_category),''),
      rating=coalesce(p_rating,rating), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Поставщик обновлён';
  end if;
end $$;

create or replace function public.app_suppliers_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('pending','accredited','blocked') then return query select false,'Неверный статус'; return; end if;
  update public.app_suppliers set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ================= ТЭО: RPC =================
create or replace function public.app_teo_total(p_teo_id uuid) returns numeric
language sql stable security definer set search_path = public
as $$ select coalesce(sum(amount),0) from public.app_teo_lines where teo_id = p_teo_id $$;

create or replace function public.app_teo_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, title text, order_number text, status text, total numeric, lines bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select t.id, t.number, t.title, o.number, t.status,
      coalesce((select sum(l.amount) from public.app_teo_lines l where l.teo_id=t.id),0),
      (select count(*) from public.app_teo_lines l where l.teo_id=t.id), t.created_at
    from public.app_teo t left join public.app_orders o on o.id=t.order_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(t.title) like '%'||qq||'%' or lower(coalesce(t.number,'')) like '%'||qq||'%')
    order by t.created_at desc;
end $$;

create or replace function public.app_teo_kpi(p_token uuid)
returns table (total bigint, drafts bigint, approved bigint, amount_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select (select count(*) from public.app_teo where (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_teo where status='draft' and (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_teo where status='approved' and (urole='admin' or tenant_id=ten)),
      (select coalesce(sum(l.amount),0) from public.app_teo_lines l
        join public.app_teo t on t.id=l.teo_id where (urole='admin' or t.tenant_id=ten));
end $$;

create or replace function public.app_teo_save(p_token uuid, p_id uuid, p_order_id uuid, p_title text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название ТЭО'; return; end if;
  if p_id is null then
    tnum := 'TEO-' || lpad(nextval('public.app_teo_seq')::text, 5, '0');
    insert into public.app_teo (tenant_id, number, order_id, title, note, created_login)
    values (ten, tnum, p_order_id, trim(p_title), nullif(trim(p_note),''), ulogin)
    returning id into tid;
    return query select tid, tnum, 'ТЭО создано';
  else
    update public.app_teo set order_id=p_order_id, title=trim(p_title), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into tid, tnum;
    return query select tid, tnum, 'ТЭО обновлено';
  end if;
end $$;

create or replace function public.app_teo_lines_list(p_token uuid, p_teo_id uuid)
returns table (id uuid, kind text, name text, qty numeric, price numeric, amount numeric, sort int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.kind, l.name, l.qty, l.price, l.amount, l.sort
    from public.app_teo_lines l join public.app_teo t on t.id=l.teo_id
    where l.teo_id=p_teo_id and (urole='admin' or t.tenant_id=ten)
    order by l.sort, l.name;
end $$;

create or replace function public.app_teo_line_save(p_token uuid, p_id uuid, p_teo_id uuid, p_kind text,
  p_name text, p_qty numeric, p_price numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; lid uuid; amt numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите статью'; return; end if;
  if not exists (select 1 from public.app_teo where id=p_teo_id and (urole='admin' or tenant_id=ten)) then raise exception 'ТЭО не найдено'; end if;
  amt := coalesce(p_qty,1)*coalesce(p_price,0);
  if p_id is null then
    insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount)
    values (p_teo_id, coalesce(nullif(trim(p_kind),''),'other'), trim(p_name), coalesce(p_qty,1), coalesce(p_price,0), amt)
    returning id into lid;
    return query select lid, 'Статья добавлена';
  else
    update public.app_teo_lines set kind=coalesce(nullif(trim(p_kind),''),kind), name=trim(p_name),
      qty=coalesce(p_qty,1), price=coalesce(p_price,0), amount=amt
     where id=p_id and teo_id=p_teo_id returning id into lid;
    return query select lid, 'Статья обновлена';
  end if;
end $$;

create or replace function public.app_teo_line_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_teo_lines l using public.app_teo t
    where l.id=p_id and t.id=l.teo_id and (urole='admin' or t.tenant_id=ten);
  return query select true,'Статья удалена';
end $$;

create or replace function public.app_teo_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('draft','approved','rejected') then return query select false,'Неверный статус'; return; end if;
  select title into t from public.app_teo where id=p_id and (urole='admin' or tenant_id=ten);
  update public.app_teo set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  if p_status='approved' then
    perform public.app_notif_roles_t(ten, array['admin','owner','director','economist'], 'ТЭО утверждено: '||coalesce(t,''), '', 'apps/teo/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_teo_from_order(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text; o record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select ao.* into o from public.app_orders ao where ao.id=p_order_id and (urole='admin' or ao.tenant_id=ten);
  if o.id is null then raise exception 'Заявка не найдена'; end if;
  tnum := 'TEO-' || lpad(nextval('public.app_teo_seq')::text, 5, '0');
  insert into public.app_teo (tenant_id, number, order_id, title, note, created_login)
  values (ten, tnum, p_order_id, 'ТЭО по заявке '||o.number, 'Создано из заявки', ulogin) returning id into tid;
  insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount, sort)
  values (tid, 'other', coalesce(o.title,'Изделие'), 1, coalesce(o.amount,0), coalesce(o.amount,0), 10);
  return query select tid, tnum, 'ТЭО создано из заявки';
end $$;

grant execute on function public.app_engraving_list(uuid,text) to anon, authenticated;
grant execute on function public.app_engraving_kpi(uuid) to anon, authenticated;
grant execute on function public.app_engraving_save(uuid,uuid,uuid,text,text,text,numeric,date,text) to anon, authenticated;
grant execute on function public.app_engraving_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_suppliers_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_suppliers_kpi(uuid) to anon, authenticated;
grant execute on function public.app_suppliers_save(uuid,uuid,text,text,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_suppliers_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_teo_list(uuid,text) to anon, authenticated;
grant execute on function public.app_teo_kpi(uuid) to anon, authenticated;
grant execute on function public.app_teo_save(uuid,uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_teo_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_teo_line_save(uuid,uuid,uuid,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_teo_line_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_teo_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_teo_from_order(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_suppliers (tenant_id, name, inn, contact, phone, email, category, rating, status, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.inn, v.contact, v.phone, v.email, v.cat, v.rating, v.status, v.note, 'supply'
from (values
  ('ООО «МеталлСервис»','7712345678','Иванов И.И.','+7 495 111-22-33','sales@metall.ru','металл',4.8,'accredited','Поставки конструкционной стали'),
  ('ООО «Инструмент-Про»','7798765432','Петров П.П.','+7 495 222-33-44','info@instr.ru','инструмент',4.5,'accredited','Твёрдосплавный инструмент'),
  ('ООО «ОснасткаПлюс»','7734567890','Сидоров А.А.','+7 812 333-44-55','zakaz@osnastka.ru','комплектующие',3.9,'pending','На аккредитации')
) as v(name,inn,contact,phone,email,cat,rating,status,note)
where not exists (select 1 from public.app_suppliers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_engraving (tenant_id, number, order_id, detail, machine, engraving_number, minutes, ship_date, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'ENG-' || lpad(nextval('public.app_engraving_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  'Маркировка партии деталей', 'Лазерный маркер', 'G-2026-001', 35, current_date + 2, 'in_progress', 'master'
where not exists (select 1 from public.app_engraving where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_teo (tenant_id, number, order_id, title, status, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'TEO-' || lpad(nextval('public.app_teo_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  'ТЭО изготовления оснастки', 'draft', 'Демо-расчёт', 'economist'
where not exists (select 1 from public.app_teo where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount, sort)
select t.id, v.kind, v.name, v.qty, v.price, v.qty*v.price, v.sort
from public.app_teo t,
(values
  ('metal','Сталь 40Х, кг', 120, 85, 10),
  ('consumables','СОЖ и расходники, л', 20, 350, 20),
  ('labor','Слесарные работы, ч', 40, 700, 30),
  ('labor','Фрезерная обработка, ч', 60, 1200, 40),
  ('service','Термообработка, кг', 120, 90, 50)
) as v(kind,name,qty,price,sort)
where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_teo_lines l where l.teo_id=t.id);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Реестры','Реестр гравирования (B36)',
   'Модуль «Гравирование»: заказ на гравировку (ENG-NNNNN) с заявкой, деталью, станком, номером гравировки, временем (мин) и датой отгрузки. Статусы: новый → в работе → выполнен. KPI: всего, в очереди, выполнено, сумма минут.',
   'гравирование маркировка реестр отгрузка время'),
  ('Реестры','Реестр поставщиков (B33/закупки)',
   'Модуль «Поставщики»: карточки контрагентов (наименование, ИНН, контакт, категория, рейтинг), статусы: на аккредитации → аккредитован → заблокирован. Связь с закупками и порталом поставщика. KPI: всего, аккредитовано, на аккредитации, заблокировано.',
   'поставщики реестр аккредитация ИНН рейтинг'),
  ('Реестры','ТЭО — технико-экономическое обоснование',
   'Модуль «ТЭО»: обоснование (TEO-NNNNN) со статьями (металл, расходники, работы, услуги, прочее). Итог считается по статьям. Можно создать из заявки одной кнопкой. Статусы: черновик → утверждено/отклонено. KPI: всего, черновиков, утверждено, сумма.',
   'ТЭО обоснование статьи себестоимость металл работы услуги')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Реестр гравирования (B36)');
-- <<<<<<<<<< 0064_registries.sql <<<<<<<<<<
-- >>>>>>>>>> 0065_labels.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0065_labels.sql  (v43 — ЭПИК F: упаковка и маркировка)
-- Формы упаковки (места) и этикеток: грузовая этикетка, бирка позиции,
-- манипуляционные знаки. Печать (клиент). База знаний. Зависит от 0001..0064.
-- ============================================================

-- ---------- Упаковка (грузовые места) ----------
create table if not exists public.app_packages (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  order_id     uuid references public.app_orders (id) on delete set null,
  package_no   int,
  kind         text not null default 'box',  -- box|pallet|crate|bag|other
  dims         text,                          -- Д×Ш×В, мм
  gross        numeric,
  net          numeric,
  positions    int,
  marks        text,                          -- манипуляционные знаки (хрупкое/верх/не кантовать)
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_packages_idx on public.app_packages (tenant_id, order_id);
alter table public.app_packages enable row level security;

-- ---------- Этикетки ----------
create table if not exists public.app_labels (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  order_id     uuid references public.app_orders (id) on delete set null,
  package_id   uuid references public.app_packages (id) on delete set null,
  label_type   text not null default 'cargo', -- cargo|position|tag
  recipient    text,
  sender       text default 'ООО «3Д Металлообработка Пресс»',
  order_number text,
  item         text,
  qty          numeric,
  dims         text,
  gross        numeric,
  net          numeric,
  position_no  int,
  identifier   text,
  cargo_no     int,
  cargo_total  int,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_labels_idx on public.app_labels (tenant_id, label_type, order_id);
alter table public.app_labels enable row level security;

-- ================= Упаковка: RPC =================
create or replace function public.app_package_list(p_token uuid, p_q text default null)
returns table (id uuid, order_number text, package_no int, kind text, dims text, gross numeric, net numeric,
               positions int, marks text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, o.number, p.package_no, p.kind, p.dims, p.gross, p.net, p.positions, p.marks, p.created_at
    from public.app_packages p left join public.app_orders o on o.id=p.order_id
    where (urole='admin' or p.tenant_id=ten)
      and (qq='' or lower(coalesce(o.number,'')) like '%'||qq||'%' or lower(coalesce(p.dims,'')) like '%'||qq||'%')
    order by coalesce(o.number,''), p.package_no;
end $$;

create or replace function public.app_package_kpi(p_token uuid)
returns table (packages bigint, gross_sum numeric, net_sum numeric, positions_sum bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(gross),0), coalesce(sum(net),0), coalesce(sum(positions),0)
    from public.app_packages where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_package_save(p_token uuid, p_id uuid, p_order_id uuid, p_package_no int,
  p_kind text, p_dims text, p_gross numeric, p_net numeric, p_positions int, p_marks text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; pid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master') then raise exception 'Недостаточно прав'; end if;
  if p_id is null then
    insert into public.app_packages (tenant_id, order_id, package_no, kind, dims, gross, net, positions, marks, note, created_login)
    values (ten, p_order_id, p_package_no, coalesce(nullif(trim(p_kind),''),'box'), nullif(trim(p_dims),''),
            p_gross, p_net, p_positions, nullif(trim(p_marks),''), nullif(trim(p_note),''), ulogin)
    returning id into pid;
    return query select pid, 'Грузовое место добавлено';
  else
    update public.app_packages set order_id=p_order_id, package_no=p_package_no, kind=coalesce(nullif(trim(p_kind),''),kind),
      dims=nullif(trim(p_dims),''), gross=p_gross, net=p_net, positions=p_positions, marks=nullif(trim(p_marks),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into pid;
    return query select pid, 'Грузовое место обновлено';
  end if;
end $$;

create or replace function public.app_package_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_packages where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Грузовое место удалено';
end $$;

-- ================= Этикетки: RPC =================
create or replace function public.app_label_list(p_token uuid, p_type text default null, p_q text default null)
returns table (id uuid, label_type text, order_number text, recipient text, sender text, item text, qty numeric,
               dims text, gross numeric, net numeric, position_no int, identifier text, cargo_no int, cargo_total int, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select l.id, l.label_type, l.order_number, l.recipient, l.sender, l.item, l.qty, l.dims, l.gross, l.net,
           l.position_no, l.identifier, l.cargo_no, l.cargo_total, l.created_at
    from public.app_labels l
    where (urole='admin' or l.tenant_id=ten)
      and (coalesce(p_type,'')='' or l.label_type=p_type)
      and (qq='' or lower(coalesce(l.recipient,'')) like '%'||qq||'%' or lower(coalesce(l.item,'')) like '%'||qq||'%' or lower(coalesce(l.order_number,'')) like '%'||qq||'%')
    order by l.created_at desc;
end $$;

create or replace function public.app_label_kpi(p_token uuid)
returns table (total bigint, cargo bigint, pos_lbl bigint, tag_lbl bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where label_type='cargo'),
    count(*) filter (where label_type='position'), count(*) filter (where label_type='tag')
    from public.app_labels where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_label_save(p_token uuid, p_id uuid, p_order_id uuid, p_package_id uuid,
  p_label_type text, p_recipient text, p_sender text, p_item text, p_qty numeric, p_dims text,
  p_gross numeric, p_net numeric, p_position_no int, p_identifier text, p_cargo_no int, p_cargo_total int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid; onum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','supply') then raise exception 'Недостаточно прав'; end if;
  onum := (select number from public.app_orders where id=p_order_id);
  if p_id is null then
    insert into public.app_labels (tenant_id, order_id, package_id, label_type, recipient, sender, order_number, item, qty,
      dims, gross, net, position_no, identifier, cargo_no, cargo_total, note, created_login)
    values (ten, p_order_id, p_package_id, coalesce(nullif(trim(p_label_type),''),'cargo'),
            nullif(trim(p_recipient),''), coalesce(nullif(trim(p_sender),''),'ООО «3Д Металлообработка Пресс»'),
            onum, nullif(trim(p_item),''), p_qty, nullif(trim(p_dims),''), p_gross, p_net, p_position_no,
            nullif(trim(p_identifier),''), p_cargo_no, p_cargo_total, nullif(trim(p_note),''), ulogin)
    returning id into lid;
    return query select lid, 'Этикетка сохранена';
  else
    update public.app_labels set order_id=p_order_id, package_id=p_package_id,
      label_type=coalesce(nullif(trim(p_label_type),''),label_type), recipient=nullif(trim(p_recipient),''),
      sender=coalesce(nullif(trim(p_sender),''),sender), order_number=onum, item=nullif(trim(p_item),''), qty=p_qty,
      dims=nullif(trim(p_dims),''), gross=p_gross, net=p_net, position_no=p_position_no, identifier=nullif(trim(p_identifier),''),
      cargo_no=p_cargo_no, cargo_total=p_cargo_total, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Этикетка обновлена';
  end if;
end $$;

create or replace function public.app_label_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_labels where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Этикетка удалена';
end $$;

grant execute on function public.app_package_list(uuid,text) to anon, authenticated;
grant execute on function public.app_package_kpi(uuid) to anon, authenticated;
grant execute on function public.app_package_save(uuid,uuid,uuid,int,text,text,numeric,numeric,int,text,text) to anon, authenticated;
grant execute on function public.app_package_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_label_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_label_kpi(uuid) to anon, authenticated;
grant execute on function public.app_label_save(uuid,uuid,uuid,uuid,text,text,text,text,numeric,text,numeric,numeric,int,text,int,int,text) to anon, authenticated;
grant execute on function public.app_label_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_packages (tenant_id, order_id, package_no, kind, dims, gross, net, positions, marks, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  v.no, v.kind, v.dims, v.gross, v.net, v.pos, v.marks, v.note, 'master'
from (values
  (1,'crate','1200×800×600', 340, 300, 4, 'Верх, не кантовать', 'Основное место'),
  (2,'pallet','1200×800×400', 180, 160, 2, 'Хрупкое, верх', 'Комплектующие')
) as v(no,kind,dims,gross,net,pos,marks,note)
where not exists (select 1 from public.app_packages where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_labels (tenant_id, order_id, package_id, label_type, recipient, order_number, item, qty, dims, gross, net, cargo_no, cargo_total, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  p.order_id, p.id, 'cargo', 'ООО «Заказчик-1»', o.number, 'Штамп вырубной', 4, p.dims, p.gross, p.net, p.package_no, 2, 'master'
from public.app_packages p join public.app_orders o on o.id=p.order_id
where p.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_labels where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Упаковка','Упаковка и маркировка груза (B37)',
   'Модуль «Упаковка и маркировка»: грузовые места (вид: коробка/паллета/ящик, габариты, брутто/нетто, число позиций, манипуляционные знаки) и этикетки: грузовая (получатель/отправитель, № заявки, товар, габариты, брутто/нетто, 1/3), бирка позиции (№ заявки, № позиции, описание, идентификатор, количество, срок) и манипуляционные знаки. Печать этикеток — из карточки.',
   'упаковка маркировка грузовая этикетка бирка брутто нетто манипуляционные знаки')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Упаковка и маркировка груза (B37)');
-- <<<<<<<<<< 0065_labels.sql <<<<<<<<<<
-- >>>>>>>>>> 0066_appbuilder.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0066_appbuilder.sql  (v44 — ЭПИК G: P2 App Builder)
-- Конструктор пользовательских сущностей: сущность → поля → записи.
-- Позволяет организации заводить свои справочники/журналы без разработки.
-- База знаний. Зависит от 0001..0065.
-- ============================================================

create table if not exists public.app_entities (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  name        text not null,
  code        text,
  icon        text default '🧩',
  description text,
  active      boolean not null default true,
  created_login text,
  created_at  timestamptz not null default now()
);
create index if not exists app_entities_idx on public.app_entities (tenant_id, active);
alter table public.app_entities enable row level security;

create table if not exists public.app_entity_fields (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid references public.app_entities (id) on delete cascade,
  name        text not null,
  code        text not null,
  field_type  text not null default 'text', -- text|number|date|select|bool|textarea
  options     text,                          -- для select: значения через запятую
  required    boolean not null default false,
  sort        int default 100
);
create index if not exists app_entity_fields_idx on public.app_entity_fields (entity_id);
alter table public.app_entity_fields enable row level security;

create table if not exists public.app_entity_records (
  id           uuid primary key default gen_random_uuid(),
  entity_id    uuid references public.app_entities (id) on delete cascade,
  tenant_id    uuid references public.tenants (id),
  data         jsonb not null default '{}'::jsonb,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_entity_records_idx on public.app_entity_records (entity_id, created_at desc);
alter table public.app_entity_records enable row level security;

-- ---------- Сущности ----------
create or replace function public.app_entity_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, code text, icon text, description text, active boolean,
               fields_count bigint, records_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select e.id, e.name, e.code, e.icon, e.description, e.active,
      (select count(*) from public.app_entity_fields f where f.entity_id=e.id),
      (select count(*) from public.app_entity_records r where r.entity_id=e.id),
      e.created_at
    from public.app_entities e
    where (urole='admin' or e.tenant_id=ten)
      and (qq='' or lower(e.name) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%')
    order by e.active desc, e.name;
end $$;

create or replace function public.app_entity_save(p_token uuid, p_id uuid, p_name text, p_code text,
  p_icon text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название сущности'; return; end if;
  if p_id is null then
    insert into public.app_entities (tenant_id, name, code, icon, description, active, created_login)
    values (ten, trim(p_name), nullif(trim(p_code),''), coalesce(nullif(trim(p_icon),''),'🧩'),
            nullif(trim(p_description),''), coalesce(p_active,true), ulogin)
    returning id into eid;
    return query select eid, 'Сущность создана';
  else
    update public.app_entities set name=trim(p_name), code=nullif(trim(p_code),''),
      icon=coalesce(nullif(trim(p_icon),''),icon), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into eid;
    return query select eid, 'Сущность обновлена';
  end if;
end $$;

-- ---------- Поля ----------
create or replace function public.app_entity_fields_list(p_token uuid, p_entity_id uuid)
returns table (id uuid, name text, code text, field_type text, options text, required boolean, sort int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then
    raise exception 'Сущность не найдена';
  end if;
  return query select f.id, f.name, f.code, f.field_type, f.options, f.required, f.sort
    from public.app_entity_fields f where f.entity_id=p_entity_id order by f.sort, f.name;
end $$;

create or replace function public.app_entity_field_save(p_token uuid, p_id uuid, p_entity_id uuid,
  p_name text, p_code text, p_field_type text, p_options text, p_required boolean, p_sort int)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then raise exception 'Сущность не найдена'; return; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_code),'') = '' then raise exception 'Укажите название и код поля'; return; end if;
  if p_field_type not in ('text','number','date','select','bool','textarea') then raise exception 'Неверный тип поля'; return; end if;
  if p_id is null then
    insert into public.app_entity_fields (entity_id, name, code, field_type, options, required, sort)
    values (p_entity_id, trim(p_name), trim(p_code), p_field_type, nullif(trim(p_options),''), coalesce(p_required,false), coalesce(p_sort,100))
    returning id into fid;
    return query select fid, 'Поле добавлено';
  else
    update public.app_entity_fields set name=trim(p_name), code=trim(p_code), field_type=p_field_type,
      options=nullif(trim(p_options),''), required=coalesce(p_required,false), sort=coalesce(p_sort,100)
     where id=p_id and entity_id=p_entity_id returning id into fid;
    return query select fid, 'Поле обновлено';
  end if;
end $$;

create or replace function public.app_entity_field_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_entity_fields f using public.app_entities e
    where f.id=p_id and e.id=f.entity_id and (urole='admin' or e.tenant_id=ten);
  return query select true,'Поле удалено';
end $$;

-- ---------- Записи ----------
create or replace function public.app_entity_records_list(p_token uuid, p_entity_id uuid, p_q text default null)
returns table (id uuid, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select r.id, r.data, r.created_login, r.created_at
    from public.app_entity_records r
    where r.entity_id=p_entity_id and (urole='admin' or r.tenant_id=ten)
      and (qq='' or lower(r.data::text) like '%'||qq||'%')
    order by r.created_at desc;
end $$;

create or replace function public.app_entity_record_save(p_token uuid, p_id uuid, p_entity_id uuid, p_data jsonb)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then raise exception 'Сущность не найдена'; return; end if;
  if p_id is null then
    insert into public.app_entity_records (entity_id, tenant_id, data, created_login)
    values (p_entity_id, ten, coalesce(p_data,'{}'::jsonb), ulogin) returning id into rid;
    return query select rid, 'Запись добавлена';
  else
    update public.app_entity_records set data=coalesce(p_data,'{}'::jsonb)
     where id=p_id and entity_id=p_entity_id and (urole='admin' or tenant_id=ten) returning id into rid;
    return query select rid, 'Запись обновлена';
  end if;
end $$;

create or replace function public.app_entity_record_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_entity_records where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Запись удалена';
end $$;

grant execute on function public.app_entity_list(uuid,text) to anon, authenticated;
grant execute on function public.app_entity_save(uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_entity_fields_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_entity_field_save(uuid,uuid,uuid,text,text,text,text,boolean,int) to anon, authenticated;
grant execute on function public.app_entity_field_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_entity_records_list(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_entity_record_save(uuid,uuid,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_entity_record_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо-сущность (тенант A) ----------
do $$
declare eid uuid;
begin
  if not exists (select 1 from public.app_entities where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='VISIT') then
    insert into public.app_entities (tenant_id, name, code, icon, description, created_login)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'Журнал посещений', 'VISIT', '📓', 'Учёт посещений подрядчиков', 'owner')
    returning id into eid;
    insert into public.app_entity_fields (entity_id, name, code, field_type, options, required, sort) values
      (eid, 'Дата', 'date', 'date', null, true, 10),
      (eid, 'ФИО', 'name', 'text', null, true, 20),
      (eid, 'Организация', 'org', 'text', null, false, 30),
      (eid, 'Цель визита', 'goal', 'select', 'обслуживание,доставка,переговоры,инспекция', false, 40),
      (eid, 'Примечание', 'note', 'textarea', null, false, 50);
    insert into public.app_entity_records (entity_id, tenant_id, data, created_login)
    values (eid, 'aaaaaaaa-0000-0000-0000-000000000001',
      jsonb_build_object('date', to_char(current_date,'YYYY-MM-DD'), 'name', 'Петров П.П.', 'org', 'ООО «Инструмент-Про»', 'goal', 'обслуживание', 'note', 'Наладка станка'),
      'owner');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','App Builder — свои справочники и журналы (P2)',
   'Модуль «Конструктор приложений»: без разработки создаются пользовательские сущности — задаются поля (текст, число, дата, список, флаг, текстarea) и ведутся записи. Подходит для журналов, реестров, дополнительных справочников предприятия. Данные изолированы по организации.',
   'app builder конструктор сущности поля записи журнал справочник P2')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='App Builder — свои справочники и журналы (P2)');
-- <<<<<<<<<< 0066_appbuilder.sql <<<<<<<<<<
-- >>>>>>>>>> 0067_escrow.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0067_escrow.sql  (v45 — ЭПИК G: P5 платежи и эскроу)
-- Эскроу-сделки: средства замораживаются до приёмки работ, комиссия платформы,
-- журнал событий, споры. База знаний. Зависит от 0001..0066.
-- ============================================================

create sequence if not exists public.app_escrow_seq;
create table if not exists public.app_escrow_deals (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text,
  order_id     uuid references public.app_orders (id) on delete set null,
  customer_id  uuid references public.app_customers (id) on delete set null,
  buyer        text,
  seller       text,
  amount       numeric not null default 0,
  fee_pct      numeric not null default 2.5,
  milestone    text,
  status       text not null default 'created', -- created|funded|in_work|released|dispute|cancelled
  funded_at    timestamptz,
  released_at  timestamptz,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_escrow_deals_idx on public.app_escrow_deals (tenant_id, status);
alter table public.app_escrow_deals enable row level security;

create table if not exists public.app_escrow_events (
  id         uuid primary key default gen_random_uuid(),
  deal_id    uuid references public.app_escrow_deals (id) on delete cascade,
  kind       text not null default 'note', -- created|funded|milestone|released|dispute|refund|note
  comment    text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_escrow_events_idx on public.app_escrow_events (deal_id, created_at);
alter table public.app_escrow_events enable row level security;

create or replace function public.app_escrow_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, order_number text, buyer text, seller text, amount numeric, fee_pct numeric,
               fee numeric, payout numeric, milestone text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.number, o.number, d.buyer, d.seller, d.amount, d.fee_pct,
           round(d.amount*d.fee_pct/100.0,2), round(d.amount*(1-d.fee_pct/100.0),2), d.milestone, d.status, d.created_at
    from public.app_escrow_deals d left join public.app_orders o on o.id=d.order_id
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(coalesce(d.number,'')) like '%'||qq||'%' or lower(coalesce(d.buyer,'')) like '%'||qq||'%' or lower(coalesce(d.seller,'')) like '%'||qq||'%')
    order by d.created_at desc;
end $$;

create or replace function public.app_escrow_kpi(p_token uuid)
returns table (total bigint, active bigint, released_sum numeric, frozen_sum numeric, fee_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*),
    count(*) filter (where status in ('funded','in_work','dispute')),
    coalesce(sum(amount) filter (where status='released'),0),
    coalesce(sum(amount) filter (where status in ('funded','in_work')),0),
    coalesce(sum(amount*fee_pct/100.0) filter (where status='released'),0)
    from public.app_escrow_deals where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_escrow_save(p_token uuid, p_id uuid, p_order_id uuid, p_customer_id uuid,
  p_buyer text, p_seller text, p_amount numeric, p_fee_pct numeric, p_milestone text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; did uuid; dnum text; tname text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Укажите сумму сделки'; return; end if;
  select name into tname from public.tenants where id=ten;
  select name into cname from public.app_customers where id=p_customer_id;
  if p_id is null then
    dnum := 'ESC-' || lpad(nextval('public.app_escrow_seq')::text, 5, '0');
    insert into public.app_escrow_deals (tenant_id, number, order_id, customer_id, buyer, seller, amount, fee_pct, milestone, note, created_login)
    values (ten, dnum, p_order_id, p_customer_id, coalesce(nullif(trim(p_buyer),''), cname), coalesce(nullif(trim(p_seller),''), tname),
            p_amount, coalesce(p_fee_pct,2.5), nullif(trim(p_milestone),''), nullif(trim(p_note),''), ulogin)
    returning id into did;
    insert into public.app_escrow_events (deal_id, kind, comment, by_login) values (did, 'created', 'Сделка создана', ulogin);
    return query select did, dnum, 'Эскроу-сделка создана';
  else
    update public.app_escrow_deals set order_id=p_order_id, customer_id=p_customer_id,
      buyer=coalesce(nullif(trim(p_buyer),''),buyer), seller=coalesce(nullif(trim(p_seller),''),seller),
      amount=p_amount, fee_pct=coalesce(p_fee_pct,fee_pct), milestone=nullif(trim(p_milestone),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into did, dnum;
    return query select did, dnum, 'Сделка обновлена';
  end if;
end $$;

create or replace function public.app_escrow_set_status(p_token uuid, p_id uuid, p_status text, p_comment text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('created','funded','in_work','released','dispute','cancelled') then return query select false,'Неверный статус'; return; end if;
  select * into d from public.app_escrow_deals where id=p_id and (urole='admin' or tenant_id=ten);
  if d.id is null then return query select false,'Сделка не найдена'; return; end if;
  update public.app_escrow_deals set status=p_status,
    funded_at = case when p_status='funded' then now() else funded_at end,
    released_at = case when p_status='released' then now() else released_at end
   where id=p_id;
  insert into public.app_escrow_events (deal_id, kind, comment, by_login)
  values (p_id, p_status, coalesce(nullif(trim(p_comment),''), 'Статус: '||p_status), ulogin);
  if p_status in ('released','dispute') then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','economist'],
      'Эскроу '||d.number||': '||p_status, coalesce(p_comment,''), 'apps/escrow/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_escrow_events_list(p_token uuid, p_deal_id uuid)
returns table (id uuid, kind text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.kind, e.comment, e.by_login, e.created_at
    from public.app_escrow_events e join public.app_escrow_deals d on d.id=e.deal_id
    where e.deal_id=p_deal_id and (urole='admin' or d.tenant_id=ten)
    order by e.created_at desc;
end $$;

grant execute on function public.app_escrow_list(uuid,text) to anon, authenticated;
grant execute on function public.app_escrow_kpi(uuid) to anon, authenticated;
grant execute on function public.app_escrow_save(uuid,uuid,uuid,uuid,text,text,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_escrow_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_escrow_events_list(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_escrow_deals (tenant_id, number, order_id, customer_id, buyer, seller, amount, fee_pct, milestone, status, funded_at, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'ESC-' || lpad(nextval('public.app_escrow_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
  (select name from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
  (select name from public.tenants where id='aaaaaaaa-0000-0000-0000-000000000001'),
  450000, 2.5, 'Отгрузка готовой оснастки', 'funded', now(), 'manager'
where not exists (select 1 from public.app_escrow_deals where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Эскроу-сделки (P5)',
   'Модуль «Эскроу»: сделка (ESC-NNNNN) связывает заявку и заказчика, фиксирует сумму, комиссию платформы (%) и этап/веху. Средства «замораживаются» (status funded) и высвобождаются исполнителю после приёмки (released); при разногласиях — спор (dispute). Ведётся журнал событий. KPI: всего, активных, высвобождено, заморожено, комиссия.',
   'эскроу платежи сделка комиссия заморозка высвобождение спор P5')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Эскроу-сделки (P5)');
-- <<<<<<<<<< 0067_escrow.sql <<<<<<<<<<
-- >>>>>>>>>> 0068_whitelabel.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0068_whitelabel.sql  (v46 — ЭПИК G: P6 white-label)
-- Брендирование организации: поддомен, логотип, цвет/тема, разрешение темы
-- по поддомену. База знаний. Зависит от 0001..0067.
-- ============================================================

alter table public.tenants add column if not exists subdomain text;
alter table public.tenants add column if not exists custom_domain text;
alter table public.tenants add column if not exists theme jsonb not null default '{}'::jsonb;

create unique index if not exists tenants_subdomain_idx on public.tenants (lower(subdomain)) where subdomain is not null;

-- ---------- Чтение/запись бренда организации ----------
create or replace function public.app_whitelabel_get(p_token uuid)
returns table (tenant_id uuid, name text, subdomain text, custom_domain text, plan text, status text,
               brand jsonb, theme jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole = 'admin' and ten is null then
    return query select t.id, t.name, t.subdomain, t.custom_domain, t.plan, t.status,
                        coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb)
      from public.tenants t order by t.created_at limit 1;
  end if;
  return query select t.id, t.name, t.subdomain, t.custom_domain, t.plan, t.status,
                      coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb)
    from public.tenants t where t.id = ten;
end $$;

create or replace function public.app_whitelabel_save(p_token uuid, p_subdomain text, p_custom_domain text,
  p_brand jsonb, p_theme jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sd text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner') then return query select false,'Недостаточно прав'; return; end if;
  if ten is null then return query select false,'Организация не определена'; return; end if;
  sd := lower(nullif(trim(coalesce(p_subdomain,'')),''));
  if sd is not null and sd !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' then
    return query select false,'Поддомен: только латиница, цифры и дефис'; return;
  end if;
  if sd is not null and exists (select 1 from public.tenants where lower(subdomain)=sd and id<>ten) then
    return query select false,'Поддомен уже занят'; return;
  end if;
  update public.tenants set subdomain=sd, custom_domain=nullif(trim(coalesce(p_custom_domain,'')),''),
    brand=coalesce(p_brand, brand), theme=coalesce(p_theme, theme)
   where id=ten;
  return query select true,'Брендирование сохранено';
end $$;

-- ---------- Разрешение темы по поддомену (для клиента, гость) ----------
create or replace function public.app_whitelabel_resolve(p_subdomain text)
returns table (tenant_id uuid, name text, brand jsonb, theme jsonb, plan text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare sd text;
begin
  sd := lower(nullif(trim(coalesce(p_subdomain,'')),''));
  if sd is null then return; end if;
  return query select t.id, t.name, coalesce(t.brand,'{}'::jsonb), coalesce(t.theme,'{}'::jsonb), t.plan
    from public.tenants t
    where (lower(t.subdomain)=sd or lower(t.custom_domain)=sd) and coalesce(t.status,'active')<>'suspended';
end $$;

grant execute on function public.app_whitelabel_get(uuid) to anon, authenticated;
grant execute on function public.app_whitelabel_save(uuid,text,text,jsonb,jsonb) to anon, authenticated;
grant execute on function public.app_whitelabel_resolve(text) to anon, authenticated;

-- ---------- Демо-тема (тенант A) ----------
update public.tenants
   set subdomain = coalesce(subdomain, 'demo'),
       theme = case when theme is null or theme='{}'::jsonb
         then jsonb_build_object('accent','#0e7490','logo','3DMP','slogan','Производство под ключ')
         else theme end
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','White-label — брендирование и поддомен (P6)',
   'Модуль «Брендирование»: организация задаёт поддомен (например 3dmp.sapfir.eu), свой домен, логотип, акцентный цвет и слоган. Тема хранится в tenants.theme и разрешается по поддомену (app_whitelabel_resolve) — клиент применяет бренд. Поддомен уникален.',
   'white-label бренд поддомен логотип тема цвет домен P6')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='White-label — брендирование и поддомен (P6)');
-- <<<<<<<<<< 0068_whitelabel.sql <<<<<<<<<<
-- >>>>>>>>>> 0069_hierarchy.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0069_hierarchy.sql  (v47 — ЭПИК G: P13 подразделения и иерархия)
-- Дерево подразделений организации, руководители, связь сотрудников. База знаний.
-- Зависит от 0001..0068.
-- ============================================================

create table if not exists public.app_departments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  parent_id   uuid references public.app_departments (id) on delete set null,
  name        text not null,
  code        text,
  head        text,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_departments_idx on public.app_departments (tenant_id, parent_id);
alter table public.app_departments enable row level security;

-- Связь сотрудника с подразделением (если есть таблица сотрудников)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='app_employees') then
    alter table public.app_employees add column if not exists department_id uuid references public.app_departments (id) on delete set null;
  end if;
end $$;

create or replace function public.app_departments_list(p_token uuid, p_q text default null)
returns table (id uuid, parent_id uuid, name text, code text, head text, active boolean, employees bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.parent_id, d.name, d.code, d.head, d.active,
      (select count(*) from public.app_employees e where e.department_id=d.id)
    from public.app_departments d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.name) like '%'||qq||'%' or lower(coalesce(d.code,'')) like '%'||qq||'%' or lower(coalesce(d.head,'')) like '%'||qq||'%')
    order by d.name;
end $$;

create or replace function public.app_department_kpi(p_token uuid)
returns table (total bigint, root bigint, with_head bigint, max_depth int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with recursive t as (
      select d.id, d.parent_id, 1 as depth from public.app_departments d
        where (urole='admin' or d.tenant_id=ten) and d.parent_id is null
      union all
      select d.id, d.parent_id, t.depth+1 from public.app_departments d join t on d.parent_id=t.id
    )
    select (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten) and parent_id is null),
      (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten) and coalesce(head,'')<>''),
      coalesce((select max(depth) from t),0);
end $$;

create or replace function public.app_department_save(p_token uuid, p_id uuid, p_parent_id uuid, p_name text,
  p_code text, p_head text, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название подразделения'; return; end if;
  if p_parent_id = p_id and p_id is not null then raise exception 'Подразделение не может быть родителем само себе'; return; end if;
  if p_id is null then
    insert into public.app_departments (tenant_id, parent_id, name, code, head, note, active)
    values (ten, p_parent_id, trim(p_name), nullif(trim(p_code),''), nullif(trim(p_head),''), nullif(trim(p_note),''), coalesce(p_active,true))
    returning id into did;
    return query select did, 'Подразделение создано';
  else
    update public.app_departments set parent_id=p_parent_id, name=trim(p_name), code=nullif(trim(p_code),''),
      head=nullif(trim(p_head),''), note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Подразделение обновлено';
  end if;
end $$;

create or replace function public.app_department_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; kids int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*) into kids from public.app_departments where parent_id=p_id;
  if kids > 0 then return query select false,'Есть дочерние подразделения — сначала перенесите их'; return; end if;
  delete from public.app_departments where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Подразделение удалено';
end $$;

grant execute on function public.app_departments_list(uuid,text) to anon, authenticated;
grant execute on function public.app_department_kpi(uuid) to anon, authenticated;
grant execute on function public.app_department_save(uuid,uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_department_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо-структура (тенант A) ----------
do $$
declare d_gen uuid; d_prod uuid; d_mech uuid; d_qc uuid;
begin
  if not exists (select 1 from public.app_departments where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_departments (tenant_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001','Управление','ADM','Директор') returning id into d_gen;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Производство','PROD','Начальник цеха') returning id into d_prod;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_prod, 'Механообработка','MECH','Мастер') returning id into d_mech;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'ОТК','QC','Начальник ОТК') returning id into d_qc;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Технологический отдел','TECH','Главный технолог');
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Снабжение','SUP','Начальник снабжения');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Подразделения и иерархия (P13)',
   'Модуль «Подразделения»: дерево структуры организации (родитель → потомки), код, руководитель, активность, число сотрудников. Сотрудники связываются с подразделением (app_employees.department_id). KPI: всего, корневых, с руководителем, глубина. Используется для разграничения и оргсхемы.',
   'подразделения иерархия оргструктура дерево отдел руководитель P13')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Подразделения и иерархия (P13)');
-- <<<<<<<<<< 0069_hierarchy.sql <<<<<<<<<<
-- >>>>>>>>>> 0070_industry.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0070_industry.sql  (v48 — ЭПИК G: P3 отраслевая аналитика)
-- Отраслевые бенчмарки (нормочас, OEE, брак, маржа и др.) + сравнение
-- показателей организации с отраслью + платформенная сводка. База знаний.
-- Зависит от 0001..0069.
-- ============================================================

create table if not exists public.app_industry_benchmarks (
  id         uuid primary key default gen_random_uuid(),
  metric     text not null,          -- normohour_rate|oee_pct|defect_pct|margin_pct|lead_days|utilization_pct
  category   text,                    -- оснастка|штампы|ЧПУ|металлообработка|общее
  region     text default 'RU',
  value      numeric not null default 0,
  unit       text,
  period     text,
  source     text,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists app_industry_benchmarks_idx on public.app_industry_benchmarks (metric, category);
alter table public.app_industry_benchmarks enable row level security;

create or replace function public.app_industry_benchmarks_list(p_token uuid, p_metric text default null)
returns table (id uuid, metric text, category text, region text, value numeric, unit text, period text, source text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  return query select b.id, b.metric, b.category, b.region, b.value, b.unit, b.period, b.source, b.note
    from public.app_industry_benchmarks b
    where (coalesce(p_metric,'')='' or b.metric=p_metric)
    order by b.metric, b.category;
end $$;

create or replace function public.app_industry_benchmark_save(p_token uuid, p_id uuid, p_metric text, p_category text,
  p_region text, p_value numeric, p_unit text, p_period text, p_source text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; bid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; return; end if;
  if coalesce(trim(p_metric),'')='' then raise exception 'Укажите метрику'; return; end if;
  if p_id is null then
    insert into public.app_industry_benchmarks (metric, category, region, value, unit, period, source, note)
    values (trim(p_metric), nullif(trim(p_category),''), coalesce(nullif(trim(p_region),''),'RU'), coalesce(p_value,0),
            nullif(trim(p_unit),''), nullif(trim(p_period),''), nullif(trim(p_source),''), nullif(trim(p_note),''))
    returning id into bid;
    return query select bid, 'Бенчмарк добавлен';
  else
    update public.app_industry_benchmarks set metric=trim(p_metric), category=nullif(trim(p_category),''),
      region=coalesce(nullif(trim(p_region),''),region), value=coalesce(p_value,value), unit=nullif(trim(p_unit),''),
      period=nullif(trim(p_period),''), source=nullif(trim(p_source),''), note=nullif(trim(p_note),'')
     where id=p_id returning id into bid;
    return query select bid, 'Бенчмарк обновлён';
  end if;
end $$;

-- Сравнение показателей организации с отраслевым бенчмарком
create or replace function public.app_industry_compare(p_token uuid)
returns table (metric text, own numeric, benchmark numeric, unit text, delta_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; own_nh numeric; own_oee numeric; own_def numeric; b_nh numeric; b_oee numeric; b_def numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  own_nh := (select avg(rate_hour) from public.app_cost_rates where (urole='admin' or tenant_id=ten) and rate_hour>0);
  own_oee := (select round(avg(case when planned_min>0 then (run_min/planned_min) * (case when total_qty>0 then good_qty/total_qty else 0 end) else null end)*100,1)
              from public.app_oee_log where (urole='admin' or tenant_id=ten));
  own_def := (select round(100.0*count(*) filter (where l.result='no')/greatest(count(*),1),1)
              from public.app_qc_lines l join public.app_qc_checks c on c.id=l.check_id
              where (urole='admin' or c.tenant_id=ten));

  b_nh := (select avg(value) from public.app_industry_benchmarks where metric='normohour_rate');
  b_oee := (select avg(value) from public.app_industry_benchmarks where metric='oee_pct');
  b_def := (select avg(value) from public.app_industry_benchmarks where metric='defect_pct');

  return query
  select 'normohour_rate', own_nh, b_nh, '₽/ч',
    case when coalesce(b_nh,0)>0 then round((own_nh-b_nh)/b_nh*100,1) else null end
  union all
  select 'oee_pct', own_oee, b_oee, '%',
    case when coalesce(b_oee,0)>0 then round((own_oee-b_oee)/b_oee*100,1) else null end
  union all
  select 'defect_pct', own_def, b_def, '%',
    case when coalesce(b_def,0)>0 then round((own_def-b_def)/b_def*100,1) else null end;
end $$;

-- Платформенная сводка (админ): агрегаты по всем организациям
create or replace function public.app_industry_stats(p_token uuid)
returns table (tenants bigint, active_tenants bigint, users bigint, orders bigint, naryads bigint, tenders bigint, escrow_released numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select
    (select count(*) from public.tenants),
    (select count(*) from public.tenants where coalesce(status,'active')='active'),
    (select count(*) from public.app_users),
    (select count(*) from public.app_orders),
    (select count(*) from public.app_naryads),
    (select count(*) from public.tenders),
    (select coalesce(sum(amount),0) from public.app_escrow_deals where status='released');
end $$;

grant execute on function public.app_industry_benchmarks_list(uuid,text) to anon, authenticated;
grant execute on function public.app_industry_benchmark_save(uuid,uuid,text,text,text,numeric,text,text,text,text) to anon, authenticated;
grant execute on function public.app_industry_compare(uuid) to anon, authenticated;
grant execute on function public.app_industry_stats(uuid) to anon, authenticated;

-- ---------- Отраслевые бенчмарки (демо-ориентиры) ----------
insert into public.app_industry_benchmarks (metric, category, region, value, unit, period, source, note)
select v.metric, v.cat, 'RU', v.val, v.unit, v.period, v.src, v.note
from (values
  ('normohour_rate','ЧПУ','RU'::text, 2500, '₽/ч','2026','обзор рынка','Средняя ставка нормочаса ЧПУ'),
  ('normohour_rate','Слесарные',null, 1200, '₽/ч','2026','обзор рынка','Слесарная обработка'),
  ('oee_pct','Металлообработка',null, 65, '%','2026','benchmark','Целевой OEE'),
  ('defect_pct','Металлообработка',null, 3, '%','2026','benchmark','Допустимый уровень брака'),
  ('margin_pct','Оснастка',null, 22, '%','2026','benchmark','Средняя маржа по оснастке'),
  ('lead_days','Оснастка',null, 45, 'дн','2026','benchmark','Средний срок изготовления'),
  ('utilization_pct','ЧПУ',null, 78, '%','2026','benchmark','Загрузка оборудования')
) as v(metric,cat,region,val,unit,period,src,note)
where not exists (select 1 from public.app_industry_benchmarks where metric='normohour_rate' and category='ЧПУ');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Отраслевая аналитика и бенчмарки (P3)',
   'Модуль «Отраслевая аналитика»: эталонные отраслевые показатели (нормочас, OEE, брак, маржа, сроки, загрузка) и сравнение показателей вашей организации с отраслью — вычисляются отклонения (delta %). Администратор платформы видит сводку по всем организациям.',
   'отраслевая аналитика бенчмарк нормочас OEE брак маржа сравнение P3')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Отраслевая аналитика и бенчмарки (P3)');
-- <<<<<<<<<< 0070_industry.sql <<<<<<<<<<
-- >>>>>>>>>> 0071_marketplace.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0071_marketplace.sql  (v49 — ЭПИК G: M1 маркетплейс мощностей)
-- Витрина свободных мощностей предприятий (кооперация/субподряд) и заявки на
-- выполнение. База знаний. Зависит от 0001..0070.
-- ============================================================

create table if not exists public.app_market_listings (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  title          text not null,
  process        text,   -- cnc|edm|grinding|heat|assembly|engraving|other
  machine        text,
  capacity_hours numeric,
  price_from     numeric,
  region         text,
  lead_days      int,
  status         text not null default 'active', -- active|paused|closed
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_market_listings_idx on public.app_market_listings (status, process);
alter table public.app_market_listings enable row level security;

create table if not exists public.app_market_requests (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  listing_id   uuid references public.app_market_listings (id) on delete set null,
  title        text not null,
  qty          numeric default 1,
  due_date     date,
  budget       numeric,
  status       text not null default 'new', -- new|quoted|accepted|declined|closed
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_market_requests_idx on public.app_market_requests (tenant_id, status);
alter table public.app_market_requests enable row level security;

-- ---------- Витрина мощностей ----------
create or replace function public.app_market_listings_list(p_token uuid, p_process text default null, p_q text default null)
returns table (id uuid, title text, process text, machine text, capacity_hours numeric, price_from numeric, region text,
               lead_days int, status text, seller text, mine boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select l.id, l.title, l.process, l.machine, l.capacity_hours, l.price_from, l.region, l.lead_days, l.status,
           t.name, (l.tenant_id = ten), l.created_at
    from public.app_market_listings l join public.tenants t on t.id=l.tenant_id
    where (l.status='active' or l.tenant_id=ten or urole='admin')
      and (coalesce(p_process,'')='' or l.process=p_process)
      and (qq='' or lower(l.title) like '%'||qq||'%' or lower(coalesce(l.machine,'')) like '%'||qq||'%' or lower(coalesce(l.region,'')) like '%'||qq||'%')
    order by (l.status<>'active'), l.created_at desc;
end $$;

create or replace function public.app_market_listing_save(p_token uuid, p_id uuid, p_title text, p_process text,
  p_machine text, p_capacity_hours numeric, p_price_from numeric, p_region text, p_lead_days int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите название объявления'; return; end if;
  if p_id is null then
    insert into public.app_market_listings (tenant_id, title, process, machine, capacity_hours, price_from, region, lead_days, note, created_login)
    values (ten, trim(p_title), nullif(trim(p_process),''), nullif(trim(p_machine),''), p_capacity_hours, p_price_from,
            nullif(trim(p_region),''), p_lead_days, nullif(trim(p_note),''), ulogin)
    returning id into lid;
    return query select lid, 'Объявление размещено';
  else
    update public.app_market_listings set title=trim(p_title), process=nullif(trim(p_process),''), machine=nullif(trim(p_machine),''),
      capacity_hours=p_capacity_hours, price_from=p_price_from, region=nullif(trim(p_region),''), lead_days=p_lead_days, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Объявление обновлено';
  end if;
end $$;

create or replace function public.app_market_listing_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('active','paused','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_market_listings set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ---------- Заявки на выполнение ----------
create or replace function public.app_market_requests_list(p_token uuid, p_q text default null)
returns table (id uuid, listing_title text, seller text, title text, qty numeric, due_date date, budget numeric,
               status text, mine boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select r.id, l.title, st.name, r.title, r.qty, r.due_date, r.budget, r.status, (r.tenant_id=ten), r.created_at
    from public.app_market_requests r
    left join public.app_market_listings l on l.id=r.listing_id
    left join public.tenants st on st.id=l.tenant_id
    where (urole='admin' or r.tenant_id=ten or l.tenant_id=ten)
      and (qq='' or lower(r.title) like '%'||qq||'%' or lower(coalesce(l.title,'')) like '%'||qq||'%')
    order by r.created_at desc;
end $$;

create or replace function public.app_market_request_save(p_token uuid, p_id uuid, p_listing_id uuid, p_title text,
  p_qty numeric, p_due_date date, p_budget numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите предмет заявки'; return; end if;
  if p_id is null then
    insert into public.app_market_requests (tenant_id, listing_id, title, qty, due_date, budget, note, created_login)
    values (ten, p_listing_id, trim(p_title), coalesce(p_qty,1), p_due_date, p_budget, nullif(trim(p_note),''), ulogin)
    returning id into rid;
    if p_listing_id is not null then
      perform public.app_notif_roles_t((select tenant_id from public.app_market_listings where id=p_listing_id),
        array['admin','owner','manager'], 'Заявка из маркетплейса: '||trim(p_title), '', 'apps/marketplace/index.html');
    end if;
    return query select rid, 'Заявка отправлена';
  else
    update public.app_market_requests set listing_id=p_listing_id, title=trim(p_title), qty=coalesce(p_qty,qty),
      due_date=p_due_date, budget=p_budget, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into rid;
    return query select rid, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_market_request_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; lid uuid; seller uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','quoted','accepted','declined','closed') then return query select false,'Неверный статус'; return; end if;
  select r.listing_id, l.tenant_id into lid, seller from public.app_market_requests r
    left join public.app_market_listings l on l.id=r.listing_id
    where r.id=p_id and (urole='admin' or r.tenant_id=ten or l.tenant_id=ten);
  if not found then return query select false,'Заявка не найдена'; return; end if;
  update public.app_market_requests set status=p_status where id=p_id;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_market_kpi(p_token uuid)
returns table (my_listings bigint, active_listings bigint, my_requests bigint, accepted bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_market_listings where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_listings where status='active' and (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_requests where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_requests where status='accepted' and (urole='admin' or tenant_id=ten));
end $$;

grant execute on function public.app_market_listings_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_market_listing_save(uuid,uuid,text,text,text,numeric,numeric,text,int,text) to anon, authenticated;
grant execute on function public.app_market_listing_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_market_requests_list(uuid,text) to anon, authenticated;
grant execute on function public.app_market_request_save(uuid,uuid,uuid,text,numeric,date,numeric,text) to anon, authenticated;
grant execute on function public.app_market_request_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_market_kpi(uuid) to anon, authenticated;

-- ---------- Демо-объявления (тенант A) ----------
insert into public.app_market_listings (tenant_id, title, process, machine, capacity_hours, price_from, region, lead_days, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.proc, v.machine, v.cap, v.price, v.region, v.lead, v.note, 'manager'
from (values
  ('Свободные мощности фрезерной группы','cnc','Feeler FTC-350Xl', 320, 2500, 'Пермь', 14, '3/5-осевая обработка'),
  ('Проволочная ЭЭО','edm','Mitsubishi FA10-VS', 180, 2200, 'Пермь', 10, 'Точная резка контура'),
  ('Термообработка (закалка/отпуск)','heat','Камерная печь', 240, 90, 'Пермь', 7, 'По кг'),
  ('Гравирование лазером','engraving','Лазерный маркер', 160, 35, 'Пермь', 3, 'Маркировка партий')
) as v(title,proc,machine,cap,price,region,lead,note)
where not exists (select 1 from public.app_market_listings where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Маркетплейс мощностей (M1)',
   'Модуль «Маркетплейс»: предприятия публикуют свободные мощности (процесс, станок, доступные часы, цена от, регион, срок) и видят витрину активных объявлений других организаций. Заявка на выполнение (кол-во, срок, бюджет) уходит владельцу мощности, статусы: новая → предложение → принята/отклонена. Кооперация и субподряд.',
   'маркетплейс мощности кооперация субподряд свободные мощности объявления M1')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Маркетплейс мощностей (M1)');
-- <<<<<<<<<< 0071_marketplace.sql <<<<<<<<<<
-- >>>>>>>>>> 0072_scale.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0072_scale.sql  (v50 — ЭПИК G: масштаб и эксплуатация)
-- Пагинация длинных списков, индексы, автотесты (смоук), журнал бэкапов,
-- статистика объёма БД. База знаний. Зависит от 0001..0071.
-- ============================================================

-- ---------- Индексы (производительность) ----------
create index if not exists app_orders_tenant_status_idx on public.app_orders (tenant_id, status, created_at desc);
create index if not exists app_naryads_tenant_status_idx on public.app_naryads (tenant_id, status);
create index if not exists app_stock_moves_tenant_idx on public.app_stock_moves (tenant_id, created_at desc);
create index if not exists app_notifications_unread_idx on public.app_notifications (user_id) where read_at is null;
create index if not exists app_documents_tenant_idx on public.app_documents (tenant_id, doc_type, created_at desc);
create index if not exists app_attachments_ref_idx on public.app_attachments (entity_type, entity_id);

-- ---------- Пагинация длинных списков ----------
create or replace function public.app_page_count(p_token uuid, p_kind text, p_q text default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; qq text; n bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  if p_kind='orders' then
    select count(*) into n from public.app_orders o
      where (urole='admin' or o.tenant_id=ten) and (qq='' or lower(coalesce(o.number,'')||' '||coalesce(o.title,'')) like '%'||qq||'%');
  elsif p_kind='knowledge' then
    select count(*) into n from public.app_knowledge k
      where (k.tenant_id is null or urole='admin' or k.tenant_id=ten) and (qq='' or lower(k.question||' '||coalesce(k.tags,'')) like '%'||qq||'%');
  elsif p_kind='events' then
    select count(*) into n from public.app_events e
      where (urole='admin' or e.login=ulogin) and (qq='' or lower(coalesce(e.action,'')||' '||coalesce(e.detail,'')) like '%'||qq||'%');
  elsif p_kind='calc' then
    select count(*) into n from public.app_calc_saves c
      where (urole='admin' or c.tenant_id=ten) and (qq='' or lower(coalesce(c.title,'')||' '||coalesce(c.ref,'')) like '%'||qq||'%');
  else
    n := 0;
  end if;
  return n;
end $$;

create or replace function public.app_page_rows(p_token uuid, p_kind text, p_page int default 1, p_size int default 20, p_q text default null)
returns table (id uuid, title text, subtitle text, meta text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; qq text; off int; lim int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  lim := greatest(1, least(coalesce(p_size,20), 200));
  off := greatest(0, (greatest(coalesce(p_page,1),1)-1)*lim);
  return query
    select o.id, o.number, coalesce(o.title,''), o.status, o.created_at from public.app_orders o
      where p_kind='orders' and (urole='admin' or o.tenant_id=ten)
        and (qq='' or lower(coalesce(o.number,'')||' '||coalesce(o.title,'')) like '%'||qq||'%')
    union all
    select k.id, k.question, coalesce(k.category,''), left(coalesce(k.answer,''), 80), coalesce(k.created_at, now()) from public.app_knowledge k
      where p_kind='knowledge' and (k.tenant_id is null or urole='admin' or k.tenant_id=ten)
        and (qq='' or lower(k.question||' '||coalesce(k.tags,'')) like '%'||qq||'%')
    union all
    select e.id, e.action, coalesce(e.detail,''), coalesce(e.login,''), e.created_at from public.app_events e
      where p_kind='events' and (urole='admin' or e.login=ulogin)
        and (qq='' or lower(coalesce(e.action,'')||' '||coalesce(e.detail,'')) like '%'||qq||'%')
    union all
    select c.id, coalesce(c.title,'Расчёт'), c.kind, coalesce(c.ref,''), c.created_at from public.app_calc_saves c
      where p_kind='calc' and (urole='admin' or c.tenant_id=ten)
        and (qq='' or lower(coalesce(c.title,'')||' '||coalesce(c.ref,'')) like '%'||qq||'%')
    order by created_at desc
    limit lim offset off;
end $$;

-- ---------- Журнал бэкапов ----------
create table if not exists public.app_backup_log (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  kind       text not null default 'manual', -- manual|auto|restore
  scope      text,
  note       text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_backup_log_idx on public.app_backup_log (created_at desc);
alter table public.app_backup_log enable row level security;

create or replace function public.app_backup_note(p_token uuid, p_kind text, p_scope text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole <> 'admin' then return query select false,'Только администратор платформы'; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_backup_log (tenant_id, kind, scope, note, by_login)
  values (ten, coalesce(nullif(trim(p_kind),''),'manual'), nullif(trim(p_scope),''), nullif(trim(p_note),''), ulogin);
  return query select true,'Запись о резервной копии добавлена';
end $$;

create or replace function public.app_backup_list(p_token uuid, p_limit int default 50)
returns table (id uuid, kind text, scope text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select b.id, b.kind, b.scope, b.note, b.by_login, b.created_at
    from public.app_backup_log b order by b.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

-- ---------- Смоук-тест (автотесты) ----------
create or replace function public.app_smoke_test(p_token uuid)
returns table (name text, ok boolean, detail text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  name := 'Сессия и права'; ok := true; detail := 'роль='||coalesce(urole,'—')||', организация='||coalesce(ten::text,'—'); return next;

  begin
    execute 'select count(*) from public.app_users' into cnt;
    name := 'Таблица пользователей'; ok := cnt>0; detail := cnt||' пользователей'; return next;
  exception when others then name := 'Таблица пользователей'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_orders where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Заявки'; ok := true; detail := cnt||' заявок'; return next;
  exception when others then name := 'Заявки'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_naryads where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Наряды'; ok := true; detail := cnt||' нарядов'; return next;
  exception when others then name := 'Наряды'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_materials where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Материалы'; ok := true; detail := cnt||' позиций'; return next;
  exception when others then name := 'Материалы'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_knowledge where ($1 is null or tenant_id=$1 or tenant_id is null)' into cnt using ten;
    name := 'База знаний'; ok := cnt>0; detail := cnt||' статей'; return next;
  exception when others then name := 'База знаний'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_calc_saves where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Мини-сервисы (0063)'; ok := true; detail := cnt||' расчётов'; return next;
  exception when others then name := 'Мини-сервисы (0063)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_escrow_deals where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Эскроу (0067)'; ok := true; detail := cnt||' сделок'; return next;
  exception when others then name := 'Эскроу (0067)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_entity_records' into cnt;
    name := 'App Builder (0066)'; ok := true; detail := cnt||' записей'; return next;
  exception when others then name := 'App Builder (0066)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_market_listings' into cnt;
    name := 'Маркетплейс (0071)'; ok := true; detail := cnt||' объявлений'; return next;
  exception when others then name := 'Маркетплейс (0071)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;
end $$;

-- ---------- Статистика объёма (админ) ----------
create or replace function public.app_scale_stats(p_token uuid)
returns table (tables bigint, functions bigint, users bigint, orders bigint, naryads bigint, notifications bigint, attachments bigint, attachments_bytes bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select
    (select count(*) from information_schema.tables where table_schema='public' and table_name like 'app\_%' escape '\'),
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'app\_%' escape '\'),
    (select count(*) from public.app_users),
    (select count(*) from public.app_orders),
    (select count(*) from public.app_naryads),
    (select count(*) from public.app_notifications),
    (select count(*) from public.app_attachments),
    (select coalesce(sum(length(data)),0) from public.app_attachments);
end $$;

grant execute on function public.app_page_count(uuid,text,text) to anon, authenticated;
grant execute on function public.app_page_rows(uuid,text,int,int,text) to anon, authenticated;
grant execute on function public.app_backup_note(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_backup_list(uuid,int) to anon, authenticated;
grant execute on function public.app_smoke_test(uuid) to anon, authenticated;
grant execute on function public.app_scale_stats(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Эксплуатация','Масштаб, пагинация и автотесты',
   'Раздел «Масштаб и эксплуатация»: постраничный вывод длинных списков (заявки, база знаний, журнал, расчёты) — app_page_count/app_page_rows; самотестирование системы (смоук) — app_smoke_test проверяет доступность ключевых таблиц и миграций; журнал резервных копий (app_backup_*) для админа; статистика объёма БД (app_scale_stats). Добавлены индексы по частым фильтрам.',
   'масштаб пагинация индексы бэкап автотесты смоук эксплуатация производительность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Масштаб, пагинация и автотесты');
-- <<<<<<<<<< 0072_scale.sql <<<<<<<<<<
-- >>>>>>>>>> 0073_norms_core.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0073_norms_core.sql  (v51 — P14 «Нормирование PRO», Сессия C)
-- Ядро нормирования: операции и ставки (диапазоны по сложности), K-коэффициенты
-- (материал/точность/геометрия/оснастка), серийность, база аналогов + автоподбор,
-- расчёт нормы. Логика перенесена из «Нормирование PRO» (без копирования файлов).
-- База знаний. Зависит от 0001..0072.
-- ============================================================

create table if not exists public.app_norms_operations (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  code         text not null,
  name         text not null,
  category     text,                       -- milling|turning|edm|grinding|locksmith|engraving|heat|other
  machine_type text,
  unit         text default 'н/ч',
  note         text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists app_norms_operations_idx on public.app_norms_operations (tenant_id, active, category);
alter table public.app_norms_operations enable row level security;

create table if not exists public.app_norms_rates (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  operation_id uuid references public.app_norms_operations (id) on delete cascade,
  complexity   text not null default 'mid',   -- simple|mid|hard
  sale_min     numeric not null default 0,
  sale_max     numeric not null default 0,
  cost_ratio   numeric not null default 0.70
);
create index if not exists app_norms_rates_idx on public.app_norms_rates (operation_id);
alter table public.app_norms_rates enable row level security;

create table if not exists public.app_norms_kfactors (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  category   text not null,   -- material|accuracy|geometry|fixture
  name       text not null,
  value      numeric not null default 1,
  note       text
);
create index if not exists app_norms_kfactors_idx on public.app_norms_kfactors (tenant_id, category);
alter table public.app_norms_kfactors enable row level security;

create table if not exists public.app_norms_serial (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  label     text,
  qty_min   int not null default 1,
  qty_max   int,                       -- null = без верхней границы
  factor    numeric not null default 1
);
create index if not exists app_norms_serial_idx on public.app_norms_serial (tenant_id);
alter table public.app_norms_serial enable row level security;

create table if not exists public.app_analogs (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  material   text,
  operation  text,
  weight     numeric,
  dims       text,
  norm_base  numeric,
  tags       text,
  note       text,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists app_analogs_idx on public.app_analogs (tenant_id, material, operation);
alter table public.app_analogs enable row level security;

-- ---------- Операции ----------
create or replace function public.app_norms_ops_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, category text, machine_type text, unit text, active boolean, rates bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select o.id, o.code, o.name, o.category, o.machine_type, o.unit, o.active,
      (select count(*) from public.app_norms_rates r where r.operation_id=o.id)
    from public.app_norms_operations o
    where (urole='admin' or o.tenant_id=ten)
      and (qq='' or lower(o.name) like '%'||qq||'%' or lower(o.code) like '%'||qq||'%')
    order by o.category, o.name;
end $$;

create or replace function public.app_norms_op_save(p_token uuid, p_id uuid, p_code text, p_name text,
  p_category text, p_machine_type text, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; oid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','master') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_code),'')='' then raise exception 'Укажите код и название операции'; return; end if;
  if p_id is null then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, note, active)
    values (ten, upper(trim(p_code)), trim(p_name), nullif(trim(p_category),''), nullif(trim(p_machine_type),''), nullif(trim(p_note),''), coalesce(p_active,true))
    returning id into oid;
    return query select oid, 'Операция создана';
  else
    update public.app_norms_operations set code=upper(trim(p_code)), name=trim(p_name),
      category=nullif(trim(p_category),''), machine_type=nullif(trim(p_machine_type),''), note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into oid;
    return query select oid, 'Операция обновлена';
  end if;
end $$;

-- ---------- Ставки ----------
create or replace function public.app_norms_rates_list(p_token uuid, p_operation_id uuid)
returns table (id uuid, complexity text, sale_min numeric, sale_max numeric, cost_ratio numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.complexity, r.sale_min, r.sale_max, r.cost_ratio
    from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id
    where r.operation_id=p_operation_id and (urole='admin' or o.tenant_id=ten)
    order by (case r.complexity when 'simple' then 1 when 'mid' then 2 else 3 end);
end $$;

create or replace function public.app_norms_rate_save(p_token uuid, p_id uuid, p_operation_id uuid, p_complexity text,
  p_sale_min numeric, p_sale_max numeric, p_cost_ratio numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','economist') then raise exception 'Недостаточно прав'; return; end if;
  if p_complexity not in ('simple','mid','hard') then raise exception 'Сложность: simple|mid|hard'; return; end if;
  if not exists (select 1 from public.app_norms_operations o where o.id=p_operation_id and (urole='admin' or o.tenant_id=ten)) then raise exception 'Операция не найдена'; return; end if;
  if p_id is null then
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio)
    values (ten, p_operation_id, p_complexity, coalesce(p_sale_min,0), coalesce(p_sale_max,0), coalesce(p_cost_ratio,0.7))
    returning id into rid;
    return query select rid, 'Ставка добавлена';
  else
    update public.app_norms_rates set complexity=p_complexity, sale_min=coalesce(p_sale_min,0),
      sale_max=coalesce(p_sale_max,0), cost_ratio=coalesce(p_cost_ratio,0.7)
     where id=p_id and operation_id=p_operation_id returning id into rid;
    return query select rid, 'Ставка обновлена';
  end if;
end $$;

create or replace function public.app_norms_rate_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_norms_rates r using public.app_norms_operations o
    where r.id=p_id and o.id=r.operation_id and (urole='admin' or o.tenant_id=ten);
  return query select true,'Ставка удалена';
end $$;

-- ---------- K-коэффициенты ----------
create or replace function public.app_norms_k_list(p_token uuid, p_category text default null)
returns table (id uuid, category text, name text, value numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select k.id, k.category, k.name, k.value, k.note
    from public.app_norms_kfactors k
    where (urole='admin' or k.tenant_id=ten) and (coalesce(p_category,'')='' or k.category=p_category)
    order by k.category, k.value;
end $$;

create or replace function public.app_norms_k_save(p_token uuid, p_id uuid, p_category text, p_name text, p_value numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; kid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if p_category not in ('material','accuracy','geometry','fixture') then raise exception 'Категория: material|accuracy|geometry|fixture'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_norms_kfactors (tenant_id, category, name, value, note)
    values (ten, p_category, trim(p_name), coalesce(p_value,1), nullif(trim(p_note),'')) returning id into kid;
    return query select kid, 'Коэффициент добавлен';
  else
    update public.app_norms_kfactors set category=p_category, name=trim(p_name), value=coalesce(p_value,1), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into kid;
    return query select kid, 'Коэффициент обновлён';
  end if;
end $$;

create or replace function public.app_norms_k_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_norms_kfactors where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Коэффициент удалён';
end $$;

-- ---------- Серийность ----------
create or replace function public.app_norms_serial_list(p_token uuid)
returns table (id uuid, label text, qty_min int, qty_max int, factor numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select s.id, s.label, s.qty_min, s.qty_max, s.factor from public.app_norms_serial s
    where (urole='admin' or s.tenant_id=ten) order by s.qty_min;
end $$;

create or replace function public.app_norms_serial_save(p_token uuid, p_id uuid, p_label text, p_qty_min int, p_qty_max int, p_factor numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if p_id is null then
    insert into public.app_norms_serial (tenant_id, label, qty_min, qty_max, factor)
    values (ten, nullif(trim(p_label),''), coalesce(p_qty_min,1), p_qty_max, coalesce(p_factor,1)) returning id into sid;
    return query select sid, 'Диапазон добавлен';
  else
    update public.app_norms_serial set label=nullif(trim(p_label),''), qty_min=coalesce(p_qty_min,1), qty_max=p_qty_max, factor=coalesce(p_factor,1)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Диапазон обновлён';
  end if;
end $$;

-- ---------- Аналоги ----------
create or replace function public.app_analogs_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, material text, operation text, weight numeric, dims text, norm_base numeric, tags text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select a.id, a.name, a.material, a.operation, a.weight, a.dims, a.norm_base, a.tags, a.created_at
    from public.app_analogs a
    where (urole='admin' or a.tenant_id=ten)
      and (qq='' or lower(a.name) like '%'||qq||'%' or lower(coalesce(a.material,'')) like '%'||qq||'%' or lower(coalesce(a.tags,'')) like '%'||qq||'%')
    order by a.created_at desc;
end $$;

create or replace function public.app_analog_save(p_token uuid, p_id uuid, p_name text, p_material text, p_operation text,
  p_weight numeric, p_dims text, p_norm_base numeric, p_tags text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; aid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','master','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите название аналога'; return; end if;
  if p_id is null then
    insert into public.app_analogs (tenant_id, name, material, operation, weight, dims, norm_base, tags, note)
    values (ten, trim(p_name), nullif(trim(p_material),''), nullif(trim(p_operation),''), p_weight, nullif(trim(p_dims),''), p_norm_base, nullif(trim(p_tags),''), nullif(trim(p_note),''))
    returning id into aid;
    return query select aid, 'Аналог добавлен';
  else
    update public.app_analogs set name=trim(p_name), material=nullif(trim(p_material),''), operation=nullif(trim(p_operation),''),
      weight=p_weight, dims=nullif(trim(p_dims),''), norm_base=p_norm_base, tags=nullif(trim(p_tags),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into aid;
    return query select aid, 'Аналог обновлён';
  end if;
end $$;

create or replace function public.app_analog_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_analogs where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Аналог удалён';
end $$;

-- ---------- Автоподбор аналога ----------
create or replace function public.app_analog_find(p_token uuid, p_material text, p_operation text, p_weight numeric default null)
returns table (id uuid, name text, material text, operation text, weight numeric, norm_base numeric, score numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.name, a.material, a.operation, a.weight, a.norm_base,
      round( (case when lower(coalesce(a.material,''))=lower(coalesce(p_material,'')) then 5 else 0 end)
           + (case when lower(coalesce(a.operation,''))=lower(coalesce(p_operation,'')) then 3 else 0 end)
           - (case when a.weight is not null and p_weight is not null and p_weight>0
                   then least(2, abs(a.weight-p_weight)/greatest(p_weight,1)*2) else 0 end), 2) as score
    from public.app_analogs a
    where (urole='admin' or a.tenant_id=ten)
    order by score desc nulls last, a.created_at desc
    limit 5;
end $$;

-- ---------- Расчёт нормы ----------
create or replace function public.app_norm_calc(p_token uuid, p_operation_id uuid, p_complexity text default 'mid',
  p_qty numeric default 1, p_kmaterial numeric default 1, p_kaccuracy numeric default 1,
  p_kgeometry numeric default 1, p_kfixture numeric default 1, p_base_override numeric default null)
returns table (operation text, complexity text, rate_sale numeric, rate_cost numeric, k_product numeric,
               serial_factor numeric, qty numeric, norm_sale numeric, norm_cost numeric, total_sale numeric, total_cost numeric, formula text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; oname text; rmin numeric; rmax numeric; c_ratio numeric; rsale numeric;
  kp numeric; sf numeric; q numeric; nsale numeric; ncost numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  q := greatest(coalesce(p_qty,1),1);
  select o.name into oname from public.app_norms_operations o where o.id=p_operation_id and (urole='admin' or o.tenant_id=ten);
  if oname is null then raise exception 'Операция не найдена'; end if;
  select r.sale_min, r.sale_max, r.cost_ratio into rmin, rmax, c_ratio
    from public.app_norms_rates r where r.operation_id=p_operation_id and r.complexity=coalesce(nullif(p_complexity,''),'mid');
  if rmin is null then rmin := 0; rmax := 0; c_ratio := 0.7; end if;
  rsale := case lower(coalesce(p_complexity,'mid'))
             when 'simple' then rmin
             when 'hard'   then rmax
             else (rmin+rmax)/2.0 end;
  if p_base_override is not null then rsale := p_base_override; end if;
  select s.factor into sf from public.app_norms_serial s
    where (urole='admin' or s.tenant_id=ten) and q >= s.qty_min and (s.qty_max is null or q <= s.qty_max)
    order by s.qty_min desc limit 1;
  sf := coalesce(sf,1);
  kp := coalesce(p_kmaterial,1)*coalesce(p_kaccuracy,1)*coalesce(p_kgeometry,1)*coalesce(p_kfixture,1);
  nsale := rsale * kp * sf;
  ncost := nsale * coalesce(c_ratio,0.7);
  return query select oname, coalesce(nullif(p_complexity,''),'mid'), round(rsale,2), round(rsale*coalesce(c_ratio,0.7),2),
    round(kp,4), round(sf,4), q, round(nsale,2), round(ncost,2), round(nsale*q,2), round(ncost*q,2),
    'норма = ставка('||coalesce(nullif(p_complexity,''),'mid')||') × K('||round(kp,3)||') × серийность('||round(sf,3)||')';
end $$;

create or replace function public.app_norms_kpi(p_token uuid)
returns table (operations bigint, rates bigint, kfactors bigint, analogs bigint, serial_ranges bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_norms_operations where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id where (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_norms_kfactors where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_analogs where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_norms_serial where (urole='admin' or tenant_id=ten));
end $$;

grant execute on function public.app_norms_ops_list(uuid,text) to anon, authenticated;
grant execute on function public.app_norms_op_save(uuid,uuid,text,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_norms_rates_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_rate_save(uuid,uuid,uuid,text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_norms_rate_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_k_list(uuid,text) to anon, authenticated;
grant execute on function public.app_norms_k_save(uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_norms_k_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_serial_list(uuid) to anon, authenticated;
grant execute on function public.app_norms_serial_save(uuid,uuid,text,int,int,numeric) to anon, authenticated;
grant execute on function public.app_analogs_list(uuid,text) to anon, authenticated;
grant execute on function public.app_analog_save(uuid,uuid,text,text,text,numeric,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_analog_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_analog_find(uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_norm_calc(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_norms_kpi(uuid) to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
do $$
declare oid uuid;
begin
  if not exists (select 1 from public.app_norms_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, unit) values
      ('aaaaaaaa-0000-0000-0000-000000000001','MILL3','Фрезерная 3-осевая','milling','3-осевой ОЦ','н/ч') returning id into oid;
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio) values
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'simple', 8000, 12000, 0.70),
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'mid', 10000, 14000, 0.70),
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'hard', 12000, 16000, 0.70);
  end if;
  if (select count(*) from public.app_norms_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') < 3 then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, unit)
    select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.cat, v.mt, 'н/ч'
    from (values
      ('MILL4','Фрезерная 4-осевая','milling','4-осевой ОЦ'),
      ('MILL5','Фрезерная 5-осевая','milling','5-осевой ОЦ'),
      ('TURN','Токарная','turning','токарный'),
      ('TURNMILL','Токарно-фрезерная','turning','токарно-фрезерный'),
      ('EDMWIRE','ЭЭО проволочная','edm','электроэрозионный'),
      ('EDMDIE','ЭЭО прошивная','edm','электроэрозионный'),
      ('EDMDRILL','ЭЭО сверлильная','edm','электроэрозионный'),
      ('GRINDFLAT','Шлифование плоское','grinding','плоскошлифовальный'),
      ('GRINDPROF','Шлифование профильное','grinding','профилешлифовальный'),
      ('LOCK','Слесарная','locksmith','верстак'),
      ('ENGR','Гравирование','engraving','лазерный маркер')
    ) as v(code,name,cat,mt)
    where not exists (select 1 from public.app_norms_operations o where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code=v.code);
  end if;
  if not exists (select 1 from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code='TURN') then
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio)
    select 'aaaaaaaa-0000-0000-0000-000000000001', o.id, v.cx, v.a, v.b, 0.70
    from public.app_norms_operations o
    cross join (values ('simple',5000,8000),('mid',6500,9500),('hard',8000,11000)) as v(cx,a,b)
    where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code='TURN';
  end if;
  if not exists (select 1 from public.app_norms_kfactors where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_kfactors (tenant_id, category, name, value) values
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Сталь конструкционная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Сталь инструментальная',1.30),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Нержавеющая',1.40),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Алюминий',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Титан',1.80),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Обычная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Повышенная',1.15),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Высокая',1.35),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Простая',0.95),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Средняя',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Сложная',1.25),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Без оснастки',1.10),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Универсальная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Спецоснастка',0.90);
  end if;
  if not exists (select 1 from public.app_norms_serial where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_serial (tenant_id, label, qty_min, qty_max, factor) values
      ('aaaaaaaa-0000-0000-0000-000000000001','Единичное',1,1,1.30),
      ('aaaaaaaa-0000-0000-0000-000000000001','Мелкая серия',2,5,1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','Средняя серия',6,50,0.85),
      ('aaaaaaaa-0000-0000-0000-000000000001','Массовое',51,null,0.75);
  end if;
  if not exists (select 1 from public.app_analogs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_analogs (tenant_id, name, material, operation, weight, dims, norm_base, tags, note) values
      ('aaaaaaaa-0000-0000-0000-000000000001','Пуансон вырубной','Сталь инструментальная','MILL3',12.5,'200×150×40',0.85,'штамп,пуансон','Аналог из архива'),
      ('aaaaaaaa-0000-0000-0000-000000000001','Матрица гибочная','Сталь инструментальная','MILL5',34.0,'400×250×80',1.60,'штамп,матрица',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Корпус пресс-формы','Сталь конструкционная','MILL4',52.0,'500×400×120',3.20,'пресс-форма,корпус',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Втулка направляющая','Сталь конструкционная','TURN',1.2,'Ø30×60',0.35,'втулка,направляющая',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Плита опорная','Сталь конструкционная','GRINDFLAT',8.0,'300×300×25',0.60,'плита,шлифование',null);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Нормирование','Ядро нормирования P14 (операции, ставки, K, серийность, аналоги)',
   'Модуль «Нормирование PRO»: справочник операций с диапазонами ставок по сложности (simple/mid/hard, sale_min…sale_max, cost_ratio); K-коэффициенты (материал/точность/геометрия/оснастка); коэффициенты серийности по количеству; база аналогов с автоподбором по материалу/операции/массе. Формула нормы: норма = ставка(сложность) × K_материала × K_точности × K_геометрии × K_оснастки × серийность. Себестоимость = норма × cost_ratio. Расчёт основан на логике проекта «Нормирование PRO», перенесён в мультитенантную модель 3DMP.',
   'нормирование нормирование pro P14 операции ставки K-коэффициент серийность аналоги автоподбор формула нормы')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Ядро нормирования P14 (операции, ставки, K, серийность, аналоги)');
-- <<<<<<<<<< 0073_norms_core.sql <<<<<<<<<<
-- >>>>>>>>>> 0074_planning_slots.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0074_planning_slots.sql  (v52 — P14 Сессия D)
-- Слоты по времени (мощность по центрам/сменам/датам) + бронирование часов,
-- политика SLA и сканер эскалации по просроченным проблемам.
-- База знаний. Зависит от 0001..0073.
-- ============================================================

create table if not exists public.app_work_slots (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  center         text not null,
  slot_date      date not null,
  shift          text not null default '1',   -- 1|2|3|night
  capacity_hours numeric not null default 8,
  used_hours     numeric not null default 0,
  status         text not null default 'open', -- open|full|blocked
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists app_work_slots_idx on public.app_work_slots (tenant_id, slot_date, center);
alter table public.app_work_slots enable row level security;

create table if not exists public.app_sla_policy (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  priority   text not null default 'normal',   -- low|normal|high|critical
  hours      int not null default 24
);
create index if not exists app_sla_policy_idx on public.app_sla_policy (tenant_id, priority);
alter table public.app_sla_policy enable row level security;

-- ---------- Слоты ----------
create or replace function public.app_slots_list(p_token uuid, p_from date default null, p_to date default null, p_center text default null)
returns table (id uuid, center text, slot_date date, shift text, capacity_hours numeric, used_hours numeric,
               free_hours numeric, status text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.center, w.slot_date, w.shift, w.capacity_hours, w.used_hours,
           round(w.capacity_hours - w.used_hours, 2), w.status, w.note
    from public.app_work_slots w
    where (urole='admin' or w.tenant_id=ten)
      and (coalesce(p_from, current_date) <= w.slot_date and w.slot_date <= coalesce(p_to, current_date + 30))
      and (coalesce(p_center,'')='' or w.center = p_center)
    order by w.slot_date, w.center, w.shift;
end $$;

create or replace function public.app_slot_save(p_token uuid, p_id uuid, p_center text, p_slot_date date,
  p_shift text, p_capacity_hours numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_center),'')='' or p_slot_date is null then raise exception 'Укажите центр и дату'; return; end if;
  if p_id is null then
    insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, note)
    values (ten, trim(p_center), p_slot_date, coalesce(nullif(trim(p_shift),''),'1'), coalesce(p_capacity_hours,8), nullif(trim(p_note),''))
    returning id into sid;
    return query select sid, 'Слот создан';
  else
    update public.app_work_slots set center=trim(p_center), slot_date=p_slot_date, shift=coalesce(nullif(trim(p_shift),''),shift),
      capacity_hours=coalesce(p_capacity_hours,capacity_hours), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Слот обновлён';
  end if;
end $$;

create or replace function public.app_slot_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_work_slots where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Слот удалён';
end $$;

create or replace function public.app_slot_book(p_token uuid, p_center text, p_slot_date date, p_shift text, p_hours numeric)
returns table (id uuid, used_hours numeric, capacity_hours numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid; used numeric; cap numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_hours,0) <= 0 then raise exception 'Укажите часы'; return; end if;
  select w.id into sid from public.app_work_slots w
    where w.tenant_id=ten and w.center=trim(p_center) and w.slot_date=p_slot_date and w.shift=coalesce(nullif(trim(p_shift),''),'1');
  if sid is null then
    insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, used_hours)
    values (ten, trim(p_center), p_slot_date, coalesce(nullif(trim(p_shift),''),'1'), 8, least(coalesce(p_hours,0),8))
    returning id, used_hours, capacity_hours into sid, used, cap;
  else
    update public.app_work_slots set used_hours = used_hours + coalesce(p_hours,0),
      status = case when used_hours + coalesce(p_hours,0) >= capacity_hours then 'full' else status end
     where id=sid returning used_hours, capacity_hours into used, cap;
  end if;
  return query select sid, used, cap, 'Забронировано ч: '||coalesce(p_hours,0);
end $$;

create or replace function public.app_slots_kpi(p_token uuid)
returns table (slots bigint, hours_capacity numeric, hours_used numeric, utilization_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cap numeric; usd numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(sum(capacity_hours),0), coalesce(sum(used_hours),0) into cap, usd
    from public.app_work_slots where (urole='admin' or tenant_id=ten)
      and slot_date between current_date and current_date + 30;
  return query select
    (select count(*) from public.app_work_slots where (urole='admin' or tenant_id=ten) and slot_date between current_date and current_date + 30),
    cap, usd, round(case when cap>0 then usd/cap*100 else 0 end, 1);
end $$;

-- ---------- SLA ----------
create or replace function public.app_sla_list(p_token uuid)
returns table (id uuid, priority text, hours int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select s.id, s.priority, s.hours from public.app_sla_policy s
    where (urole='admin' or s.tenant_id=ten)
    order by (case s.priority when 'critical' then 1 when 'high' then 2 when 'normal' then 3 else 4 end);
end $$;

create or replace function public.app_sla_save(p_token uuid, p_id uuid, p_priority text, p_hours int)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if p_priority not in ('low','normal','high','critical') then raise exception 'Приоритет: low|normal|high|critical'; return; end if;
  if p_id is null then
    insert into public.app_sla_policy (tenant_id, priority, hours) values (ten, p_priority, greatest(coalesce(p_hours,24),1)) returning id into sid;
    return query select sid, 'Политика SLA добавлена';
  else
    update public.app_sla_policy set priority=p_priority, hours=greatest(coalesce(p_hours,24),1)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Политика SLA обновлена';
  end if;
end $$;

create or replace function public.app_escalation_scan(p_token uuid)
returns table (escalated int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int := 0; h int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  update public.app_issues i
     set escalated = true, escalated_at = now(), updated_at = now()
   where (urole='admin' or i.tenant_id=ten)
     and coalesce(i.escalated,false) = false
     and i.status not in ('done','closed','resolved','cancelled')
     and ( (i.due_date is not null and i.due_date < current_date)
        or (i.due_date is null and i.created_at < now() - make_interval(hours => coalesce(
              (select s2.hours from public.app_sla_policy s2 where s2.tenant_id=i.tenant_id and s2.priority=i.priority limit 1), 24))) );
  get diagnostics n = row_count;
  if n > 0 then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief'],
      'Эскалация: просрочено проблем', n || ' шт (превышен SLA)', 'apps/issues/index.html');
  end if;
  return query select n;
end $$;

grant execute on function public.app_slots_list(uuid,date,date,text) to anon, authenticated;
grant execute on function public.app_slot_save(uuid,uuid,text,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_slot_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_slot_book(uuid,text,date,text,numeric) to anon, authenticated;
grant execute on function public.app_slots_kpi(uuid) to anon, authenticated;
grant execute on function public.app_sla_list(uuid) to anon, authenticated;
grant execute on function public.app_sla_save(uuid,uuid,text,int) to anon, authenticated;
grant execute on function public.app_escalation_scan(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare c text; d int;
begin
  if not exists (select 1 from public.app_work_slots where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    foreach c in array array['Фрезерный участок','Токарный участок','ЭЭО','Шлифование'] loop
      for d in 0..6 loop
        insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, used_hours, status)
        values ('aaaaaaaa-0000-0000-0000-000000000001', c, current_date + d, '1', 8,
                case when d=0 then 5.5 when d=1 then 8 else 0 end,
                case when d=1 then 'full' else 'open' end);
      end loop;
    end loop;
  end if;
  if not exists (select 1 from public.app_sla_policy where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_sla_policy (tenant_id, priority, hours) values
      ('aaaaaaaa-0000-0000-0000-000000000001','critical',4),
      ('aaaaaaaa-0000-0000-0000-000000000001','high',8),
      ('aaaaaaaa-0000-0000-0000-000000000001','normal',24),
      ('aaaaaaaa-0000-0000-0000-000000000001','low',72);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Нормирование','Слоты по времени и SLA-эскалация (P14 Сессия D)',
   'Модуль «Слоты и загрузка»: мощность рабочих центров по датам и сменам (capacity/used, статус open/full), бронирование часов. Политика SLA по приоритетам (critical 4ч, high 8ч, normal 24ч, low 72ч). Сканер эскалации поднимает просроченные проблемы (по due_date или created_at + SLA) и уведомляет руководителей.',
   'слоты смена мощность загрузка бронирование SLA эскалация просрочка P14')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Слоты по времени и SLA-эскалация (P14 Сессия D)');
-- <<<<<<<<<< 0074_planning_slots.sql <<<<<<<<<<
-- >>>>>>>>>> 0075_storage_files.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0075_storage_files.sql  (v53 — P14 Сессия E)
-- Хранилище файлов (Supabase Storage bucket saas-files) + реестр app_files
-- (чертежи/КД/фото), сводный журнал истории. База знаний. Зависит от 0001..0074.
-- ============================================================

-- ---------- Bucket (public) ----------
insert into storage.buckets (id, name, public)
values ('saas-files', 'saas-files', true)
on conflict (id) do nothing;

-- ---------- Политики Storage (идемпотентно) ----------
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_read') then
    create policy saas_files_read on storage.objects for select using (bucket_id = 'saas-files');
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_write') then
    create policy saas_files_write on storage.objects for insert with check (bucket_id = 'saas-files');
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_delete') then
    create policy saas_files_delete on storage.objects for delete using (bucket_id = 'saas-files');
  end if;
end $$;

-- ---------- Реестр файлов ----------
create table if not exists public.app_files (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  entity_type  text not null default 'other',   -- order|naryad|client|invoice|spec|norms|other
  entity_id    uuid,
  name         text not null,
  mime         text,
  size_bytes   bigint,
  path         text not null,
  uploaded_by  text,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_files_idx on public.app_files (tenant_id, entity_type, entity_id, created_at desc);
alter table public.app_files enable row level security;

create or replace function public.app_file_url(p_path text) returns text
language sql immutable
as $$ select 'https://zfkbzzmtbrueaksfaqbf.supabase.co/storage/v1/object/public/saas-files/' || p_path $$;

create or replace function public.app_file_register(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_size bigint, p_path text, p_note text default null)
returns table (id uuid, url text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_path),'')='' then raise exception 'Путь файла не задан'; return; end if;
  insert into public.app_files (tenant_id, entity_type, entity_id, name, mime, size_bytes, path, uploaded_by, note)
  values (ten, coalesce(nullif(trim(p_entity_type),''),'other'), p_entity_id, coalesce(nullif(trim(p_name),''),'файл'), nullif(trim(p_mime),''),
          p_size, trim(p_path), ulogin, nullif(trim(p_note),''))
  returning id into fid;
  return query select fid, public.app_file_url(trim(p_path)), 'Файл зарегистрирован';
end $$;

drop function if exists public.app_files_list(uuid,text,uuid);
create or replace function public.app_files_list(p_token uuid, p_entity_type text default null, p_entity_id uuid default null)
returns table (id uuid, entity_type text, entity_id uuid, name text, mime text, size_bytes bigint, path text, url text, uploaded_by text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select f.id, f.entity_type, f.entity_id, f.name, f.mime, f.size_bytes, f.path, public.app_file_url(f.path), f.uploaded_by, f.created_at
    from public.app_files f
    where (urole='admin' or f.tenant_id=ten)
      and (coalesce(p_entity_type,'')='' or f.entity_type=p_entity_type)
      and (p_entity_id is null or f.entity_id=p_entity_id)
    order by f.created_at desc;
end $$;

create or replace function public.app_file_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_files where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Файл удалён';
end $$;

create or replace function public.app_files_kpi(p_token uuid)
returns table (total bigint, total_bytes bigint, orders_files bigint, drawings bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(size_bytes),0)::bigint,
    count(*) filter (where entity_type='order'),
    count(*) filter (where mime like '%dwg%' or mime like '%pdf%' or lower(name) similar to '%(dwg|dxf|stl|pdf)%')
    from public.app_files where (urole='admin' or tenant_id=ten);
end $$;

-- ---------- Сводный журнал ----------
create or replace function public.app_journal_list(p_token uuid, p_limit int default 50)
returns table (kind text, title text, detail text, who text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select q.kind, q.title, q.detail, q.who, q.at from (
      select 'Расчёт'::text as kind, coalesce(c.title,'Расчёт') as title, c.kind as detail, coalesce(c.created_login,'') as who, c.created_at as at
        from public.app_calc_saves c
        where (urole='admin' or c.tenant_id=ten)
      union all
      select 'Файл'::text, f.name, f.entity_type, coalesce(f.uploaded_by,''), f.created_at
        from public.app_files f
        where (urole='admin' or f.tenant_id=ten)
      union all
      select 'Событие'::text, e.action, coalesce(e.detail,''), coalesce(e.login,''), e.created_at
        from public.app_events e
        where (urole='admin' or e.login=ulogin)
    ) q
    order by q.at desc
    limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

grant execute on function public.app_file_register(uuid,text,uuid,text,text,bigint,text,text) to anon, authenticated;
grant execute on function public.app_files_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_file_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_files_kpi(uuid) to anon, authenticated;
grant execute on function public.app_journal_list(uuid,int) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Хранилище файлов и сводный журнал (P14 Сессия E)',
   'Модуль «Файлы и журнал»: вложения (чертежи/КД/фото/PDF) в Supabase Storage (bucket saas-files, публичный), метаданные в app_files с привязкой к сущности (заявка/наряд/клиент/спецификация). Сводный журнал (app_journal_list) объединяет расчёты, файлы и события. Загрузка — через Supabase Storage, регистрация — через app_file_register.',
   'файлы вложения storage bucket чертежи журнал история P12')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Хранилище файлов и сводный журнал (P14 Сессия E)');
-- <<<<<<<<<< 0075_storage_files.sql <<<<<<<<<<
-- >>>>>>>>>> 0076_forecast.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0076_forecast.sql  (v54 — Сессия F: B39 «Прогноз загрузки»)
-- Прогноз по существующим данным: загрузка по дням (план часы открытых нарядов
-- vs мощность слотов), ETA по нарядам/заказам, риск просрочки. Новых таблиц нет.
-- База знаний. Зависит от 0001..0075.
-- ============================================================

create or replace function public.app_forecast_load(p_token uuid, p_days int default 14)
returns table (day date, planned numeric, capacity numeric, load_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  n := greatest(1, least(coalesce(p_days,14), 90));
  return query
    with days as (
      select generate_series(current_date, current_date + (n-1), interval '1 day')::date as d
    )
    select d,
      (select coalesce(sum(greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0)),0)
         from public.app_naryads na
        where (urole='admin' or na.tenant_id=ten)
          and na.status not in ('done','closed','cancelled')
          and coalesce(na.plan_end, na.due_date, current_date) = d),
      (select coalesce(sum(w.capacity_hours),0) from public.app_work_slots w
        where (urole='admin' or w.tenant_id=ten) and w.slot_date = d),
      round( 100.0 * (select coalesce(sum(greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0)),0)
                        from public.app_naryads na
                       where (urole='admin' or na.tenant_id=ten)
                         and na.status not in ('done','closed','cancelled')
                         and coalesce(na.plan_end, na.due_date, current_date) = d)
             / greatest((select coalesce(sum(w.capacity_hours),0) from public.app_work_slots w
                          where (urole='admin' or w.tenant_id=ten) and w.slot_date = d), 1), 1)
    from days order by d;
end $$;

create or replace function public.app_forecast_orders(p_token uuid, p_limit int default 50)
returns table (id uuid, number text, title text, center text, order_number text, remaining numeric,
               avg_daily_capacity numeric, eta_days int, eta_date date, due_date date, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; avg_cap numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(avg(cap),8) into avg_cap from (
    select w.slot_date, sum(w.capacity_hours) cap from public.app_work_slots w
     where (urole='admin' or w.tenant_id=ten) and w.slot_date >= current_date
     group by w.slot_date) t;
  avg_cap := greatest(coalesce(avg_cap,8),1);
  return query
    select na.id, na.number, na.title,
      (select wc.name from public.app_work_centers wc where wc.id=na.wc_id),
      (select o.number from public.app_orders o where o.id=na.order_id),
      round(rem.h,1),
      round(avg_cap,1),
      ceil(rem.h / avg_cap)::int,
      current_date + ceil(rem.h / avg_cap)::int,
      na.due_date,
      case
        when na.due_date is not null and na.due_date < current_date then 'просрочен'
        when na.due_date is not null and na.due_date < current_date + ceil(rem.h / avg_cap)::int then 'риск'
        else 'норма' end
    from public.app_naryads na
    cross join lateral (select greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0) as h) rem
    where (urole='admin' or na.tenant_id=ten) and na.status not in ('done','closed','cancelled')
    order by (case when na.due_date is not null and na.due_date < current_date then 0 else 1 end), eta_days desc
    limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

create or replace function public.app_forecast_kpi(p_token uuid)
returns table (open_naryads bigint, open_hours numeric, avg_daily_capacity numeric, avg_load_pct numeric, overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cap numeric; usd numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(sum(capacity_hours),0), coalesce(sum(used_hours),0) into cap, usd
    from public.app_work_slots where (urole='admin' or tenant_id=ten) and slot_date between current_date and current_date + 14;
  return query select
    (select count(*) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled')),
    (select coalesce(sum(greatest(coalesce(plan_hours,0)-coalesce(fact_hours,0),0)),0) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled')),
    round(cap/14.0,1),
    round(case when cap>0 then usd/cap*100 else 0 end,1),
    (select count(*) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled') and due_date is not null and due_date < current_date);
end $$;

grant execute on function public.app_forecast_load(uuid,int) to anon, authenticated;
grant execute on function public.app_forecast_orders(uuid,int) to anon, authenticated;
grant execute on function public.app_forecast_kpi(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Прогноз загрузки (B39)',
   'Модуль «Прогноз загрузки»: расчёт по существующим данным — загрузка по дням (план-часы открытых нарядов против мощности слотов), ETA по нарядам/заказам (остаток часов ÷ средняя дневная мощность) и риск просрочки (сравнение ETA с due_date). Помогает выравнивать загрузку и предупреждать срывы сроков.',
   'прогноз загрузка ETA сроки ёмкость слоты план-факт риск просрочка B39')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Прогноз загрузки (B39)');
-- <<<<<<<<<< 0076_forecast.sql <<<<<<<<<<
-- >>>>>>>>>> 0077_setup.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0077_setup.sql  (v55 — Сессия G: B20 «Наладка»)
-- Наладки/переналадки оборудования: план/факт часов, статусы, исполнитель,
-- привязка к наряду. База знаний. Зависит от 0001..0076.
-- ============================================================

create table if not exists public.app_setups (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  equipment     text,
  setup_type    text not null default 'setup',  -- setup|changeover|trial|adjust
  planned_hours numeric default 0,
  fact_hours    numeric default 0,
  status        text not null default 'planned', -- planned|in_progress|done|cancelled
  assignee      text,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_setups_idx on public.app_setups (tenant_id, status, created_at desc);
alter table public.app_setups enable row level security;

create or replace function public.app_setups_list(p_token uuid, p_q text default null)
returns table (id uuid, naryad_number text, equipment text, setup_type text, planned_hours numeric,
               fact_hours numeric, status text, assignee text, naryad_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, na.number, s.equipment, s.setup_type, s.planned_hours, s.fact_hours, s.status, s.assignee, s.naryad_id, s.created_at
    from public.app_setups s left join public.app_naryads na on na.id = s.naryad_id
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(coalesce(s.equipment,'')) like '%'||qq||'%' or lower(coalesce(s.assignee,'')) like '%'||qq||'%' or lower(coalesce(na.number,'')) like '%'||qq||'%')
    order by (s.status='done'), s.created_at desc;
end $$;

create or replace function public.app_setup_save(p_token uuid, p_id uuid, p_naryad_id uuid, p_equipment text,
  p_setup_type text, p_planned_hours numeric, p_assignee text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist','operator') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_equipment),'')='' then raise exception 'Укажите оборудование'; return; end if;
  if p_id is null then
    insert into public.app_setups (tenant_id, naryad_id, equipment, setup_type, planned_hours, assignee, note, created_login)
    values (ten, p_naryad_id, trim(p_equipment), coalesce(nullif(trim(p_setup_type),''),'setup'), coalesce(p_planned_hours,0), nullif(trim(p_assignee),''), nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, 'Наладка создана';
  else
    update public.app_setups set naryad_id=p_naryad_id, equipment=trim(p_equipment), setup_type=coalesce(nullif(trim(p_setup_type),''),setup_type),
      planned_hours=coalesce(p_planned_hours,planned_hours), assignee=nullif(trim(p_assignee),''), note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Наладка обновлена';
  end if;
end $$;

create or replace function public.app_setup_set_status(p_token uuid, p_id uuid, p_status text, p_fact_hours numeric default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('planned','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_setups set status=p_status,
    fact_hours = coalesce(p_fact_hours, fact_hours),
    updated_at = now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_setup_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_setups where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Наладка удалена';
end $$;

create or replace function public.app_setups_kpi(p_token uuid)
returns table (total bigint, planned bigint, in_progress bigint, done bigint, hours_planned numeric, hours_fact numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='planned'), count(*) filter (where status='in_progress'),
    count(*) filter (where status='done'), coalesce(sum(planned_hours),0), coalesce(sum(fact_hours),0)
    from public.app_setups where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_setups_list(uuid,text) to anon, authenticated;
grant execute on function public.app_setup_save(uuid,uuid,uuid,text,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_setup_set_status(uuid,uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_setup_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_setups_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_setups (tenant_id, naryad_id, equipment, setup_type, planned_hours, fact_hours, status, assignee, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  (select id from public.app_naryads where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  v.eq, v.st, v.ph, v.fh, v.status, v.who, v.note, 'master'
from (values
  ('Feeler FTC-350Xl','changeover', 1.5, 0, 'planned','Сидоров','Переналадка под новый патрон'),
  ('ЭЭО проволочная','setup', 2.0, 1.5, 'in_progress','Петров','Установка проволоки 0.25'),
  ('Плоскошлифовальный','adjust', 0.5, 0.5, 'done','Иванов','Правка круга')
) as v(eq,st,ph,fh,status,who,note)
where not exists (select 1 from public.app_setups where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Наладка оборудования (B20)',
   'Модуль «Наладка»: учёт наладок/переналадок/пробных пусков/подналадок оборудования с планом и фактом часов, исполнителем и привязкой к наряду. Статусы: запланирована → в работе → выполнена. KPI: всего, план/факт часов. Помогает видеть долю простоев на переналадку.',
   'наладка переналадка setup простои часы план факт B20')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Наладка оборудования (B20)');
-- <<<<<<<<<< 0077_setup.sql <<<<<<<<<<
-- >>>>>>>>>> 0078_lean.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0078_lean.sql  (v56 — Сессия H: B7 «Бережливое производство»)
-- Кайдзен-предложения и 7 видов потерь: статусы, экономия, эффект.
-- База знаний. Зависит от 0001..0077.
-- ============================================================

create table if not exists public.app_lean_actions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  title       text not null,
  category    text not null default 'other', -- overproduction|waiting|transport|overprocessing|inventory|motion|defects|other
  description text,
  author      text,
  status      text not null default 'idea',  -- idea|approved|in_progress|done|rejected
  savings     numeric default 0,             -- экономия ₽/год
  effect      text,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_lean_actions_idx on public.app_lean_actions (tenant_id, status, category);
alter table public.app_lean_actions enable row level security;

create or replace function public.app_lean_list(p_token uuid, p_q text default null)
returns table (id uuid, title text, category text, author text, status text, savings numeric, effect text, description text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select a.id, a.title, a.category, a.author, a.status, a.savings, a.effect, a.description, a.created_at
    from public.app_lean_actions a
    where (urole='admin' or a.tenant_id=ten)
      and (qq='' or lower(a.title) like '%'||qq||'%' or lower(coalesce(a.author,'')) like '%'||qq||'%' or lower(coalesce(a.description,'')) like '%'||qq||'%')
    order by (a.status='done'), a.created_at desc;
end $$;

create or replace function public.app_lean_save(p_token uuid, p_id uuid, p_title text, p_category text,
  p_description text, p_author text, p_savings numeric, p_effect text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите название предложения'; return; end if;
  if p_category not in ('overproduction','waiting','transport','overprocessing','inventory','motion','defects','other') then raise exception 'Неверная категория потерь'; return; end if;
  if p_id is null then
    insert into public.app_lean_actions (tenant_id, title, category, description, author, savings, effect, created_login)
    values (ten, trim(p_title), p_category, nullif(trim(p_description),''), coalesce(nullif(trim(p_author),''), ulogin), coalesce(p_savings,0), nullif(trim(p_effect),''), ulogin)
    returning id into lid;
    return query select lid, 'Предложение добавлено';
  else
    update public.app_lean_actions set title=trim(p_title), category=p_category, description=nullif(trim(p_description),''),
      author=coalesce(nullif(trim(p_author),''),author), savings=coalesce(p_savings,0), effect=nullif(trim(p_effect),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Предложение обновлено';
  end if;
end $$;

create or replace function public.app_lean_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('idea','approved','in_progress','done','rejected') then return query select false,'Неверный статус'; return; end if;
  update public.app_lean_actions set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_lean_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_lean_actions where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Предложение удалено';
end $$;

create or replace function public.app_lean_kpi(p_token uuid)
returns table (total bigint, ideas bigint, active bigint, done bigint, savings_sum numeric, top_category text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; tc text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select a.category into tc from public.app_lean_actions a
    where (urole='admin' or a.tenant_id=ten) group by a.category order by count(*) desc limit 1;
  return query select count(*), count(*) filter (where status='idea'),
    count(*) filter (where status in ('approved','in_progress')),
    count(*) filter (where status='done'),
    coalesce(sum(savings) filter (where status='done'),0), tc
    from public.app_lean_actions where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_lean_list(uuid,text) to anon, authenticated;
grant execute on function public.app_lean_save(uuid,uuid,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_lean_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_lean_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lean_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_lean_actions (tenant_id, title, category, description, author, status, savings, effect, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.cat, v.descr, v.author, v.status, v.sav, v.eff, 'master'
from (values
  ('Сократить время поиска инструмента','motion','Организовать тумбы с маркировкой у станков','Мастер', 'done', 60000, 'поиск инструмента −40%'),
  ('Уменьшить переналадку','waiting','SMED: подготовка оснастки заранее','Технолог','in_progress',120000, 'простои −25%'),
  ('Повторное использование СОЖ','inventory','Система регенерации СОЖ','Снабженец','idea',80000, null),
  ('Снизить брак по размеру','defects','Контрольный калибр на операции 20','ОТК','approved',150000,'брак −0.5%')
) as v(title,cat,descr,author,status,sav,eff)
where not exists (select 1 from public.app_lean_actions where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Бережливое производство (B7)',
   'Модуль «Бережливое производство»: кайдзен-предложения по 7 видам потерь (перепроизводство, ожидание, транспортировка, излишняя обработка, запасы, движения, дефекты). Статусы: идея → одобрено → в работе → внедрено. Учёт экономии (₽/год) и эффекта. KPI: всего, идей, в работе, внедрено, сумма экономии.',
   'бережливое производство lean кайдзен 7 видов потерь экономия B7')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Бережливое производство (B7)');
-- <<<<<<<<<< 0078_lean.sql <<<<<<<<<<
-- >>>>>>>>>> 0079_permissions_matrix.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0079_permissions_matrix.sql  (v57 — P8 шаг 1)
-- Покрытие матрицы прав (app_role_permissions) новыми модулями + helper app_guard
-- для серверной проверки в мутирующих RPC. admin/owner — всегда полный доступ.
-- Идемпотентно. Зависит от 0001..0078.
-- ============================================================

create or replace function public.app_guard(p_token uuid, p_module text, p_action text default 'view')
returns void
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_can(p_token, p_module, coalesce(nullif(p_action,''),'view')) then
    raise exception 'Нет прав: % (%)', p_module, coalesce(nullif(p_action,''),'view');
  end if;
end $$;

grant execute on function public.app_guard(uuid,text,text) to anon, authenticated;

-- ---------- Матрица: назначить право правки по ролям (view=true всегда для этих строк) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, v.edit
from (values
  ('technologist','norms',true),('technologist','calc',true),('technologist','nc',true),('technologist','registry',true),
  ('technologist','bom',true),('technologist','assistant',true),('technologist','setup',true),('technologist','slots',true),
  ('technologist','forecast',false),('technologist','files',true),
  ('manager','crm',true),('manager','tkp',true),('manager','orders',true),('manager','suppliers',true),('manager','teo',true),
  ('manager','marketplace',true),('manager','escrow',true),('manager','labels',true),('manager','engraving',true),
  ('manager','files',true),('manager','builder',true),('manager','forecast',false),
  ('master','production',true),('master','setup',true),('master','slots',true),('master','mes',true),('master','tooling',true),
  ('master','forecast',false),('master','terminal',true),('master','lean',true),
  ('chief','production',true),('chief','planning',true),('chief','slots',true),('chief','forecast',true),('chief','setup',true),
  ('chief','issues',true),('chief','lean',true),
  ('economist','economics',true),('economist','teo',true),('economist','escrow',true),('economist','industry',true),('economist','calc',true),
  ('supply','procurement',true),('supply','suppliers',true),('supply','warehouse',true),('supply','marketplace',true),
  ('operator','terminal',true),('operator','mes',true),('operator','setup',false),
  ('qc','qc',true),('qc','quality',true),('qc','passport',true),('qc','files',false)
) as v(role, module, edit)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

-- ---------- Просмотр новых модулей для офисных ролей (view=true, edit=false) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, false
from (values
  ('director','norms'),('director','forecast'),('director','setup'),('director','lean'),('director','files'),('director','marketplace'),
  ('manager','norms'),('manager','setup'),('manager','slots'),('manager','lean'),
  ('master','norms'),('master','files'),
  ('chief','files'),('chief','norms'),
  ('economist','norms'),('economist','files'),
  ('supply','forecast'),('supply','files'),
  ('qc','files')
) as v(role, module)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

-- ---------- Сводка матрицы (для админа/аудита) ----------
create or replace function public.app_permissions_overview(p_token uuid)
returns table (module_id text, roles_total bigint, editors text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then raise exception 'Только администратор/владелец'; end if;
  return query
    select p.module_id, count(*),
      string_agg(p.role, ', ' order by p.role) filter (where p.can_edit)
    from public.app_role_permissions p
    where p.tenant_id is null
    group by p.module_id
    order by p.module_id;
end $$;

grant execute on function public.app_permissions_overview(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права доступа и матрица ролей (P8)',
   'Права: admin/owner — полный доступ всегда; остальные роли — по матрице app_role_permissions (role × module × view/edit). Если строки нет — просмотр разрешён, редактирование запрещено (безопасный дефолт). Новые модули (нормирование, слоты, прогноз, наладка, lean, файлы, эскроу, маркетплейс, ТЭО, UI-справочники) добавлены в матрицу. Серверная проверка — helper app_guard(token, module, action) → возбуждает исключение при отсутствии права.',
   'права роли матрица app_can app_guard доступ P8 permissions')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права доступа и матрица ролей (P8)');
-- <<<<<<<<<< 0079_permissions_matrix.sql <<<<<<<<<<
-- >>>>>>>>>> 0080_dictionaries.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0080_dictionaries.sql  (v58 — Сессия J: настраиваемые справочники)
-- Универсальные справочники (ключ → значения-варианты) для самостоятельного
-- наполнения/редактирования: категории поставщиков, виды потерь, типы наладок,
-- виды упаковки, типы этикеток и любые другие. База знаний. Зависит от 0001..0079.
-- ============================================================

create table if not exists public.app_dictionaries (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text not null,
  name        text not null,
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists app_dictionaries_code_idx on public.app_dictionaries (tenant_id, lower(code));
create index if not exists app_dictionaries_idx on public.app_dictionaries (tenant_id, active);
alter table public.app_dictionaries enable row level security;

create table if not exists public.app_dictionary_items (
  id       uuid primary key default gen_random_uuid(),
  dict_id  uuid references public.app_dictionaries (id) on delete cascade,
  value    text not null,        -- код/значение (латиницей или как угодно)
  label    text not null,        -- отображаемое название
  sort     int default 100,
  active   boolean not null default true
);
create index if not exists app_dictionary_items_idx on public.app_dictionary_items (dict_id, sort);
alter table public.app_dictionary_items enable row level security;

-- ---------- Справочники ----------
create or replace function public.app_dicts_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, description text, active boolean, items bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.code, d.name, d.description, d.active,
      (select count(*) from public.app_dictionary_items i where i.dict_id=d.id)
    from public.app_dictionaries d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.name) like '%'||qq||'%' or lower(d.code) like '%'||qq||'%')
    order by d.name;
end $$;

create or replace function public.app_dict_save(p_token uuid, p_id uuid, p_code text, p_name text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите код и название'; return; end if;
  if p_id is null then
    insert into public.app_dictionaries (tenant_id, code, name, description, active)
    values (ten, trim(p_code), trim(p_name), nullif(trim(p_description),''), coalesce(p_active,true)) returning id into did;
    return query select did, 'Справочник создан';
  else
    update public.app_dictionaries set code=trim(p_code), name=trim(p_name), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Справочник обновлён';
  end if;
end $$;

create or replace function public.app_dict_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_dictionaries where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Справочник удалён';
end $$;

-- ---------- Значения ----------
create or replace function public.app_dict_items_list(p_token uuid, p_dict_id uuid)
returns table (id uuid, value text, label text, sort int, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_dictionaries d where d.id=p_dict_id and (urole='admin' or d.tenant_id=ten)) then raise exception 'Справочник не найден'; end if;
  return query select i.id, i.value, i.label, i.sort, i.active from public.app_dictionary_items i
    where i.dict_id=p_dict_id order by i.sort, i.label;
end $$;

create or replace function public.app_dict_items_by_code(p_token uuid, p_code text)
returns table (value text, label text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select i.value, i.label
    from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id
    where (urole='admin' or d.tenant_id=ten) and lower(d.code)=lower(trim(p_code)) and d.active and i.active
    order by i.sort, i.label;
end $$;

create or replace function public.app_dict_item_save(p_token uuid, p_id uuid, p_dict_id uuid, p_value text, p_label text, p_sort int, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; iid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if not exists (select 1 from public.app_dictionaries d where d.id=p_dict_id and (urole='admin' or d.tenant_id=ten)) then raise exception 'Справочник не найден'; return; end if;
  if coalesce(trim(p_value),'')='' or coalesce(trim(p_label),'')='' then raise exception 'Укажите значение и название'; return; end if;
  if p_id is null then
    insert into public.app_dictionary_items (dict_id, value, label, sort, active)
    values (p_dict_id, trim(p_value), trim(p_label), coalesce(p_sort,100), coalesce(p_active,true)) returning id into iid;
    return query select iid, 'Значение добавлено';
  else
    update public.app_dictionary_items set value=trim(p_value), label=trim(p_label), sort=coalesce(p_sort,100), active=coalesce(p_active,active)
     where id=p_id and dict_id=p_dict_id returning id into iid;
    return query select iid, 'Значение обновлено';
  end if;
end $$;

create or replace function public.app_dict_item_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_dictionary_items i using public.app_dictionaries d
    where i.id=p_id and d.id=i.dict_id and (urole='admin' or d.tenant_id=ten);
  return query select true,'Значение удалено';
end $$;

create or replace function public.app_dicts_kpi(p_token uuid)
returns table (dicts bigint, items bigint, active_items bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_dictionaries where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id where (urole='admin' or d.tenant_id=ten)),
    (select count(*) from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id where i.active and (urole='admin' or d.tenant_id=ten));
end $$;

grant execute on function public.app_dicts_list(uuid,text) to anon, authenticated;
grant execute on function public.app_dict_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_dict_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dict_items_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dict_items_by_code(uuid,text) to anon, authenticated;
grant execute on function public.app_dict_item_save(uuid,uuid,uuid,text,text,int,boolean) to anon, authenticated;
grant execute on function public.app_dict_item_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dicts_kpi(uuid) to anon, authenticated;

-- ---------- Сиды (тенант A) ----------
do $$
declare did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values
      ('aaaaaaaa-0000-0000-0000-000000000001','supplier_category','Категории поставщиков',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'металл','Металл',10),(did,'инструмент','Инструмент',20),(did,'комплектующие','Комплектующие',30),(did,'услуги','Услуги',40),(did,'прочее','Прочее',50);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','loss_type','Виды потерь') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'overproduction','Перепроизводство',10),(did,'waiting','Ожидание',20),(did,'transport','Транспортировка',30),
      (did,'overprocessing','Излишняя обработка',40),(did,'inventory','Запасы',50),(did,'motion','Движения',60),(did,'defects','Дефекты',70),(did,'other','Прочее',80);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','setup_type','Типы наладок') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'setup','Наладка',10),(did,'changeover','Переналадка',20),(did,'trial','Пробный пуск',30),(did,'adjust','Подналадка',40);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','package_kind','Виды упаковки') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'box','Коробка',10),(did,'pallet','Паллета',20),(did,'crate','Ящик',30),(did,'bag','Мешок',40),(did,'other','Прочее',50);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','label_type','Типы этикеток') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'cargo','Грузовая этикетка',10),(did,'position','Бирка позиции',20),(did,'tag','Манипуляционный знак',30);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Настраиваемые справочники',
   'Модуль «Справочники (настраиваемые)»: единый механизм списков/вариантов для самостоятельного наполнения — код справочника и значения (код → название, порядок, активность). Предзаполнены: категории поставщиков, виды потерь, типы наладок, виды упаковки, типы этикеток. Любой модуль может получать варианты через app_dict_items_by_code(code) и строить выпадающие списки из своих данных, а не из жёстко зашитых значений.',
   'настраиваемые справочники списки выпадающие словарь варианты app_dict_items_by_code')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Настраиваемые справочники');
-- <<<<<<<<<< 0080_dictionaries.sql <<<<<<<<<<
-- >>>>>>>>>> 0081_doc_templates_ext.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0081_doc_templates_ext.sql  (v59 — расширение шаблонов)
-- Дополнительные шаблоны документов, словарь типов документов, дублирование
-- шаблона. База знаний. Зависит от 0001..0080.
-- ============================================================

-- ---------- Дублирование шаблона ----------
create or replace function public.app_doc_template_duplicate(p_token uuid, p_id uuid)
returns table (id uuid, name text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; mid uuid; mname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
  select t.tenant_id, t.doc_type, t.name || ' (копия)', t.body, t.active
    from public.app_doc_templates t
   where t.id=p_id and (urole='admin' or t.tenant_id=ten)
   returning id, name into mid, mname;
  return query select mid, mname, 'Шаблон скопирован';
end $$;

grant execute on function public.app_doc_template_duplicate(uuid,uuid) to anon, authenticated;

-- ---------- Словарь типов документов ----------
do $$
declare did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and lower(code)='doc_type') then
    insert into public.app_dictionaries (tenant_id, code, name, description)
    values ('aaaaaaaa-0000-0000-0000-000000000001','doc_type','Типы документов','Шаблоны документов') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'kp','Коммерческое предложение',10),
      (did,'contract','Договор',20),
      (did,'act','Акт',30),
      (did,'invoice','Счёт на оплату',40),
      (did,'waybill','Накладная',50),
      (did,'tz','Техническое задание',60),
      (did,'techcard','Технологическая карта',70),
      (did,'passport','Паспорт качества',80),
      (did,'other','Прочее',90);
  end if;
end $$;

-- ---------- Дополнительные шаблоны (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
begin
  insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
  select A, v.t, v.n, v.b, true
  from (values
    ('invoice','Счёт на оплату',
     'СЧЁТ на оплату № {{order}} от {{date}}' || chr(10) || 'Плательщик: {{customer}}' || chr(10) || 'Основание: {{title}}' || chr(10) || 'Сумма: {{amount}} ₽'),
    ('waybill','Накладная (ТОРГ-12)',
     'НАКЛАДНАЯ № {{order}} от {{date}}' || chr(10) || 'Поставщик: 3DMP' || chr(10) || 'Получатель: {{customer}}' || chr(10) || 'Наименование: {{title}}'),
    ('act','Акт приёма-передачи',
     'АКТ приёма-передачи № {{order}} от {{date}}' || chr(10) || 'Работы выполнены: {{title}}' || chr(10) || 'Заказчик: {{customer}}' || chr(10) || 'Стоимость: {{amount}} ₽'),
    ('tz','Техническое задание',
     'ТЕХНИЧЕСКОЕ ЗАДАНИЕ' || chr(10) || 'Изделие: {{title}}' || chr(10) || 'Заказчик: {{customer}}' || chr(10) || 'Требования: (заполните)'),
    ('passport','Паспорт качества',
     'ПАСПОРТ КАЧЕСТВА' || chr(10) || 'Изделие: {{title}}' || chr(10) || 'Заказ № {{order}} от {{date}}' || chr(10) || 'Соответствует ТУ/ГОСТ: (указать)')
  ) as v(t,n,b)
  where not exists (select 1 from public.app_doc_templates t2 where t2.tenant_id=A and t2.name=v.n);
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Документы','Шаблоны документов — расширение',
   'Модуль «Шаблоны документов»: пользователь сам создаёт/редактирует шаблоны (типы берутся из справочника «Типы документов»), подставляет переменные {{customer}}, {{order}}, {{title}}, {{amount}}, {{date}} и создаёт готовый документ по заявке. Добавлены типовые шаблоны: счёт, накладная, акт приёма-передачи, ТЗ, паспорт качества; любой шаблон можно дублировать и править.',
   'шаблоны документы КП договор акт счёт накладная ТЗ паспорт подстановки дублирование')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Шаблоны документов — расширение');
-- <<<<<<<<<< 0081_doc_templates_ext.sql <<<<<<<<<<
-- >>>>>>>>>> 0082_partners.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0082_partners.sql  (v60 — Сессия K: C2 «Партнёрский кабинет»)
-- Партнёры (агенты/интеграторы) и их сделки-рефералы, комиссия, статусы.
-- База знаний. Зависит от 0001..0081.
-- ============================================================

create table if not exists public.app_partners (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  name           text not null,
  inn            text,
  contact        text,
  phone          text,
  email          text,
  region         text,
  category       text,                 -- агент|интегратор|сервис|поставщик|прочее
  commission_pct numeric not null default 5,
  status         text not null default 'active', -- active|paused|archived
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_partners_idx on public.app_partners (tenant_id, status);
alter table public.app_partners enable row level security;

create table if not exists public.app_partner_deals (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  partner_id    uuid references public.app_partners (id) on delete set null,
  order_id      uuid references public.app_orders (id) on delete set null,
  title         text not null,
  amount        numeric not null default 0,
  commission    numeric not null default 0,
  status        text not null default 'new', -- new|in_work|won|lost
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_partner_deals_idx on public.app_partner_deals (tenant_id, status);
alter table public.app_partner_deals enable row level security;

-- ---------- Партнёры ----------
create or replace function public.app_partners_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, inn text, contact text, phone text, email text, region text, category text,
               commission_pct numeric, status text, deals bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, p.name, p.inn, p.contact, p.phone, p.email, p.region, p.category, p.commission_pct, p.status,
      (select count(*) from public.app_partner_deals d where d.partner_id=p.id)
    from public.app_partners p
    where (urole='admin' or p.tenant_id=ten)
      and (qq='' or lower(p.name) like '%'||qq||'%' or lower(coalesce(p.contact,'')) like '%'||qq||'%')
    order by (p.status='archived'), p.name;
end $$;

create or replace function public.app_partner_save(p_token uuid, p_id uuid, p_name text, p_inn text, p_contact text,
  p_phone text, p_email text, p_region text, p_category text, p_commission_pct numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; pid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите наименование партнёра'; return; end if;
  if p_id is null then
    insert into public.app_partners (tenant_id, name, inn, contact, phone, email, region, category, commission_pct, note, created_login)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''), nullif(trim(p_email),''),
            nullif(trim(p_region),''), nullif(trim(p_category),''), coalesce(p_commission_pct,5), nullif(trim(p_note),''), ulogin)
    returning id into pid;
    return query select pid, 'Партнёр добавлен';
  else
    update public.app_partners set name=trim(p_name), inn=nullif(trim(p_inn),''), contact=nullif(trim(p_contact),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), region=nullif(trim(p_region),''),
      category=nullif(trim(p_category),''), commission_pct=coalesce(p_commission_pct,commission_pct), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into pid;
    return query select pid, 'Партнёр обновлён';
  end if;
end $$;

create or replace function public.app_partner_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('active','paused','archived') then return query select false,'Неверный статус'; return; end if;
  update public.app_partners set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_partners_kpi(p_token uuid)
returns table (partners bigint, active bigint, deals bigint, won_amount numeric, commission_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_partners where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_partners where status='active' and (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_partner_deals where (urole='admin' or tenant_id=ten)),
    (select coalesce(sum(amount),0) from public.app_partner_deals where status='won' and (urole='admin' or tenant_id=ten)),
    (select coalesce(sum(commission),0) from public.app_partner_deals where status='won' and (urole='admin' or tenant_id=ten));
end $$;

-- ---------- Сделки партнёров ----------
create or replace function public.app_partner_deals_list(p_token uuid, p_q text default null)
returns table (id uuid, partner_id uuid, partner_name text, order_number text, title text, amount numeric,
               commission numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.partner_id, p.name, o.number, d.title, d.amount, d.commission, d.status, d.created_at
    from public.app_partner_deals d
    left join public.app_partners p on p.id=d.partner_id
    left join public.app_orders o on o.id=d.order_id
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.title) like '%'||qq||'%' or lower(coalesce(p.name,'')) like '%'||qq||'%')
    order by d.created_at desc;
end $$;

create or replace function public.app_partner_deal_save(p_token uuid, p_id uuid, p_partner_id uuid, p_order_id uuid,
  p_title text, p_amount numeric, p_commission numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите предмет сделки'; return; end if;
  if p_id is null then
    insert into public.app_partner_deals (tenant_id, partner_id, order_id, title, amount, commission, note, created_login)
    values (ten, p_partner_id, p_order_id, trim(p_title), coalesce(p_amount,0), coalesce(p_commission,0), nullif(trim(p_note),''), ulogin)
    returning id into did;
    return query select did, 'Сделка добавлена';
  else
    update public.app_partner_deals set partner_id=p_partner_id, order_id=p_order_id, title=trim(p_title),
      amount=coalesce(p_amount,0), commission=coalesce(p_commission,0), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Сделка обновлена';
  end if;
end $$;

create or replace function public.app_partner_deal_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_work','won','lost') then return query select false,'Неверный статус'; return; end if;
  update public.app_partner_deals set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_partners_list(uuid,text) to anon, authenticated;
grant execute on function public.app_partner_save(uuid,uuid,text,text,text,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_partner_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_partners_kpi(uuid) to anon, authenticated;
grant execute on function public.app_partner_deals_list(uuid,text) to anon, authenticated;
grant execute on function public.app_partner_deal_save(uuid,uuid,uuid,uuid,text,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_partner_deal_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; pid uuid;
begin
  if not exists (select 1 from public.app_partners where tenant_id=A) then
    insert into public.app_partners (tenant_id, name, inn, contact, phone, email, region, category, commission_pct, status, created_login)
    values (A, 'ООО «Промтех-Агент»', '5901234567', 'Орлов О.О.', '+7 342 111-22-33', 'agent@promtech.ru', 'Пермь', 'агент', 5, 'active', 'manager')
    returning id into pid;
    insert into public.app_partners (tenant_id, name, contact, phone, email, region, category, commission_pct, status, created_login)
    values (A, 'ИП Смирнов (интегратор)', 'Смирнов С.С.', '+7 342 222-33-44', 'smirnov@int.ru', 'Екатеринбург', 'интегратор', 7, 'active', 'manager');
    insert into public.app_partner_deals (tenant_id, partner_id, order_id, title, amount, commission, status, created_login)
    values (A, pid, (select id from public.app_orders where tenant_id=A order by created_at limit 1),
            'Поставка оснастки (реферал)', 380000, 19000, 'in_work', 'manager');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Партнёрский кабинет (C2)',
   'Модуль «Партнёры»: реестр агентов/интеграторов/сервис-партнёров с реквизитами, категорией, процентом комиссии и статусом (активен/пауза/архив); сделки-рефералы с суммой и комиссией, статусы (новая → в работе → выиграна/проиграна). KPI: партнёры, активные, сделки, выигранная сумма, комиссия.',
   'партнёры агенты интеграторы рефералы комиссия сделки C2')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Партнёрский кабинет (C2)');
-- <<<<<<<<<< 0082_partners.sql <<<<<<<<<<
-- >>>>>>>>>> 0083_equipment_catalog.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0083_equipment_catalog.sql  (v61 — Сессия L: A11 «Каталог оборудования»)
-- Каталог оборудования к поставке/продаже: модели, производитель, тип, оси,
-- точность, цена, описание. База знаний. Зависит от 0001..0082.
-- ============================================================

create table if not exists public.app_equipment_catalog (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  name        text not null,
  brand       text,
  category    text,                 -- cnc|lathe|edm|grinding|press|measuring|other
  axes        int,
  accuracy    text,
  price       numeric default 0,
  currency    text default 'RUB',
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_equipment_catalog_idx on public.app_equipment_catalog (tenant_id, active, category);
alter table public.app_equipment_catalog enable row level security;

create or replace function public.app_equipment_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, name text, brand text, category text, axes int, accuracy text, price numeric, currency text, description text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select e.id, e.name, e.brand, e.category, e.axes, e.accuracy, e.price, e.currency, e.description, e.active
    from public.app_equipment_catalog e
    where (urole='admin' or e.tenant_id=ten)
      and (coalesce(p_category,'')='' or e.category=p_category)
      and (qq='' or lower(e.name) like '%'||qq||'%' or lower(coalesce(e.brand,'')) like '%'||qq||'%')
    order by e.active desc, e.brand, e.name;
end $$;

create or replace function public.app_equipment_save(p_token uuid, p_id uuid, p_name text, p_brand text, p_category text,
  p_axes int, p_accuracy text, p_price numeric, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите модель/название'; return; end if;
  if p_id is null then
    insert into public.app_equipment_catalog (tenant_id, name, brand, category, axes, accuracy, price, description, active)
    values (ten, trim(p_name), nullif(trim(p_brand),''), nullif(trim(p_category),''), p_axes, nullif(trim(p_accuracy),''), coalesce(p_price,0), nullif(trim(p_description),''), coalesce(p_active,true))
    returning id into eid;
    return query select eid, 'Позиция добавлена';
  else
    update public.app_equipment_catalog set name=trim(p_name), brand=nullif(trim(p_brand),''), category=nullif(trim(p_category),''),
      axes=p_axes, accuracy=nullif(trim(p_accuracy),''), price=coalesce(p_price,0), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into eid;
    return query select eid, 'Позиция обновлена';
  end if;
end $$;

create or replace function public.app_equipment_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_equipment_catalog where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Позиция удалена';
end $$;

create or replace function public.app_equipment_kpi(p_token uuid)
returns table (total bigint, active bigint, categories bigint, price_min numeric, price_max numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where active),
    count(distinct category) filter (where category is not null),
    coalesce(min(price) filter (where price>0),0), coalesce(max(price),0)
    from public.app_equipment_catalog where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_equipment_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_equipment_save(uuid,uuid,text,text,text,int,text,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_equipment_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_equipment_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_equipment_catalog (tenant_id, name, brand, category, axes, accuracy, price, description)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.brand, v.cat, v.axes, v.acc, v.price, v.descr
from (values
  ('Feeler FTC-350Xl','Feeler','cnc',3,'±0.005 мм', 8500000, 'Вертикальный обрабатывающий центр'),
  ('Mitsubishi FA10-VS','Mitsubishi','edm',2,'±0.003 мм', 6200000, 'Проволочно-вырезной электроэрозионный'),
  ('Okamoto PSG-64B','Okamoto','grinding',0,'±0.002 мм', 4100000, 'Плоскошлифовальный станок'),
  ('DMG CTX beta 800','DMG MORI','lathe',4,'±0.005 мм', 14500000, 'Токарно-фрезерный с противошпинделем'),
  ('Zeiss Contura','Zeiss','measuring',0,'±0.001 мм', 7800000, 'КИМ (координатно-измерительная машина)')
) as v(name,brand,cat,axes,acc,price,descr)
where not exists (select 1 from public.app_equipment_catalog where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Каталог оборудования (A11)',
   'Модуль «Каталог оборудования»: витрина станков и оборудования к поставке — модель, производитель, тип (ЧПУ/токарные/ЭЭО/шлифование/прессы/измерения), число осей, точность, цена, описание. Позиции можно включать/выключать и использовать в продажах и КП.',
   'каталог оборудования поставка станки витрина цена A11')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Каталог оборудования (A11)');
-- <<<<<<<<<< 0083_equipment_catalog.sql <<<<<<<<<<
-- >>>>>>>>>> 0084_staff_crm.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0084_staff_crm.sql  (v62 — Сессия M: B12 «CRM сотрудников»)
-- Кадровый учёт и развитие: карточки сотрудников, статусы, рейтинг, история
-- взаимодействий (1-на-1, аттестация, повышение, замечание). Зависит от 0001..0083.
-- ============================================================

create table if not exists public.app_staff_crm (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  pos        text,
  department text,
  manager    text,
  status     text not null default 'active', -- active|leave|fired
  hired_at   date,
  rating     numeric default 0,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists app_staff_crm_idx on public.app_staff_crm (tenant_id, status);
alter table public.app_staff_crm enable row level security;

create table if not exists public.app_staff_events (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid references public.app_staff_crm (id) on delete cascade,
  kind       text not null default 'note', -- note|one_on_one|review|promotion|warning
  note       text,
  author     text,
  created_at timestamptz not null default now()
);
create index if not exists app_staff_events_idx on public.app_staff_events (staff_id, created_at desc);
alter table public.app_staff_events enable row level security;

create or replace function public.app_staff_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, pos text, department text, manager text, status text, hired_at date, rating numeric, events bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.name, s.pos, s.department, s.manager, s.status, s.hired_at, s.rating,
      (select count(*) from public.app_staff_events e where e.staff_id=s.id)
    from public.app_staff_crm s
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(coalesce(s.pos,'')) like '%'||qq||'%' or lower(coalesce(s.department,'')) like '%'||qq||'%')
    order by (s.status='fired'), s.name;
end $$;

create or replace function public.app_staff_save(p_token uuid, p_id uuid, p_name text, p_position text, p_department text,
  p_manager text, p_status text, p_hired_at date, p_rating numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите ФИО'; return; end if;
  if coalesce(p_status,'active') not in ('active','leave','fired') then raise exception 'Неверный статус'; return; end if;
  if p_id is null then
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating, note)
    values (ten, trim(p_name), nullif(trim(p_position),''), nullif(trim(p_department),''), nullif(trim(p_manager),''),
            coalesce(nullif(trim(p_status),''),'active'), p_hired_at, coalesce(p_rating,0), nullif(trim(p_note),''))
    returning id into sid;
    return query select sid, 'Сотрудник добавлен';
  else
    update public.app_staff_crm set name=trim(p_name), pos=nullif(trim(p_position),''), department=nullif(trim(p_department),''),
      manager=nullif(trim(p_manager),''), status=coalesce(nullif(trim(p_status),''),status), hired_at=p_hired_at,
      rating=coalesce(p_rating,rating), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Данные обновлены';
  end if;
end $$;

create or replace function public.app_staff_event_add(p_token uuid, p_staff_id uuid, p_kind text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_staff_crm s where s.id=p_staff_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Сотрудник не найден'; return; end if;
  insert into public.app_staff_events (staff_id, kind, note, author)
  values (p_staff_id, coalesce(nullif(trim(p_kind),''),'note'), nullif(trim(p_note),''), ulogin)
  returning id into eid;
  return query select eid, 'Запись добавлена';
end $$;

create or replace function public.app_staff_events_list(p_token uuid, p_staff_id uuid)
returns table (id uuid, kind text, note text, author text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_staff_crm s where s.id=p_staff_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Сотрудник не найден'; end if;
  return query select e.id, e.kind, e.note, e.author, e.created_at
    from public.app_staff_events e where e.staff_id=p_staff_id order by e.created_at desc;
end $$;

create or replace function public.app_staff_kpi(p_token uuid)
returns table (total bigint, active bigint, on_leave bigint, fired bigint, avg_rating numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='active'), count(*) filter (where status='leave'),
    count(*) filter (where status='fired'), round(coalesce(avg(rating) filter (where rating>0),0),1)
    from public.app_staff_crm where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_staff_list(uuid,text) to anon, authenticated;
grant execute on function public.app_staff_save(uuid,uuid,text,text,text,text,text,date,numeric,text) to anon, authenticated;
grant execute on function public.app_staff_event_add(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_staff_events_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_staff_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_staff_crm where tenant_id=A) then
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating, note)
    values (A, 'Сидоров А.А.', 'Мастер участка', 'Механообработка', 'Начальник цеха', 'active', current_date - 900, 4.6, 'Ключевой сотрудник')
    returning id into sid;
    insert into public.app_staff_events (staff_id, kind, note, author) values
      (sid,'one_on_one','Обсуждены цели на квартал','Директор'),
      (sid,'review','Аттестация: соответствует, премия 10%','Директор');
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating)
    values (A, 'Петров П.П.', 'Оператор ЧПУ', 'Механообработка', 'Сидоров А.А.', 'active', current_date - 300, 4.1),
           (A, 'Иванов И.И.', 'Технолог', 'Технологический отдел', 'Главный технолог', 'leave', current_date - 600, 4.8);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Персонал','CRM сотрудников (B12)',
   'Модуль «CRM сотрудников»: кадровые карточки (ФИО, должность, подразделение, руководитель, статус: работает/отпуск/уволен, дата приёма, рейтинг) и история взаимодействий (заметка, 1-на-1, аттестация, повышение, замечание). KPI: всего, работают, в отпуске, уволены, средний рейтинг. Дополняет HR и оргструктуру.',
   'CRM сотрудников кадры развитие аттестация рейтинг B12')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='CRM сотрудников (B12)');
-- <<<<<<<<<< 0084_staff_crm.sql <<<<<<<<<<
-- >>>>>>>>>> 0085_config_options.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0085_config_options.sql  (v63 — Сессия N: A8 «Конфигуратор спец-технологий»)
-- Опции (группа → опция с наценкой) и расчёт стоимости конфигурации.
-- База знаний. Зависит от 0001..0084.
-- ============================================================

create table if not exists public.app_config_options (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  group_name  text not null,
  name        text not null,
  price_delta numeric not null default 0,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_config_options_idx on public.app_config_options (tenant_id, group_name, active);
alter table public.app_config_options enable row level security;

create or replace function public.app_config_groups(p_token uuid)
returns table (group_name text, options bigint, price_min numeric, price_max numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select o.group_name, count(*), coalesce(min(o.price_delta),0), coalesce(max(o.price_delta),0)
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten) and o.active
    group by o.group_name order by o.group_name;
end $$;

create or replace function public.app_config_options_list(p_token uuid, p_group text default null)
returns table (id uuid, group_name text, name text, price_delta numeric, note text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select o.id, o.group_name, o.name, o.price_delta, o.note, o.active
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten)
      and (coalesce(p_group,'')='' or o.group_name=p_group)
    order by o.group_name, o.name;
end $$;

create or replace function public.app_config_option_save(p_token uuid, p_id uuid, p_group text, p_name text, p_price_delta numeric, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; oid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_group),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите группу и название'; return; end if;
  if p_id is null then
    insert into public.app_config_options (tenant_id, group_name, name, price_delta, note, active)
    values (ten, trim(p_group), trim(p_name), coalesce(p_price_delta,0), nullif(trim(p_note),''), coalesce(p_active,true)) returning id into oid;
    return query select oid, 'Опция добавлена';
  else
    update public.app_config_options set group_name=trim(p_group), name=trim(p_name), price_delta=coalesce(p_price_delta,0),
      note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into oid;
    return query select oid, 'Опция обновлена';
  end if;
end $$;

create or replace function public.app_config_option_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_config_options where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Опция удалена';
end $$;

create or replace function public.app_config_estimate(p_token uuid, p_ids uuid[])
returns table (cnt int, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; c int; t numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*), coalesce(sum(price_delta),0) into c, t
    from public.app_config_options o
    where (urole='admin' or o.tenant_id=ten) and o.id = any(coalesce(p_ids, array[]::uuid[]));
  return query select coalesce(c,0), coalesce(t,0);
end $$;

grant execute on function public.app_config_groups(uuid) to anon, authenticated;
grant execute on function public.app_config_options_list(uuid,text) to anon, authenticated;
grant execute on function public.app_config_option_save(uuid,uuid,text,text,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_config_option_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_config_estimate(uuid,uuid[]) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_config_options (tenant_id, group_name, name, price_delta, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.g, v.n, v.p, v.note
from (values
  ('Точность','Повышенная точность (IT6)', 15000, 'Доп. контроль и доводка'),
  ('Точность','Высокая точность (IT5)', 40000, 'Финишное шлифование/притирка'),
  ('Покрытие','Азотирование', 25000, 'Упрочнение поверхности'),
  ('Покрытие','Хромирование', 35000, 'Износостойкость'),
  ('Термообработка','Закалка + отпуск', 30000, 'HRC 45–50'),
  ('Термообработка','Стабилизация', 12000, 'Снятие напряжений'),
  ('Оснастка','Спецоснастка (проект)', 60000, 'Проектирование и изготовление'),
  ('Измерения','КИМ-контроль', 18000, 'Протокол измерений')
) as v(g,n,p,note)
where not exists (select 1 from public.app_config_options where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Конфигуратор спец-технологий (A8)',
   'Модуль «Конфигуратор»: наборы опций по группам (точность, покрытие, термообработка, оснастка, измерения) с наценкой. Пользователь отмечает нужные опции — система считает суммарное удорожание. Основа быстрого расчёта спец-технологий и КП.',
   'конфигуратор опции спец-технологии точность покрытие термообработка наценка A8')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Конфигуратор спец-технологий (A8)');
-- <<<<<<<<<< 0085_config_options.sql <<<<<<<<<<
-- >>>>>>>>>> 0086_reverse.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0086_reverse.sql  (v64 — Сессия O: A6 «Реверс-инжиниринг»)
-- Заявки на обратное проектирование: метод съёма (скан/обмер/чертёж/фото/
-- образец), результат (модель/чертёж), статусы. Зависит от 0001..0085.
-- ============================================================

create sequence if not exists public.app_reverse_seq;
create table if not exists public.app_reverse_orders (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  title         text not null,
  customer      text,
  part          text,
  method        text not null default 'scan',   -- scan|measure|drawing|photo|sample
  result_type   text not null default 'model',  -- model|drawing|both
  status        text not null default 'new',    -- new|scanning|modelling|review|done|cancelled
  assignee      text,
  order_id      uuid references public.app_orders (id) on delete set null,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_reverse_orders_idx on public.app_reverse_orders (tenant_id, status, created_at desc);
alter table public.app_reverse_orders enable row level security;

create or replace function public.app_reverse_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, title text, customer text, part text, method text, result_type text,
               status text, assignee text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select r.id, r.number, r.title, r.customer, r.part, r.method, r.result_type, r.status, r.assignee, o.number, r.created_at
    from public.app_reverse_orders r left join public.app_orders o on o.id=r.order_id
    where (urole='admin' or r.tenant_id=ten)
      and (qq='' or lower(r.title) like '%'||qq||'%' or lower(coalesce(r.customer,'')) like '%'||qq||'%' or lower(coalesce(r.part,'')) like '%'||qq||'%')
    order by (r.status='done'), r.created_at desc;
end $$;

create or replace function public.app_reverse_save(p_token uuid, p_id uuid, p_title text, p_customer text, p_part text,
  p_method text, p_result_type text, p_assignee text, p_order_id uuid, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid; rnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите изделие/название'; return; end if;
  if coalesce(p_method,'scan') not in ('scan','measure','drawing','photo','sample') then raise exception 'Неверный метод'; return; end if;
  if coalesce(p_result_type,'model') not in ('model','drawing','both') then raise exception 'Неверный результат'; return; end if;
  if p_id is null then
    rnum := 'REV-' || lpad(nextval('public.app_reverse_seq')::text, 5, '0');
    insert into public.app_reverse_orders (tenant_id, number, title, customer, part, method, result_type, assignee, order_id, note, created_login)
    values (ten, rnum, trim(p_title), nullif(trim(p_customer),''), nullif(trim(p_part),''), p_method, p_result_type,
            nullif(trim(p_assignee),''), p_order_id, nullif(trim(p_note),''), ulogin)
    returning id into rid;
    return query select rid, rnum, 'Заявка на реверс-инжиниринг создана';
  else
    update public.app_reverse_orders set title=trim(p_title), customer=nullif(trim(p_customer),''), part=nullif(trim(p_part),''),
      method=p_method, result_type=p_result_type, assignee=nullif(trim(p_assignee),''), order_id=p_order_id, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into rid, rnum;
    return query select rid, rnum, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_reverse_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','scanning','modelling','review','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_reverse_orders set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_reverse_kpi(p_token uuid)
returns table (total bigint, new_cnt bigint, in_progress bigint, done bigint, by_drawing bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='new'),
    count(*) filter (where status in ('scanning','modelling','review')),
    count(*) filter (where status='done'),
    count(*) filter (where method='drawing')
    from public.app_reverse_orders where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_reverse_list(uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_save(uuid,uuid,text,text,text,text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_reverse_orders (tenant_id, number, title, customer, part, method, result_type, status, assignee, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  'REV-' || lpad(nextval('public.app_reverse_seq')::text,5,'0'), v.title, v.cust, v.part, v.m, v.rt, v.st, v.who, 'technologist'
from (values
  ('Обратное проектирование зубчатого колеса','ООО «Механика»','Колесо z=42','scan','model','modelling','Технолог'),
  ('Обмер корпуса редуктора','АО «Привод»','Корпус','measure','drawing','done','Мастер')
) as v(title,cust,part,m,rt,st,who)
where not exists (select 1 from public.app_reverse_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Реверс-инжиниринг (A6)',
   'Модуль «Реверс-инжиниринг»: заявки на обратное проектирование (REV-NNNNN) — изделие, заказчик, деталь, метод съёма данных (3D-скан/обмер/чертёж/фото/образец), требуемый результат (3D-модель/чертёж/оба), исполнитель, связь с заявкой. Статусы: новая → сканирование → моделирование → проверка → готово. KPI по этапам.',
   'реверс-инжиниринг обратное проектирование 3д скан обмер чертёж модель A6')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Реверс-инжиниринг (A6)');
-- <<<<<<<<<< 0086_reverse.sql <<<<<<<<<<
-- >>>>>>>>>> 0087_guard_rollout.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0087_guard_rollout.sql  (v65 — P8 шаг 2: серверная матрица прав)
-- Внедрение app_guard в мутирующие RPC (слайс: эскроу, маркетплейс).
-- Права берутся из матрицы app_role_permissions: admin/owner — всегда; иначе
-- по роли/модулю. Зависит от 0001..0086.
-- ============================================================

-- ---------- Escrow: save ----------
create or replace function public.app_escrow_save(p_token uuid, p_id uuid, p_order_id uuid, p_customer_id uuid,
  p_buyer text, p_seller text, p_amount numeric, p_fee_pct numeric, p_milestone text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; did uuid; dnum text; tname text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'escrow', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Укажите сумму сделки'; return; end if;
  select name into tname from public.tenants where id=ten;
  select name into cname from public.app_customers where id=p_customer_id;
  if p_id is null then
    dnum := 'ESC-' || lpad(nextval('public.app_escrow_seq')::text, 5, '0');
    insert into public.app_escrow_deals (tenant_id, number, order_id, customer_id, buyer, seller, amount, fee_pct, milestone, note, created_login)
    values (ten, dnum, p_order_id, p_customer_id, coalesce(nullif(trim(p_buyer),''), cname), coalesce(nullif(trim(p_seller),''), tname),
            p_amount, coalesce(p_fee_pct,2.5), nullif(trim(p_milestone),''), nullif(trim(p_note),''), ulogin)
    returning id into did;
    insert into public.app_escrow_events (deal_id, kind, comment, by_login) values (did, 'created', 'Сделка создана', ulogin);
    return query select did, dnum, 'Эскроу-сделка создана';
  else
    update public.app_escrow_deals set order_id=p_order_id, customer_id=p_customer_id,
      buyer=coalesce(nullif(trim(p_buyer),''),buyer), seller=coalesce(nullif(trim(p_seller),''),seller),
      amount=p_amount, fee_pct=coalesce(p_fee_pct,fee_pct), milestone=nullif(trim(p_milestone),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into did, dnum;
    return query select did, dnum, 'Сделка обновлена';
  end if;
end $$;

-- ---------- Escrow: set_status ----------
create or replace function public.app_escrow_set_status(p_token uuid, p_id uuid, p_status text, p_comment text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'escrow','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('created','funded','in_work','released','dispute','cancelled') then return query select false,'Неверный статус'; return; end if;
  select * into d from public.app_escrow_deals where id=p_id and (urole='admin' or tenant_id=ten);
  if d.id is null then return query select false,'Сделка не найдена'; return; end if;
  update public.app_escrow_deals set status=p_status,
    funded_at = case when p_status='funded' then now() else funded_at end,
    released_at = case when p_status='released' then now() else released_at end
   where id=p_id;
  insert into public.app_escrow_events (deal_id, kind, comment, by_login)
  values (p_id, p_status, coalesce(nullif(trim(p_comment),''), 'Статус: '||p_status), ulogin);
  if p_status in ('released','dispute') then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','economist'],
      'Эскроу '||d.number||': '||p_status, coalesce(p_comment,''), 'apps/escrow/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

-- ---------- Marketplace: listing save ----------
create or replace function public.app_market_listing_save(p_token uuid, p_id uuid, p_title text, p_process text,
  p_machine text, p_capacity_hours numeric, p_price_from numeric, p_region text, p_lead_days int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'marketplace', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите название объявления'; return; end if;
  if p_id is null then
    insert into public.app_market_listings (tenant_id, title, process, machine, capacity_hours, price_from, region, lead_days, note, created_login)
    values (ten, trim(p_title), nullif(trim(p_process),''), nullif(trim(p_machine),''), p_capacity_hours, p_price_from,
            nullif(trim(p_region),''), p_lead_days, nullif(trim(p_note),''), ulogin)
    returning id into lid;
    return query select lid, 'Объявление размещено';
  else
    update public.app_market_listings set title=trim(p_title), process=nullif(trim(p_process),''), machine=nullif(trim(p_machine),''),
      capacity_hours=p_capacity_hours, price_from=p_price_from, region=nullif(trim(p_region),''), lead_days=p_lead_days, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Объявление обновлено';
  end if;
end $$;

-- ---------- Marketplace: request save ----------
create or replace function public.app_market_request_save(p_token uuid, p_id uuid, p_listing_id uuid, p_title text,
  p_qty numeric, p_due_date date, p_budget numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'marketplace', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите предмет заявки'; return; end if;
  if p_id is null then
    insert into public.app_market_requests (tenant_id, listing_id, title, qty, due_date, budget, note, created_login)
    values (ten, p_listing_id, trim(p_title), coalesce(p_qty,1), p_due_date, p_budget, nullif(trim(p_note),''), ulogin)
    returning id into rid;
    if p_listing_id is not null then
      perform public.app_notif_roles_t((select tenant_id from public.app_market_listings where id=p_listing_id),
        array['admin','owner','manager'], 'Заявка из маркетплейса: '||trim(p_title), '', 'apps/marketplace/index.html');
    end if;
    return query select rid, 'Заявка отправлена';
  else
    update public.app_market_requests set listing_id=p_listing_id, title=trim(p_title), qty=coalesce(p_qty,qty),
      due_date=p_due_date, budget=p_budget, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into rid;
    return query select rid, 'Заявка обновлена';
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав в RPC (P8 шаг 2)',
   'Мутирующие RPC проверяют права на сервере через app_guard(token, module, action) (матрица app_role_permissions): admin/owner — всегда; остальные — по назначенным правам. Начато с эскроу и маркетплейса; rollout продолжается по остальным модулям. UI-скрытие кнопок — только удобство, реальная защита — на сервере.',
   'права app_guard серверная проверка RPC матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав в RPC (P8 шаг 2)');
-- <<<<<<<<<< 0087_guard_rollout.sql <<<<<<<<<<
-- >>>>>>>>>> 0088_guard_broad.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0088_guard_broad.sql  (v66 — P8 шаг 2, широкий rollout)
-- Внедрение серверной проверки app_guard в мутирующие RPC по списку функций.
-- Для каждой функции тело берётся из pg_get_functiondef и в начало блока
-- (после BEGIN) добавляется `perform public.app_guard(p_token,'<module>','edit')`.
-- Идемпотентно: функции, где уже есть app_guard/app_can, пропускаются.
-- Зависит от 0001..0087.
-- ============================================================

do $$
declare
  v record;
  r record;
  def text;
  n_fixed int := 0;
begin
  for v in
    select * from (values
      ('app_norms_op_save','norms'),
      ('app_norms_rate_save','norms'),
      ('app_norms_rate_delete','norms'),
      ('app_norms_k_save','norms'),
      ('app_norms_serial_save','norms'),
      ('app_analog_save','norms'),
      ('app_slot_save','slots'),
      ('app_slot_book','slots'),
      ('app_sla_save','slots'),
      ('app_setup_save','setup'),
      ('app_setup_set_status','setup'),
      ('app_lean_save','lean'),
      ('app_lean_set_status','lean'),
      ('app_partner_save','partners'),
      ('app_partner_deal_save','partners'),
      ('app_equipment_save','equipment'),
      ('app_staff_save','staff'),
      ('app_staff_event_add','staff'),
      ('app_config_option_save','config'),
      ('app_reverse_save','reverse'),
      ('app_reverse_set_status','reverse'),
      ('app_dict_save','dicts'),
      ('app_dict_item_save','dicts'),
      ('app_teo_save','teo'),
      ('app_teo_line_save','teo'),
      ('app_engraving_save','engraving'),
      ('app_package_save','labels'),
      ('app_label_save','labels'),
      ('app_suppliers_save','suppliers'),
      ('app_file_register','files'),
      ('app_file_delete','files'),
      ('app_entity_save','builder'),
      ('app_entity_field_save','builder'),
      ('app_entity_record_save','builder'),
      ('app_department_save','departments'),
      ('app_whitelabel_save','whitelabel'),
      ('app_market_listing_set_status','marketplace'),
      ('app_market_request_set_status','marketplace'),
      ('app_escrow_save','escrow'),
      ('app_escrow_set_status','escrow')
    ) as t(fname, mod)
  loop
    for r in
      select pg_get_functiondef(p.oid) as d
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname = v.fname
         and p.prolang = (select oid from pg_language where lanname='plpgsql')
    loop
      def := r.d;
      if position('app_guard(' in def) = 0 and position('app_can(' in def) = 0 then
        def := regexp_replace(
          def,
          '(?i)' || chr(10) || 'begin',
          chr(10) || 'begin' || chr(10) || '  perform public.app_guard(p_token, ''' || v.mod || ''', ''edit'');'
        );
        execute def;
        n_fixed := n_fixed + 1;
      end if;
    end loop;
  end loop;
  raise notice 'app_guard внедрён в % функций', n_fixed;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав — широкий rollout (P8 шаг 2)',
   'Все ключевые мутирующие RPC проверяют права на сервере через app_guard(token, module, edit) по матрице app_role_permissions. Покрыты модули: нормирование, слоты, наладка, lean, партнёры, оборудование, кадры, конфигуратор, реверс, справочники, ТЭО, гравирование, маркировка, поставщики, файлы, конструктор, подразделения, брендирование, маркетплейс, эскроу. admin/owner — всегда; остальные — по назначенным правам.',
   'права app_guard серверная проверка rollout матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав — широкий rollout (P8 шаг 2)');
-- <<<<<<<<<< 0088_guard_broad.sql <<<<<<<<<<
-- >>>>>>>>>> 0089_permissions_more.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0089_permissions_more.sql  (v67 — P8: матрица для новых модулей)
-- Назначение прав (view/edit) для модулей, добавленных после 0079: dicts, staff,
-- partners, equipment, config, reverse, departments, files. Идемпотентно.
-- admin/owner — уже всегда полный доступ. Зависит от 0001..0088.
-- ============================================================

insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, v.edit
from (values
  ('manager','dicts',true),('technologist','dicts',true),('director','dicts',true),
  ('manager','staff',true),('director','staff',true),('chief','staff',true),
  ('manager','partners',true),('director','partners',true),
  ('manager','equipment',true),('technologist','equipment',true),
  ('technologist','config',true),('manager','config',true),
  ('manager','reverse',true),('technologist','reverse',true),('master','reverse',true),
  ('manager','departments',true),('chief','departments',true),('director','departments',true),
  ('manager','files',true),('technologist','files',true),
  ('economist','config',false),('economist','reverse',false),('chief','reverse',false),
  ('operator','reverse',false),('qc','dicts',false)
) as v(role, module, edit)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права на новые модули',
   'Для модулей dicts (справочники), staff (кадры), partners, equipment, config, reverse, departments, files назначены права правки по ролям (менеджер, технолог, директор, начальник цеха, мастер). Администратор и владелец имеют полный доступ всегда. Матрица — app_role_permissions; проверка — app_can/app_guard.',
   'права матрица новые модули dicts staff partners equipment config reverse departments P8')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права на новые модули');
-- <<<<<<<<<< 0089_permissions_more.sql <<<<<<<<<<
-- >>>>>>>>>> 0090_permissions_rest.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0090_permissions_rest.sql  (v68 — P8: права для остальных модулей)
-- Широкие права правки (view/edit) для бизнес-модулей, чтобы широкий rollout
-- app_guard не сломал рабочие потоки. admin/owner — всегда. Платформенные
-- модули (admin/platform/roles/api/scale) НЕ расширяются (только admin/owner).
-- Идемпотентно. Зависит от 0001..0089.
-- ============================================================

insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, r.role, m.module, true, true
from (values ('manager'),('director'),('technologist'),('chief'),('master'),('operator'),('supply'),('qc'),('economist')) as r(role)
cross join (values
  ('orders'),('bom'),('registry'),('calc'),('crm'),('tkp'),('docs'),('templates'),
  ('procurement'),('supplier'),('production'),('mes'),('planning'),('warehouse'),
  ('maintenance'),('tooling'),('oee'),('terminal'),('issues'),('service'),('calendar'),
  ('nc'),('qc'),('passport'),('quality'),('economics'),('finance'),('hr'),('departments'),
  ('staff'),('dicts'),('partners'),('equipment'),('config'),('reverse'),('norms'),('slots'),
  ('setup'),('lean'),('files'),('labels'),('engraving'),('suppliers'),('teo'),('assistant'),
  ('industry'),('builder'),('whitelabel')
) as m(module)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = r.role and p.module_id = m.module
);

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права бизнес-модулей (широкие)',
   'Для бизнес-модулей (заявки, документы, производство, качество, экономика, персонал и др.) право правки назначено офисным/цеховым ролям, чтобы серверная проверка app_guard не блокировала рабочие процессы. Платформенные модули (admin, platform, roles, api, scale) доступны только администратору/владельцу. Централизованно меняется в app_role_permissions.',
   'права бизнес-модули широкие роли app_guard P8 матрица')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права бизнес-модулей (широкие)');
-- <<<<<<<<<< 0090_permissions_rest.sql <<<<<<<<<<
-- >>>>>>>>>> 0091_guard_rest.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0091_guard_rest.sql  (v69 — P8 шаг 2: остаточный rollout)
-- Внедрение app_guard в оставшиеся мутирующие RPC (автоинъекция через
-- pg_get_functiondef; после BEGIN). Идемпотентно. Зависит от 0001..0090.
-- ============================================================

do $$
declare
  v record; r record; def text; n_fixed int := 0;
begin
  for v in
    select * from (values
      ('app_bom_save','bom'),
      ('app_material_save','registry'),
      ('app_operation_save','registry'),
      ('app_process_create','registry'),
      ('app_route_set_status','registry'),
      ('app_ref_material_save','registry'),
      ('app_customer_save','crm'),
      ('app_deal_save','crm'),
      ('app_tkp_save','tkp'),
      ('app_tkp_set_status','tkp'),
      ('app_doc_create','docs'),
      ('app_doc_update','docs'),
      ('app_doc_set_status','docs'),
      ('app_doc_template_save','templates'),
      ('app_tender_create','procurement'),
      ('app_tender_set_status','procurement'),
      ('app_supplier_profile_save','supplier'),
      ('app_suppliers_set_status','suppliers'),
      ('app_naryad_create','production'),
      ('app_naryad_update','production'),
      ('app_naryad_close','production'),
      ('app_mes_create','mes'),
      ('app_mes_delete','mes'),
      ('app_mes_set_status','mes'),
      ('app_mes_ops_set_status','mes'),
      ('app_shift_add','planning'),
      ('app_shift_delete','planning'),
      ('app_stock_move','warehouse'),
      ('app_mnt_plan_save','maintenance'),
      ('app_mnt_register','maintenance'),
      ('app_tool_save','tooling'),
      ('app_tool_delete','tooling'),
      ('app_tool_life_save','tooling'),
      ('app_oee_save','oee'),
      ('app_issue_save','issues'),
      ('app_issue_set_status','issues'),
      ('app_escalation_scan','issues'),
      ('app_service_save','service'),
      ('app_service_set_status','service'),
      ('app_calendar_save','calendar'),
      ('app_calendar_delete','calendar'),
      ('app_nc_save','nc'),
      ('app_nc_set_status','nc'),
      ('app_qc_create','qc'),
      ('app_qc_set_status','qc'),
      ('app_defect_add','qc'),
      ('app_passport_create','passport'),
      ('app_trace_add','quality'),
      ('app_invoice_create','finance'),
      ('app_invoice_set_status','finance'),
      ('app_payment_add','finance'),
      ('app_employee_save','hr'),
      ('app_training_add','staff'),
      ('app_training_set_status','staff'),
      ('app_kb_add','assistant'),
      ('app_industry_benchmark_save','industry'),
      ('app_api_key_create','api'),
      ('app_webhook_add','api'),
      ('app_webhook_delete','api'),
      ('app_platform_tenant_create','platform'),
      ('app_platform_tenant_update','platform'),
      ('app_tenant_user_create','admin'),
      ('app_tenant_user_update','admin'),
      ('app_tenant_user_reset','admin'),
      ('app_role_perm_set','roles'),
      ('app_calc_save','calc'),
      ('app_calc_delete','calc'),
      ('app_attachment_add','files'),
      ('app_attachment_delete','files'),
      ('app_analog_delete','norms'),
      ('app_norms_k_delete','norms'),
      ('app_config_option_delete','config'),
      ('app_department_delete','departments'),
      ('app_dict_delete','dicts'),
      ('app_dict_item_delete','dicts'),
      ('app_entity_field_delete','builder'),
      ('app_entity_record_delete','builder'),
      ('app_equipment_delete','equipment'),
      ('app_label_delete','labels'),
      ('app_package_delete','labels'),
      ('app_lean_delete','lean'),
      ('app_partner_set_status','partners'),
      ('app_partner_deal_set_status','partners'),
      ('app_engraving_set_status','engraving'),
      ('app_setup_delete','setup'),
      ('app_slot_delete','slots'),
      ('app_teo_set_status','teo'),
      ('app_teo_line_delete','teo')
    ) as t(fname, mod)
  loop
    for r in
      select pg_get_functiondef(p.oid) as d
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname = v.fname
         and p.prolang = (select oid from pg_language where lanname='plpgsql')
    loop
      def := r.d;
      if position('app_guard(' in def) = 0 and position('app_can(' in def) = 0 then
        def := regexp_replace(
          def,
          '(?i)' || chr(10) || 'begin',
          chr(10) || 'begin' || chr(10) || '  perform public.app_guard(p_token, ''' || v.mod || ''', ''edit'');'
        );
        execute def;
        n_fixed := n_fixed + 1;
      end if;
    end loop;
  end loop;
  raise notice 'app_guard внедрён ещё в % функций', n_fixed;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав — полный охват RPC (P8 шаг 2)',
   'Серверная проверка app_guard охватывает практически все мутирующие RPC сервиса: заявки, КТПП, производство, качество, экономику, финансы, персонал, документы, платформу и прикладные модули. Права — из матрицы app_role_permissions. Платформенные операции (admin/platform/roles/api) доступны только администратору/владельцу.',
   'права app_guard полный охват RPC матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав — полный охват RPC (P8 шаг 2)');
-- <<<<<<<<<< 0091_guard_rest.sql <<<<<<<<<<
-- >>>>>>>>>> 0092_iiot_dnc.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0092_iiot_dnc.sql  (v70 — Пункт 3: IIoT-телеметрия и DNC)
-- Приём телеметрии станков (метрики во времени) и очередь DNC-заданий
-- (передача УП на станок). Зависит от 0001..0091.
-- ============================================================

create table if not exists public.app_iiot_readings (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  machine    text not null,
  metric     text not null default 'state',   -- state|count|speed|temp|power|vibration|other
  value      numeric not null default 0,
  source     text,
  ts         timestamptz not null default now()
);
create index if not exists app_iiot_readings_idx on public.app_iiot_readings (tenant_id, machine, ts desc);
alter table public.app_iiot_readings enable row level security;

create table if not exists public.app_dnc_jobs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  machine       text not null,
  program_name  text not null,
  nc_id         uuid,
  status        text not null default 'queued', -- queued|sent|running|done|failed
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_dnc_jobs_idx on public.app_dnc_jobs (tenant_id, status, created_at desc);
alter table public.app_dnc_jobs enable row level security;

create or replace function public.app_iiot_ingest(p_token uuid, p_machine text, p_metric text, p_value numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'production', 'edit');
  if coalesce(trim(p_machine),'')='' then raise exception 'Укажите станок'; return; end if;
  return query
    insert into public.app_iiot_readings (tenant_id, machine, metric, value, source)
    values (public.app_my_tenant(p_token), trim(p_machine), coalesce(nullif(trim(p_metric),''),'state'), coalesce(p_value,0), 'api')
    returning app_iiot_readings.id, 'Показание принято';
end $$;

create or replace function public.app_iiot_readings_list(p_token uuid, p_machine text default null, p_limit int default 50)
returns table (id uuid, machine text, metric text, value numeric, source text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.machine, r.metric, r.value, r.source, r.ts
    from public.app_iiot_readings r
    where (urole='admin' or r.tenant_id=ten) and (coalesce(p_machine,'')='' or r.machine=p_machine)
    order by r.ts desc limit greatest(1, least(coalesce(p_limit,50),500));
end $$;

create or replace function public.app_iiot_kpi(p_token uuid)
returns table (readings_today bigint, machines bigint, last_ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_iiot_readings where (urole='admin' or tenant_id=ten) and ts >= date_trunc('day', now())),
    (select count(distinct machine) from public.app_iiot_readings where (urole='admin' or tenant_id=ten)),
    (select max(ts) from public.app_iiot_readings where (urole='admin' or tenant_id=ten));
end $$;

create or replace function public.app_dnc_list(p_token uuid, p_q text default null)
returns table (id uuid, machine text, program_name text, status text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select d.id, d.machine, d.program_name, d.status, d.note, d.created_at
    from public.app_dnc_jobs d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.program_name) like '%'||qq||'%' or lower(d.machine) like '%'||qq||'%')
    order by (d.status='done'), d.created_at desc;
end $$;

create or replace function public.app_dnc_save(p_token uuid, p_id uuid, p_machine text, p_program_name text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'production', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_machine),'')='' or coalesce(trim(p_program_name),'')='' then raise exception 'Укажите станок и программу'; return; end if;
  if p_id is null then
    insert into public.app_dnc_jobs (tenant_id, machine, program_name, note, created_login)
    values (ten, trim(p_machine), trim(p_program_name), nullif(trim(p_note),''), ulogin) returning id into did;
    return query select did, 'Задание в очереди';
  else
    update public.app_dnc_jobs set machine=trim(p_machine), program_name=trim(p_program_name), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Задание обновлено';
  end if;
end $$;

create or replace function public.app_dnc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'production','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('queued','sent','running','done','failed') then return query select false,'Неверный статус'; return; end if;
  update public.app_dnc_jobs set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_iiot_ingest(uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_iiot_readings_list(uuid,text,int) to anon, authenticated;
grant execute on function public.app_iiot_kpi(uuid) to anon, authenticated;
grant execute on function public.app_dnc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_dnc_save(uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_dnc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо ----------
insert into public.app_iiot_readings (tenant_id, machine, metric, value)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.m, v.met, v.val
from (values ('Feeler FTC-350Xl','state',1),('Feeler FTC-350Xl','speed',4200),('ЭЭО проволочная','power',3.2)) as v(m,met,val)
where not exists (select 1 from public.app_iiot_readings where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
insert into public.app_dnc_jobs (tenant_id, machine, program_name, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001','Feeler FTC-350Xl','O1234_MILL.NC','queued','master'
where not exists (select 1 from public.app_dnc_jobs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','IIoT-телеметрия и DNC (B13/B18)',
   'Модуль «IIoT и DNC»: приём телеметрии станков (метрики: состояние, счётчик, обороты, мощность, температура, вибрация) во времени и очередь DNC-заданий (передача УП на станок) со статусами queued→sent→running→done/failed. Основа онлайн-мониторинга и безбумажной передачи программ.',
   'IIoT телеметрия станки DNC NC мониторинг онлайн B13 B18')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='IIoT-телеметрия и DNC (B13/B18)');

-- <<<<<<<<<< 0092_iiot_dnc.sql <<<<<<<<<<
-- >>>>>>>>>> 0093_usage_counters.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0093_usage_counters.sql  (v71 — Пункт 3: P1 счётчики использования)
-- Счётчики использования по организации (метрика → значение) для тарифов/аналитики.
-- Зависит от 0001..0092.
-- ============================================================

create table if not exists public.app_usage_counters (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  metric     text not null,
  value      numeric not null default 0,
  updated_at timestamptz not null default now()
);
create unique index if not exists app_usage_counters_uq on public.app_usage_counters (tenant_id, metric);
create index if not exists app_usage_counters_idx on public.app_usage_counters (tenant_id);
alter table public.app_usage_counters enable row level security;

create or replace function public.app_counter_bump(p_token uuid, p_metric text, p_delta numeric default 1)
returns table (metric text, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; m text; v numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'platform', 'edit');
  ten := public.app_my_tenant(p_token);
  m := lower(trim(coalesce(p_metric,'')));
  if m = '' then raise exception 'Укажите метрику'; return; end if;
  insert into public.app_usage_counters (tenant_id, metric, value)
  values (ten, m, coalesce(p_delta,1))
  on conflict (tenant_id, metric)
  do update set value = public.app_usage_counters.value + coalesce(p_delta,1), updated_at = now()
  returning public.app_usage_counters.metric, public.app_usage_counters.value into metric, value;
  return next;
end $$;

create or replace function public.app_counters_list(p_token uuid)
returns table (metric text, value numeric, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.metric, c.value, c.updated_at
    from public.app_usage_counters c
    where (urole='admin' or c.tenant_id=ten) order by c.metric;
end $$;

create or replace function public.app_counters_kpi(p_token uuid)
returns table (metrics bigint, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(value),0) from public.app_usage_counters where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_counter_bump(uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_counters_list(uuid) to anon, authenticated;
grant execute on function public.app_counters_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Счётчики использования (P1)',
   'Модуль «Счётчики использования»: учёт метрик (заявки, наряды, созданные документы, файлы, вход пользователей и др.) по организации — для тарифов P1 Cloud и аналитики. Инкремент: app_counter_bump(metric, delta); просмотр: app_counters_list.',
   'счётчики использование метрики тарифы аналитика P1')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Счётчики использования (P1)');

-- <<<<<<<<<< 0093_usage_counters.sql <<<<<<<<<<
-- >>>>>>>>>> 0094_links_dicts.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0094_links_dicts.sql  (v72 — Пункт 4: словари для модулей)
-- Единые справочники для выпадающих списков: виды статей ТЭО, процессы
-- маркетплейса, категории операций нормирования. Идемпотентно. 0001..0093.
-- ============================================================

do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='teo_line_kind') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'teo_line_kind','Виды статей ТЭО',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'metal','Металл',10),(did,'consumables','Расходники',20),(did,'labor','Работы',30),(did,'service','Услуги',40),(did,'other','Прочее',50);
  end if;
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='marketplace_process') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'marketplace_process','Процессы (маркетплейс)',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'cnc','ЧПУ',10),(did,'edm','ЭЭО',20),(did,'grinding','Шлифование',30),(did,'heat','Термообработка',40),
      (did,'assembly','Сборка',50),(did,'engraving','Гравирование',60),(did,'other','Прочее',70);
  end if;
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='norms_category') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'norms_category','Категории операций',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'milling','Фрезерная',10),(did,'turning','Токарная',20),(did,'edm','ЭЭО',30),(did,'grinding','Шлифование',40),
      (did,'locksmith','Слесарная',50),(did,'engraving','Гравирование',60),(did,'heat','Термообработка',70),(did,'other','Прочее',80);
  end if;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Связки: словари для модулей',
   'Типы статей ТЭО, процессы маркетплейса и категории операций нормирования берутся из настраиваемых справочников (dicts) через app_dict_items_by_code — единый источник значений и подписей.',
   'связки словари ТЭО маркетплейс нормирование app_dict_items_by_code')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Связки: словари для модулей');

-- <<<<<<<<<< 0094_links_dicts.sql <<<<<<<<<<
-- >>>>>>>>>> 0095_smoke_ext.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0095_smoke_ext.sql  (v73 — Пункт 5: расширенные автотесты)
-- app_smoke_test_ext: проверка доступности новых контуров (IIoT/DNC, счётчики,
-- справочники, нормирование, слоты, наладка, lean, партнёры, оборудование,
-- кадры, конфигуратор, реверс) и покрытия прав. Зависит от 0001..0094.
-- ============================================================

create or replace function public.app_smoke_test_ext(p_token uuid)
returns table (name text, ok boolean, detail text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  begin
    execute 'select count(*) from public.app_iiot_readings where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'IIoT-телеметрия (0092)'; ok := true; detail := cnt||' показаний'; return next;
  exception when others then name := 'IIoT-телеметрия (0092)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_dnc_jobs where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'DNC-очередь (0092)'; ok := true; detail := cnt||' заданий'; return next;
  exception when others then name := 'DNC-очередь (0092)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_usage_counters where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Счётчики использования (0093)'; ok := true; detail := cnt||' метрик'; return next;
  exception when others then name := 'Счётчики использования (0093)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_dictionaries where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Справочники (0080)'; ok := cnt>0; detail := cnt||' справочников'; return next;
  exception when others then name := 'Справочники (0080)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_norms_operations where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Нормирование (0073)'; ok := cnt>0; detail := cnt||' операций'; return next;
  exception when others then name := 'Нормирование (0073)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_work_slots where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Слоты (0074)'; ok := true; detail := cnt||' слотов'; return next;
  exception when others then name := 'Слоты (0074)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_setups where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Наладка (0077)'; ok := true; detail := cnt||' наладок'; return next;
  exception when others then name := 'Наладка (0077)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_lean_actions where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Lean (0078)'; ok := true; detail := cnt||' предложений'; return next;
  exception when others then name := 'Lean (0078)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_partners where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Партнёры (0082)'; ok := true; detail := cnt||' партнёров'; return next;
  exception when others then name := 'Партнёры (0082)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_equipment_catalog where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Каталог оборудования (0083)'; ok := true; detail := cnt||' позиций'; return next;
  exception when others then name := 'Каталог оборудования (0083)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_staff_crm where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'CRM сотрудников (0084)'; ok := true; detail := cnt||' карточек'; return next;
  exception when others then name := 'CRM сотрудников (0084)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_config_options where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Конфигуратор (0085)'; ok := cnt>0; detail := cnt||' опций'; return next;
  exception when others then name := 'Конфигуратор (0085)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_reverse_orders where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Реверс-инжиниринг (0086)'; ok := true; detail := cnt||' заявок'; return next;
  exception when others then name := 'Реверс-инжиниринг (0086)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname=''public'' and pg_get_functiondef(p.oid) like ''%app_guard(%''' into cnt;
    name := 'Покрытие прав app_guard'; ok := cnt >= 100; detail := cnt||' функций под guard'; return next;
  exception when others then name := 'Покрытие прав app_guard'; ok := false; detail := sqlerrm; return next; end;
end $$;

grant execute on function public.app_smoke_test_ext(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Эксплуатация','Расширенные автотесты',
   'Функция app_smoke_test_ext проверяет доступность и наполнение новых контуров (IIoT/DNC, счётчики, справочники, нормирование, слоты, наладка, lean, партнёры, оборудование, кадры, конфигуратор, реверс) и покрытие прав app_guard. Запускать на странице «Масштаб и эксплуатация».',
   'автотесты смоук app_smoke_test_ext QA проверка контуров')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Расширенные автотесты');

-- <<<<<<<<<< 0095_smoke_ext.sql <<<<<<<<<<
-- >>>>>>>>>> 0096_core_schema.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0096_core_schema.sql  (v74 — Партия A: ядро платформы)
-- Движок схем (тип → поля), единый источник значений (ref_options), связи
-- между сущностями (links), включение модулей по предприятию (tenant_modules).
-- Зависит от 0001..0095.
-- ============================================================

create table if not exists public.app_schemas (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text not null,
  name        text not null,
  icon        text default '🧩',
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists app_schemas_uq on public.app_schemas (tenant_id, code);
alter table public.app_schemas enable row level security;

create table if not exists public.app_schema_fields (
  id            uuid primary key default gen_random_uuid(),
  schema_id     uuid references public.app_schemas (id) on delete cascade,
  code          text not null,
  label         text not null,
  field_type    text not null default 'text',  -- text|number|date|select|textarea|bool|ref|table
  options       text,
  ref_source    text,                          -- dict:code | orders | clients | partners | equipment | operations
  required      boolean not null default false,
  sort          int default 100,
  default_value text
);
create index if not exists app_schema_fields_idx on public.app_schema_fields (schema_id, sort);
alter table public.app_schema_fields enable row level security;

create table if not exists public.app_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  source_type text not null,
  source_id   uuid not null,
  target_type text not null,
  target_id   uuid not null,
  kind        text,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_links_src_idx on public.app_links (tenant_id, source_type, source_id);
create index if not exists app_links_tgt_idx on public.app_links (tenant_id, target_type, target_id);
alter table public.app_links enable row level security;

create table if not exists public.app_tenant_modules (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  module     text not null,
  enabled    boolean not null default true,
  enabled_at timestamptz not null default now()
);
create unique index if not exists app_tenant_modules_uq on public.app_tenant_modules (tenant_id, module);
alter table public.app_tenant_modules enable row level security;

-- ---------- Схемы ----------
create or replace function public.app_schemas_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, icon text, description text, active boolean, fields bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.code, s.name, s.icon, s.description, s.active,
      (select count(*) from public.app_schema_fields f where f.schema_id=s.id)
    from public.app_schemas s
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(s.code) like '%'||qq||'%')
    order by s.name;
end $$;

create or replace function public.app_schema_save(p_token uuid, p_id uuid, p_code text, p_name text, p_icon text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите код и название'; return; end if;
  if p_id is null then
    insert into public.app_schemas (tenant_id, code, name, icon, description, active)
    values (ten, lower(trim(p_code)), trim(p_name), coalesce(nullif(trim(p_icon),''),'🧩'), nullif(trim(p_description),''), coalesce(p_active,true)) returning id into sid;
    return query select sid, 'Схема создана';
  else
    update public.app_schemas set code=lower(trim(p_code)), name=trim(p_name), icon=coalesce(nullif(trim(p_icon),''),icon),
      description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Схема обновлена';
  end if;
end $$;

create or replace function public.app_schema_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_schemas where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Схема удалена';
end $$;

create or replace function public.app_schema_fields_list(p_token uuid, p_schema_id uuid)
returns table (id uuid, code text, label text, field_type text, options text, ref_source text, required boolean, sort int, default_value text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_schemas s where s.id=p_schema_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Схема не найдена'; end if;
  return query select f.id, f.code, f.label, f.field_type, f.options, f.ref_source, f.required, f.sort, f.default_value
    from public.app_schema_fields f where f.schema_id=p_schema_id order by f.sort, f.label;
end $$;

create or replace function public.app_schema_field_save(p_token uuid, p_id uuid, p_schema_id uuid, p_code text, p_label text,
  p_field_type text, p_options text, p_ref_source text, p_required boolean, p_sort int, p_default text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_schemas s where s.id=p_schema_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Схема не найдена'; return; end if;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_label),'')='' then raise exception 'Укажите код и подпись поля'; return; end if;
  if p_field_type not in ('text','number','date','select','textarea','bool','ref','table') then raise exception 'Неверный тип поля'; return; end if;
  if p_id is null then
    insert into public.app_schema_fields (schema_id, code, label, field_type, options, ref_source, required, sort, default_value)
    values (p_schema_id, trim(p_code), trim(p_label), p_field_type, nullif(trim(p_options),''), nullif(trim(p_ref_source),''), coalesce(p_required,false), coalesce(p_sort,100), nullif(trim(p_default),''))
    returning id into fid;
    return query select fid, 'Поле добавлено';
  else
    update public.app_schema_fields set code=trim(p_code), label=trim(p_label), field_type=p_field_type, options=nullif(trim(p_options),''),
      ref_source=nullif(trim(p_ref_source),''), required=coalesce(p_required,false), sort=coalesce(p_sort,100), default_value=nullif(trim(p_default),'')
     where id=p_id and schema_id=p_schema_id returning id into fid;
    return query select fid, 'Поле обновлено';
  end if;
end $$;

create or replace function public.app_schema_field_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_schema_fields f using public.app_schemas s
    where f.id=p_id and s.id=f.schema_id and (urole='admin' or s.tenant_id=ten);
  return query select true,'Поле удалено';
end $$;

-- ---------- Единый источник значений ----------
create or replace function public.app_ref_options(p_token uuid, p_kind text, p_code text default null)
returns table (value text, label text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; k text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); k := lower(coalesce(trim(p_kind),''));
  if k='dict' then
    return query select i.value, i.label from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id
      where (urole='admin' or d.tenant_id=ten) and lower(d.code)=lower(coalesce(p_code,'')) and d.active and i.active order by i.sort;
  elsif k='orders' then
    return query select o.id::text, o.number||' · '||coalesce(o.title,'') from public.app_orders o where (urole='admin' or o.tenant_id=ten) order by o.created_at desc limit 500;
  elsif k='clients' then
    return query select c.id::text, coalesce(c.name,'') from public.app_customers c where (urole='admin' or c.tenant_id=ten) order by c.name limit 500;
  elsif k='partners' then
    return query select p.id::text, p.name from public.app_partners p where (urole='admin' or p.tenant_id=ten) order by p.name limit 500;
  elsif k='equipment' then
    return query select e.id::text, e.name from public.app_equipment_catalog e where (urole='admin' or e.tenant_id=ten) order by e.name limit 500;
  elsif k='operations' then
    return query select o.id::text, o.code||' · '||o.name from public.app_norms_operations o where (urole='admin' or o.tenant_id=ten) order by o.name limit 500;
  else
    return;
  end if;
end $$;

-- ---------- Связи ----------
create or replace function public.app_links_list(p_token uuid, p_type text, p_id uuid)
returns table (id uuid, direction text, source_type text, source_id uuid, target_type text, target_id uuid, kind text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, 'out'::text, l.source_type, l.source_id, l.target_type, l.target_id, l.kind, l.note, l.created_at
      from public.app_links l where (urole='admin' or l.tenant_id=ten) and l.source_type=p_type and l.source_id=p_id
    union all
    select l.id, 'in'::text, l.source_type, l.source_id, l.target_type, l.target_id, l.kind, l.note, l.created_at
      from public.app_links l where (urole='admin' or l.tenant_id=ten) and l.target_type=p_type and l.target_id=p_id
    order by created_at desc;
end $$;

create or replace function public.app_link_add(p_token uuid, p_source_type text, p_source_id uuid, p_target_type text, p_target_id uuid, p_kind text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_source_type),'')='' or coalesce(trim(p_target_type),'')='' then raise exception 'Укажите типы связи'; return; end if;
  insert into public.app_links (tenant_id, source_type, source_id, target_type, target_id, kind, note)
  values (ten, trim(p_source_type), p_source_id, trim(p_target_type), p_target_id, nullif(trim(p_kind),''), nullif(trim(p_note),''))
  returning id into lid;
  return query select lid, 'Связь добавлена';
end $$;

create or replace function public.app_link_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_links where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Связь удалена';
end $$;

-- ---------- Модули предприятия ----------
create or replace function public.app_tenant_modules_list(p_token uuid)
returns table (module text, enabled boolean, enabled_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.module, m.enabled, m.enabled_at from public.app_tenant_modules m
    where (urole='admin' or m.tenant_id=ten) order by m.module;
end $$;

create or replace function public.app_tenant_module_set(p_token uuid, p_module text, p_enabled boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_module),'')='' then return query select false,'Укажите модуль'; return; end if;
  insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
  values (ten, lower(trim(p_module)), coalesce(p_enabled,true), now())
  on conflict (tenant_id, module) do update set enabled=coalesce(p_enabled,true), enabled_at=now();
  return query select true,'Модуль обновлён';
end $$;

grant execute on function public.app_schemas_list(uuid,text) to anon, authenticated;
grant execute on function public.app_schema_save(uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_schema_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_schema_fields_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_schema_field_save(uuid,uuid,uuid,text,text,text,text,text,boolean,int,text) to anon, authenticated;
grant execute on function public.app_schema_field_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ref_options(uuid,text,text) to anon, authenticated;
grant execute on function public.app_links_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_link_add(uuid,text,uuid,text,uuid,text,text) to anon, authenticated;
grant execute on function public.app_link_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tenant_modules_list(uuid) to anon, authenticated;
grant execute on function public.app_tenant_module_set(uuid,text,boolean) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='contract') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'contract','Договор','📜','Договор подряда/поставки') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, required, sort) values
      (sid,'customer','Заказчик',       'ref',   true, 10),
      (sid,'contractor','Исполнитель',   'text',  true, 20),
      (sid,'subject','Предмет',          'text',  true, 30),
      (sid,'amount','Сумма',             'number',true, 40),
      (sid,'vat','НДС, %',               'number',false,50),
      (sid,'date_start','Начало',        'date',  false,60),
      (sid,'date_end','Окончание',       'date',  false,70),
      (sid,'payment','Порядок оплаты',   'textarea',false,80);
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'techcard','Техкарта','🗒','Технологическая карта') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'product','Изделие',          'text',  null,         true, 10),
      (sid,'material','Материал',        'ref',   'dict:material_kind', false,20),
      (sid,'operation','Операция',       'ref',   'operations', false,30),
      (sid,'machine','Оборудование',     'ref',   'equipment',  false,40),
      (sid,'norm_hours','Норма, н·ч',    'number',null,         false,50),
      (sid,'control','Контроль',         'textarea',null,       false,60);
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'kp','Коммерческое предложение','🧾','КП с позициями') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, required, sort) values
      (sid,'customer','Заказчик',    'ref',    true, 10),
      (sid,'valid_until','Действует до','date', false,20),
      (sid,'discount','Скидка, %',   'number', false,30),
      (sid,'items','Позиции',        'table',  false,40);
  end if;
  if not exists (select 1 from public.app_tenant_modules where tenant_id=A) then
    insert into public.app_tenant_modules (tenant_id, module, enabled)
    select A, m, true from (values
      ('auth'),('panel'),('dashboard'),('guide'),('orders'),('crm'),('tkp'),('docs'),('templates'),
      ('registry'),('bom'),('calc'),('norms'),('production'),('mes'),('terminal'),('qc'),('warehouse'),
      ('economics'),('hr'),('roles'),('dicts'),('files'),('builder'),('org'),('platform'),('admin')
    ) as t(m);
  end if;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Ядро платформы: схемы, источники, связи, модули предприятия',
   'Партия A: движок схем app_schemas/app_schema_fields (типы и поля — конструктор), единый источник значений app_ref_options (dict/orders/clients/partners/equipment/operations), связи app_links, включение модулей по предприятию app_tenant_modules. Используется во всех модулях для динамических форм, справочников, табличных частей и связей.',
   'ядро платформа схемы поля ref_options связи app_links tenant_modules конструктор')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Ядро платформы: схемы, источники, связи, модули предприятия');

-- <<<<<<<<<< 0096_core_schema.sql <<<<<<<<<<
-- >>>>>>>>>> 0097_adoption.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0097_adoption.sql  (v75 — Партия I: карта внедрения)
-- app_adoption_map: по каждому модулю — включён ли (app_tenant_modules) и есть ли
-- фактические данные (используется). app_adoption_kpi. Зависит от 0001..0096.
-- ============================================================

create or replace function public.app_adoption_map(p_token uuid)
returns table (module text, enabled boolean, records bigint, used boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; m record; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  for m in
    select * from (values
      ('orders','app_orders'),('crm','app_customers'),('docs','app_documents'),('templates','app_doc_templates'),
      ('dicts','app_dictionaries'),('norms','app_norms_operations'),('calc','app_calc_saves'),
      ('slots','app_work_slots'),('setup','app_setups'),('lean','app_lean_actions'),
      ('partners','app_partners'),('equipment','app_equipment_catalog'),('staff','app_staff_crm'),
      ('config','app_config_options'),('reverse','app_reverse_orders'),('escrow','app_escrow_deals'),
      ('marketplace','app_market_listings'),('suppliers','app_suppliers'),('teo','app_teo'),
      ('labels','app_labels'),('engraving','app_engraving'),('files','app_files'),('iiot','app_iiot_readings')
    ) as t(mod, tbl)
  loop
    cnt := 0;
    if to_regclass('public.'||m.tbl) is not null then
      begin
        execute 'select count(*) from public.'||m.tbl||' where ($1 is null or tenant_id=$1)' into cnt using ten;
      exception when undefined_column then
        begin execute 'select count(*) from public.'||m.tbl into cnt; exception when others then cnt := 0; end;
      end;
    end if;
    return query select m.mod,
      coalesce((select tm.enabled from public.app_tenant_modules tm where tm.tenant_id=ten and tm.module=m.mod), false),
      cnt, cnt > 0;
  end loop;
end $$;

create or replace function public.app_adoption_kpi(p_token uuid)
returns table (modules_known bigint, enabled bigint, used bigint, progress_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; e bigint; u bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*) filter (where enabled), count(*) filter (where used) into e, u from public.app_adoption_map(p_token);
  return query select 23::bigint, coalesce(e,0), coalesce(u,0), round(case when 23>0 then coalesce(u,0)::numeric/23*100 else 0 end, 0);
end $$;

grant execute on function public.app_adoption_map(uuid) to anon, authenticated;
grant execute on function public.app_adoption_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Карта внедрения (I)',
   'Экран «Карта внедрения»: по каждому модулю видно, включён ли он для предприятия (app_tenant_modules) и используется ли по факту (есть записи). Прогресс внедрения, рекомендованный следующий шаг по волнам. Помогает предприятию видеть, что уже работает, для чего и что включать дальше.',
   'внедрение карта adoption волны профиль предприятия онбординг прогресс')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Карта внедрения (I)');

-- <<<<<<<<<< 0097_adoption.sql <<<<<<<<<<
-- >>>>>>>>>> 0098_remarks.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0098_remarks.sql  (v77 — модуль «Замечания к странице»)
-- Таблица app_page_remarks + RPC. Tenant-изоляция. Зависит от 0001..0097.
-- ============================================================

create table if not exists public.app_page_remarks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  module        text,
  url           text,
  x             numeric not null default 0,
  y             numeric not null default 0,
  role          text not null default 'employee',
  role_name     text,
  author        text,
  type          text,
  text          text,
  resolved      boolean not null default false,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_page_remarks_idx on public.app_page_remarks (tenant_id, module, created_at desc);
alter table public.app_page_remarks enable row level security;

create or replace function public.app_remark_list(p_token uuid, p_module text default null, p_url text default null)
returns table (id uuid, module text, url text, x numeric, y numeric, role text, role_name text, author text, type text, text text, resolved boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.module, r.url, r.x, r.y, r.role, r.role_name, r.author, r.type, r.text, r.resolved, r.created_at
    from public.app_page_remarks r
    where (urole='admin' or r.tenant_id=ten)
      and (coalesce(p_module,'')='' or r.module=p_module)
      and (coalesce(p_url,'')='' or r.url=p_url)
    order by r.created_at desc;
end $$;

create or replace function public.app_remark_create(p_token uuid, p_module text, p_url text, p_x numeric, p_y numeric,
  p_role text, p_role_name text, p_author text, p_type text, p_text text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_page_remarks (tenant_id, module, url, x, y, role, role_name, author, type, text, created_login)
  values (ten, nullif(trim(p_module),''), nullif(trim(p_url),''), coalesce(p_x,0), coalesce(p_y,0),
          coalesce(nullif(trim(p_role),''),'employee'), nullif(trim(p_role_name),''), nullif(trim(p_author),''),
          nullif(trim(p_type),''), nullif(trim(p_text),''), ulogin)
  returning id into rid;
  return query select rid, 'Замечание сохранено';
end $$;

create or replace function public.app_remark_resolve(p_token uuid, p_id uuid, p_resolved boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_page_remarks set resolved=coalesce(p_resolved,false), updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_remark_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_page_remarks where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Замечание удалено';
end $$;

create or replace function public.app_remark_delete_all(p_token uuid, p_module text default null, p_url text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_page_remarks r
   where (urole='admin' or r.tenant_id=ten)
     and (coalesce(p_module,'')='' or r.module=p_module)
     and (coalesce(p_url,'')='' or r.url=p_url);
  return query select true,'Замечания удалены';
end $$;

grant execute on function public.app_remark_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_remark_create(uuid,text,text,numeric,numeric,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_remark_resolve(uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.app_remark_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_remark_delete_all(uuid,text,text) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Замечания к странице (модуль)',
   'Модуль «Замечания к странице»: визуальные замечания поверх снимка страницы (метки в %), роли сотрудник/клиент, типы, статусы; экспорт PDF (снимок+метки+таблица). Данные — app_page_remarks через RPC; без backend используется демо-режим (localStorage) и mock-снимок.',
   'замечания страница remarks метки PDF bug-mode снимок')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Замечания к странице (модуль)');

-- <<<<<<<<<< 0098_remarks.sql <<<<<<<<<<
-- >>>>>>>>>> 0099_bug_mode.sql >>>>>>>>>>
-- ============================================================
-- 3DMP Service · 0099_bug_mode.sql  (v78 — Bug Mode: баги поверх замечаний)
-- Расширяем app_page_remarks (kind/payload/status) и добавляем RPC для багов.
-- Диагностический конверт Report хранится в payload jsonb. Зависит 0001..0098.
-- ============================================================

alter table public.app_page_remarks add column if not exists kind text not null default 'remark'; -- remark|bug
alter table public.app_page_remarks add column if not exists payload jsonb;
alter table public.app_page_remarks add column if not exists status text not null default 'new';  -- new|in_work|fixed|rejected (для багов)

create or replace function public.app_bug_create(p_token uuid, p_module text, p_url text, p_x numeric, p_y numeric,
  p_role_name text, p_author text, p_type text, p_text text, p_payload jsonb)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_page_remarks (tenant_id, module, url, x, y, role, role_name, author, type, text, kind, payload, status, created_login)
  values (ten, nullif(trim(p_module),''), nullif(trim(p_url),''), coalesce(p_x,0), coalesce(p_y,0), 'employee',
          nullif(trim(p_role_name),''), nullif(trim(p_author),''), coalesce(nullif(trim(p_type),''),'Ошибка'), nullif(trim(p_text),''),
          'bug', coalesce(p_payload,'{}'::jsonb), 'new', ulogin)
  returning id into rid;
  if ten is not null then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager'], 'Новый баг: '||coalesce(nullif(trim(p_text),''),'без описания'), coalesce(p_url,''), 'apps/bugbox/index.html');
  end if;
  return query select rid, 'Баг передан разработчику';
end $$;

create or replace function public.app_bug_list(p_token uuid, p_status text default null, p_module text default null)
returns table (id uuid, module text, url text, x numeric, y numeric, author text, type text, text text, status text, payload jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.module, r.url, r.x, r.y, r.author, r.type, r.text, r.status, r.payload, r.created_at
    from public.app_page_remarks r
    where (urole='admin' or r.tenant_id=ten) and r.kind='bug'
      and (coalesce(p_status,'')='' or r.status=p_status)
      and (coalesce(p_module,'')='' or r.module=p_module)
    order by r.created_at desc;
end $$;

create or replace function public.app_bug_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_work','fixed','rejected') then return query select false,'Неверный статус'; return; end if;
  update public.app_page_remarks set status=p_status, updated_at=now() where id=p_id and kind='bug' and (urole='admin' or tenant_id=ten);
  return query select true,'Статус баг-репорта обновлён';
end $$;

create or replace function public.app_bug_kpi(p_token uuid)
returns table (total bigint, new_cnt bigint, in_work bigint, fixed bigint, rejected bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='new'), count(*) filter (where status='in_work'),
    count(*) filter (where status='fixed'), count(*) filter (where status='rejected')
    from public.app_page_remarks where kind='bug' and (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_bug_create(uuid,text,text,numeric,numeric,text,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_bug_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_bug_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_bug_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Bug Mode и баг-репорты',
   'Режим бага: клик по элементу собирает CSS-селектор, console-ошибки и breadcrumbs, формирует диагностический конверт Report и передаёт разработчику (PDF + JSON + deep-link + уведомление). Баги хранятся в app_page_remarks (kind=bug, payload, статусы new/in_work/fixed/rejected), дашборд — apps/bugbox.',
   'bug mode баг репорт report конверт селектор console breadcrumbs bugbox')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Bug Mode и баг-репорты');

-- <<<<<<<<<< 0099_bug_mode.sql <<<<<<<<<<
