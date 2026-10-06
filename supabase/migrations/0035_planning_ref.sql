-- ============================================================
-- 3DMP Service · 0035_planning_ref.sql  (v17.0 — переработка «Планирование»)
-- Гант и загрузка центров: связи маршрут/заявка/приоритет, прогресс операций,
-- коррекция бага app_capacity (несуществующий wc.tenant_id). База знаний.
-- Зависит от 0001..0034.
-- ============================================================

-- ---------- Гант: наряды с план-датами (расширено) ----------
drop function if exists public.app_schedule(uuid);
create or replace function public.app_schedule(p_token uuid)
returns table (id uuid, number text, title text, wc_id uuid, wc_name text, assignee text, status text, priority text,
               route_number text, order_number text, ops_total bigint, ops_done bigint,
               plan_start date, plan_end date, due_date date, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.wc_id, w.name, n.assignee, n.status, n.priority,
           r.number, o.number,
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id),
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id and op.done),
           n.plan_start, n.plan_end, n.due_date, n.plan_hours, n.fact_hours
    from public.app_naryads n
    left join public.app_work_centers w on w.id = n.wc_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_orders o on o.id = n.order_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by coalesce(n.plan_start, n.created_at::date), n.created_at;
end $$;

-- ---------- Загрузка рабочих центров (фикс бага wc.tenant_id) ----------
drop function if exists public.app_capacity(uuid);
create or replace function public.app_capacity(p_token uuid)
returns table (wc_id uuid, wc_name text, kind text, cost_hour numeric,
               active_naryads bigint, plan_hours numeric, fact_hours numeric, ops_open bigint, overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.name, w.kind, w.cost_hour,
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten)),
           coalesce((select sum(n.plan_hours) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten)), 0),
           coalesce((select sum(n.fact_hours) from public.app_naryads n where n.wc_id = w.id and (urole='admin' or n.tenant_id = ten)), 0),
           (select count(*) from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
              where n.wc_id = w.id and not op.done and (urole='admin' or n.tenant_id = ten)),
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.due_date is not null and n.due_date < current_date and n.status in ('open','in_progress') and (urole='admin' or n.tenant_id = ten))
    from public.app_work_centers w
    order by w.name;
end $$;

grant execute on function public.app_schedule(uuid) to anon, authenticated;
grant execute on function public.app_capacity(uuid) to anon, authenticated;

-- ---------- База знаний: планирование ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Планирование','Как планировать сроки нарядов (Гант)?',
   'В «Планировании» на вкладке «Гант» задайте план-старт и план-финиш наряда в таблице ниже диаграммы. Полосы показывают длительность, цвет — статус наряда (открыт/в работе/закрыт); видно маршрут, заявку и прогресс операций. Даты используются диспетчерской и напоминаниями.',
   'планирование гант сроки план-старт план-финиш наряд'),
  ('Планирование','Как читать загрузку рабочих центров?',
   'Вкладка «Загрузка» показывает по каждому центру: активные наряды, план и факт нормо-часов, открытые операции и просроченные наряды. Полоса — относительная загрузка. Так видно «узкие места» и куда перераспределить работы.',
   'загрузка рабочий центр нормочасы операции просрочка узкое место')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Планирование');
