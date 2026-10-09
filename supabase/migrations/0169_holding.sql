-- ============================================================
-- 3DMP Service · 0169_holding.sql  (W22 — Холдинг / CPM)
-- Площадки группы, снимки KPI, консолидация, KPI группы.
-- Идемпотентно. Зависит от 0001..0168.
-- ============================================================

create table if not exists public.app_holding_units (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),   -- головная организация
  unit_tenant_id uuid references public.tenants (id),   -- площадка (может быть null)
  name           text not null,
  code           text,
  region         text,
  share          numeric not null default 100,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);
alter table public.app_holding_units enable row level security;

create table if not exists public.app_holding_snapshots (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),   -- головная (владелец данных)
  unit_id    uuid not null references public.app_holding_units (id) on delete cascade,
  period     date not null default current_date,
  revenue    numeric not null default 0,
  cost       numeric not null default 0,
  profit     numeric not null default 0,
  kpi        jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists app_holding_snap_idx on public.app_holding_snapshots (tenant_id, unit_id, period desc);
alter table public.app_holding_snapshots enable row level security;

-- ---------- Площадки ----------
create or replace function public.app_holding_units_list(p_token uuid)
returns table (id uuid, name text, code text, region text, share numeric, active boolean, unit_tenant_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select u.id,u.name,u.code,u.region,u.share,u.active,u.unit_tenant_id from public.app_holding_units u where adm or u.tenant_id=ten order by u.name;
end $$;

create or replace function public.app_holding_unit_save(p_token uuid, p_id uuid, p_name text, p_code text, p_region text, p_share numeric, p_unit_tenant uuid, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите название площадки',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_holding_units (tenant_id,name,code,region,share,unit_tenant_id,active)
    values (ten,left(trim(p_name),160),nullif(trim(p_code),''),nullif(trim(p_region),''),coalesce(p_share,100),p_unit_tenant,coalesce(p_active,true))
    returning id into newid;
    return query select true,'Площадка добавлена',newid;
  else
    update public.app_holding_units u set name=left(trim(p_name),160),code=nullif(trim(p_code),''),region=nullif(trim(p_region),''),share=coalesce(p_share,u.share),unit_tenant_id=p_unit_tenant,active=coalesce(p_active,u.active)
     where u.id=p_id and (public.app_is_platform_admin(p_token) or u.tenant_id=ten) returning u.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Площадка сохранена',newid;
  end if;
end $$;

create or replace function public.app_holding_unit_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_holding_units u where u.id=p_id and (public.app_is_platform_admin(p_token) or u.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Площадка удалена';
end $$;

-- ---------- Снимки ----------
create or replace function public.app_holding_snapshot_save(p_token uuid, p_unit_id uuid, p_period date, p_revenue numeric, p_cost numeric, p_kpi jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; prf numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if not exists (select 1 from public.app_holding_units h where h.id=p_unit_id and (public.app_is_platform_admin(p_token) or h.tenant_id=ten)) then
    return query select false,'Площадка не найдена',null::uuid; return;
  end if;
  prf := coalesce(p_revenue,0) - coalesce(p_cost,0);
  insert into public.app_holding_snapshots (tenant_id,unit_id,period,revenue,cost,profit,kpi)
  values (ten,p_unit_id,coalesce(p_period,current_date),coalesce(p_revenue,0),coalesce(p_cost,0),prf,coalesce(p_kpi,'{}'::jsonb))
  returning id into newid;
  return query select true,'Снимок добавлен',newid;
end $$;

create or replace function public.app_holding_consolidate(p_token uuid, p_period date default null)
returns table (unit text, region text, share numeric, revenue numeric, cost numeric, profit numeric, period date)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; pr date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  pr := coalesce(p_period, current_date);
  return query
    select h.name, h.region, h.share,
           s.revenue * h.share/100, s.cost * h.share/100, s.profit * h.share/100, s.period
      from public.app_holding_units h
      left join lateral (
        select * from public.app_holding_snapshots sn
         where sn.unit_id = h.id and (adm or sn.tenant_id = ten) and sn.period <= pr
         order by sn.period desc limit 1
      ) s on true
     where adm or h.tenant_id = ten
     order by h.name;
end $$;

create or replace function public.app_holding_kpi(p_token uuid)
returns table (units bigint, units_active bigint, revenue numeric, cost numeric, profit numeric, snapshots bigint)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_holding_units h where adm or h.tenant_id=ten),
    (select count(*) from public.app_holding_units h where (adm or h.tenant_id=ten) and h.active),
    (select coalesce(sum(c.revenue),0) from public.app_holding_consolidate(p_token, null) c),
    (select coalesce(sum(c.cost),0) from public.app_holding_consolidate(p_token, null) c),
    (select coalesce(sum(c.profit),0) from public.app_holding_consolidate(p_token, null) c),
    (select count(*) from public.app_holding_snapshots s where adm or s.tenant_id=ten);
end $$;

-- ---------- Демо ----------
insert into public.app_holding_units (tenant_id, name, code, region, share, active)
select 'aaaaaaaa-0000-0000-0000-000000000001','Площадка «Север»','PL-N','Север',100,true
where not exists (select 1 from public.app_holding_units where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='PL-N');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','Холдинг/CPM: площадки, консолидация, KPI группы',
       'W22: площадки группы (app_holding_units: код/регион/доля), снимки KPI (app_holding_snapshots: выручка/себестоимость/прибыль/произвольные KPI за период), консолидация с учётом доли (app_holding_consolidate), KPI группы (app_holding_kpi). Модуль «Холдинг» (apps/holding).',
       'холдинг CPM площадки консолидация KPI группа мультизавод','Платформа'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Холдинг/CPM: площадки, консолидация, KPI группы');

-- ---------- Права ----------
grant execute on function public.app_holding_units_list(uuid) to anon, authenticated;
grant execute on function public.app_holding_unit_save(uuid,uuid,text,text,text,numeric,uuid,boolean) to anon, authenticated;
grant execute on function public.app_holding_unit_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_holding_snapshot_save(uuid,uuid,date,numeric,numeric,jsonb) to anon, authenticated;
grant execute on function public.app_holding_consolidate(uuid,date) to anon, authenticated;
grant execute on function public.app_holding_kpi(uuid) to anon, authenticated;
