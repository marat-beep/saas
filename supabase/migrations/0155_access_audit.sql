-- ============================================================
-- 3DMP Service · 0155_access_audit.sql  (W10 — Enterprise-права и аудит)
-- Наборы прав, делегирование, маршруты согласований, расширенный аудит по подразделениям.
-- Идемпотентно. Зависит от 0001..0154.
-- ============================================================

-- ---------- Наборы прав ----------
create table if not exists public.app_permission_sets (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  description   text,
  perms         jsonb not null default '{}'::jsonb,  -- {"модуль":{"view":true,"edit":false}}
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_permission_sets_idx on public.app_permission_sets (tenant_id);
alter table public.app_permission_sets enable row level security;

create table if not exists public.app_permission_assignments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  set_id      uuid not null references public.app_permission_sets (id) on delete cascade,
  target_type text not null default 'role',   -- role|user|department
  target_ref  text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_permission_assign_idx on public.app_permission_assignments (set_id, target_type, target_ref);
alter table public.app_permission_assignments enable row level security;

-- ---------- Делегирование ----------
create table if not exists public.app_delegations (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  from_user     uuid references public.app_users (id) on delete cascade,
  to_user       uuid references public.app_users (id) on delete cascade,
  module        text,
  action        text,                     -- null|view|edit
  from_date     date default current_date,
  to_date       date,
  active        boolean not null default true,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_delegations_to_idx on public.app_delegations (to_user, active);
alter table public.app_delegations enable row level security;

-- ---------- Маршруты согласований ----------
create table if not exists public.app_approval_routes (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  name        text not null,
  doc_type    text,                        -- order|document|invoice|tender|other
  steps       jsonb not null default '[]'::jsonb,  -- [{"ord":1,"role":"chief","name":"Нач. цеха"}]
  active      boolean not null default true,
  created_by  uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at  timestamptz not null default now()
);
alter table public.app_approval_routes enable row level security;

create table if not exists public.app_approval_requests (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  route_id      uuid references public.app_approval_routes (id) on delete set null,
  entity_type   text,
  entity_id     uuid,
  entity_title  text,
  status        text not null default 'pending',  -- pending|approved|rejected|cancelled
  current_step  integer not null default 1,
  total_steps   integer not null default 1,
  requested_by  uuid references public.app_users (id) on delete set null,
  requested_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_approval_requests_idx on public.app_approval_requests (tenant_id, status);
alter table public.app_approval_requests enable row level security;

create table if not exists public.app_approval_actions (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.app_approval_requests (id) on delete cascade,
  step_ord    integer,
  actor       uuid references public.app_users (id) on delete set null,
  actor_login text,
  action      text not null,               -- approve|reject
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists app_approval_actions_idx on public.app_approval_actions (request_id, created_at);
alter table public.app_approval_actions enable row level security;

-- ---------- Расширенный аудит ----------
create table if not exists public.app_audit_policies (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  scope_type  text not null default 'all',   -- all|module|department
  scope_ref   text,
  module      text,
  action      text,
  min_role    text,
  enabled     boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table public.app_audit_policies enable row level security;

create table if not exists public.app_audit_ext (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  actor         uuid references public.app_users (id) on delete set null,
  actor_login   text,
  actor_role    text,
  module        text,
  action        text,
  entity_type   text,
  entity_id     uuid,
  department_id uuid,
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists app_audit_ext_idx on public.app_audit_ext (tenant_id, created_at desc);
alter table public.app_audit_ext enable row level security;

-- ---------- app_can v2: учёт наборов прав и делегирования ----------
create or replace function public.app_can(p_token uuid, p_module text, p_action text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; uid uuid; ulogin text; ten uuid; vw boolean; ed boolean; act text; hasrole boolean; dept text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if urole is null then return false; end if;
  if urole in ('admin','owner') then return true; end if;
  act := lower(coalesce(nullif(p_action,''),'view'));
  if act not in ('view','edit') then act := 'view'; end if;
  ten := public.app_my_tenant(p_token);
  select e.department_id::text into dept from public.app_employees e where e.user_login = ulogin and e.tenant_id = ten limit 1;

  -- 1) матрица ролей (базовый уровень)
  select p.can_view, p.can_edit into vw, ed
    from public.app_role_permissions p
    where p.role = urole and p.module_id = p_module and (p.tenant_id = ten or p.tenant_id is null)
    limit 1;
  hasrole := found;
  if act = 'edit' then
    if coalesce(ed,false) then return true; end if;
  else
    if (case when hasrole then coalesce(vw,false) else true end) then return true; end if;
  end if;

  -- 2) наборы прав (роль / пользователь / подразделение) — повышают права
  if exists (
    select 1
      from public.app_permission_assignments a
      join public.app_permission_sets s on s.id = a.set_id
     where coalesce(a.active,true) and (a.tenant_id = ten or a.tenant_id is null)
       and (
         (a.target_type = 'role' and a.target_ref = urole)
         or (a.target_type = 'user' and a.target_ref = uid::text)
         or (a.target_type = 'department' and a.target_ref = dept)
       )
       and coalesce(((s.perms -> p_module) ->> act)::boolean, false)
  ) then return true; end if;

  -- 3) делегирование (активное, на текущего пользователя)
  if exists (
    select 1 from public.app_delegations d
     where d.to_user = uid and coalesce(d.active,true)
       and current_date between coalesce(d.from_date, current_date) and coalesce(d.to_date, '9999-12-31'::date)
       and (d.module is null or d.module = p_module)
       and (d.action is null or d.action = '' or lower(d.action) = act
            or (lower(d.action) = 'edit' and act = 'view'))
  ) then return true; end if;

  -- нет явного разрешения
  if act = 'edit' then return false; end if;
  return case when hasrole then coalesce(vw,false) else true end;
end $$;

grant execute on function public.app_can(uuid,text,text) to anon, authenticated;

-- ---------- RPC: наборы прав ----------
create or replace function public.app_perm_sets_list(p_token uuid)
returns table (id uuid, name text, description text, perms jsonb, assign_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.name, s.description, s.perms,
           (select count(*) from public.app_permission_assignments a where a.set_id = s.id),
           s.created_at
      from public.app_permission_sets s where adm or s.tenant_id = ten order by s.created_at desc;
end $$;

create or replace function public.app_perm_set_save(p_token uuid, p_id uuid, p_name text, p_description text, p_perms jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название набора', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_permission_sets (tenant_id,name,description,perms,created_by,created_login)
    values (ten, left(trim(p_name),120), nullif(trim(p_description),''), coalesce(p_perms,'{}'::jsonb),
            (select s.uid from public.app_session_user(p_token) s), uname)
    returning app_permission_sets.id into newid;
    return query select true,'Набор создан', newid;
  else
    update public.app_permission_sets s set name = left(trim(p_name),120), description = nullif(trim(p_description),''),
           perms = coalesce(p_perms, s.perms), updated_at = now()
     where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten)
     returning s.id into newid;
    if newid is null then return query select false,'Набор не найден', null::uuid; return; end if;
    return query select true,'Набор сохранён', newid;
  end if;
end $$;

create or replace function public.app_perm_set_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_permission_sets s where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Набор не найден'; return; end if;
  return query select true,'Набор удалён';
end $$;

create or replace function public.app_perm_assign_list(p_token uuid, p_set_id uuid)
returns table (id uuid, set_id uuid, target_type text, target_ref text, target_name text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.set_id, a.target_type, a.target_ref,
           case a.target_type
             when 'user' then (select u.login from public.app_users u where u.id::text = a.target_ref limit 1)
             when 'department' then (select d.name from public.app_departments d where d.id::text = a.target_ref limit 1)
             else a.target_ref end,
           a.active
      from public.app_permission_assignments a
      join public.app_permission_sets s on s.id = a.set_id
     where a.set_id = p_set_id and (adm or s.tenant_id = ten)
     order by a.target_type, a.target_ref;
end $$;

create or replace function public.app_perm_assign_save(p_token uuid, p_set_id uuid, p_target_type text, p_target_ref text, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if not public.app_is_platform_admin(p_token) then
    if not exists (select 1 from public.app_permission_sets s where s.id = p_set_id and s.tenant_id = ten) then
      return query select false,'Набор не найден', null::uuid; return;
    end if;
  end if;
  if coalesce(trim(p_target_type),'') not in ('role','user','department') then
    return query select false,'Недопустимый тип назначения', null::uuid; return;
  end if;
  if coalesce(trim(p_target_ref),'') = '' then return query select false,'Укажите получателя', null::uuid; return; end if;
  if exists (select 1 from public.app_permission_assignments a where a.set_id=p_set_id and a.target_type=p_target_type and a.target_ref=p_target_ref) then
    update public.app_permission_assignments a set active = coalesce(p_active,true)
     where a.set_id=p_set_id and a.target_type=p_target_type and a.target_ref=p_target_ref
     returning a.id into newid;
    return query select true,'Назначение обновлено', newid;
  end if;
  insert into public.app_permission_assignments (tenant_id, set_id, target_type, target_ref, active)
  values (ten, p_set_id, p_target_type, p_target_ref, coalesce(p_active,true))
  returning app_permission_assignments.id into newid;
  return query select true,'Назначено', newid;
end $$;

create or replace function public.app_perm_assign_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_permission_assignments a
   using public.app_permission_sets s
   where a.id = p_id and a.set_id = s.id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Назначение не найдено'; return; end if;
  return query select true,'Назначение удалено';
end $$;

create or replace function public.app_effective_perms(p_token uuid)
returns table (module text, source text, can_view boolean, can_edit boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; uid uuid; ulogin text; ten uuid; dept text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select e.department_id::text into dept from public.app_employees e where e.user_login = ulogin and e.tenant_id = ten limit 1;

  return query select p.module_id, 'роль'::text, coalesce(p.can_view,false), coalesce(p.can_edit,false)
    from public.app_role_permissions p where p.role = urole and (p.tenant_id = ten or p.tenant_id is null);

  return query
    select k::text, 'набор'::text,
           bool_or(coalesce((s.perms -> k ->> 'view')::boolean,false)),
           bool_or(coalesce((s.perms -> k ->> 'edit')::boolean,false))
      from public.app_permission_assignments a
      join public.app_permission_sets s on s.id = a.set_id
      cross join lateral jsonb_object_keys(s.perms) as k
     where coalesce(a.active,true) and (a.tenant_id = ten or a.tenant_id is null)
       and ( (a.target_type='role' and a.target_ref=urole)
          or (a.target_type='user' and a.target_ref=uid::text)
          or (a.target_type='department' and a.target_ref=dept) )
     group by k;

  return query
    select coalesce(d.module,'(все модули)'), 'делегирование',
           true, (d.action is null or d.action='' or lower(d.action)='edit')
      from public.app_delegations d
     where d.to_user = uid and coalesce(d.active,true)
       and current_date between coalesce(d.from_date,current_date) and coalesce(d.to_date,'9999-12-31'::date);
end $$;

-- ---------- RPC: делегирование ----------
create or replace function public.app_delegations_list(p_token uuid)
returns table (id uuid, from_login text, to_login text, module text, action text, from_date date, to_date date, active boolean, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, fu.login, tu.login, d.module, d.action, d.from_date, d.to_date, d.active, d.note, d.created_at
      from public.app_delegations d
      left join public.app_users fu on fu.id = d.from_user
      left join public.app_users tu on tu.id = d.to_user
     where adm or d.tenant_id = ten
     order by d.created_at desc;
end $$;

create or replace function public.app_delegation_save(p_token uuid, p_id uuid, p_to_user uuid, p_module text, p_action text,
  p_from_date date, p_to_date date, p_active boolean, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; me uuid; newid uuid; act text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin, s.uid into ten, uname, me from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_to_user is null then return query select false,'Выберите, кому делегировать', null::uuid; return; end if;
  if p_to_user = me then return query select false,'Нельзя делегировать самому себе', null::uuid; return; end if;
  act := nullif(lower(trim(coalesce(p_action,''))), '');
  if act is not null and act not in ('view','edit') then return query select false,'Действие: view или edit', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_delegations (tenant_id, from_user, to_user, module, action, from_date, to_date, active, note, created_by, created_login)
    values (ten, me, p_to_user, nullif(trim(coalesce(p_module,'')),''), act, coalesce(p_from_date,current_date), p_to_date,
            coalesce(p_active,true), nullif(trim(p_note),''), me, uname)
    returning app_delegations.id into newid;
    return query select true,'Делегирование создано', newid;
  else
    update public.app_delegations d set to_user = p_to_user, module = nullif(trim(coalesce(p_module,'')),''),
           action = act, from_date = coalesce(p_from_date, d.from_date), to_date = p_to_date,
           active = coalesce(p_active, d.active), note = nullif(trim(p_note),'')
     where d.id = p_id and (d.from_user = me or public.app_is_platform_admin(p_token) or public.app_is_owner(p_token))
     returning d.id into newid;
    if newid is null then return query select false,'Делегирование не найдено', null::uuid; return; end if;
    return query select true,'Делегирование сохранено', newid;
  end if;
end $$;

create or replace function public.app_delegation_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare me uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid into me from public.app_session_user(p_token) s;
  delete from public.app_delegations d where d.id = p_id and (d.from_user = me or public.app_is_platform_admin(p_token) or public.app_is_owner(p_token));
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Делегирование не найдено'; return; end if;
  return query select true,'Делегирование удалено';
end $$;

-- ---------- RPC: маршруты согласований ----------
create or replace function public.app_approval_routes_list(p_token uuid)
returns table (id uuid, name text, doc_type text, steps jsonb, active boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.name, r.doc_type, r.steps, r.active, r.created_at
    from public.app_approval_routes r where adm or r.tenant_id = ten order by r.created_at desc;
end $$;

create or replace function public.app_approval_route_save(p_token uuid, p_id uuid, p_name text, p_doc_type text, p_steps jsonb, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название маршрута', null::uuid; return; end if;
  if p_steps is not null and jsonb_typeof(p_steps) <> 'array' then return query select false,'Шаги должны быть массивом', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_approval_routes (tenant_id,name,doc_type,steps,active,created_by,created_login)
    values (ten, left(trim(p_name),120), nullif(trim(p_doc_type),''), coalesce(p_steps,'[]'::jsonb), coalesce(p_active,true),
            (select s.uid from public.app_session_user(p_token) s), uname)
    returning app_approval_routes.id into newid;
    return query select true,'Маршрут создан', newid;
  else
    update public.app_approval_routes r set name = left(trim(p_name),120), doc_type = nullif(trim(p_doc_type),''),
           steps = coalesce(p_steps, r.steps), active = coalesce(p_active, r.active)
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten)
     returning r.id into newid;
    if newid is null then return query select false,'Маршрут не найден', null::uuid; return; end if;
    return query select true,'Маршрут сохранён', newid;
  end if;
end $$;

create or replace function public.app_approval_route_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_approval_routes r where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Маршрут не найден'; return; end if;
  return query select true,'Маршрут удалён';
end $$;

create or replace function public.app_approval_request_create(p_token uuid, p_route_id uuid, p_entity_type text, p_entity_id uuid, p_entity_title text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; me uuid; steps jsonb; total int; newid uuid; step jsonb; role text; uid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin, s.uid into ten, uname, me from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select r.steps into steps from public.app_approval_routes r where r.id = p_route_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten) and r.active;
  if steps is null then return query select false,'Маршрут не найден или неактивен', null::uuid; return; end if;
  total := jsonb_array_length(steps);
  if total = 0 then return query select false,'В маршруте нет шагов', null::uuid; return; end if;
  insert into public.app_approval_requests (tenant_id, route_id, entity_type, entity_id, entity_title, status, current_step, total_steps, requested_by, requested_login)
  values (ten, p_route_id, nullif(trim(p_entity_type),''), p_entity_id, left(coalesce(p_entity_title,''),200), 'pending', 1, total, me, uname)
  returning app_approval_requests.id into newid;

  step := steps -> 0;
  role := nullif(step->>'role',''); uid := null;
  begin uid := (step->>'user_id')::uuid; exception when others then uid := null; end;
  if uid is not null then
    perform public.app_notif_send(uid, 'Согласование', 'Требуется согласование: ' || coalesce(p_entity_title,''), 'apps/access/index.html');
  elsif role is not null then
    perform public.app_notif_roles_t(ten, array[role], 'Согласование', 'Требуется согласование: ' || coalesce(p_entity_title,''), 'apps/access/index.html');
  end if;
  return query select true,'Заявка отправлена на согласование', newid;
end $$;

create or replace function public.app_approval_requests_list(p_token uuid, p_status text default null, p_limit integer default 100)
returns table (id uuid, route_name text, entity_type text, entity_title text, status text, current_step integer, total_steps integer,
               requested_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select r.id, ar.name, r.entity_type, r.entity_title, r.status, r.current_step, r.total_steps, r.requested_login, r.created_at
      from public.app_approval_requests r
      left join public.app_approval_routes ar on ar.id = r.route_id
     where (adm or r.tenant_id = ten) and (st is null or r.status = st)
     order by r.created_at desc limit greatest(coalesce(p_limit,100),1);
end $$;

-- Заявки, ожидающие действия текущего пользователя
create or replace function public.app_approval_my(p_token uuid)
returns table (id uuid, route_name text, entity_type text, entity_title text, current_step integer, total_steps integer,
               requested_login text, step_name text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; uid uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, ar.name, r.entity_type, r.entity_title, r.current_step, r.total_steps, r.requested_login,
           coalesce((ar.steps -> (r.current_step - 1))->>'name', (ar.steps -> (r.current_step - 1))->>'role'),
           r.created_at
      from public.app_approval_requests r
      left join public.app_approval_routes ar on ar.id = r.route_id
     where r.tenant_id = ten and r.status = 'pending'
       and (
         (ar.steps -> (r.current_step - 1))->>'role' = urole
         or ((ar.steps -> (r.current_step - 1))->>'user_id') = uid::text
         or public.app_is_owner(p_token)
       )
     order by r.created_at desc;
end $$;

create or replace function public.app_approval_act(p_token uuid, p_request_id uuid, p_action text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; me uuid; urole text; req record; steps jsonb; step jsonb; role text; uid uuid; act text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin, s.uid, s.urole into ten, uname, me, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  act := lower(trim(coalesce(p_action,'')));
  if act not in ('approve','reject') then return query select false,'Действие: approve или reject'; return; end if;
  select r.id, r.route_id, r.status, r.current_step, r.total_steps, r.entity_title, r.requested_by
    into req from public.app_approval_requests r where r.id = p_request_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  if req.id is null then return query select false,'Заявка не найдена'; return; end if;
  if req.status <> 'pending' then return query select false,'Заявка уже обработана'; return; end if;
  select rr.steps into steps from public.app_approval_routes rr where rr.id = req.route_id;
  step := steps -> (req.current_step - 1);
  role := nullif(step->>'role',''); uid := null;
  begin uid := (step->>'user_id')::uuid; exception when others then uid := null; end;
  if not (public.app_is_owner(p_token) or role = urole or uid = me) then
    return query select false,'Ваш этап ещё не наступил или нет прав'; return;
  end if;

  insert into public.app_approval_actions (request_id, step_ord, actor, actor_login, action, comment)
  values (p_request_id, req.current_step, me, uname, act, nullif(trim(p_comment),''));

  if act = 'reject' then
    update public.app_approval_requests r set status='rejected', updated_at=now() where r.id = p_request_id;
    if req.requested_by is not null then perform public.app_notif_send(req.requested_by, 'Согласование отклонено', coalesce(req.entity_title,''), 'apps/access/index.html'); end if;
    return query select true,'Заявка отклонена';
  end if;

  if req.current_step < req.total_steps then
    update public.app_approval_requests r set current_step = r.current_step + 1, updated_at = now() where r.id = p_request_id;
    step := steps -> req.current_step;   -- следующий шаг (0-based)
    role := nullif(step->>'role',''); uid := null;
    begin uid := (step->>'user_id')::uuid; exception when others then uid := null; end;
    if uid is not null then
      perform public.app_notif_send(uid, 'Согласование', 'Следующий этап: ' || coalesce(req.entity_title,''), 'apps/access/index.html');
    elsif role is not null then
      perform public.app_notif_roles_t(ten, array[role], 'Согласование', 'Следующий этап: ' || coalesce(req.entity_title,''), 'apps/access/index.html');
    end if;
    return query select true,'Этап согласован, передан дальше';
  else
    update public.app_approval_requests r set status='approved', updated_at=now() where r.id = p_request_id;
    if req.requested_by is not null then perform public.app_notif_send(req.requested_by, 'Согласование завершено', coalesce(req.entity_title,''), 'apps/access/index.html'); end if;
    return query select true,'Заявка согласована';
  end if;
end $$;

-- ---------- RPC: расширенный аудит ----------
create or replace function public.app_audit_policies_list(p_token uuid)
returns table (id uuid, scope_type text, scope_ref text, scope_name text, module text, action text, min_role text, enabled boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.scope_type, p.scope_ref,
           case when p.scope_type='department' then (select d.name from public.app_departments d where d.id::text = p.scope_ref limit 1) else null end,
           p.module, p.action, p.min_role, p.enabled
      from public.app_audit_policies p where adm or p.tenant_id = ten order by p.created_at desc;
end $$;

create or replace function public.app_audit_policy_save(p_token uuid, p_id uuid, p_scope_type text, p_scope_ref text, p_module text, p_action text, p_min_role text, p_enabled boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_scope_type),'all') not in ('all','module','department') then
    return query select false,'Недопустимая область политики', null::uuid; return;
  end if;
  if p_id is null then
    insert into public.app_audit_policies (tenant_id, scope_type, scope_ref, module, action, min_role, enabled)
    values (ten, coalesce(nullif(trim(p_scope_type),''),'all'), nullif(trim(p_scope_ref),''), nullif(trim(p_module),''),
            nullif(trim(p_action),''), nullif(trim(p_min_role),''), coalesce(p_enabled,true))
    returning app_audit_policies.id into newid;
    return query select true,'Политика создана', newid;
  else
    update public.app_audit_policies p set scope_type = coalesce(nullif(trim(p_scope_type),''),p.scope_type),
           scope_ref = nullif(trim(p_scope_ref),''), module = nullif(trim(p_module),''), action = nullif(trim(p_action),''),
           min_role = nullif(trim(p_min_role),''), enabled = coalesce(p_enabled,p.enabled)
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Политика не найдена', null::uuid; return; end if;
    return query select true,'Политика сохранена', newid;
  end if;
end $$;

create or replace function public.app_audit_policy_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_audit_policies p where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Политика не найдена'; return; end if;
  return query select true,'Политика удалена';
end $$;

create or replace function public.app_audit_write(p_token uuid, p_module text, p_action text, p_entity_type text, p_entity_id uuid, p_detail jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; me uuid; urole text; dept uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin, s.uid, s.urole into ten, uname, me, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select e.department_id into dept from public.app_employees e where e.user_login = uname and e.tenant_id = ten limit 1;
  insert into public.app_audit_ext (tenant_id, actor, actor_login, actor_role, module, action, entity_type, entity_id, department_id, detail)
  values (ten, me, uname, urole, nullif(trim(p_module),''), nullif(trim(p_action),''), nullif(trim(p_entity_type),''), p_entity_id, dept, coalesce(p_detail,'{}'::jsonb));
  return query select true,'Записано в журнал аудита';
end $$;

create or replace function public.app_audit_ext_list(p_token uuid, p_module text default null, p_limit integer default 100)
returns table (actor_login text, actor_role text, module text, action text, entity_type text, entity_id uuid, detail jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; m text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  m := nullif(trim(coalesce(p_module,'')),'');
  return query
    select a.actor_login, a.actor_role, a.module, a.action, a.entity_type, a.entity_id, a.detail, a.created_at
      from public.app_audit_ext a
     where (adm or a.tenant_id = ten) and (m is null or a.module = m)
     order by a.created_at desc limit greatest(coalesce(p_limit,100),1);
end $$;

create or replace function public.app_audit_kpi(p_token uuid)
returns table (events bigint, actors bigint, modules bigint, today bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_audit_ext a where adm or a.tenant_id = ten),
    (select count(distinct a.actor) from public.app_audit_ext a where adm or a.tenant_id = ten),
    (select count(distinct a.module) from public.app_audit_ext a where adm or a.tenant_id = ten),
    (select count(*) from public.app_audit_ext a where (adm or a.tenant_id = ten) and a.created_at::date = current_date);
end $$;

-- ---------- Демо ----------
insert into public.app_permission_sets (tenant_id, name, description, perms, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Базовый пакет (оператор)',
       'Просмотр продаж и производства, правка производства',
       '{"orders":{"view":true,"edit":false},"production":{"view":true,"edit":true},"mes":{"view":true,"edit":true}}'::jsonb, 'owner'
where not exists (select 1 from public.app_permission_sets where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Базовый пакет (оператор)');

insert into public.app_permission_assignments (tenant_id, set_id, target_type, target_ref, active)
select 'aaaaaaaa-0000-0000-0000-000000000001', s.id, 'role', 'operator', true
from public.app_permission_sets s
where s.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and s.name='Базовый пакет (оператор)'
  and not exists (select 1 from public.app_permission_assignments a where a.set_id = s.id and a.target_type='role' and a.target_ref='operator');

insert into public.app_approval_routes (tenant_id, name, doc_type, steps, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Согласование заявки', 'order',
       '[{"ord":1,"role":"chief","name":"Начальник цеха"},{"ord":2,"role":"director","name":"Директор"}]'::jsonb, true, 'owner'
where not exists (select 1 from public.app_approval_routes where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Согласование заявки');

insert into public.app_audit_policies (tenant_id, scope_type, scope_ref, module, action, min_role, enabled)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'module', null, 'service', 'edit', null, true
where not exists (select 1 from public.app_audit_policies where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and scope_type='module' and module='service');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Enterprise-права и аудит: наборы прав, делегирование, согласования',
   'W10: наборы прав (app_permission_sets + назначения на роль/пользователя/подразделение, app_effective_perms), делегирование полномочий (app_delegations; app_can учитывает активные делегирования и наборы прав), маршруты согласований (app_approval_routes со шагами-ролями, app_approval_requests/actions, уведомления по этапам), расширенный аудит (app_audit_policies по подразделениям/модулям, app_audit_ext через app_audit_write, KPI). Модуль «Права и согласования» (apps/access).',
   'права наборы делегирование согласования маршруты аудит подразделения политики enterprise')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Enterprise-права и аудит: наборы прав, делегирование, согласования'
);

-- ---------- Права ----------
grant execute on function public.app_perm_sets_list(uuid) to anon, authenticated;
grant execute on function public.app_perm_set_save(uuid,uuid,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_perm_set_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_perm_assign_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_perm_assign_save(uuid,uuid,text,text,boolean) to anon, authenticated;
grant execute on function public.app_perm_assign_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_effective_perms(uuid) to anon, authenticated;
grant execute on function public.app_delegations_list(uuid) to anon, authenticated;
grant execute on function public.app_delegation_save(uuid,uuid,uuid,text,text,date,date,boolean,text) to anon, authenticated;
grant execute on function public.app_delegation_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_approval_routes_list(uuid) to anon, authenticated;
grant execute on function public.app_approval_route_save(uuid,uuid,text,text,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_approval_route_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_approval_request_create(uuid,uuid,text,uuid,text) to anon, authenticated;
grant execute on function public.app_approval_requests_list(uuid,text,integer) to anon, authenticated;
grant execute on function public.app_approval_my(uuid) to anon, authenticated;
grant execute on function public.app_approval_act(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_audit_policies_list(uuid) to anon, authenticated;
grant execute on function public.app_audit_policy_save(uuid,uuid,text,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_audit_policy_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_audit_write(uuid,text,text,text,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_audit_ext_list(uuid,text,integer) to anon, authenticated;
grant execute on function public.app_audit_kpi(uuid) to anon, authenticated;
