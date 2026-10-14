-- ============================================================
-- 3DMP Service · 0256_cost_consistency.sql  (PROP-16 — согласованность себестоимости)
-- app_order_cost_plan_fact: единый источник ставки с app_order_cost
-- (операция.base_rate → рабочий центр.cost_hour, фолбэк — ставка шага маршрута),
-- план/факт труда считаются по одной ставке; отклонение = (факт-план) × ставка.
-- Идемпотентно (create or replace). Зависит от 0114/0042.
-- ============================================================

create or replace function public.app_order_cost_plan_fact(p_token uuid, p_order_id uuid)
returns table (order_number text, plan_hours numeric, fact_hours numeric, hours_dev numeric,
               rate_avg numeric, plan_labor numeric, fact_labor numeric, labor_dev numeric,
               plan_materials numeric, plan_total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; onum text; mat numeric := 0; ph numeric := 0; fh numeric := 0; rate numeric := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.number into onum from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id=ten);
  if onum is null then raise exception 'Заказ не найден'; return; end if;

  select coalesce(sum(n.plan_hours),0), coalesce(sum(n.fact_hours),0) into ph, fh
    from public.app_naryads n where n.order_id = p_order_id and (urole='admin' or n.tenant_id=ten);

  -- Единая ставка — тот же источник, что в app_order_cost: операция.base_rate → центр.cost_hour.
  select coalesce(avg(nullif(coalesce(nullif(o.base_rate,0), wc.cost_hour, 0), 0)), 0) into rate
    from public.app_naryad_ops op
    join public.app_naryads n on n.id = op.naryad_id
    left join public.app_operations o on o.id = op.operation_id
    left join public.app_work_centers wc on wc.id = n.wc_id
    where n.order_id = p_order_id and (urole='admin' or n.tenant_id=ten);

  -- Фолбэк — средняя ставка шагов маршрута (если в нарядах ставок нет).
  if rate = 0 then
    select coalesce(avg(rs.rate_hour),0) into rate
      from public.app_route_steps rs join public.app_routes r on r.id = rs.route_id
      where r.order_id = p_order_id and rs.rate_hour is not null and rs.rate_hour > 0;
  end if;

  -- Материалы — плановые из спецификаций (как и в app_order_cost при отсутствии складских движений).
  select coalesce(sum(bc.materials_cost),0) into mat
    from public.app_bom b
    cross join lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) bc
    where b.order_id = p_order_id and (urole='admin' or b.tenant_id=ten);

  return query select
    onum,
    round(ph,2), round(fh,2), round(fh - ph,2),
    round(rate,2),
    round(ph * rate,2), round(fh * rate,2), round((fh - ph) * rate,2),
    round(mat,2), round(ph * rate + mat,2);
end $$;

grant execute on function public.app_order_cost_plan_fact(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Согласованность себестоимости: план/факт и себестоимость заявки',
   'app_order_cost и app_order_cost_plan_fact используют одну базу ставок: операция.base_rate → рабочий центр.cost_hour (фолбэк — ставка шага маршрута). План/факт труда считаются по общей ставке: plan_labor = план-часы × ставка, fact_labor = факт-часы × ставка, отклонение = (факт−план) × ставка. Материалы — плановые из спецификаций (app_bom_cost).',
   'себестоимость согласованность ставка план факт экономика app_order_cost app_order_cost_plan_fact')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
