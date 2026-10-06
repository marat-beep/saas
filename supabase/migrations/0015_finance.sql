-- ============================================================
-- 3DMP Service · 0015_finance.sql  (v2.2 — финансы)
-- Счета, платежи, взаиморасчёты (дебиторка). Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0014.
-- ============================================================

create sequence if not exists public.app_invoice_seq;

create table if not exists public.app_invoices (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  customer      text,
  amount        numeric not null default 0,
  status        text not null default 'draft',   -- draft | sent | paid | overdue | cancelled
  due_date      date,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  paid_at       timestamptz
);
create index if not exists app_invoices_tenant_idx on public.app_invoices (tenant_id, created_at desc);

create table if not exists public.app_payments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  invoice_id  uuid not null references public.app_invoices (id) on delete cascade,
  amount      numeric not null,
  method      text not null default 'bank',   -- cash | bank | card
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_payments_invoice_idx on public.app_payments (invoice_id, created_at desc);

alter table public.app_invoices enable row level security;
alter table public.app_payments enable row level security;

-- ---------- Счета: список с оплаченной суммой ----------
drop function if exists public.app_invoice_list(uuid);
create or replace function public.app_invoice_list(p_token uuid)
returns table (id uuid, number text, customer text, order_number text, amount numeric, paid numeric,
               status text, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, o.number, i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.created_at
    from public.app_invoices i left join public.app_orders o on o.id = i.order_id
    where (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

create or replace function public.app_invoice_create(p_token uuid, p_order_id uuid, p_customer text, p_amount numeric, p_due_date date, p_note text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; iid uuid; inum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, amount, status, due_date, note, created_by, created_login)
  values (ten, inum, p_order_id, nullif(trim(p_customer),''), p_amount, 'draft', p_due_date, nullif(trim(p_note),''), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum;
end $$;

create or replace function public.app_invoice_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_invoices set status = p_status, paid_at = case when p_status='paid' then now() else paid_at end
   where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус счёта обновлён';
end $$;

-- ---------- Платежи ----------
create or replace function public.app_payment_add(p_token uuid, p_invoice_id uuid, p_amount numeric, p_method text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; urole text; ten uuid; inv public.app_invoices; paid numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into inv from public.app_invoices where id = p_invoice_id and (urole='admin' or tenant_id = ten);
  if inv.id is null then return query select false,'Счёт не найден'; return; end if;
  if coalesce(p_amount,0) <= 0 then return query select false,'Сумма платежа должна быть > 0'; return; end if;

  insert into public.app_payments (tenant_id, invoice_id, amount, method, note, by_login)
  values (inv.tenant_id, inv.id, p_amount, coalesce(nullif(trim(p_method),''),'bank'), nullif(trim(p_note),''), ulogin);

  select coalesce(sum(p.amount),0) into paid from public.app_payments p where p.invoice_id = inv.id;
  if paid >= inv.amount then
    update public.app_invoices set status='paid', paid_at = now() where id = inv.id;
    perform public.app_notif_roles_t(inv.tenant_id, array['admin','manager','owner'], 'Счёт ' || inv.number || ' оплачен',
            to_char(paid,'FM999G999G999G999') || ' ₽', 'apps/finance/index.html');
  end if;
  return query select true,'Платёж добавлен';
end $$;

create or replace function public.app_payment_list(p_token uuid, p_invoice_id uuid)
returns table (id uuid, amount numeric, method text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.amount, p.method, p.note, p.by_login, p.created_at
    from public.app_payments p join public.app_invoices i on i.id = p.invoice_id
    where p.invoice_id = p_invoice_id and (urole='admin' or i.tenant_id = ten)
    order by p.created_at desc;
end $$;

-- ---------- KPI финансов ----------
create or replace function public.app_finance_kpi(p_token uuid)
returns table (invoices_total bigint, sum_total numeric, sum_paid numeric, receivable numeric, overdue bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_invoices i where (urole='admin' or i.tenant_id=ten)),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.status <> 'cancelled'),
    (select coalesce(sum(p.amount),0) from public.app_payments p join public.app_invoices i on i.id=p.invoice_id where (urole='admin' or i.tenant_id=ten)),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.status in ('sent','overdue')),
    (select count(*) from public.app_invoices i where (urole='admin' or i.tenant_id=ten) and i.due_date < current_date and i.status in ('sent','overdue'));
end $$;

grant execute on function public.app_invoice_list(uuid) to anon, authenticated;
grant execute on function public.app_invoice_create(uuid,uuid,text,numeric,date,text) to anon, authenticated;
grant execute on function public.app_invoice_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_payment_add(uuid,uuid,numeric,text,text) to anon, authenticated;
grant execute on function public.app_payment_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_finance_kpi(uuid) to anon, authenticated;

-- ---------- Демо-счёт ----------
insert into public.app_invoices (tenant_id, number, customer, amount, status, due_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'INV-DEMO1', 'ООО «Привод»', 184000, 'sent', (current_date + 10), 'owner'
where not exists (select 1 from public.app_invoices where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
