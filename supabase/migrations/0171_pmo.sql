-- ============================================================
-- 3DMP Service · 0171_pmo.sql  (W25 — PMO / Проекты)
-- Портфели, вехи (progress), риски проектов; KPI.
-- Идемпотентно. Зависит от 0001..0170.
-- ============================================================

create table if not exists public.app_pmo_portfolios (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  name text not null, owner_login text, status text not null default 'active', note text,
  created_login text, created_at timestamptz not null default now()
);
alter table public.app_pmo_portfolios enable row level security;

create table if not exists public.app_pmo_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  portfolio_id uuid references public.app_pmo_portfolios (id) on delete cascade,
  project_id uuid references public.app_projects (id) on delete cascade,
  priority text default 'normal', weight numeric default 100, status text default 'active', created_at timestamptz not null default now()
);
alter table public.app_pmo_items enable row level security;

create table if not exists public.app_pmo_milestones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  project_id uuid references public.app_projects (id) on delete cascade,
  name text not null, due_date date, status text not null default 'pending', weight numeric default 1, created_at timestamptz not null default now()
);
alter table public.app_pmo_milestones enable row level security;

create table if not exists public.app_pmo_risks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  project_id uuid references public.app_projects (id) on delete set null,
  title text not null, probability integer default 3, impact integer default 3,
  status text not null default 'open', mitigation text, created_at timestamptz not null default now()
);
alter table public.app_pmo_risks enable row level security;

-- ---------- Портфели ----------
create or replace function public.app_pmo_portfolios_list(p_token uuid)
returns table (id uuid, name text, owner_login text, status text, projects bigint)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select p.id,p.name,p.owner_login,p.status,(select count(*) from public.app_pmo_items i where i.portfolio_id=p.id)
    from public.app_pmo_portfolios p where adm or p.tenant_id=ten order by p.name;
end $$;

create or replace function public.app_pmo_portfolio_save(p_token uuid, p_id uuid, p_name text, p_owner text, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите название портфеля',null::uuid; return; end if;
  st:=coalesce(nullif(trim(p_status),''),'active');
  if p_id is null then
    insert into public.app_pmo_portfolios (tenant_id,name,owner_login,status,note,created_login)
    values (ten,left(trim(p_name),160),nullif(trim(p_owner),''),st,nullif(trim(p_note),''),uname) returning id into newid;
    return query select true,'Портфель создан',newid;
  else
    update public.app_pmo_portfolios p set name=left(trim(p_name),160),owner_login=nullif(trim(p_owner),''),status=st,note=nullif(trim(p_note),'')
     where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten) returning p.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Портфель сохранён',newid;
  end if;
end $$;

create or replace function public.app_pmo_portfolio_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_pmo_portfolios p where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Портфель удалён';
end $$;

-- ---------- Состав портфеля ----------
create or replace function public.app_pmo_items_list(p_token uuid, p_portfolio_id uuid)
returns table (id uuid, project text, priority text, weight numeric, status text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select i.id,pj.name,i.priority,i.weight,i.status
    from public.app_pmo_items i left join public.app_projects pj on pj.id=i.project_id
   where i.portfolio_id=p_portfolio_id and (adm or i.tenant_id=ten) order by i.priority, pj.name;
end $$;

create or replace function public.app_pmo_item_save(p_token uuid, p_id uuid, p_portfolio_id uuid, p_project_id uuid, p_priority text, p_weight numeric)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if p_id is null then
    insert into public.app_pmo_items (tenant_id,portfolio_id,project_id,priority,weight)
    values (ten,p_portfolio_id,p_project_id,coalesce(nullif(trim(p_priority),''),'normal'),coalesce(p_weight,100)) returning id into newid;
    return query select true,'Проект добавлен в портфель',newid;
  else
    update public.app_pmo_items i set project_id=coalesce(p_project_id,i.project_id),priority=coalesce(nullif(trim(p_priority),''),i.priority),weight=coalesce(p_weight,i.weight)
     where i.id=p_id and (public.app_is_platform_admin(p_token) or i.tenant_id=ten) returning i.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Сохранено',newid;
  end if;
end $$;

create or replace function public.app_pmo_item_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_pmo_items i where i.id=p_id and (public.app_is_platform_admin(p_token) or i.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Удалено';
end $$;

-- ---------- Вехи ----------
create or replace function public.app_pmo_milestones_list(p_token uuid, p_project_id uuid default null)
returns table (id uuid, project text, name text, due_date date, status text, weight numeric)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select m.id,pj.name,m.name,m.due_date,m.status,m.weight
    from public.app_pmo_milestones m left join public.app_projects pj on pj.id=m.project_id
   where (adm or m.tenant_id=ten) and (p_project_id is null or m.project_id=p_project_id) order by m.due_date nulls last;
end $$;

create or replace function public.app_pmo_milestone_save(p_token uuid, p_id uuid, p_project_id uuid, p_name text, p_due date, p_status text, p_weight numeric)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите веху',null::uuid; return; end if;
  st:=coalesce(nullif(trim(p_status),''),'pending');
  if st not in ('pending','done','cancelled') then return query select false,'Недопустимый статус',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_pmo_milestones (tenant_id,project_id,name,due_date,status,weight)
    values (ten,p_project_id,left(trim(p_name),160),p_due,st,coalesce(p_weight,1)) returning id into newid;
    return query select true,'Веха добавлена',newid;
  else
    update public.app_pmo_milestones m set project_id=coalesce(p_project_id,m.project_id),name=left(trim(p_name),160),due_date=p_due,status=st,weight=coalesce(p_weight,m.weight)
     where m.id=p_id and (public.app_is_platform_admin(p_token) or m.tenant_id=ten) returning m.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Веха сохранена',newid;
  end if;
end $$;

create or replace function public.app_pmo_milestone_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  st:=lower(trim(coalesce(p_status,'')));
  if st not in ('pending','done','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_pmo_milestones m set status=st where m.id=p_id and (public.app_is_platform_admin(p_token) or m.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

-- ---------- Риски ----------
create or replace function public.app_pmo_risks_list(p_token uuid, p_limit integer default 100)
returns table (id uuid, project text, title text, probability integer, impact integer, severity integer, status text, mitigation text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select r.id,pj.name,r.title,r.probability,r.impact,r.probability*r.impact,r.status,r.mitigation
    from public.app_pmo_risks r left join public.app_projects pj on pj.id=r.project_id
   where adm or r.tenant_id=ten order by (r.probability*r.impact) desc limit greatest(coalesce(p_limit,100),1);
end $$;

create or replace function public.app_pmo_risk_save(p_token uuid, p_id uuid, p_project_id uuid, p_title text, p_prob integer, p_impact integer, p_status text, p_mitigation text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_title),'')='' then return query select false,'Укажите риск',null::uuid; return; end if;
  st:=coalesce(nullif(trim(p_status),''),'open');
  if p_id is null then
    insert into public.app_pmo_risks (tenant_id,project_id,title,probability,impact,status,mitigation)
    values (ten,p_project_id,left(trim(p_title),200),least(greatest(coalesce(p_prob,3),1),5),least(greatest(coalesce(p_impact,3),1),5),st,nullif(trim(p_mitigation),'')) returning id into newid;
    return query select true,'Риск добавлен',newid;
  else
    update public.app_pmo_risks r set project_id=coalesce(p_project_id,r.project_id),title=left(trim(p_title),200),probability=least(greatest(coalesce(p_prob,r.probability),1),5),impact=least(greatest(coalesce(p_impact,r.impact),1),5),status=st,mitigation=nullif(trim(p_mitigation),'')
     where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten) returning r.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Риск сохранён',newid;
  end if;
end $$;

create or replace function public.app_pmo_risk_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  st:=lower(trim(coalesce(p_status,'')));
  if st not in ('open','mitigated','closed') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_pmo_risks r set status=st where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

create or replace function public.app_pmo_kpi(p_token uuid)
returns table (portfolios bigint, projects bigint, milestones bigint, milestones_done bigint, milestones_overdue bigint, risks_open bigint, risks_high bigint)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_pmo_portfolios p where adm or p.tenant_id=ten),
    (select count(*) from public.app_projects p where adm or p.tenant_id=ten),
    (select count(*) from public.app_pmo_milestones m where adm or m.tenant_id=ten),
    (select count(*) from public.app_pmo_milestones m where (adm or m.tenant_id=ten) and m.status='done'),
    (select count(*) from public.app_pmo_milestones m where (adm or m.tenant_id=ten) and m.status='pending' and m.due_date < current_date),
    (select count(*) from public.app_pmo_risks r where (adm or r.tenant_id=ten) and r.status='open'),
    (select count(*) from public.app_pmo_risks r where (adm or r.tenant_id=ten) and r.status='open' and r.probability*r.impact >= 15);
end $$;

-- ---------- Демо ----------
insert into public.app_pmo_portfolios (tenant_id, name, owner_login, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001','Портфель 2026','owner','active','owner'
where not exists (select 1 from public.app_pmo_portfolios where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Портфель 2026');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Производство','PMO: портфели, вехи, риски проектов',
       'W25: портфели (app_pmo_portfolios) и состав (app_pmo_items: проект/приоритет/вес), вехи проекта (app_pmo_milestones: срок/статус/вес), реестр рисков (app_pmo_risks: вероятность×влияние = серьёзность, статус, план мероприятий), KPI (app_pmo_kpi). Модуль «Портфель проектов» (apps/pmo).',
       'PMO портфель проект веха риск probability impact','Производство'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='PMO: портфели, вехи, риски проектов');

-- ---------- Права ----------
grant execute on function public.app_pmo_portfolios_list(uuid) to anon, authenticated;
grant execute on function public.app_pmo_portfolio_save(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_pmo_portfolio_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_pmo_items_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_pmo_item_save(uuid,uuid,uuid,uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_pmo_item_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_pmo_milestones_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_pmo_milestone_save(uuid,uuid,uuid,text,date,text,numeric) to anon, authenticated;
grant execute on function public.app_pmo_milestone_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_pmo_risks_list(uuid,integer) to anon, authenticated;
grant execute on function public.app_pmo_risk_save(uuid,uuid,uuid,text,integer,integer,text,text) to anon, authenticated;
grant execute on function public.app_pmo_risk_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_pmo_kpi(uuid) to anon, authenticated;
