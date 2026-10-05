-- ============================================================
-- 3DMP Service · 0011_planning.sql  (v1.6 — планирование)
-- План-даты нарядов, диаграмма Ганта, загрузка рабочих центров.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0010.
-- ============================================================

alter table public.app_naryads add column if not exists plan_start date;
alter table public.app_naryads add column if not exists plan_end date;

-- демо: проставить план-даты существующим нарядам
update public.app_naryads set plan_start = created_at::date, plan_end = (created_at::date + 3)
 where plan_start is null;

create index if not exists app_naryads_plan_idx on public.app_naryads (plan_start, plan_end);

-- ---------- Гант: наряды с план-датами ----------
create or replace function public.app_schedule(p_token uuid)
returns table (id uuid, number text, title text, wc_name text, assignee text, status text,
               plan_start date, plan_end date, due_date date, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, w.name, n.assignee, n.status,
           n.plan_start, n.plan_end, n.due_date, n.plan_hours, n.fact_hours
    from public.app_naryads n
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by coalesce(n.plan_start, n.created_at::date), n.created_at;
end $$;

-- ---------- Загрузка рабочих центров ----------
create or replace function public.app_capacity(p_token uuid)
returns table (wc_id uuid, wc_name text, kind text, cost_hour numeric,
               active_naryads bigint, plan_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.name, w.kind, w.cost_hour,
           (select count(*) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress')),
           coalesce((select sum(n.plan_hours) from public.app_naryads n where n.wc_id = w.id and n.status in ('open','in_progress')), 0),
           coalesce((select sum(n.fact_hours) from public.app_naryads n where n.wc_id = w.id), 0)
    from public.app_work_centers w
    where (urole = 'admin' or w.tenant_id = ten)
    order by w.name;
end $$;

-- ---------- Назначить план-даты наряду ----------
create or replace function public.app_naryad_schedule(p_token uuid, p_id uuid, p_start date, p_end date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_naryads set plan_start = p_start, plan_end = p_end, updated_at = now()
   where id = p_id
     and (urole = 'admin' or tenant_id = ten)
     and (p_end is null or p_start is null or p_end >= p_start);
  return query select true,'Сроки обновлены';
end $$;

grant execute on function public.app_schedule(uuid) to anon, authenticated;
grant execute on function public.app_capacity(uuid) to anon, authenticated;
grant execute on function public.app_naryad_schedule(uuid,uuid,date,date) to anon, authenticated;
