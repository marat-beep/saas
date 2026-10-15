-- ============================================================
-- 3DMP Service · 0268_credit_atp.sql  (R4 · PROP-22 — кредитный лимит и ATP)
-- Кредитный лимит клиента + проверка (лимит/долг/доступно) и доступность материала (ATP).
-- Идемпотентно.
-- ============================================================

alter table public.app_customers add column if not exists credit_limit numeric not null default 0;

create or replace function public.app_customer_credit(p_token uuid, p_customer_id uuid)
returns table (name text, credit_limit numeric, debt numeric, available numeric, ok boolean)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; cname text; climit numeric; cdebt numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.name, c.credit_limit into cname, climit from public.app_customers c where c.id = p_customer_id limit 1;
  if cname is null then return query select null::text, 0::numeric, 0::numeric, 0::numeric, false; return; end if;
  select coalesce(sum(i.amount), 0) into cdebt from public.app_invoices i where i.customer = cname and coalesce(i.status, '') <> 'paid';
  return query select cname, coalesce(climit, 0), cdebt, coalesce(climit, 0) - cdebt, (coalesce(climit, 0) = 0 or cdebt <= coalesce(climit, 0));
end $$;
grant execute on function public.app_customer_credit(uuid,uuid) to anon, authenticated;

create or replace function public.app_atp(p_token uuid, p_material_id uuid)
returns table (material text, on_hand numeric, available numeric)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; mname text; mqty numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select m.name, m.qty into mname, mqty from public.app_materials m where m.id = p_material_id limit 1;
  if mname is null then return query select null::text, 0::numeric, 0::numeric; return; end if;
  return query select mname, coalesce(mqty, 0), coalesce(mqty, 0);
end $$;
grant execute on function public.app_atp(uuid,uuid) to anon, authenticated;

create or replace function public.app_customer_set_credit(p_token uuid, p_customer_id uuid, p_limit numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_customers set credit_limit = coalesce(p_limit, 0) where id = p_customer_id and (urole = 'admin' or tenant_id = ten or tenant_id is null);
  return query select true, 'Лимит обновлён';
end $$;
grant execute on function public.app_customer_set_credit(uuid,uuid,numeric) to anon, authenticated;
