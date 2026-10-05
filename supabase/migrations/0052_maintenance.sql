-- ============================================================
-- 3DMP Service · 0052_maintenance.sql  (v32.0 — прототип B15 → продукт «ТОиР»)
-- Обслуживание и ремонт оборудования: планы ТО/ППР, регистрация работ, история, KPI.
-- Связь: оборудование (app_equipment), реестр процессов ПР.17/ПР.19. База знаний.
-- Зависит от 0001..0051.
-- ============================================================

create table if not exists public.app_mnt_plans (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  kind          text not null default 'to1',   -- to1|to2|to3|ppr|repair|service
  title         text,
  period_days   integer,
  last_done     date,
  next_due      date,
  responsible   text,
  active        boolean not null default true,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists app_mnt_plans_idx on public.app_mnt_plans (tenant_id, next_due);
alter table public.app_mnt_plans enable row level security;

create table if not exists public.app_mnt_log (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  plan_id      uuid references public.app_mnt_plans (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  kind         text,
  work_date    date not null default current_date,
  executor     text,
  cost         numeric default 0,
  works        text,
  replaced     text,
  status       text not null default 'done',   -- done|planned
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_mnt_log_idx on public.app_mnt_log (tenant_id, work_date desc);
alter table public.app_mnt_log enable row level security;

-- ---------- KPI ----------
create or replace function public.app_mnt_kpi(p_token uuid)
returns table (plans_total bigint, due bigint, overdue bigint, done_month bigint, cost_month numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active),
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active and p.next_due is not null and p.next_due between current_date and current_date+30),
    (select count(*) from public.app_mnt_plans p where (urole='admin' or p.tenant_id=ten) and p.active and p.next_due is not null and p.next_due < current_date),
    (select count(*) from public.app_mnt_log l where (urole='admin' or l.tenant_id=ten) and l.work_date >= date_trunc('month', current_date)),
    (select coalesce(sum(l.cost),0) from public.app_mnt_log l where (urole='admin' or l.tenant_id=ten) and l.work_date >= date_trunc('month', current_date));
end $$;

-- ---------- Планы ----------
create or replace function public.app_mnt_plans_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment_id uuid, equipment text, kind text, title text, period_days integer,
               last_done date, next_due date, days_left integer, status text, responsible text, active boolean, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, p.equipment_id, e.name, p.kind, p.title, p.period_days, p.last_done, p.next_due,
      case when p.next_due is null then null else (p.next_due - current_date) end,
      case when p.next_due is null then 'none'
           when p.next_due < current_date then 'overdue'
           when p.next_due < current_date + 30 then 'due'
           else 'ok' end,
      p.responsible, p.active, p.note
    from public.app_mnt_plans p left join public.app_equipment e on e.id = p.equipment_id
    where (urole='admin' or p.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(p.title,'')) like '%'||qq||'%' or lower(coalesce(p.responsible,'')) like '%'||qq||'%')
    order by (p.next_due is null), p.next_due;
end $$;

create or replace function public.app_mnt_plan_save(p_token uuid, p_id uuid, p_equipment_id uuid, p_kind text, p_title text,
  p_period_days integer, p_last_done date, p_next_due date, p_responsible text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; nd date;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief') then return query select false,'Недостаточно прав'; return; end if;
  nd := coalesce(p_next_due, case when p_last_done is not null and p_period_days is not null then p_last_done + p_period_days else null end);
  if p_id is null then
    insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, last_done, next_due, responsible, note)
    values (ten, p_equipment_id, coalesce(nullif(trim(p_kind),''),'to1'), nullif(trim(p_title),''), p_period_days, p_last_done, nd, nullif(trim(p_responsible),''), nullif(trim(p_note),''));
  else
    update public.app_mnt_plans set equipment_id=p_equipment_id, kind=coalesce(nullif(trim(p_kind),''),kind),
      title=nullif(trim(p_title),''), period_days=p_period_days, last_done=p_last_done, next_due=nd,
      responsible=nullif(trim(p_responsible),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Регистрация выполнения (ТО/ремонт) ----------
create or replace function public.app_mnt_register(p_token uuid, p_plan_id uuid, p_equipment_id uuid, p_kind text,
  p_date date, p_executor text, p_cost numeric, p_works text, p_replaced text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; eid uuid; nd date; pd integer; k text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','operator','supply') then return query select false,'Недостаточно прав'; return; end if;

  eid := p_equipment_id; k := p_kind;
  if p_plan_id is not null then
    select p.equipment_id, coalesce(k, p.kind), p.period_days into eid, k, pd
      from public.app_mnt_plans p where p.id = p_plan_id and (urole='admin' or p.tenant_id=ten);
    if eid is null and pd is null then return query select false,'План не найден'; return; end if;
    nd := case when pd is not null then coalesce(p_date,current_date) + pd else null end;
    update public.app_mnt_plans p set last_done = coalesce(p_date, current_date), next_due = nd where p.id = p_plan_id;
  end if;

  insert into public.app_mnt_log (tenant_id, plan_id, equipment_id, kind, work_date, executor, cost, works, replaced, status, note, created_login)
  values (ten, p_plan_id, eid, k, coalesce(p_date,current_date), nullif(trim(p_executor),''), coalesce(p_cost,0),
          nullif(trim(p_works),''), nullif(trim(p_replaced),''), 'done', nullif(trim(p_note),''), ulogin);

  perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief'], 'ТОиР: выполнено', coalesce(p_works,'Работы по обслуживанию'), 'apps/maintenance/index.html');
  return query select true,'Работа зарегистрирована';
end $$;

-- ---------- История ----------
create or replace function public.app_mnt_log_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment text, kind text, work_date date, executor text, cost numeric, works text, replaced text, note text, created_login text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select l.id, e.name, l.kind, l.work_date, l.executor, l.cost, l.works, l.replaced, l.note, l.created_login
    from public.app_mnt_log l left join public.app_equipment e on e.id = l.equipment_id
    where (urole='admin' or l.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(l.works,'')) like '%'||qq||'%' or lower(coalesce(l.executor,'')) like '%'||qq||'%')
    order by l.work_date desc, l.created_at desc;
end $$;

grant execute on function public.app_mnt_kpi(uuid) to anon, authenticated;
grant execute on function public.app_mnt_plans_list(uuid,text) to anon, authenticated;
grant execute on function public.app_mnt_plan_save(uuid,uuid,uuid,text,text,integer,date,date,text,text) to anon, authenticated;
grant execute on function public.app_mnt_register(uuid,uuid,uuid,text,date,text,numeric,text,text,text) to anon, authenticated;
grant execute on function public.app_mnt_log_list(uuid,text) to anon, authenticated;

-- ---------- Демо-планы (тенант A) ----------
insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, last_done, next_due, responsible, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.id, v.kind, v.title, v.period, current_date - v.ago, current_date - v.ago + v.period, 'master', v.note
from public.app_equipment e
join (values
  ('frezerny','to1','ТО-1 фрезерного ЧПУ',30,20,'Ежемесячное ТО'),
  ('tokarny','to2','ТО-2 токарного',90,80,'Квартальное ТО'),
  ('shlifovalny','ppr','ППР шлифовального',180,200,'Просрочено — планировать ППР'),
  ('edm','to1','ТО-1 ЭЭО',30,25,'Проверка диэлектрика')
) as v(kind_eq, kind, title, period, ago, note) on e.kind = v.kind_eq
where not exists (select 1 from public.app_mnt_plans where tenant_id='aaaaaaaa-0000-0000-0000-000000000001')
limit 4;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ТОиР','Как вести обслуживание и ремонт оборудования?',
   'Модуль «Обслуживание и ремонт»: планы ТО/ППР по оборудованию (период, ответственный, следующая дата), регистрация выполненных работ (дата, исполнитель, стоимость, что сделано, что заменено) и история. KPI: всего планов, «истекает» (≤30 дней), «просрочено», выполнено за месяц и суммарные затраты.',
   'ТОиР обслуживание ремонт ППР ТО план оборудование история'),
  ('ТОиР','Связь с процессами и MES',
   'Обслуживание соответствует процессам ПР.17 (обслуживание) и ПР.19 (ремонт). Работы по ТО снижают простои, что отражается в OEE (диспетчерская/аналитика). Просроченные ППР выделяются отдельно — планируйте их заранее.',
   'ТОиР процесс ПР.17 ПР.19 простои OEE ППР')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести обслуживание и ремонт оборудования?');
