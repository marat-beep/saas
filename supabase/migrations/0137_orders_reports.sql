-- ============================================================
-- 3DMP Service · 0137_orders_reports.sql  (M2 — Заказы: отчёт и KPI)
-- Отчёт по заказам за период и расширенные KPI. Идемпотентно. Зависит от 0001..0136.
-- ============================================================

drop function if exists public.app_order_report(uuid,date,date);
create or replace function public.app_order_report(p_token uuid, p_from date default null, p_to date default null)
returns table (number text, customer text, title text, status text, priority text, order_type text,
               due_date date, assignee text, amount numeric, created_at timestamptz)
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
    select o.number, coalesce(c.name, o.customer), o.title, o.status, o.priority, o.order_type,
           o.due_date, o.assignee, o.amount, o.created_at
      from public.app_orders o
      left join public.app_customers c on c.id = o.customer_id
     where (urole='admin' or o.tenant_id = ten)
       and o.created_at::date between d1 and d2
     order by o.created_at desc;
end $$;

drop function if exists public.app_order_kpi_ext(uuid);
create or replace function public.app_order_kpi_ext(p_token uuid)
returns table (total bigint, amount_sum numeric, overdue bigint, done_month bigint, avg_lead_days numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select count(*),
           coalesce(sum(amount),0),
           count(*) filter (where due_date is not null and due_date < current_date and status not in ('done','cancelled')),
           count(*) filter (where status='done' and updated_at::date >= date_trunc('month', current_date)::date),
           round(avg(extract(epoch from (updated_at - created_at))/86400.0) filter (where status='done'), 1)
      from public.app_orders o
     where (urole='admin' or o.tenant_id = ten);
end $$;

grant execute on function public.app_order_report(uuid,date,date)   to anon, authenticated;
grant execute on function public.app_order_kpi_ext(uuid)            to anon, authenticated;
