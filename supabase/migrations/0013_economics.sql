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
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.kind, r.name, r.rate_hour from public.app_cost_rates r
    where (urole='admin' or r.tenant_id = ten) order by r.kind, r.name;
end $$;

-- ---------- Себестоимость заявки ----------
create or replace function public.app_order_cost(p_token uuid, p_order_id uuid)
returns table (plan_hours numeric, fact_hours numeric, work_cost numeric,
               material_cost numeric, overhead numeric, total numeric, amount numeric, margin numeric)
language plpgsql security definer set search_path = public
as $$
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
create or replace function public.app_economics(p_token uuid)
returns table (orders_total bigint, orders_open bigint, naryads_open bigint, naryads_closed bigint,
               plan_hours numeric, fact_hours numeric, defects_open bigint, low_stock bigint, avg_rate numeric)
language plpgsql security definer set search_path = public
as $$
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
