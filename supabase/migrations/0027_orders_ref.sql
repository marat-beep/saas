-- ============================================================
-- 3DMP Service · 0027_orders_ref.sql  (v11.0 — переработка «Заявки» как эталон)
-- Заказчики (CRM), расширение заявки: срок, исполнитель, сумма, заказчик.
-- Позиции заявки, связи заявки с документами/нарядами/счетами/маршрутами.
-- Наполнение базы знаний (app_knowledge). Изоляция по tenant. Зависит от 0001..0026.
-- ============================================================

-- ---------- Заказчики (CRM) ----------
create table if not exists public.app_customers (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  name           text not null,
  inn            text,
  contact_person text,
  phone          text,
  email          text,
  address        text,
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists app_customers_tenant_idx on public.app_customers (tenant_id, name);
alter table public.app_customers enable row level security;

-- ---------- Расширение заявки ----------
alter table public.app_orders add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_orders add column if not exists due_date    date;
alter table public.app_orders add column if not exists assignee    text;
alter table public.app_orders add column if not exists amount      numeric;
create index if not exists app_orders_customer_idx on public.app_orders (customer_id);

-- ============================================================
--  CRM: RPC
-- ============================================================
create or replace function public.app_customer_list(p_token uuid)
returns table (id uuid, name text, inn text, contact_person text, phone text, email text, address text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.name, c.inn, c.contact_person, c.phone, c.email, c.address, c.note
    from public.app_customers c where (urole='admin' or c.tenant_id = ten) order by c.name;
end $$;

create or replace function public.app_customer_save(p_token uuid, p_id uuid, p_name text, p_inn text,
  p_contact_person text, p_phone text, p_email text, p_address text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название заказчика'; end if;
  if p_id is null then
    insert into public.app_customers (tenant_id, name, inn, contact_person, phone, email, address, note)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact_person),''),
            nullif(trim(p_phone),''), nullif(trim(p_email),''), nullif(trim(p_address),''), nullif(trim(p_note),''))
    returning app_customers.id into cid;
  else
    update public.app_customers set name=trim(p_name), inn=nullif(trim(p_inn),''), contact_person=nullif(trim(p_contact_person),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), address=nullif(trim(p_address),''), note=nullif(trim(p_note),'')
     where id=p_id and (ten is null or tenant_id=ten) returning app_customers.id into cid;
  end if;
  return query select cid, 'Заказчик сохранён';
end $$;

-- ============================================================
--  Заявки: RPC (переработка)
-- ============================================================
drop function if exists public.app_order_create(uuid,text,text,text,text,text,text);
drop function if exists public.app_order_list(uuid);
drop function if exists public.app_order_get(uuid,uuid);

-- Создать заявку (расширенная).
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null, p_amount numeric default null
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid; cname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, customer_id, contact, priority,
                                 status, due_date, assignee, amount, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  if nullif(trim(p_assignee),'') is not null then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Назначена заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  end if;

  return query select oid, onum;
end $$;

-- Список заявок (расширенный).
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

-- Одна заявка (расширенная).
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.customer_id, c.name,
           o.contact, o.status, o.priority, o.due_date, o.assignee, o.amount,
           o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

-- Изменить заявку.
create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; cname text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_id and (urole='admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки'; return; end if;

  cname := null;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  update public.app_orders set title = trim(p_title), description = nullif(trim(p_description),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), customer_id = p_customer_id,
    customer = coalesce(cname, customer), contact = nullif(trim(p_contact),''), due_date = p_due_date,
    assignee = nullif(trim(p_assignee),''), amount = p_amount, updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

-- ---------- Позиции заявки ----------
create or replace function public.app_order_items_list(p_token uuid, p_order_id uuid)
returns table (id uuid, name text, qty numeric, unit text, price numeric, amount numeric)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select i.id, i.name, i.qty, i.unit, i.price, round(coalesce(i.qty,0)*coalesce(i.price,0),2)
    from public.app_order_items i where i.order_id = p_order_id order by i.id;
end $$;

create or replace function public.app_order_item_add(p_token uuid, p_order_id uuid, p_name text, p_qty numeric, p_unit text, p_price numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; total numeric;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_order_id and (urole='admin' or o.tenant_id = ten)) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование позиции'; return; end if;
  insert into public.app_order_items (order_id, name, qty, unit, price)
  values (p_order_id, trim(p_name), coalesce(p_qty,1), nullif(trim(p_unit),''), p_price);
  select coalesce(sum(coalesce(i.qty,0)*coalesce(i.price,0)),0) into total from public.app_order_items i where i.order_id = p_order_id;
  update public.app_orders o set amount = case when coalesce(o.amount,0) = 0 then total else o.amount end, updated_at = now() where o.id = p_order_id;
  return query select true,'Позиция добавлена';
end $$;

create or replace function public.app_order_item_remove(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; oid uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select i.order_id into oid from public.app_order_items i join public.app_orders o on o.id = i.order_id
    where i.id = p_id and (urole='admin' or o.tenant_id = ten);
  if oid is null then return query select false,'Позиция не найдена'; return; end if;
  delete from public.app_order_items where id = p_id;
  return query select true,'Позиция удалена';
end $$;

-- ---------- Связи заявки ----------
create or replace function public.app_order_docs(p_token uuid, p_order_id uuid)
returns table (id uuid, doc_type text, number text, title text, status text, amount numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.status, d.amount, d.created_at
    from public.app_documents d where d.order_id = p_order_id and (urole='admin' or d.tenant_id = ten)
    order by d.created_at desc;
end $$;

create or replace function public.app_order_naryads(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, title text, status text, plan_hours numeric, fact_hours numeric, route_number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.status, n.plan_hours, n.fact_hours, r.number
    from public.app_naryads n left join public.app_routes r on r.id = n.route_id
    where n.order_id = p_order_id and (urole='admin' or n.tenant_id = ten)
    order by n.created_at desc;
end $$;

create or replace function public.app_order_invoices(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, amount numeric, status text, due_date date)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select i.id, i.number, i.amount, i.status, i.due_date
    from public.app_invoices i where i.order_id = p_order_id and (urole='admin' or i.tenant_id = ten)
    order by i.created_at desc;
end $$;

create or replace function public.app_order_routes(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, name text, status text, total_min numeric, total_cost numeric)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.number, r.name, r.status, r.total_min, r.total_cost
    from public.app_routes r where r.order_id = p_order_id and (urole='admin' or r.tenant_id = ten)
    order by r.created_at desc;
end $$;

grant execute on function public.app_customer_list(uuid) to anon, authenticated;
grant execute on function public.app_customer_save(uuid,uuid,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric) to anon, authenticated;
grant execute on function public.app_order_list(uuid) to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric) to anon, authenticated;
grant execute on function public.app_order_items_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_item_add(uuid,uuid,text,numeric,text,numeric) to anon, authenticated;
grant execute on function public.app_order_item_remove(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_docs(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_naryads(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_invoices(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_routes(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо-заказчики (тенант A)
-- ============================================================
insert into public.app_customers (tenant_id, name, inn, contact_person, phone, email, address)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.inn, v.cp, v.phone, v.email, v.addr
from (values
  ('ООО «ТехноМаш»', '7701234567', 'Иванов И.И.', '+7 495 111-22-33', 'zakaz@technomash.ru', 'г. Москва, ул. Заводская, 1'),
  ('АО «АвиаДеталь»', '7809876543', 'Петрова А.С.', '+7 812 222-33-44', 'sales@aviadetal.ru', 'г. Санкт-Петербург, пр. Металлистов, 10'),
  ('ООО «ЭнергоРемонт»', '5022334455', 'Сидоров П.П.', '+7 916 555-66-77', 'info@energoremont.ru', 'г. Подольск, ул. Ремонтная, 5')
) as v(name,inn,cp,phone,email,addr)
where not exists (select 1 from public.app_customers where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001');

-- ============================================================
--  База знаний: описания модуля «Заявки» (тенант A)
-- ============================================================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Заявки','Как создать заявку и что заполнить?',
   'Откройте модуль «Заявки» → «Новая заявка». Обязательно: тема. Рекомендуется: заказчик (из CRM), источник, срок, приоритет, исполнитель, сумма и описание. Заявка получает номер REQ-NNNNN и попадает в общий список; ответственным приходит уведомление.',
   'заявка создать требования поля'),
  ('Заявки','Что такое заказчик в CRM и как он связан с заявкой?',
   'Заказчик (модуль «Заявки», блок CRM) — карточка контрагента: название, ИНН, контактное лицо, телефон, e-mail, адрес. При создании заявки выбирается заказчик; заявка хранит и ссылку на карточку, и имя. Это основа для КП, договора и счёта.',
   'заказчик CRM контрагент связь'),
  ('Заявки','Как заявка связана с КП, договором, счётом и нарядом?',
   'Карточка заявки показывает связанные сущности: документы (КП/договор/акт, модуль «Документы»), счета (модуль «Финансы»), наряды и маршруты (модули «Производство» и «Справочники»). Связь по заявке: документ/счёт/наряд создаются с указанием заявки. Это единый сквозной поток: заявка → КП → договор → наряд → счёт → оплата.',
   'заявка связи КП договор счет наряд маршрут поток'),
  ('Заявки','Приоритеты и сроки заявок',
   'Приоритет: низкий / обычный / высокий. Срок (план-дата) задаётся вручную и используется планированием и нарядами. Просрочку смотрите фильтрами и в KPI. Для срочных заказов ставьте высокий приоритет — он виден мастеру и в диспетчерской.',
   'приоритет срок дедлайн планирование'),
  ('Система','Роли и доступ в модуле «Заявки»',
   'Директор/владелец и администратор видят все заявки организации; начальник цеха, мастер, технолог, снабженец, экономист — видят заявки организации; рядовой пользователь — только свои созданные. Все данные изолированы по организации (tenant).',
   'роли доступ права заявки организация')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Заявки');
