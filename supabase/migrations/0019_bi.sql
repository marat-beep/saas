-- ============================================================
-- 3DMP Service · 0019_bi.sql  (v4.0 — аналитика/BI)
-- Агрегаты для дашбордов (платежи по месяцам, счета/заявки/наряды по статусам).
-- Изоляция по tenant. Зависит от 0001..0018.
-- ============================================================

create or replace function public.app_bi(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; res jsonb;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  select jsonb_build_object(
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object('m', t.m, 'sum', t.s) order by t.m)
      from (
        select to_char(date_trunc('month', p.created_at), 'YYYY-MM') as m, sum(p.amount) as s
        from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
        where (urole='admin' or i.tenant_id = ten) and p.created_at >= now() - interval '6 months'
        group by 1
      ) t), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt, 'sum', t.s))
      from (
        select status, count(*) as cnt, coalesce(sum(amount),0) as s
        from public.app_invoices where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (
        select status, count(*) as cnt from public.app_orders where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb),
    'naryads', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (
        select status, count(*) as cnt from public.app_naryads where (urole='admin' or tenant_id = ten) group by status
      ) t), '[]'::jsonb)
  ) into res;

  return res;
end $$;

grant execute on function public.app_bi(uuid) to anon, authenticated;
