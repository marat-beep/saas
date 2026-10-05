-- ============================================================
-- 3DMP Service · 0060_issues_service.sql  (v38 — ЭПИК C: эскалация B24 + сервис B29)
-- app_issues (проблемы/эскалация/SLA) и app_service_requests (заявки на сервис/ремонт).
-- База знаний. Зависит от 0001..0059.
-- ============================================================

create table if not exists public.app_issues (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  title        text not null,
  description  text,
  priority     text not null default 'normal', -- low|normal|high|critical
  source       text,
  status       text not null default 'open',   -- open|in_progress|resolved|closed
  assignee     text,
  due_date     date,
  escalated    boolean not null default false,
  escalated_at timestamptz,
  order_id     uuid references public.app_orders (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_issues_idx on public.app_issues (tenant_id, status, priority);
alter table public.app_issues enable row level security;

create sequence if not exists public.app_service_seq;
create table if not exists public.app_service_requests (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  customer_id   uuid references public.app_customers (id) on delete set null,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  title         text not null,
  kind          text not null default 'service', -- service|repair|warranty
  status        text not null default 'new',     -- new|scheduled|in_progress|done|cancelled
  scheduled_date date,
  engineer      text,
  works         text,
  cost          numeric,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_service_idx on public.app_service_requests (tenant_id, status);
alter table public.app_service_requests enable row level security;

-- ---------- Проблемы ----------
create or replace function public.app_issue_list(p_token uuid, p_q text default null)
returns table (id uuid, title text, priority text, status text, assignee text, due_date date, escalated boolean,
               order_number text, equipment text, created_at timestamptz, overdue boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select i.id, i.title, i.priority, i.status, i.assignee, i.due_date, i.escalated, o.number, e.name, i.created_at,
      (i.due_date is not null and i.due_date < current_date and i.status not in ('resolved','closed'))
    from public.app_issues i
    left join public.app_orders o on o.id = i.order_id
    left join public.app_equipment e on e.id = i.equipment_id
    where (urole='admin' or i.tenant_id = ten)
      and (qq='' or lower(i.title) like '%'||qq||'%' or lower(coalesce(i.assignee,'')) like '%'||qq||'%')
    order by (i.status in ('resolved','closed')), case i.priority when 'critical' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, i.created_at desc;
end $$;

create or replace function public.app_issue_kpi(p_token uuid)
returns table (issues_open bigint, critical bigint, escalated bigint, overdue bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*) filter (where status not in ('resolved','closed')),
    count(*) filter (where priority='critical' and status not in ('resolved','closed')),
    count(*) filter (where escalated and status not in ('resolved','closed')),
    count(*) filter (where due_date is not null and due_date < current_date and status not in ('resolved','closed'))
    from public.app_issues where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_issue_save(p_token uuid, p_id uuid, p_title text, p_description text, p_priority text,
  p_assignee text, p_due_date date, p_order_id uuid, p_equipment_id uuid, p_source text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','qc','supply','technologist','operator') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему'; return; end if;
  if p_id is null then
    insert into public.app_issues (tenant_id, title, description, priority, assignee, due_date, order_id, equipment_id, source, created_login)
    values (ten, trim(p_title), nullif(trim(p_description),''), coalesce(nullif(trim(p_priority),''),'normal'),
            nullif(trim(p_assignee),''), p_due_date, p_order_id, p_equipment_id, nullif(trim(p_source),''), ulogin);
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief'],
      'Новая проблема: '||trim(p_title), coalesce(nullif(trim(p_priority),''),'normal'), 'apps/issues/index.html');
  else
    update public.app_issues set title=trim(p_title), description=nullif(trim(p_description),''),
      priority=coalesce(nullif(trim(p_priority),''),priority), assignee=nullif(trim(p_assignee),''), due_date=p_due_date,
      order_id=p_order_id, equipment_id=p_equipment_id, source=nullif(trim(p_source),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_issue_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('open','in_progress','resolved','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_issues set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_issue_escalate(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; t text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select title into t from public.app_issues where id=p_id and (urole='admin' or tenant_id=ten);
  if t is null then return query select false,'Проблема не найдена'; return; end if;
  update public.app_issues set escalated=true, escalated_at=now(), priority='critical', updated_at=now() where id=p_id;
  perform public.app_notif_roles_t(ten, array['admin','owner','director','manager'], 'ЭСКАЛАЦИЯ: '||t, coalesce(p_note,''), 'apps/issues/index.html');
  return query select true,'Проблема эскалирована руководству';
end $$;

-- ---------- Заявки на сервис ----------
create or replace function public.app_service_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, customer text, equipment text, title text, kind text, status text,
               scheduled_date date, engineer text, cost numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.number, c.name, e.name, s.title, s.kind, s.status, s.scheduled_date, s.engineer, s.cost, s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    where (urole='admin' or s.tenant_id = ten)
      and (qq='' or lower(s.title) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%' or lower(coalesce(s.engineer,'')) like '%'||qq||'%')
    order by s.created_at desc;
end $$;

create or replace function public.app_service_kpi(p_token uuid)
returns table (requests bigint, open bigint, done bigint, cost_sum numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status not in ('done','cancelled')),
    count(*) filter (where status='done'), coalesce(sum(cost),0)
    from public.app_service_requests where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_service_save(p_token uuid, p_id uuid, p_customer_id uuid, p_equipment_id uuid,
  p_title text, p_kind text, p_scheduled_date date, p_engineer text, p_works text, p_cost numeric, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; sid uuid; snum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите тему'; return; end if;
  if p_id is null then
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests (tenant_id, number, customer_id, equipment_id, title, kind, scheduled_date, engineer, works, cost, note, created_login)
    values (ten, snum, p_customer_id, p_equipment_id, trim(p_title), coalesce(nullif(trim(p_kind),''),'service'), p_scheduled_date,
            nullif(trim(p_engineer),''), nullif(trim(p_works),''), p_cost, nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, snum, 'Заявка создана';
  else
    update public.app_service_requests set customer_id=p_customer_id, equipment_id=p_equipment_id, title=trim(p_title),
      kind=coalesce(nullif(trim(p_kind),''),kind), scheduled_date=p_scheduled_date, engineer=nullif(trim(p_engineer),''),
      works=nullif(trim(p_works),''), cost=p_cost, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into sid, snum;
    return query select sid, snum, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_service_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','scheduled','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_service_requests set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_issue_list(uuid,text) to anon, authenticated;
grant execute on function public.app_issue_kpi(uuid) to anon, authenticated;
grant execute on function public.app_issue_save(uuid,uuid,text,text,text,text,date,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_issue_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_issue_escalate(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_service_list(uuid,text) to anon, authenticated;
grant execute on function public.app_service_kpi(uuid) to anon, authenticated;
grant execute on function public.app_service_save(uuid,uuid,uuid,uuid,text,text,date,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_service_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_issues (tenant_id, title, description, priority, status, assignee, due_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.descr, v.pr, v.st, v.asg, current_date + v.days, 'master'
from (values
  ('Простой фрезерного DMU-50 (поломка)', 'Ожидание ремонта шпинделя', 'critical', 'in_progress', 'master', 0),
  ('Задержка материала по заказу', 'Нет стали 40Х на складе', 'high', 'open', 'supply', 2),
  ('Дефект кромки после ЭЭО', 'Задиры на контуре', 'normal', 'open', 'qc', 5)
) as v(title, descr, pr, st, asg, days)
where not exists (select 1 from public.app_issues where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_service_requests (tenant_id, number, customer_id, equipment_id, title, kind, status, scheduled_date, engineer, works, cost, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0'),
       (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind='frezerny' order by name limit 1),
       'Пусконаладка штампа у заказчика', 'service', 'scheduled', current_date + 3, 'service', 'Пробный прогон, подгонка', 25000, 'manager'
where not exists (select 1 from public.app_service_requests where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Проблемы','Как работает эскалация проблем (B24)?',
   'Модуль «Проблемы»: тема, приоритет (низкий/обычный/высокий/критический), исполнитель, срок, статус. Просроченные и критические выделяются. Кнопка «Эскалировать» поднимает приоритет до критического и уведомляет руководство (директор/владелец).',
   'проблемы эскалация приоритет SLA уведомление руководитель'),
  ('Сервис','Заявки на сервис и ремонт (B29)',
   'Модуль «Сервис»: заявки (SRV-NNNNN) с заказчиком, оборудованием, видом (сервис/ремонт/гарантия), датой, инженером, работами и стоимостью. Статусы: новая → запланирована → в работе → выполнена. KPI: заявок, открытых, выполнено, сумма затрат.',
   'сервис ремонт заявка инженер выезд гарантия')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как работает эскалация проблем (B24)?');
