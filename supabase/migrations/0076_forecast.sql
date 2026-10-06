-- ============================================================
-- 3DMP Service · 0076_forecast.sql  (v54 — Сессия F: B39 «Прогноз загрузки»)
-- Прогноз по существующим данным: загрузка по дням (план часы открытых нарядов
-- vs мощность слотов), ETA по нарядам/заказам, риск просрочки. Новых таблиц нет.
-- База знаний. Зависит от 0001..0075.
-- ============================================================

create or replace function public.app_forecast_load(p_token uuid, p_days int default 14)
returns table (day date, planned numeric, capacity numeric, load_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  n := greatest(1, least(coalesce(p_days,14), 90));
  return query
    with days as (
      select generate_series(current_date, current_date + (n-1), interval '1 day')::date as d
    )
    select d,
      (select coalesce(sum(greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0)),0)
         from public.app_naryads na
        where (urole='admin' or na.tenant_id=ten)
          and na.status not in ('done','closed','cancelled')
          and coalesce(na.plan_end, na.due_date, current_date) = d),
      (select coalesce(sum(w.capacity_hours),0) from public.app_work_slots w
        where (urole='admin' or w.tenant_id=ten) and w.slot_date = d),
      round( 100.0 * (select coalesce(sum(greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0)),0)
                        from public.app_naryads na
                       where (urole='admin' or na.tenant_id=ten)
                         and na.status not in ('done','closed','cancelled')
                         and coalesce(na.plan_end, na.due_date, current_date) = d)
             / greatest((select coalesce(sum(w.capacity_hours),0) from public.app_work_slots w
                          where (urole='admin' or w.tenant_id=ten) and w.slot_date = d), 1), 1)
    from days order by d;
end $$;

create or replace function public.app_forecast_orders(p_token uuid, p_limit int default 50)
returns table (id uuid, number text, title text, center text, order_number text, remaining numeric,
               avg_daily_capacity numeric, eta_days int, eta_date date, due_date date, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; avg_cap numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(avg(cap),8) into avg_cap from (
    select w.slot_date, sum(w.capacity_hours) cap from public.app_work_slots w
     where (urole='admin' or w.tenant_id=ten) and w.slot_date >= current_date
     group by w.slot_date) t;
  avg_cap := greatest(coalesce(avg_cap,8),1);
  return query
    select na.id, na.number, na.title,
      (select wc.name from public.app_work_centers wc where wc.id=na.wc_id),
      (select o.number from public.app_orders o where o.id=na.order_id),
      round(rem.h,1),
      round(avg_cap,1),
      ceil(rem.h / avg_cap)::int,
      current_date + ceil(rem.h / avg_cap)::int,
      na.due_date,
      case
        when na.due_date is not null and na.due_date < current_date then 'просрочен'
        when na.due_date is not null and na.due_date < current_date + ceil(rem.h / avg_cap)::int then 'риск'
        else 'норма' end
    from public.app_naryads na
    cross join lateral (select greatest(coalesce(na.plan_hours,0) - coalesce(na.fact_hours,0),0) as h) rem
    where (urole='admin' or na.tenant_id=ten) and na.status not in ('done','closed','cancelled')
    order by (case when na.due_date is not null and na.due_date < current_date then 0 else 1 end), eta_days desc
    limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

create or replace function public.app_forecast_kpi(p_token uuid)
returns table (open_naryads bigint, open_hours numeric, avg_daily_capacity numeric, avg_load_pct numeric, overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cap numeric; usd numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(sum(capacity_hours),0), coalesce(sum(used_hours),0) into cap, usd
    from public.app_work_slots where (urole='admin' or tenant_id=ten) and slot_date between current_date and current_date + 14;
  return query select
    (select count(*) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled')),
    (select coalesce(sum(greatest(coalesce(plan_hours,0)-coalesce(fact_hours,0),0)),0) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled')),
    round(cap/14.0,1),
    round(case when cap>0 then usd/cap*100 else 0 end,1),
    (select count(*) from public.app_naryads where (urole='admin' or tenant_id=ten) and status not in ('done','closed','cancelled') and due_date is not null and due_date < current_date);
end $$;

grant execute on function public.app_forecast_load(uuid,int) to anon, authenticated;
grant execute on function public.app_forecast_orders(uuid,int) to anon, authenticated;
grant execute on function public.app_forecast_kpi(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Прогноз загрузки (B39)',
   'Модуль «Прогноз загрузки»: расчёт по существующим данным — загрузка по дням (план-часы открытых нарядов против мощности слотов), ETA по нарядам/заказам (остаток часов ÷ средняя дневная мощность) и риск просрочки (сравнение ETA с due_date). Помогает выравнивать загрузку и предупреждать срывы сроков.',
   'прогноз загрузка ETA сроки ёмкость слоты план-факт риск просрочка B39')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Прогноз загрузки (B39)');
