-- ============================================================
-- 3DMP Service · 0122_service_v2.sql  (S1 — Сервис ЧПУ: ядро SR v2)
-- Дополнение apps/service по ТЗ: приоритет/канал/гарантия/SLA, история,
-- выезды, KPI (SLA/MTTR/FTFR/CSAT), авто-тикет от IIoT.
-- Идемпотентно. Зависит от 0001..0121.
-- ============================================================

alter table public.app_service_requests add column if not exists priority text not null default 'normal';   -- low|normal|high|critical
alter table public.app_service_requests add column if not exists channel text default 'manual';             -- phone|email|portal|dealer|iiot|manual
alter table public.app_service_requests add column if not exists source text default 'manual';              -- manual|iiot|import
alter table public.app_service_requests add column if not exists is_warranty boolean not null default false;
alter table public.app_service_requests add column if not exists issue_id uuid references public.app_issues (id) on delete set null;
alter table public.app_service_requests add column if not exists assigned_login text;
alter table public.app_service_requests add column if not exists contact text;
alter table public.app_service_requests add column if not exists location text;
alter table public.app_service_requests add column if not exists fault_code text;
alter table public.app_service_requests add column if not exists reported_at timestamptz;
alter table public.app_service_requests add column if not exists response_due timestamptz;
alter table public.app_service_requests add column if not exists resolve_due timestamptz;
alter table public.app_service_requests add column if not exists first_response_at timestamptz;
alter table public.app_service_requests add column if not exists resolved_at timestamptz;
alter table public.app_service_requests add column if not exists closed_at timestamptz;
alter table public.app_service_requests add column if not exists labor_hours numeric;
alter table public.app_service_requests add column if not exists downtime_hours numeric;
alter table public.app_service_requests add column if not exists root_cause text;
alter table public.app_service_requests add column if not exists solution text;
alter table public.app_service_requests add column if not exists satisfaction integer;                    -- CSAT 1..5
alter table public.app_service_requests add column if not exists updated_at timestamptz default now();
create index if not exists app_service_priority_idx on public.app_service_requests (tenant_id, priority, status);

create table if not exists public.app_service_history (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  request_id  uuid not null references public.app_service_requests (id) on delete cascade,
  kind        text not null default 'event',   -- event|status|assign|visit|part|comment|sla
  text        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_service_history_idx on public.app_service_history (request_id, created_at);

create table if not exists public.app_service_visits (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  request_id     uuid not null references public.app_service_requests (id) on delete cascade,
  engineer       text,
  planned_at     timestamptz,
  arrived_at     timestamptz,
  finished_at    timestamptz,
  status         text not null default 'assigned',  -- assigned|on_way|in_work|done|cancelled
  place          text,
  work_report    text,
  offline_client_id text,
  created_at     timestamptz not null default now()
);
create index if not exists app_service_visits_idx on public.app_service_visits (request_id, created_at);

alter table public.app_service_history enable row level security;
alter table public.app_service_visits  enable row level security;

-- ---------- SLA по приоритету ----------
drop function if exists public.app_service_sla_minutes(text);
create or replace function public.app_service_sla_minutes(p_priority text)
returns table (resp_min integer, res_min integer)
language sql immutable
as $$
  select v.resp, v.res from (values
    ('critical', 60, 240),
    ('high', 240, 1440),
    ('normal', 480, 2880),
    ('low', 1440, 4320)
  ) as v(pr, resp, res) where v.pr = coalesce(nullif(trim(p_priority),''),'normal')
$$;
grant execute on function public.app_service_sla_minutes(text) to anon, authenticated;

-- ---------- Список заявок v2 ----------
drop function if exists public.app_service_list(uuid,text);
create or replace function public.app_service_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, customer text, equipment text, title text, kind text, status text, priority text,
               channel text, source text, is_warranty boolean, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, cost numeric, sla_state text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.number, c.name, e.name, s.title, s.kind, s.status, s.priority,
           s.channel, s.source, s.is_warranty, s.assigned_login, s.engineer,
           s.scheduled_date, s.reported_at, s.response_due, s.resolve_due,
           s.first_response_at, s.resolved_at, s.cost,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    where (urole='admin' or s.tenant_id = ten)
      and (qq='' or lower(s.title) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%'
           or lower(coalesce(s.engineer,'')) like '%'||qq||'%' or lower(coalesce(s.number,'')) like '%'||qq||'%')
    order by (s.priority='critical') desc, s.created_at desc;
end $$;

-- ---------- Карточка заявки ----------
drop function if exists public.app_service_get(uuid,uuid);
create or replace function public.app_service_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, customer_id uuid, customer text, equipment_id uuid, equipment text, title text,
               kind text, status text, priority text, channel text, source text, is_warranty boolean,
               contact text, location text, fault_code text, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, closed_at timestamptz,
               labor_hours numeric, downtime_hours numeric, cost numeric, works text, note text,
               root_cause text, solution text, satisfaction integer, sla_state text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.number, s.customer_id, c.name, s.equipment_id, e.name, s.title, s.kind, s.status, s.priority,
           s.channel, s.source, s.is_warranty, s.contact, s.location, s.fault_code, s.assigned_login, s.engineer,
           s.scheduled_date, s.reported_at, s.response_due, s.resolve_due, s.first_response_at, s.resolved_at, s.closed_at,
           s.labor_hours, s.downtime_hours, s.cost, s.works, s.note, s.root_cause, s.solution, s.satisfaction,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    where s.id = p_id and (urole='admin' or s.tenant_id = ten);
end $$;

-- ---------- Сохранение заявки v2 ----------
drop function if exists public.app_service_save(uuid,uuid,uuid,uuid,text,text,date,text,text,numeric,text);
create or replace function public.app_service_save(
  p_token uuid, p_id uuid, p_customer_id uuid, p_equipment_id uuid, p_title text, p_kind text,
  p_scheduled_date date, p_engineer text, p_works text, p_cost numeric, p_note text,
  p_priority text default null, p_channel text default null, p_is_warranty boolean default null,
  p_contact text default null, p_location text default null, p_assigned_login text default null
) returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid; snum text; pr text; respmin integer; resmin integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','support') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите тему'; return; end if;
  pr := coalesce(nullif(trim(p_priority),''),'normal');
  if pr not in ('low','normal','high','critical') then raise exception 'Неверный приоритет'; return; end if;

  if p_id is null then
    select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes(pr);
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, customer_id, equipment_id, title, kind, priority, channel, is_warranty, contact, location,
       scheduled_date, engineer, assigned_login, works, cost, note, reported_at, response_due, resolve_due, created_login)
    values (ten, snum, p_customer_id, p_equipment_id, trim(p_title), coalesce(nullif(trim(p_kind),''),'service'), pr,
            coalesce(nullif(trim(p_channel),''),'manual'), coalesce(p_is_warranty, false), nullif(trim(p_contact),''), nullif(trim(p_location),''),
            p_scheduled_date, nullif(trim(p_engineer),''), nullif(trim(p_assigned_login),''), nullif(trim(p_works),''), p_cost,
            nullif(trim(p_note),''), now(), now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), ulogin)
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка создана (' || pr || ')', ulogin);
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
            'Сервис: новая заявка ' || snum, trim(p_title), 'apps/service/index.html');
    return query select sid, snum, 'Заявка создана';
  else
    update public.app_service_requests set customer_id=p_customer_id, equipment_id=p_equipment_id, title=trim(p_title),
      kind=coalesce(nullif(trim(p_kind),''),kind), priority=pr, channel=coalesce(nullif(trim(p_channel),''),channel),
      is_warranty=coalesce(p_is_warranty,is_warranty), contact=nullif(trim(p_contact),''), location=nullif(trim(p_location),''),
      scheduled_date=p_scheduled_date, engineer=nullif(trim(p_engineer),''), assigned_login=nullif(trim(p_assigned_login),''),
      works=nullif(trim(p_works),''), cost=p_cost, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into sid, snum;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка изменена', ulogin);
    return query select sid, snum, 'Заявка обновлена';
  end if;
end $$;

-- ---------- Смена статуса v2 (таймстампы + история + уведомление) ----------
drop function if exists public.app_service_set_status(uuid,uuid,text);
create or replace function public.app_service_set_status(p_token uuid, p_id uuid, p_status text, p_note text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; srow record; snum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','scheduled','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  select number into snum from public.app_service_requests where id=p_id and (urole='admin' or tenant_id=ten);
  if snum is null then return query select false,'Заявка не найдена'; return; end if;

  update public.app_service_requests set
    status = p_status,
    first_response_at = case when p_status in ('scheduled','in_progress') then coalesce(first_response_at, now()) else first_response_at end,
    resolved_at = case when p_status = 'done' then coalesce(resolved_at, now()) else resolved_at end,
    closed_at = case when p_status in ('done','cancelled') then coalesce(closed_at, now()) else null end,
    updated_at = now()
   where id = p_id;

  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, 'status', 'Статус: ' || p_status || coalesce(' — ' || nullif(trim(p_note),''), ''), ulogin);

  perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
          'Сервис ' || snum || ': ' || p_status, coalesce(nullif(trim(p_note),''), 'Обновлён статус заявки'), 'apps/service/index.html');
  return query select true,'Статус обновлён';
end $$;

-- ---------- Назначение инженера + выезд ----------
drop function if exists public.app_service_assign(uuid,uuid,text,timestamptz,text);
create or replace function public.app_service_assign(p_token uuid, p_id uuid, p_engineer text, p_planned_at timestamptz default null, p_place text default null)
returns table (ok boolean, message text, visit_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; srow record; vid uuid;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select number, equipment_id into srow from public.app_service_requests where id=p_id and (urole='admin' or tenant_id=ten);
  if srow.number is null then return query select false,'Заявка не найдена', null::uuid; return; end if;

  update public.app_service_requests set assigned_login=nullif(trim(p_engineer),''), engineer=nullif(trim(p_engineer),''),
         scheduled_date=coalesce(p_planned_at::date, scheduled_date), status=case when status='new' then 'scheduled' else status end,
         updated_at=now()
   where id=p_id;
  insert into public.app_service_visits (tenant_id, request_id, engineer, planned_at, place, status)
  values (ten, p_id, nullif(trim(p_engineer),''), p_planned_at, nullif(trim(p_place),''), 'assigned')
  returning id into vid;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, 'assign', 'Назначен инженер: ' || coalesce(nullif(trim(p_engineer),''),'—'), ulogin);
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
          'Сервис ' || srow.number || ': назначен выезд', coalesce(nullif(trim(p_engineer),'') || ' · ' || nullif(trim(p_place),''), 'Выезд'), 'apps/service/index.html');
  return query select true,'Инженер назначен', vid;
end $$;

-- ---------- История ----------
drop function if exists public.app_service_history_list(uuid,uuid);
create or replace function public.app_service_history_list(p_token uuid, p_id uuid)
returns table (id uuid, kind text, text text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query select h.id, h.kind, h.text, h.by_login, h.created_at
    from public.app_service_history h
    where h.request_id = p_id and (urole='admin' or h.tenant_id=ten)
    order by h.created_at;
end $$;

drop function if exists public.app_service_history_add(uuid,uuid,text,text);
create or replace function public.app_service_history_add(p_token uuid, p_id uuid, p_text text, p_kind text default 'comment')
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return query select false,'Доступ запрещён'; return; end if;
  if coalesce(trim(p_text),'')='' then return query select false,'Пустой комментарий'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_service_requests r where r.id=p_id and (urole='admin' or r.tenant_id=ten)) then
    return query select false,'Заявка не найдена'; return; end if;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, coalesce(nullif(trim(p_kind),''),'comment'), trim(p_text), ulogin);
  return query select true,'Добавлено';
end $$;

-- ---------- Выезды ----------
drop function if exists public.app_service_visit_list(uuid,uuid);
create or replace function public.app_service_visit_list(p_token uuid, p_id uuid)
returns table (id uuid, engineer text, planned_at timestamptz, arrived_at timestamptz, finished_at timestamptz,
               status text, place text, work_report text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.engineer, v.planned_at, v.arrived_at, v.finished_at, v.status, v.place, v.work_report, v.created_at
    from public.app_service_visits v
    where v.request_id = p_id and (urole='admin' or v.tenant_id=ten)
    order by v.created_at;
end $$;

drop function if exists public.app_service_visit_status(uuid,uuid,text,text);
create or replace function public.app_service_visit_status(p_token uuid, p_visit_id uuid, p_status text, p_report text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid; snum text;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return query select false,'Доступ запрещён'; return; end if;
  if p_status not in ('assigned','on_way','in_work','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  ten := public.app_my_tenant(p_token);
  select v.request_id, r.number into rid, snum from public.app_service_visits v
    join public.app_service_requests r on r.id=v.request_id
   where v.id=p_visit_id and (urole='admin' or v.tenant_id=ten);
  if rid is null then return query select false,'Выезд не найден'; return; end if;
  update public.app_service_visits set
    status = p_status,
    arrived_at = case when p_status in ('on_way','in_work') then coalesce(arrived_at, now()) else arrived_at end,
    finished_at = case when p_status in ('done','cancelled') then coalesce(finished_at, now()) else finished_at end,
    work_report = coalesce(nullif(trim(p_report),''), work_report)
   where id = p_visit_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, rid, 'visit', 'Выезд: ' || p_status || coalesce(' — ' || nullif(trim(p_report),''), ''), ulogin);
  return query select true,'Статус выезда обновлён';
end $$;

-- ---------- KPI v2 ----------
drop function if exists public.app_service_kpi(uuid);
create or replace function public.app_service_kpi(p_token uuid)
returns table (requests bigint, open bigint, critical bigint, overdue_sla bigint, done bigint,
               mttr_hours numeric, ftfr_pct numeric, csat_avg numeric, cost_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select count(*),
           count(*) filter (where status not in ('done','cancelled')),
           count(*) filter (where priority='critical' and status not in ('done','cancelled')),
           count(*) filter (where status not in ('done','cancelled') and resolve_due is not null and resolve_due < now()),
           count(*) filter (where status='done'),
           round(avg(extract(epoch from (resolved_at - coalesce(reported_at, created_at)))/3600.0) filter (where status='done' and resolved_at is not null), 1),
           round(100.0 * count(*) filter (where status='done' and (select count(*) from public.app_service_visits v where v.request_id = r.id) <= 1)
                 / nullif(count(*) filter (where status='done'), 0), 1),
           round(avg(satisfaction) filter (where satisfaction is not null), 2),
           coalesce(sum(cost), 0)
      from public.app_service_requests r
     where (urole='admin' or r.tenant_id = ten);
end $$;

-- ---------- Авто-тикет от IIoT (ошибки ЧПУ) ----------
drop function if exists public.app_service_iiot_auto(uuid,integer);
create or replace function public.app_service_iiot_auto(p_token uuid, p_hours integer default 24)
returns table (created integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; r record; cnt int := 0; sid uuid; snum text; respmin integer; resmin integer;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return query select 0,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','view') then return query select 0,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select i.machine, i.metric, i.value, i.ts, e.id as eq_id, e.name as eq_name
      from public.app_iiot_readings i
      join public.app_equipment e on e.name = i.machine
     where (urole='admin' or i.tenant_id = ten)
       and i.metric in ('fault','alarm','error')
       and coalesce(i.value,0) > 0
       and i.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours,24),168)))
       and not exists (select 1 from public.app_service_requests s
                        where s.equipment_id = e.id and s.status not in ('done','cancelled'))
  loop
    select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes('critical');
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, equipment_id, title, kind, priority, channel, source, fault_code, reported_at, response_due, resolve_due, created_login)
    values (ten, snum, r.eq_id, 'Авто-тикет IIoT: ' || r.metric || ' на ' || r.eq_name, 'repair', 'critical', 'iiot', 'iiot',
            r.metric || '=' || coalesce(r.value,0)::text, r.ts, now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), ulogin)
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Авто-тикет от IIoT: ' || r.metric || '=' || coalesce(r.value,0)::text, 'iiot');
    cnt := cnt + 1;
  end loop;
  if cnt > 0 then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
            'IIoT: создано сервисных заявок — ' || cnt, 'Ошибки ЧПУ требуют реакции', 'apps/service/index.html');
  end if;
  return query select cnt, case when cnt>0 then 'Создано заявок: ' || cnt else 'Новых ошибок IIoT нет' end;
end $$;

grant execute on function public.app_service_list(uuid,text)                                   to anon, authenticated;
grant execute on function public.app_service_get(uuid,uuid)                                    to anon, authenticated;
grant execute on function public.app_service_save(uuid,uuid,uuid,uuid,text,text,date,text,text,numeric,text,text,text,boolean,text,text,text) to anon, authenticated;
grant execute on function public.app_service_set_status(uuid,uuid,text,text)                   to anon, authenticated;
grant execute on function public.app_service_assign(uuid,uuid,text,timestamptz,text)           to anon, authenticated;
grant execute on function public.app_service_history_list(uuid,uuid)                           to anon, authenticated;
grant execute on function public.app_service_history_add(uuid,uuid,text,text)                  to anon, authenticated;
grant execute on function public.app_service_visit_list(uuid,uuid)                             to anon, authenticated;
grant execute on function public.app_service_visit_status(uuid,uuid,text,text)                 to anon, authenticated;
grant execute on function public.app_service_kpi(uuid)                                         to anon, authenticated;
grant execute on function public.app_service_iiot_auto(uuid,integer)                           to anon, authenticated;

-- ---------- Обновить существующие демо-заявки (приоритет/отчёты) ----------
update public.app_service_requests
   set reported_at = coalesce(reported_at, created_at),
       priority = coalesce(nullif(priority,''),'normal'),
       is_warranty = (kind = 'warranty')
 where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
   and (reported_at is null or priority is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Сервис ЧПУ: приоритеты, SLA, выезды',
   'Заявка сервиса (SRV-): приоритет (low/normal/high/critical) задаёт SLA-план (реакция/решение) из app_service_sla_minutes; поля канал, источник (manual/iiot), гарантия, контакт, место, код ошибки. История — app_service_history (событие/статус/назначение/выезд/комментарий); выезды — app_service_visits (назначен/в пути/в работе/завершён). Назначение инженера — app_service_assign (создаёт выезд и уведомляет). KPI: SLA-просрочка, MTTR, FTFR, CSAT, затраты. Авто-тикеты от IIoT — app_service_iiot_auto (ошибки ЧПУ из app_iiot_readings).',
   'сервис ЧПУ SR приоритет SLA MTTR MTBF FTFR CSAT выезд IIoT авто-тикет')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Сервис ЧПУ: приоритеты, SLA, выезды'
);
