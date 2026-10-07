-- ============================================================
-- 3DMP Service · 0138_quality_reports.sql  (M3 — Качество: отчёты ОТК и претензий)
-- Отчёт по проверкам ОТК и по претензиям/CAPA за период. Идемпотентно. Зависит от 0001..0137.
-- ============================================================

drop function if exists public.app_qc_report(uuid,date,date);
create or replace function public.app_qc_report(p_token uuid, p_from date default null, p_to date default null)
returns table (number text, product text, status text, inspector text, checked_at timestamptz, created_at timestamptz, defects bigint)
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
    select c.number, c.product, c.status, c.inspector, c.checked_at, c.created_at,
           (select count(*) from public.app_qc_lines l where l.check_id = c.id and l.result = 'no')
      from public.app_qc_checks c
     where (urole='admin' or c.tenant_id = ten)
       and c.created_at::date between d1 and d2
     order by c.created_at desc;
end $$;

drop function if exists public.app_claims_report(uuid,date,date);
create or replace function public.app_claims_report(p_token uuid, p_from date default null, p_to date default null)
returns table (number text, customer text, product text, reason text, severity text, status text, created_at timestamptz,
               capa_total bigint, capa_done bigint)
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
    select cl.number, cl.customer, cl.product, cl.reason, cl.severity, cl.status, cl.created_at,
           (select count(*) from public.app_capa_actions a where a.claim_id = cl.id),
           (select count(*) from public.app_capa_actions a where a.claim_id = cl.id and a.status in ('done','verified'))
      from public.app_claims cl
     where (urole='admin' or cl.tenant_id = ten)
       and cl.created_at::date between d1 and d2
     order by cl.created_at desc;
end $$;

grant execute on function public.app_qc_report(uuid,date,date)       to anon, authenticated;
grant execute on function public.app_claims_report(uuid,date,date)   to anon, authenticated;
