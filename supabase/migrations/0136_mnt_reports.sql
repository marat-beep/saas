-- ============================================================
-- 3DMP Service · 0136_mnt_reports.sql  (M1 — ТОиР: отчёты и KPI по видам)
-- Отчёт по работам ТОиР за период и сводка по видам работ.
-- Идемпотентно. Зависит от 0001..0135.
-- ============================================================

drop function if exists public.app_mnt_report(uuid,date,date);
create or replace function public.app_mnt_report(p_token uuid, p_from date default null, p_to date default null)
returns table (work_date date, equipment text, kind text, works text, replaced text, executor text, cost numeric, part_cost numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; d1 date; d2 date;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  d1 := coalesce(p_from, current_date - 90); d2 := coalesce(p_to, current_date);
  return query
    select l.work_date, e.name, l.kind, l.works, l.replaced, l.executor, l.cost, l.part_cost
      from public.app_mnt_log l
      left join public.app_equipment e on e.id = l.equipment_id
     where (urole='admin' or l.tenant_id = ten)
       and coalesce(l.work_date, l.created_at::date) between d1 and d2
     order by coalesce(l.work_date, l.created_at::date) desc;
end $$;

drop function if exists public.app_mnt_kpi_kinds(uuid);
create or replace function public.app_mnt_kpi_kinds(p_token uuid)
returns table (kind text, cnt bigint, cost numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(l.kind,'—'), count(*), coalesce(sum(coalesce(l.cost,0)+coalesce(l.part_cost,0)),0)
      from public.app_mnt_log l
     where (urole='admin' or l.tenant_id = ten)
     group by coalesce(l.kind,'—')
     order by count(*) desc;
end $$;

grant execute on function public.app_mnt_report(uuid,date,date)   to anon, authenticated;
grant execute on function public.app_mnt_kpi_kinds(uuid)          to anon, authenticated;
