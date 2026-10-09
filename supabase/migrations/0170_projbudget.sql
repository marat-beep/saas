-- ============================================================
-- 3DMP Service · 0170_projbudget.sql  (W28 — Бюджетирование проектов)
-- Смета проекта (версии), план-факт по статьям, освоение (EVM-задел), KPI.
-- Идемпотентно. Зависит от 0001..0169.
-- ============================================================

create table if not exists public.app_proj_budgets (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  project_id    uuid references public.app_projects (id) on delete set null,
  name          text not null,
  version       integer not null default 1,
  currency      text default 'RUB',
  status        text not null default 'draft',   -- draft|approved|closed
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
alter table public.app_proj_budgets enable row level security;

create table if not exists public.app_proj_budget_lines (
  id           uuid primary key default gen_random_uuid(),
  budget_id    uuid not null references public.app_proj_budgets (id) on delete cascade,
  category     text not null,
  item         text,
  amount_plan  numeric not null default 0,
  amount_fact  numeric not null default 0,
  note         text
);
create index if not exists app_proj_budget_lines_idx on public.app_proj_budget_lines (budget_id, category);
alter table public.app_proj_budget_lines enable row level security;

create or replace function public.app_proj_budgets_list(p_token uuid, p_project_id uuid default null)
returns table (id uuid, project text, name text, version integer, status text, plan_total numeric, fact_total numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select b.id, p.name, b.name, b.version, b.status,
           coalesce((select sum(l.amount_plan) from public.app_proj_budget_lines l where l.budget_id=b.id),0),
           coalesce((select sum(l.amount_fact) from public.app_proj_budget_lines l where l.budget_id=b.id),0)
      from public.app_proj_budgets b left join public.app_projects p on p.id=b.project_id
     where (adm or b.tenant_id=ten) and (p_project_id is null or b.project_id=p_project_id)
     order by b.created_at desc;
end $$;

create or replace function public.app_proj_budget_save(p_token uuid, p_id uuid, p_project_id uuid, p_name text, p_version integer, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите название сметы',null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'draft');
  if st not in ('draft','approved','closed') then return query select false,'Недопустимый статус',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_proj_budgets (tenant_id,project_id,name,version,status,note,created_login)
    values (ten,p_project_id,left(trim(p_name),160),greatest(coalesce(p_version,1),1),st,nullif(trim(p_note),''),uname)
    returning id into newid;
    return query select true,'Смета создана',newid;
  else
    update public.app_proj_budgets b set project_id=p_project_id,name=left(trim(p_name),160),version=greatest(coalesce(p_version,b.version),1),status=st,note=nullif(trim(p_note),'')
     where b.id=p_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten) returning b.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Смета сохранена',newid;
  end if;
end $$;

create or replace function public.app_proj_budget_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_proj_budgets b where b.id=p_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Смета удалена';
end $$;

create or replace function public.app_proj_budget_lines_list(p_token uuid, p_budget_id uuid)
returns table (id uuid, category text, item text, amount_plan numeric, amount_fact numeric, note text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id,l.category,l.item,l.amount_plan,l.amount_fact,l.note
    from public.app_proj_budget_lines l join public.app_proj_budgets b on b.id=l.budget_id
   where l.budget_id=p_budget_id and (adm or b.tenant_id=ten) order by l.category;
end $$;

create or replace function public.app_proj_budget_line_save(p_token uuid, p_id uuid, p_budget_id uuid, p_category text, p_item text, p_plan numeric, p_fact numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_proj_budgets b where b.id=p_budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten)) then
    return query select false,'Смета не найдена',null::uuid; return;
  end if;
  if coalesce(trim(p_category),'')='' then return query select false,'Укажите статью',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_proj_budget_lines (budget_id,category,item,amount_plan,amount_fact,note)
    values (p_budget_id,left(trim(p_category),120),nullif(trim(p_item),''),coalesce(p_plan,0),coalesce(p_fact,0),nullif(trim(p_note),''))
    returning id into newid;
    return query select true,'Строка добавлена',newid;
  else
    update public.app_proj_budget_lines l set category=left(trim(p_category),120),item=nullif(trim(p_item),''),amount_plan=coalesce(p_plan,l.amount_plan),amount_fact=coalesce(p_fact,l.amount_fact),note=nullif(trim(p_note),'')
     where l.id=p_id and exists (select 1 from public.app_proj_budgets b where b.id=l.budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten)) returning l.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Строка сохранена',newid;
  end if;
end $$;

create or replace function public.app_proj_budget_line_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_proj_budget_lines l using public.app_proj_budgets b
   where l.id=p_id and b.id=l.budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Строка удалена';
end $$;

create or replace function public.app_proj_budget_plan_fact(p_token uuid, p_budget_id uuid)
returns table (category text, amount_plan numeric, amount_fact numeric, delta numeric, pct numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select l.category, sum(l.amount_plan), sum(l.amount_fact), sum(l.amount_fact)-sum(l.amount_plan),
           case when sum(l.amount_plan)>0 then round(sum(l.amount_fact)/sum(l.amount_plan)*100,1) end
      from public.app_proj_budget_lines l join public.app_proj_budgets b on b.id=l.budget_id
     where l.budget_id=p_budget_id and (adm or b.tenant_id=ten)
     group by l.category order by l.category;
end $$;

create or replace function public.app_proj_budget_evm(p_token uuid, p_budget_id uuid)
returns table (pv numeric, ac numeric, ev numeric, cpi numeric, spi numeric, eac numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; v_pv numeric; v_ac numeric; v_ev numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select coalesce(sum(l.amount_plan),0), coalesce(sum(l.amount_fact),0) into v_pv, v_ac
    from public.app_proj_budget_lines l join public.app_proj_budgets b on b.id=l.budget_id
   where l.budget_id=p_budget_id and (adm or b.tenant_id=ten);
  -- EV принимаем равным фактическим затратам (задел: при появлении % выполнения заменить)
  v_ev := v_ac;
  return query select v_pv, v_ac, v_ev,
    case when v_ac>0 then round(v_ev/v_ac*100,1) end,
    case when v_pv>0 then round(v_ev/v_pv*100,1) end,
    case when v_ac>0 then round(v_pv/v_ac*v_ac,0) end;
end $$;

create or replace function public.app_proj_budget_kpi(p_token uuid)
returns table (budgets bigint, plan_total numeric, fact_total numeric, margin_pct numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; pl numeric; fa numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select coalesce(sum(l.amount_plan),0), coalesce(sum(l.amount_fact),0) into pl, fa
    from public.app_proj_budget_lines l join public.app_proj_budgets b on b.id=l.budget_id
   where (adm or b.tenant_id=ten);
  return query select
    (select count(*) from public.app_proj_budgets b where adm or b.tenant_id=ten),
    pl, fa, case when pl>0 then round((pl-fa)/pl*100,1) end;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Экономика','Бюджетирование проектов: смета, план-факт, освоение (EVM)',
       'W28: смета проекта (app_proj_budgets: проект/версия/статус), строки по статьям план/факт (app_proj_budget_lines), план-факт (app_proj_budget_plan_fact), освоение EVM-задел (app_proj_budget_evm: PV/AC/EV, CPI/SPI, EAC), KPI (app_proj_budget_kpi). Дашборды — через отчеты/BI. Модуль «Бюджет проектов» (apps/projbudget).',
       'бюджет проект смета план-факт освоение EVM CPI SPI EAC','Экономика'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Бюджетирование проектов: смета, план-факт, освоение (EVM)');

-- ---------- Права ----------
grant execute on function public.app_proj_budgets_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_save(uuid,uuid,uuid,text,integer,text,text) to anon, authenticated;
grant execute on function public.app_proj_budget_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_line_save(uuid,uuid,uuid,text,text,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_proj_budget_line_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_plan_fact(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_evm(uuid,uuid) to anon, authenticated;
grant execute on function public.app_proj_budget_kpi(uuid) to anon, authenticated;
