-- ============================================================
-- 3DMP Service · 0032_procurement_ref.sql  (v15.0 — переработка «Закупки»)
-- Закупки: связь с заявкой (потребность), исполнитель, лучшая цена, карточка.
-- Витрина поставщика и подача КП — как есть. База знаний. Tenant-изоляция.
-- Зависит от 0001..0031.
-- ============================================================

alter table public.tenders add column if not exists order_id uuid references public.app_orders (id) on delete set null;
alter table public.tenders add column if not exists assignee text;
create index if not exists tenders_order_idx on public.tenders (order_id);

-- ---------- Создание закупки ----------
drop function if exists public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date);
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date,
  p_order_id uuid default null, p_assignee text default null
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; tid uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;
  -- created_by в tenders ссылается на auth.users, поэтому не заполняем его app-пользователем.
  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, assignee, status, tenant_id)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, p_order_id, nullif(trim(p_assignee),''), 'open', ten)
  returning tenders.id into tid;
  return query select tid, 'Закупка опубликована';
end $$;

-- ---------- Список закупок (расширенный) ----------
drop function if exists public.app_tender_list_full(uuid);
create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, description text, category text, material text, qty numeric, unit text,
               customer text, deadline date, status text, order_id uuid, order_number text, assignee text,
               bids_count bigint, best_price numeric, awarded_bid_id uuid, created_at timestamptz, closed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.description, t.category, t.material, t.qty, t.unit,
           t.customer, t.deadline, t.status, t.order_id, o.number, t.assignee,
           (select count(*) from public.bids b where b.tender_id = t.id),
           (select min(b.price) from public.bids b where b.tender_id = t.id),
           t.awarded_bid_id, t.created_at, t.closed_at
    from public.tenders t left join public.app_orders o on o.id = t.order_id
    where (urole = 'admin' or t.tenant_id = ten)
    order by t.created_at desc;
end $$;

-- ---------- Карточка закупки ----------
create or replace function public.app_tender_get(p_token uuid, p_id uuid)
returns table (id uuid, title text, description text, category text, material text, qty numeric, unit text,
               customer text, deadline date, status text, order_id uuid, order_number text, assignee text,
               bids_count bigint, best_price numeric, awarded_bid_id uuid, created_at timestamptz, closed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.description, t.category, t.material, t.qty, t.unit,
           t.customer, t.deadline, t.status, t.order_id, o.number, t.assignee,
           (select count(*) from public.bids b where b.tender_id = t.id),
           (select min(b.price) from public.bids b where b.tender_id = t.id),
           t.awarded_bid_id, t.created_at, t.closed_at
    from public.tenders t left join public.app_orders o on o.id = t.order_id
    where t.id = p_id and (urole = 'admin' or t.tenant_id = ten);
end $$;

grant execute on function public.app_tender_create(uuid,text,text,text,text,numeric,text,text,date,uuid,text) to anon, authenticated;
grant execute on function public.app_tender_list_full(uuid) to anon, authenticated;
grant execute on function public.app_tender_get(uuid,uuid) to anon, authenticated;

-- ---------- Демо: закупка по заявке (тенант A) ----------
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, status, tenant_id)
select 'Закупка: сталь 40Х, круг Ø80', 'Металлопрокат для изготовления кронштейна.',
       'Металлопрокат', 'Сталь 40Х, круг', 125, 'кг', null, (current_date + 14), o.id, 'open',
       'aaaaaaaa-0000-0000-0000-000000000001'
from public.app_orders o
where o.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.tenders t where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and t.order_id is not null)
order by o.created_at limit 1;

-- ---------- База знаний: закупки ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Закупки','Как работает закупка от потребности до победителя?',
   'Закупщик создаёт закупку (можно из потребности по заявке): категория, материал, количество, срок подачи. Закупка публикуется в витрине портала поставщиков. Поставщики подают КП (цена, срок, комментарий). Закупщик сравнивает предложения (лучшая цена подсвечена) и выбирает победителя — статус «Победитель», остальные получают уведомление.',
   'закупка потребность заявка КП поставщик победитель'),
  ('Закупки','Что видит поставщик и как подать КП?',
   'Поставщик входит в «Портал поставщика», видит открытые закупки с фильтрами и поиском, открывает карточку и подаёт КП (цена, срок, комментарий); КП можно изменить до выбора победителя. Раздел «Мои КП» показывает статус: Подано/Принято/Отклонено. Требуется аккредитация.',
   'поставщик портал КП подача аккредитация'),
  ('Закупки','KPI и статусы закупок',
   'Статусы: Открыта → Победитель → Закрыта. KPI: сколько открыто, определено победителей, закрыто, и сколько КП подано. Лучшая цена по закупке видна сразу в списке.',
   'KPI закупки статус открыта победитель закрыта')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Закупки');
