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
