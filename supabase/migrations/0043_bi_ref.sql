-- ============================================================
-- 3DMP Service · 0043_bi_ref.sql  (v25.0 — переработка «Аналитика/BI»)
-- Обогащённые агрегаты: оплаты, счета, заявки (статус/тип), наряды, производство
-- план/факт, качество, закупки, склад, экономика. База знаний. Зависит от 0001..0042.
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
      from (select to_char(date_trunc('month', p.created_at), 'YYYY-MM') as m, sum(p.amount) as s
            from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
            where (urole='admin' or i.tenant_id = ten) and p.created_at >= now() - interval '6 months'
            group by 1) t), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt, 'sum', t.s))
      from (select status, count(*) cnt, coalesce(sum(amount),0) s from public.app_invoices where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_orders where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'orders_type', coalesce((
      select jsonb_agg(jsonb_build_object('type', t.ot, 'count', t.cnt))
      from (select coalesce(order_type,'single') ot, count(*) cnt from public.app_orders where (urole='admin' or tenant_id=ten) group by 1) t), '[]'::jsonb),
    'naryads', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_naryads where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'production', coalesce((
      select jsonb_agg(jsonb_build_object('wc', t.wc, 'plan', t.plan, 'fact', t.fact) order by t.wc)
      from (select w.name wc, coalesce(sum(n.plan_hours),0) plan, coalesce(sum(n.fact_hours),0) fact
            from public.app_naryads n left join public.app_work_centers w on w.id = n.wc_id
            where (urole='admin' or n.tenant_id=ten) group by w.name) t), '[]'::jsonb),
    'quality', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.app_qc_checks where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'procurement', coalesce((
      select jsonb_agg(jsonb_build_object('status', t.status, 'count', t.cnt))
      from (select status, count(*) cnt from public.tenders where (urole='admin' or tenant_id=ten) group by status) t), '[]'::jsonb),
    'warehouse', jsonb_build_object(
      'low', (select count(*) from public.app_materials m where m.qty < m.min_qty and (urole='admin' or m.tenant_id=ten)),
      'stock_value', (select coalesce(round(sum(m.qty*m.price),2),0) from public.app_materials m where (urole='admin' or m.tenant_id=ten))),
    'economics', jsonb_build_object(
      'amount', (select coalesce(sum(o.amount),0) from public.app_orders o where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'),
      'cost', (select coalesce(round(sum(c.total),2),0) from public.app_orders o, lateral public.app_order_cost(p_token, o.id) c where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'),
      'margin', (select coalesce(round(sum(c.margin),2),0) from public.app_orders o, lateral public.app_order_cost(p_token, o.id) c where (urole='admin' or o.tenant_id=ten) and o.status<>'cancelled'))
  ) into res;

  return res;
end $$;

grant execute on function public.app_bi(uuid) to anon, authenticated;

-- ---------- База знаний: аналитика ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Аналитика','Что показывает аналитика (BI)?',
   'Аналитика собирает данные всех модулей в дашборд: оплаты по месяцам, счета по статусам, заявки (по статусам и типам), наряды, производство (план/факт по центрам), качество (годен/брак), закупки, склад (стоимость запаса, нехватка) и экономику (сумма/себестоимость/маржа).',
   'аналитика BI дашборд графики KPI свод'),
  ('Отчёты','Как выгрузить отчёт в PDF/DOC/CSV/JSON?',
   'В «Отчётах» выберите набор данных (заявки, наряды, закупки, склад, паспорта, счета, экономика, ОТК), задайте заголовок и период, затем выгрузите: CSV/JSON — данные, DOC/PDF — оформленный отчёт с шапкой, KPI и подписью. Есть сводный отчёт KPI за период.',
   'отчёты экспорт PDF DOC CSV JSON печать сводный')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Аналитика');
