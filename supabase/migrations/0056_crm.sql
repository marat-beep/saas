-- ============================================================
-- 3DMP Service · 0056_crm.sql  (v36.0 — ЭПИК A: CRM / сделки, прототипы B12/A14)
-- Воронка сделок по заказчикам, стадии, суммы/вероятность, связь с заявкой.
-- База знаний. Зависит от 0001..0055.
-- ============================================================

create table if not exists public.app_deals (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  customer_id uuid references public.app_customers (id) on delete set null,
  title       text not null,
  stage       text not null default 'lead', -- lead|qualified|proposal|negotiation|won|lost
  amount      numeric,
  probability integer default 10,
  source      text,
  owner_login text,
  next_action text,
  due_date    date,
  order_id    uuid references public.app_orders (id) on delete set null,
  note        text,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_deals_idx on public.app_deals (tenant_id, stage);
alter table public.app_deals enable row level security;

-- ---------- Список ----------
create or replace function public.app_deal_list(p_token uuid, p_q text default null)
returns table (id uuid, customer_id uuid, customer text, title text, stage text, amount numeric, probability integer,
               weighted numeric, source text, owner_login text, next_action text, due_date date, order_id uuid, order_number text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.customer_id, c.name, d.title, d.stage, d.amount, d.probability,
      round(coalesce(d.amount,0)*coalesce(d.probability,0)/100.0, 2), d.source, d.owner_login, d.next_action, d.due_date, d.order_id, o.number, d.note
    from public.app_deals d
    left join public.app_customers c on c.id = d.customer_id
    left join public.app_orders o on o.id = d.order_id
    where (urole='admin' or d.tenant_id = ten)
      and (qq='' or lower(d.title) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%' or lower(coalesce(d.owner_login,'')) like '%'||qq||'%')
    order by case d.stage when 'negotiation' then 0 when 'proposal' then 1 when 'qualified' then 2 when 'lead' then 3 when 'won' then 4 else 5 end, d.updated_at desc;
end $$;

-- ---------- KPI ----------
create or replace function public.app_deal_kpi(p_token uuid)
returns table (deals_total bigint, open_deals bigint, pipeline numeric, won_sum numeric, won_count bigint, conversion numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*),
    count(*) filter (where stage not in ('won','lost')),
    coalesce(sum(coalesce(amount,0)*coalesce(probability,0)/100.0) filter (where stage not in ('won','lost')),0),
    coalesce(sum(amount) filter (where stage='won'),0),
    count(*) filter (where stage='won'),
    case when count(*) filter (where stage in ('won','lost')) > 0
         then round(100.0 * count(*) filter (where stage='won') / count(*) filter (where stage in ('won','lost')),1) else 0 end
    from public.app_deals where (urole='admin' or tenant_id = ten);
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_deal_save(p_token uuid, p_id uuid, p_customer_id uuid, p_title text, p_stage text,
  p_amount numeric, p_probability integer, p_source text, p_owner text, p_next_action text, p_due_date date, p_order_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите название сделки'; return; end if;
  if p_id is null then
    insert into public.app_deals (tenant_id, customer_id, title, stage, amount, probability, source, owner_login, next_action, due_date, order_id, note, created_login)
    values (ten, p_customer_id, trim(p_title), coalesce(nullif(trim(p_stage),''),'lead'), p_amount, coalesce(p_probability,10),
            nullif(trim(p_source),''), nullif(trim(p_owner),''), nullif(trim(p_next_action),''), p_due_date, p_order_id, nullif(trim(p_note),''), ulogin);
  else
    update public.app_deals set customer_id=p_customer_id, title=trim(p_title), stage=coalesce(nullif(trim(p_stage),''),stage),
      amount=p_amount, probability=coalesce(p_probability,probability), source=nullif(trim(p_source),''), owner_login=nullif(trim(p_owner),''),
      next_action=nullif(trim(p_next_action),''), due_date=p_due_date, order_id=p_order_id, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сделка сохранена';
end $$;

-- ---------- Смена стадии ----------
create or replace function public.app_deal_set_stage(p_token uuid, p_id uuid, p_stage text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_stage not in ('lead','qualified','proposal','negotiation','won','lost') then return query select false,'Неверная стадия'; return; end if;
  select d.title, d.tenant_id into t from public.app_deals d where d.id = p_id and (urole='admin' or d.tenant_id=ten);
  if t.title is null then return query select false,'Сделка не найдена'; return; end if;
  update public.app_deals set stage=p_stage, updated_at=now() where id=p_id;
  if p_stage = 'won' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director'], 'Сделка выиграна: '||t.title, '', 'apps/crm/index.html');
  end if;
  return query select true,'Стадия обновлена';
end $$;

grant execute on function public.app_deal_list(uuid,text) to anon, authenticated;
grant execute on function public.app_deal_kpi(uuid) to anon, authenticated;
grant execute on function public.app_deal_save(uuid,uuid,uuid,text,text,numeric,integer,text,text,text,date,uuid,text) to anon, authenticated;
grant execute on function public.app_deal_set_stage(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_deals (tenant_id, customer_id, title, stage, amount, probability, source, owner_login, next_action, due_date)
select 'aaaaaaaa-0000-0000-0000-000000000001',
       (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
       v.title, v.stage, v.amount, v.prob, 'входящая', 'manager', v.next, current_date + v.days
from (values
  ('Изготовление пресс-формы', 'negotiation', 850000, 60, 'согласовать ТЗ', 5),
  ('Партия штампов (5 шт)', 'proposal', 1200000, 40, 'отправить КП', 3),
  ('Реверс-инжиниринг детали', 'qualified', 180000, 25, 'оценка трудоёмкости', 7),
  ('Кронштейны, серия', 'won', 39167.09, 100, 'выставить счёт', 0)
) as v(title, stage, amount, prob, next, days)
where not exists (select 1 from public.app_deals where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('CRM','Как вести воронку сделок?',
   'Модуль «CRM»: сделки по заказчикам со стадиями (лид → квалифицирован), предложение, переговоры, выиграна/проиграна), суммой и вероятностью. Взвешенная сумма = сумма × вероятность. KPI: сделок, открытых, воронка (взвешенная), выиграно (сумма/число), конверсия. Сделку можно связать с заявкой.',
   'CRM воронка сделки стадии сумма вероятность конверсия'),
  ('CRM','Связь CRM с заявками и ТКП',
   'Сделка ведёт к заявке (модуль «Заявки») и КП/ТКП (модуль «Документы»/реестр ТКП). При выигрыше сделки приходит уведомление. Так продажи связаны с производством и финансами.',
   'CRM заявка ТКП КП сделка связь продажи')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести воронку сделок?');
