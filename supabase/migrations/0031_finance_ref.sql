-- ============================================================
-- 3DMP Service · 0031_finance_ref.sql  (v14.0 — переработка «Финансы»)
-- Счета и оплаты: CRM-заказчик, связь с договором (документ), исполнитель,
-- остаток, просрочка. Карточка счёта. База знаний. Изоляция по tenant.
-- Зависит от 0001..0030.
-- ============================================================

alter table public.app_invoices add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_invoices add column if not exists document_id uuid references public.app_documents (id) on delete set null;
alter table public.app_invoices add column if not exists assignee text;
create index if not exists app_invoices_customer_idx on public.app_invoices (customer_id);

-- ---------- Список счетов (расширенный) ----------
drop function if exists public.app_invoice_list(uuid);
create or replace function public.app_invoice_list(p_token uuid)
returns table (id uuid, number text, customer text, customer_id uuid, customer_name text,
               order_id uuid, order_number text, document_id uuid, document_number text,
               amount numeric, paid numeric, balance numeric, status text, due_date date, assignee text,
               is_overdue boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, i.customer_id, c.name, i.order_id, o.number, i.document_id, d.number,
           i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.assignee,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue')),
           i.created_at
    from public.app_invoices i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_customers c on c.id = i.customer_id
    left join public.app_documents d on d.id = i.document_id
    where (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

-- ---------- Карточка счёта ----------
create or replace function public.app_invoice_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, customer text, customer_id uuid, customer_name text,
               order_id uuid, order_number text, document_id uuid, document_number text,
               amount numeric, paid numeric, balance numeric, status text, due_date date, assignee text,
               is_overdue boolean, note text, created_login text, created_at timestamptz, paid_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, i.number, i.customer, i.customer_id, c.name, i.order_id, o.number, i.document_id, d.number,
           i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date, i.assignee,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue')),
           i.note, i.created_login, i.created_at, i.paid_at
    from public.app_invoices i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_customers c on c.id = i.customer_id
    left join public.app_documents d on d.id = i.document_id
    where i.id = p_id and (urole='admin' or i.tenant_id = ten);
end $$;

-- ---------- Создание счёта ----------
drop function if exists public.app_invoice_create(uuid,uuid,text,numeric,date,text);
create or replace function public.app_invoice_create(p_token uuid, p_order_id uuid, p_customer text, p_amount numeric, p_due_date date, p_note text,
  p_customer_id uuid default null, p_document_id uuid default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; iid uuid; inum text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, customer_id, document_id, amount, status, due_date, assignee, note, created_by, created_login)
  values (ten, inum, p_order_id, coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, p_document_id, p_amount, 'draft',
          p_due_date, nullif(trim(p_assignee),''), nullif(trim(p_note),''), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum;
end $$;

-- ---------- Статус счёта (с уведомлением) ----------
create or replace function public.app_invoice_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; inum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select i.number into inum from public.app_invoices i where i.id = p_id and (urole='admin' or i.tenant_id = ten);
  if inum is null then return query select false,'Счёт не найден'; return; end if;
  update public.app_invoices set status = p_status, paid_at = case when p_status='paid' then now() else paid_at end where id = p_id;
  if p_status = 'sent' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','economist'], 'Счёт ' || inum || ' выставлен', 'Отправил: ' || coalesce(ulogin,''), 'apps/finance/index.html');
  end if;
  return query select true,'Статус счёта обновлён';
end $$;

grant execute on function public.app_invoice_list(uuid) to anon, authenticated;
grant execute on function public.app_invoice_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_invoice_create(uuid,uuid,text,numeric,date,text,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_invoice_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: финансы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Финансы','Как выставить счёт и связать с заявкой/договором?',
   'В модуле «Финансы» нажмите «Новый счёт»: выберите заявку и заказчика (CRM), укажите сумму, срок и (при наличии) договор. Счёт получит номер INV-NNNNN. В карточке заявки и документа он появится в связях. Статус: черновик → отправлен → оплачен.',
   'счет выставление заявка договор CRM INV'),
  ('Финансы','Как учитываются частичные оплаты и дебиторка?',
   'Каждый платёж (наличные/банк/карта) уменьшает остаток счёта. Остаток = сумма − оплачено. Когда оплачено не меньше суммы, счёт автоматически становится «Оплачен». Дебиторка — это счета со статусом «Отправлен/Просрочен»; просрочка — если срок прошёл, а оплата не полная.',
   'оплата частичная дебиторка остаток просрочка'),
  ('Финансы','Что видно в KPI финансов?',
   'Плитки: количество счетов, сумма выставлено, оплачено, дебиторка (к взысканию) и число просроченных. Эти показатели — основа аналитики (модуль «Аналитика») и отчётов.',
   'KPI финансы дебиторка выставлено оплачено')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Финансы');
