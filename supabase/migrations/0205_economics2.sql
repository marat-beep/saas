-- ============================================================
-- 3DMP Service · 0205_economics2.sql  (X19 — Экономика/платформа 2.0)
-- Сводный дашборд экономики, MRR по подпискам, матрица квот/лимитов,
-- приём платежа биллинга. Идемпотентно. Зависит от 0001..0204.
-- ============================================================

create or replace function public.app_economics_dashboard(p_token uuid)
returns table (orders_count bigint, invoices_total numeric, invoices_paid numeric, invoices_due numeric,
               cash_in_plan numeric, cash_out_plan numeric, avg_check numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_orders o where adm or o.tenant_id=ten),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where adm or i.tenant_id=ten),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (adm or i.tenant_id=ten) and i.status='paid'),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (adm or i.tenant_id=ten) and i.status in ('sent','overdue')),
    (select coalesce(sum(c.amount),0) from public.app_cash_plan c where (adm or c.tenant_id=ten) and c.kind='in' and c.status in ('planned','overdue')),
    (select coalesce(sum(c.amount),0) from public.app_cash_plan c where (adm or c.tenant_id=ten) and c.kind='out' and c.status in ('planned','overdue')),
    (select round(avg(i.amount),2) from public.app_invoices i where (adm or i.tenant_id=ten));
end $$;

create or replace function public.app_mrr_report(p_token uuid)
returns table (active_subs bigint, mrr numeric, arpu numeric, trial_subs bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_subscriptions s where (adm or s.tenant_id=ten) and s.status='active'),
    (select coalesce(sum(s.amount),0) from public.app_subscriptions s where (adm or s.tenant_id=ten) and s.status='active'),
    (select round(coalesce(avg(s.amount),0),2) from public.app_subscriptions s where (adm or s.tenant_id=ten) and s.status='active'),
    (select count(*) from public.app_subscriptions s where (adm or s.tenant_id=ten) and s.status='trial');
end $$;

create or replace function public.app_quota_matrix(p_token uuid)
returns table (metric text, used numeric, quota numeric, pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; m text; u numeric; q numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  for m in select x from unnest(array['users','storage_mb','api_calls','documents','ai_tokens','orders']) x loop
    u := public.app_quota_used(ten, m);
    q := public.app_quota_limit(ten, m);
    metric := m; used := coalesce(u,0); quota := q; pct := case when coalesce(q,0) > 0 then round(100.0*coalesce(u,0)/q,1) else null end;
    return next;
  end loop;
end $$;

create or replace function public.app_billing_mark_paid(p_token uuid, p_invoice_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'billing') then return query select false,'Нет прав на биллинг'; return; end if;
  select * into r from public.app_invoice_set_status(p_token, p_invoice_id, 'paid') x;
  if r.ok is null then return query select true,'Платёж отмечен'; return; end if;
  return query select r.ok, r.message;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Экономика/платформа 2.0: сводный дашборд, MRR, квоты, приём платежа (X19)',
   'Экономика 2.0: сводный дашборд (app_economics_dashboard — заказы, счета/оплаты/дебиторка, плановые приток/отток, средний чек), MRR по подпискам (app_mrr_report — активные/триал/ARPU), матрица квот/лимитов (app_quota_matrix — пользователи, хранилище, вызовы API, документы, AI-токены, заказы; reuse app_quota_used/limit), приём платежа биллинга (app_billing_mark_paid). Платёжный календарь — app_cash_calendar; факт себестоимости — app_cost_fact; дашборды BI — W41.',
   'экономика финансы MRR подписка квота лимит платёж биллинг дашборд себестоимость календарь')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Экономика/платформа 2.0: сводный дашборд, MRR, квоты, приём платежа (X19)'
);

-- ================= Права =================
grant execute on function public.app_economics_dashboard(uuid) to anon, authenticated;
grant execute on function public.app_mrr_report(uuid) to anon, authenticated;
grant execute on function public.app_quota_matrix(uuid) to anon, authenticated;
grant execute on function public.app_billing_mark_paid(uuid,uuid) to anon, authenticated;
