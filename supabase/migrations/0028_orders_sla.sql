-- ============================================================
-- 3DMP Service · 0028_orders_sla.sql  (v11.1 — типы заказов и SLA)
-- Тип заказа (единичный/серийный/оснастка/инжиниринг) и уведомления о просрочке.
-- Изоляция по tenant. Зависит от 0001..0027.
-- ============================================================

alter table public.app_orders add column if not exists order_type text not null default 'single'; -- single|batch|tooling|engineering
alter table public.app_orders add column if not exists overdue_notified_at timestamptz;

-- ---------- Создать заявку (с типом) ----------
drop function if exists public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric);
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null,
  p_amount numeric default null, p_order_type text default 'single'
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
                                 status, due_date, assignee, amount, order_type, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, coalesce(nullif(trim(p_order_type),''),'single'), ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

-- ---------- Список заявок (с типом) ----------
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text,
               due_date date, assignee text, amount numeric, order_type text,
               created_login text, created_at timestamptz, updated_at timestamptz)
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
           o.due_date, o.assignee, o.amount, o.order_type, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

-- ---------- Одна заявка (с типом) ----------
drop function if exists public.app_order_get(uuid,uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, customer_id uuid, customer_name text,
               contact text, status text, priority text, due_date date, assignee text, amount numeric, order_type text,
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
           o.contact, o.status, o.priority, o.due_date, o.assignee, o.amount, o.order_type,
           o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

-- ---------- Изменить заявку (с типом) ----------
drop function if exists public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric);
create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric, p_order_type text)
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
    assignee = nullif(trim(p_assignee),''), amount = p_amount,
    order_type = coalesce(nullif(trim(p_order_type),''), order_type), updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

-- ---------- SLA: уведомления о просрочке (однократно на заявку) ----------
create or replace function public.app_order_sla_check(p_token uuid)
returns table (notified bigint)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; n bigint;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select 0::bigint; return; end if;
  ten := public.app_my_tenant(p_token);
  with ov as (
    update public.app_orders o
       set overdue_notified_at = now()
     where (urole = 'admin' or o.tenant_id = ten)
       and o.due_date is not null and o.due_date < current_date
       and o.status not in ('done','cancelled')
       and o.overdue_notified_at is null
    returning o.number, o.title, o.tenant_id
  ), ins as (
    insert into public.app_notifications (user_id, title, body, link)
    select u.id, 'Просрочена заявка ' || ov.number, ov.title, 'apps/orders/index.html'
    from ov join public.app_users u
      on u.active and u.role in ('admin','manager','owner') and (ov.tenant_id is null or u.tenant_id = ov.tenant_id)
    returning 1
  )
  select count(*) into n from ins;
  return query select n;
end $$;

grant execute on function public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_order_list(uuid) to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_update(uuid,uuid,text,text,text,uuid,text,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_order_sla_check(uuid) to anon, authenticated;

-- ---------- База знаний: типы заказов и SLA ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Заявки','Типы заказов: какие бывают и зачем поле «Тип»?',
   'Тип заказа уточняет характер работы и влияет на маршрут и планирование: «Единичный/штучный» — разовые детали; «Серийный/партия» — повторяемые партии, выгодны типовые техпроцессы; «Оснастка/штамп/пресс-форма» — изготовление оснастки (длинный цикл, проектирование); «Инжиниринг/НИОКР» — реверс-инжиниринг, конструкторские работы. Тип отображается бейджем в списке и карточке.',
   'тип заказа единичный серийный оснастка инжиниринг НИОКР'),
  ('Заявки','Как работает напоминание о просрочке (SLA)?',
   'Если у заявки задан срок и он прошёл, а статус не «Выполнена» и не «Отменена», система один раз создаёт уведомление о просрочке ответственным (директор, начальник цеха, менеджер). Повторно по одной заявке не уведомляет. Просроченные видно фильтром «Просрочены» и в KPI. Двигайте срок или закрывайте заявку, чтобы убрать просрочку.',
   'SLA просрочка срок уведомление напоминание')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Типы заказов: какие бывают и зачем поле «Тип»?');
