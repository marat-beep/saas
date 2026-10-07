-- ============================================================
-- 3DMP Service · 0114_order_cost.sql  (v135 — Экономика: себестоимость «план/факт»)
-- Сравнение плана и факта по заказу: часы нарядов (plan/fact), средняя ставка
-- по маршрутам, стоимость труда; отклонения. Материалы — плановые из спецификаций.
-- Идемпотентно. Зависит от 0001..0113.
-- ============================================================

create or replace function public.app_order_cost_plan_fact(p_token uuid, p_order_id uuid)
returns table (order_number text, plan_hours numeric, fact_hours numeric, hours_dev numeric,
               rate_avg numeric, plan_labor numeric, fact_labor numeric, labor_dev numeric,
               plan_materials numeric, plan_total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; onum text; mat numeric := 0; work numeric := 0; tot numeric := 0;
        ph numeric := 0; fh numeric := 0; rate numeric := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.number into onum from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id=ten);
  if onum is null then raise exception 'Заказ не найден'; return; end if;

  select coalesce(sum(bc.materials_cost),0), coalesce(sum(bc.work_cost),0), coalesce(sum(bc.total),0)
    into mat, work, tot
    from public.app_bom b
    cross join lateral public.app_bom_cost(p_token, b.id, coalesce(b.qty,1)) bc
    where b.order_id = p_order_id and (urole='admin' or b.tenant_id=ten);

  select coalesce(sum(n.plan_hours),0), coalesce(sum(n.fact_hours),0) into ph, fh
    from public.app_naryads n where n.order_id = p_order_id and (urole='admin' or n.tenant_id=ten);

  select coalesce(avg(rs.rate_hour),0) into rate
    from public.app_route_steps rs join public.app_routes r on r.id = rs.route_id
    where r.order_id = p_order_id and rs.rate_hour is not null and rs.rate_hour > 0;
  if rate is null or rate = 0 then rate := case when ph > 0 then work / ph else 0 end; end if;

  return query select
    onum,
    round(ph,2), round(fh,2), round(fh - ph,2),
    round(rate,2),
    round(work,2), round(fh * rate,2), round(fh * rate - work,2),
    round(mat,2), round(tot,2);
end $$;

grant execute on function public.app_order_cost_plan_fact(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Себестоимость по заказу: план и факт',
   'app_order_cost_plan_fact сравнивает план и факт по заказу: плановые часы нарядов и фактические (fact_hours), средняя ставка по маршрутам, стоимость труда; материалы/итог — плановые из спецификаций (app_bom_cost). Отклонения показывают перерасход/экономию. Открывается в модуле «Экономика».',
   'себестоимость план факт заказ наряды часы ставка отклонение экономика')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Себестоимость по заказу: план и факт');
