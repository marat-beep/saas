-- ============================================================
-- 3DMP Service · 0124_service_s3.sql  (S3 — Сервис ЧПУ: правила IIoT, MTBF/загрузка, акт, интеграции)
-- Правила авто-тикетов IIoT (app_service_iot_rules), метрики MTBF и загрузка
-- инженеров, данные акта (app_service_act), события в app_integrations.
-- Идемпотентно. Зависит от 0001..0123.
-- ============================================================

create table if not exists public.app_service_iot_rules (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  metric     text not null,
  op         text not null default '>=',   -- >= | >
  threshold  numeric not null default 1,
  priority   text not null default 'critical',
  kind       text not null default 'repair',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_service_iot_rules_idx on public.app_service_iot_rules (tenant_id, metric, active);
alter table public.app_service_iot_rules enable row level security;

-- ---------- Правила ----------
drop function if exists public.app_service_iot_rules_list(uuid);
create or replace function public.app_service_iot_rules_list(p_token uuid)
returns table (id uuid, metric text, op text, threshold numeric, priority text, kind text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.metric, r.op, r.threshold, r.priority, r.kind, r.active
    from public.app_service_iot_rules r
    where (urole='admin' or r.tenant_id is null or r.tenant_id = ten)
    order by r.metric;
end $$;

drop function if exists public.app_service_iot_rule_save(uuid,uuid,text,text,numeric,text,text,boolean);
create or replace function public.app_service_iot_rule_save(
  p_token uuid, p_id uuid, p_metric text, p_op text, p_threshold numeric, p_priority text, p_kind text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; rid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_metric),'') = '' then return query select false, 'Укажите метрику', null::uuid; return; end if;
  if p_op is not null and p_op not in ('>=','>') then return query select false, 'Неверный оператор', null::uuid; return; end if;
  if p_priority is not null and p_priority not in ('low','normal','high','critical') then return query select false, 'Неверный приоритет', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_service_iot_rules (tenant_id, metric, op, threshold, priority, kind, active)
    values (ten, trim(p_metric), coalesce(nullif(trim(p_op),''),'>='), coalesce(p_threshold,1), coalesce(nullif(trim(p_priority),''),'critical'), coalesce(nullif(trim(p_kind),''),'repair'), coalesce(p_active,true))
    returning app_service_iot_rules.id into rid;
  else
    update public.app_service_iot_rules r set metric=trim(p_metric), op=coalesce(nullif(trim(p_op),''),r.op),
      threshold=coalesce(p_threshold,r.threshold), priority=coalesce(nullif(trim(p_priority),''),r.priority),
      kind=coalesce(nullif(trim(p_kind),''),r.kind), active=coalesce(p_active,r.active)
     where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten);
    if not found then return query select false, 'Правило не найдено', null::uuid; return; end if;
    rid := p_id;
  end if;
  return query select true, 'Правило сохранено', rid;
end $$;

drop function if exists public.app_service_iot_rule_delete(uuid,uuid);
create or replace function public.app_service_iot_rule_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_service_iot_rules r where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten);
  if not found then return query select false, 'Правило не найдено'; return; end if;
  return query select true, 'Правило удалено';
end $$;

-- ---------- Авто-тикеты IIoT по правилам (v2) ----------
create or replace function public.app_service_iiot_auto(p_token uuid, p_hours integer default 24)
returns table (created integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; r record; cnt int := 0; sid uuid; snum text;
        respmin integer; resmin integer; rpr text; rkind text;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return query select 0,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','view') then return query select 0,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select i.machine, i.metric, i.value, i.ts, i.tenant_id, e.id as eq_id, e.name as eq_name
      from public.app_iiot_readings i
      join public.app_equipment e on e.name = i.machine
     where (urole='admin' or i.tenant_id = ten)
       and coalesce(i.value,0) > 0
       and i.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours,24),168)))
       and (
         i.metric in ('fault','alarm','error')
         or exists (select 1 from public.app_service_iot_rules rr
                     where rr.active and rr.metric = i.metric and (rr.tenant_id is null or rr.tenant_id = i.tenant_id)
                       and ((rr.op = '>=' and i.value >= rr.threshold) or (rr.op = '>' and i.value > rr.threshold)))
       )
       and not exists (select 1 from public.app_service_requests s
                        where s.equipment_id = e.id and s.status not in ('done','cancelled'))
  loop
    select rr.priority, rr.kind into rpr, rkind from public.app_service_iot_rules rr
     where rr.active and rr.metric = r.metric and (rr.tenant_id is null or rr.tenant_id = r.tenant_id)
       and ((rr.op = '>=' and r.value >= rr.threshold) or (rr.op = '>' and r.value > rr.threshold))
     order by rr.threshold desc limit 1;
    rpr := coalesce(rpr, 'critical');
    rkind := coalesce(rkind, 'repair');
    select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes(rpr);
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, equipment_id, title, kind, priority, channel, source, fault_code, reported_at, response_due, resolve_due, created_login)
    values (ten, snum, r.eq_id, 'Авто-тикет IIoT: ' || r.metric || '=' || coalesce(r.value,0)::text || ' на ' || r.eq_name, rkind, rpr, 'iiot', 'iiot',
            r.metric || '=' || coalesce(r.value,0)::text, r.ts, now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), ulogin)
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Авто-тикет IIoT (' || rpr || '): ' || r.metric || '=' || coalesce(r.value,0)::text, 'iiot');
    cnt := cnt + 1;
  end loop;
  if cnt > 0 then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
            'IIoT: создано сервисных заявок — ' || cnt, 'Сработали правила ошибок ЧПУ', 'apps/service/index.html');
  end if;
  return query select cnt, case when cnt>0 then 'Создано заявок: ' || cnt else 'Новых срабатываний нет' end;
end $$;

-- ---------- KPI: MTBF, активные выезды, инженеры ----------
drop function if exists public.app_service_kpi_ext(uuid);
create or replace function public.app_service_kpi_ext(p_token uuid)
returns table (mtbf_hours numeric, active_visits bigint, engineers bigint, avg_resolve_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select
      (select round(avg(gap)/3600.0, 1) from (
         select extract(epoch from (reported_at - lag(reported_at) over (partition by equipment_id order by reported_at))) as gap
           from public.app_service_requests r
          where r.status = 'done' and r.kind in ('repair','service') and (urole='admin' or r.tenant_id = ten)
       ) g where gap is not null),
      (select count(*) from public.app_service_visits v where v.status not in ('done','cancelled') and (urole='admin' or v.tenant_id = ten)),
      (select count(distinct coalesce(v.engineer,'')) from public.app_service_visits v where v.status not in ('done','cancelled') and coalesce(v.engineer,'')<>'' and (urole='admin' or v.tenant_id = ten)),
      (select round(avg(extract(epoch from (resolved_at - coalesce(reported_at, created_at)))/3600.0), 1)
         from public.app_service_requests r where r.status='done' and r.resolved_at is not null and (urole='admin' or r.tenant_id = ten));
end $$;

drop function if exists public.app_service_engineer_load(uuid);
create or replace function public.app_service_engineer_load(p_token uuid)
returns table (engineer text, open_visits bigint, open_requests bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(v.engineer,'(не назначен)'),
           count(distinct v.id),
           count(distinct v.request_id)
      from public.app_service_visits v
     where v.status not in ('done','cancelled') and (urole='admin' or v.tenant_id = ten)
     group by coalesce(v.engineer,'(не назначен)')
     order by count(distinct v.id) desc;
end $$;

-- ---------- Данные акта ----------
drop function if exists public.app_service_act(uuid,uuid);
create or replace function public.app_service_act(p_token uuid, p_id uuid)
returns table (number text, customer text, equipment text, title text, works text, solution text,
               reported_at timestamptz, resolved_at timestamptz, cost numeric, parts_cost numeric, parts text, engineer text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.number, c.name, e.name, r.title, r.works, r.solution, r.reported_at, coalesce(r.resolved_at, r.closed_at),
           r.cost, r.parts_cost,
           (select string_agg(coalesce(sp.part_name,'') || ' × ' || sp.qty, ', ') from public.app_service_parts sp where sp.request_id = r.id),
           coalesce(r.assigned_login, r.engineer)
      from public.app_service_requests r
      left join public.app_customers c on c.id = r.customer_id
      left join public.app_equipment e on e.id = r.equipment_id
     where r.id = p_id and (urole='admin' or r.tenant_id = ten);
end $$;

-- ---------- Смена статуса v3: событие в интеграции при закрытии ----------
create or replace function public.app_service_set_status(p_token uuid, p_id uuid, p_status text, p_note text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; snum text; intg uuid;
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

  -- событие в интеграции (ERP/WMS/дилер) при выполнении
  if p_status = 'done' then
    begin
      select i.id into intg from public.app_integrations i
       where i.active and i.kind in ('odata','webhook','edo') and (i.tenant_id is null or i.tenant_id = ten)
       order by (i.kind = 'odata') desc limit 1;
      if intg is not null then
        perform public.app_integration_enqueue(p_token, intg, 'out', jsonb_build_object('event','service_done','number',snum,'request_id',p_id));
      end if;
    exception when others then null;
    end;
  end if;

  perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
          'Сервис ' || snum || ': ' || p_status, coalesce(nullif(trim(p_note),''), 'Обновлён статус заявки'), 'apps/service/index.html');
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_service_iot_rules_list(uuid)                              to anon, authenticated;
grant execute on function public.app_service_iot_rule_save(uuid,uuid,text,text,numeric,text,text,boolean) to anon, authenticated;
grant execute on function public.app_service_iot_rule_delete(uuid,uuid)                         to anon, authenticated;
grant execute on function public.app_service_kpi_ext(uuid)                                      to anon, authenticated;
grant execute on function public.app_service_engineer_load(uuid)                                to anon, authenticated;
grant execute on function public.app_service_act(uuid,uuid)                                     to anon, authenticated;

-- ---------- Демо-правила (тенант A) ----------
insert into public.app_service_iot_rules (tenant_id, metric, op, threshold, priority, kind, active)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.metric, v.op, v.thr, v.prio, v.kind, true
from (values ('fault','>=',1,'critical','repair'),
             ('alarm','>=',1,'high','repair'),
             ('temperature','>=',80,'high','repair'),
             ('vibration','>=',5,'normal','repair')) as v(metric,op,thr,prio,kind)
where not exists (
  select 1 from public.app_service_iot_rules r
   where r.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and r.metric = v.metric
);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Сервис ЧПУ: правила IIoT, MTBF, акт, интеграции',
   'Правила авто-тикетов IIoT (app_service_iot_rules): метрика, оператор (>=/>), порог, приоритет и вид заявки; сканер app_service_iiot_auto создаёт заявки по сработавшим правилам (плюс метрики fault/alarm/error). Метрики сервиса: app_service_kpi_ext (MTBF, активные выезды, инженеры, среднее время решения), app_service_engineer_load (загрузка инженеров). Данные акта — app_service_act (для печати/акта: заказчик, оборудование, работы, решение, запчасти, стоимость). При закрытии заявки событие уходит в интеграции (app_integration_enqueue: ERP/WMS/дилер).',
   'сервис ЧПУ IIoT правила порог MTBF загрузка инженер акт интеграции ERP WMS дилер')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Сервис ЧПУ: правила IIoT, MTBF, акт, интеграции'
);
