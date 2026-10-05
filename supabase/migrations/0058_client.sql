-- ============================================================
-- 3DMP Service · 0058_client.sql  (v36.2 — ЭПИК A: кабинет заказчика, прототип A3)
-- Роль `client` (внешний заказчик): привязка к заказчику + read-проекции
-- (заявки, документы, счета, ТКП). База знаний. Зависит от 0001..0057.
-- ============================================================

create table if not exists public.app_client_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  app_user_id uuid references public.app_users (id) on delete cascade,
  customer_id uuid references public.app_customers (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (app_user_id, customer_id)
);
create index if not exists app_client_links_idx on public.app_client_links (app_user_id);
alter table public.app_client_links enable row level security;

-- ---------- Контекст клиента ----------
create or replace function public.app_client_context(p_token uuid)
returns table (customer_id uuid, customer text, tenant_name text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select l.customer_id, c.name, t.name
    from public.app_client_links l
    join public.app_customers c on c.id = l.customer_id
    left join public.tenants t on t.id = l.tenant_id
    where l.app_user_id = uid;
end $$;

-- ---------- Заявки клиента ----------
create or replace function public.app_client_orders(p_token uuid)
returns table (number text, title text, status text, priority text, due_date date, amount numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select o.number, o.title, o.status, o.priority, o.due_date, o.amount, o.created_at
    from public.app_orders o
    where o.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by o.created_at desc;
end $$;

-- ---------- Документы клиента ----------
create or replace function public.app_client_docs(p_token uuid)
returns table (number text, doc_type text, title text, status text, amount numeric, valid_until date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select d.number, d.doc_type, d.title, d.status, d.amount, d.valid_until, d.created_at
    from public.app_documents d
    where d.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by d.created_at desc;
end $$;

-- ---------- Счета клиента ----------
create or replace function public.app_client_invoices(p_token uuid)
returns table (number text, amount numeric, paid numeric, balance numeric, status text, due_date date, is_overdue boolean)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select i.number, i.amount,
           coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.amount - coalesce((select sum(p.amount) from public.app_payments p where p.invoice_id = i.id),0),
           i.status, i.due_date,
           (i.due_date is not null and i.due_date < current_date and i.status in ('sent','overdue'))
    from public.app_invoices i
    where i.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by i.created_at desc;
end $$;

-- ---------- ТКП клиента ----------
create or replace function public.app_client_tkp(p_token uuid)
returns table (number text, subject text, valid_until date, price numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'client' and urole <> 'admin' then raise exception 'Доступ только для заказчика'; end if;
  return query
    select t.number, t.subject, t.valid_until, t.price, t.status, t.created_at
    from public.app_tkp_registry t
    where t.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
    order by t.created_at desc;
end $$;

grant execute on function public.app_client_context(uuid) to anon, authenticated;
grant execute on function public.app_client_orders(uuid) to anon, authenticated;
grant execute on function public.app_client_docs(uuid) to anon, authenticated;
grant execute on function public.app_client_invoices(uuid) to anon, authenticated;
grant execute on function public.app_client_tkp(uuid) to anon, authenticated;

-- ---------- Демо: клиентский доступ (тенант A) ----------
insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values ('client', extensions.crypt('client', extensions.gen_salt('bf')), 'Клиент (портал)', 'client', 'aaaaaaaa-0000-0000-0000-000000000001')
on conflict (login) do update set role='client', tenant_id=excluded.tenant_id, full_name=excluded.full_name;

insert into public.app_client_links (tenant_id, app_user_id, customer_id)
select 'aaaaaaaa-0000-0000-0000-000000000001', u.id, c.id
from public.app_users u, public.app_customers c
where u.login='client'
  and c.id = (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1)
  and not exists (select 1 from public.app_client_links where app_user_id=u.id and customer_id=c.id);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кабинет заказчика','Как клиент видит свои заказы?',
   'Внешний заказчик входит под ролью client и видит только свои данные: заявки (статусы, суммы, сроки), документы (КП/договор/акт), счета (оплачено/остаток/просрочка) и ТКП. Доступ привязан к карточке заказчика (CRM) через связку «пользователь ↔ заказчик».',
   'кабинет заказчика client роль заявки документы счета ТКП портал')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как клиент видит свои заказы?');
