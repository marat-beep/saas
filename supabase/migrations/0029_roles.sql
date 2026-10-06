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
