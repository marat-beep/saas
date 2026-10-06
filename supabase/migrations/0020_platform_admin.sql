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
