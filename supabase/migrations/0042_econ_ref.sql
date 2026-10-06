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
