-- ============================================================
-- 3DMP Service · 0173_itsm.sql  (W24 — ITSM / ITIL)
-- Каталог ИТ-услуг, заявки/инциденты ИТ со SLA; KPI.
-- Идемпотентно. Зависит от 0001..0172.
-- ============================================================

create table if not exists public.app_it_services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  name text not null, category text, owner_login text, sla_hours integer default 8, active boolean default true, note text, created_at timestamptz default now()
);
alter table public.app_it_services enable row level security;

create table if not exists public.app_it_tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  number text, service_id uuid references public.app_it_services (id) on delete set null,
  title text not null, description text, priority text default 'normal',
  status text not null default 'new', assignee_login text, due_at timestamptz,
  created_login text, created_at timestamptz default now(), resolved_at timestamptz
);
alter table public.app_it_tickets enable row level security;

create or replace function public.app_it_services_list(p_token uuid)
returns table (id uuid, name text, category text, owner_login text, sla_hours integer, active boolean, tickets bigint)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select s.id,s.name,s.category,s.owner_login,s.sla_hours,s.active,(select count(*) from public.app_it_tickets t where t.service_id=s.id)
    from public.app_it_services s where adm or s.tenant_id=ten order by s.name;
end $$;

create or replace function public.app_it_service_save(p_token uuid, p_id uuid, p_name text, p_category text, p_owner text, p_sla integer, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите услугу',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_it_services (tenant_id,name,category,owner_login,sla_hours,active) values (ten,left(trim(p_name),160),nullif(trim(p_category),''),nullif(trim(p_owner),''),coalesce(p_sla,8),coalesce(p_active,true)) returning id into newid;
    return query select true,'Услуга добавлена',newid;
  else
    update public.app_it_services s set name=left(trim(p_name),160),category=nullif(trim(p_category),''),owner_login=nullif(trim(p_owner),''),sla_hours=coalesce(p_sla,s.sla_hours),active=coalesce(p_active,s.active)
     where s.id=p_id and (public.app_is_platform_admin(p_token) or s.tenant_id=ten) returning s.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Услуга сохранена',newid;
  end if;
end $$;

create or replace function public.app_it_service_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_it_services s where s.id=p_id and (public.app_is_platform_admin(p_token) or s.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Услуга удалена';
end $$;

create or replace function public.app_it_tickets_list(p_token uuid, p_status text default null)
returns table (id uuid, number text, service text, title text, priority text, status text, assignee_login text, due_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  st:=nullif(trim(coalesce(p_status,'')),'');
  return query select t.id,t.number,s.name,t.title,t.priority,t.status,t.assignee_login,t.due_at,t.created_at
    from public.app_it_tickets t left join public.app_it_services s on s.id=t.service_id
   where (adm or t.tenant_id=ten) and (st is null or t.status=st) order by t.created_at desc;
end $$;

create or replace function public.app_it_ticket_save(p_token uuid, p_id uuid, p_service_id uuid, p_title text, p_description text, p_priority text, p_assignee text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; sla integer; pr text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_title),'')='' then return query select false,'Укажите тему заявки',null::uuid; return; end if;
  pr:=coalesce(nullif(trim(p_priority),''),'normal');
  select coalesce(s.sla_hours,8) into sla from public.app_it_services s where s.id=p_service_id and (public.app_is_platform_admin(p_token) or s.tenant_id=ten);
  if p_id is null then
    insert into public.app_it_tickets (tenant_id,service_id,title,description,priority,status,assignee_login,due_at,created_login)
    values (ten,p_service_id,left(trim(p_title),200),nullif(trim(p_description),''),pr,'new',nullif(trim(p_assignee),''),now() + (coalesce(sla,8)||' hours')::interval,uname) returning id into newid;
    return query select true,'Заявка создана',newid;
  else
    update public.app_it_tickets t set service_id=coalesce(p_service_id,t.service_id),title=left(trim(p_title),200),description=nullif(trim(p_description),''),priority=pr,assignee_login=nullif(trim(p_assignee),'')
     where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten) returning t.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Заявка сохранена',newid;
  end if;
end $$;

create or replace function public.app_it_ticket_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  st:=lower(trim(coalesce(p_status,'')));
  if st not in ('new','in_progress','resolved','closed') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_it_tickets t set status=st, resolved_at=case when st in ('resolved','closed') then coalesce(resolved_at,now()) else null end
   where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

create or replace function public.app_itsm_kpi(p_token uuid)
returns table (services bigint, tickets bigint, open_tickets bigint, in_progress bigint, resolved bigint, sla_breached bigint)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_it_services s where adm or s.tenant_id=ten),
    (select count(*) from public.app_it_tickets t where adm or t.tenant_id=ten),
    (select count(*) from public.app_it_tickets t where (adm or t.tenant_id=ten) and t.status in ('new','in_progress')),
    (select count(*) from public.app_it_tickets t where (adm or t.tenant_id=ten) and t.status='in_progress'),
    (select count(*) from public.app_it_tickets t where (adm or t.tenant_id=ten) and t.status in ('resolved','closed')),
    (select count(*) from public.app_it_tickets t where (adm or t.tenant_id=ten) and t.status in ('new','in_progress') and t.due_at < now());
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','ITSM/ITIL: каталог услуг и заявки со SLA',
       'W24: каталог ИТ-услуг (app_it_services: категория/владелец/SLA), заявки/инциденты (app_it_tickets: услуга/приоритет/исполнитель, SLA-срок due_at, статусы new→in_progress→resolved/closed), KPI (app_itsm_kpi: открытые, просрочка SLA). Модуль «ИТ-сервисы (ITSM)» (apps/itsm).',
       'ITSM ITIL услуги заявка инцидент SLA help desk','Платформа'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='ITSM/ITIL: каталог услуг и заявки со SLA');

-- ---------- Права ----------
grant execute on function public.app_it_services_list(uuid) to anon, authenticated;
grant execute on function public.app_it_service_save(uuid,uuid,text,text,text,integer,boolean) to anon, authenticated;
grant execute on function public.app_it_service_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_it_tickets_list(uuid,text) to anon, authenticated;
grant execute on function public.app_it_ticket_save(uuid,uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_it_ticket_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_itsm_kpi(uuid) to anon, authenticated;
