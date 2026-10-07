-- ============================================================
-- 3DMP Service · 0127_service_workflow.sql  (S5 — эскалация SLA, связь с ППР, затраты в интеграцию)
-- Углубление процесса: контроль/эскалация SLA, автозаявки из ТОиР (ПРР),
-- обогащение события ERP стоимостью. Идемпотентно. Зависит от 0001..0126.
-- ============================================================

alter table public.app_service_requests add column if not exists sla_notified_at timestamptz;
alter table public.app_service_requests add column if not exists plan_id uuid references public.app_mnt_plans (id) on delete set null;

-- ---------- Контроль и эскалация SLA ----------
drop function if exists public.app_service_sla_scan(uuid);
create or replace function public.app_service_sla_scan(p_token uuid)
returns table (escalated integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; r record; cnt int := 0;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return query select 0,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','view') then return query select 0,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select s.id, s.number, s.title, s.priority, s.equipment_id, s.resolve_due
      from public.app_service_requests s
     where (urole='admin' or s.tenant_id = ten)
       and s.status not in ('done','cancelled')
       and s.resolve_due is not null and s.resolve_due < now()
       and s.sla_notified_at is null
  loop
    update public.app_service_requests set sla_notified_at = now() where id = r.id;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, r.id, 'sla', 'SLA просрочен — эскалация руководству', coalesce((select ulogin from public.app_session_user(p_token)),'system'));
    -- критичные дополнительно эскалируются в проблему
    if r.priority = 'critical' and (select issue_id from public.app_service_requests where id = r.id) is null then
      begin
        perform public.app_service_escalate(p_token, r.id, 'Просрочен SLA (критичная заявка)');
      exception when others then null;
      end;
    end if;
    perform public.app_notif_roles_t(coalesce((select tenant_id from public.app_service_requests where id=r.id),ten),
            array['admin','owner','director','manager','chief','master'],
            'SLA ПРОСРОЧЕН: ' || r.number, coalesce(r.title,'') || ' · до ' || to_char(r.resolve_due,'DD.MM HH24:MI'), 'apps/service/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, case when cnt>0 then 'Эскалировано заявок: ' || cnt else 'Просрочек SLA нет' end;
end $$;

-- ---------- Автозаявки из ТОиР (ППР по наработке/сроку) ----------
drop function if exists public.app_service_ppr_scan(uuid);
create or replace function public.app_service_ppr_scan(p_token uuid)
returns table (created integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; r record; cnt int := 0; sid uuid; snum text; respmin int; resmin int;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return query select 0,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','view') then return query select 0,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes('normal');
  for r in
    select p.id as plan_id, p.tenant_id, p.equipment_id, p.kind, p.responsible, e.name as eq_name, rs.status
      from public.app_mnt_runtime_status(p_token) rs
      join public.app_mnt_plans p on p.id = rs.plan_id
      left join public.app_equipment e on e.id = p.equipment_id
     where rs.status = 'overdue'
       and not exists (select 1 from public.app_service_requests s
                        where s.equipment_id = p.equipment_id and s.status not in ('done','cancelled'))
       and not exists (select 1 from public.app_service_requests s where s.plan_id = p.id and s.status not in ('done','cancelled'))
  loop
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, equipment_id, title, kind, priority, channel, source, plan_id, reported_at, response_due, resolve_due, assigned_login, created_login)
    values (coalesce(r.tenant_id,ten), snum, r.equipment_id, 'ППР: ' || coalesce(r.eq_name,'оборудование') || ' (' || coalesce(r.kind,'ТО') || ')',
            'service', 'high', 'manual', 'ppr', r.plan_id, now(), now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), r.responsible,
            (select ulogin from public.app_session_user(p_token)))
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (coalesce(r.tenant_id,ten), sid, 'event', 'Автозаявка из ТОиР (ППР по наработке/сроку)', 'system');
    cnt := cnt + 1;
  end loop;
  if cnt > 0 then
    perform public.app_notif_roles_t(ten, array['admin','owner','director','manager','chief','master'],
            'ППР: создано сервисных заявок — ' || cnt, 'Плановые ТО по наработке/сроку', 'apps/service/index.html');
  end if;
  return query select cnt, case when cnt>0 then 'Создано по ППР: ' || cnt else 'Плановых к запуску нет' end;
end $$;

-- ---------- app_service_get: план ТОиР ----------
drop function if exists public.app_service_get(uuid,uuid);
create or replace function public.app_service_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, customer_id uuid, customer text, equipment_id uuid, equipment text, title text,
               kind text, status text, priority text, channel text, source text, is_warranty boolean,
               contact text, location text, fault_code text, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, closed_at timestamptz,
               labor_hours numeric, downtime_hours numeric, cost numeric, parts_cost numeric, works text, note text,
               root_cause text, solution text, satisfaction integer, warranty_id uuid, warranty_number text,
               contract_id uuid, contract_number text, plan_id uuid, sla_state text, created_at timestamptz)
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
           s.labor_hours, s.downtime_hours, s.cost, s.parts_cost, s.works, s.note, s.root_cause, s.solution, s.satisfaction,
           s.warranty_id, w.number, s.contract_id, k.number, s.plan_id,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    left join public.app_warranties w on w.id = s.warranty_id
    left join public.app_service_contracts k on k.id = s.contract_id
    where s.id = p_id and (urole='admin' or s.tenant_id = ten);
end $$;

-- ---------- app_service_complete: стоимость в событие ERP ----------
create or replace function public.app_service_complete(
  p_token uuid, p_id uuid, p_works text, p_solution text,
  p_labor_hours numeric default null, p_downtime_hours numeric default null, p_cost numeric default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; snum text; intg uuid; vcost numeric; vparts numeric; visw boolean;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select number into snum from public.app_service_requests where id=p_id and (public.app_is_platform_admin(p_token) or tenant_id=ten);
  if snum is null then return query select false, 'Заявка не найдена'; return; end if;
  update public.app_service_requests set
    works = coalesce(nullif(trim(p_works),''), works),
    solution = coalesce(nullif(trim(p_solution),''), solution),
    labor_hours = coalesce(p_labor_hours, labor_hours),
    downtime_hours = coalesce(p_downtime_hours, downtime_hours),
    cost = coalesce(p_cost, cost),
    status = 'done', first_response_at = coalesce(first_response_at, now()),
    resolved_at = coalesce(resolved_at, now()), closed_at = coalesce(closed_at, now()), updated_at = now()
   where id = p_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, 'event', 'Работа завершена: ' || coalesce(nullif(trim(p_solution),''), coalesce(nullif(trim(p_works),''),'—')), ulogin);
  update public.app_service_visits set status='done', finished_at=coalesce(finished_at, now()),
         work_report=coalesce(work_report, nullif(trim(p_solution),''))
   where request_id = p_id and status not in ('done','cancelled');
  select coalesce(cost,0), coalesce(parts_cost,0), is_warranty into vcost, vparts, visw from public.app_service_requests where id=p_id;
  begin
    select i.id into intg from public.app_integrations i
     where i.active and i.kind in ('odata','webhook','edo') and (i.tenant_id is null or i.tenant_id = ten)
     order by (i.kind='odata') desc limit 1;
    if intg is not null then
      perform public.app_integration_enqueue(p_token, intg, 'out',
        jsonb_build_object('event','service_done','number',snum,'request_id',p_id,'cost',vcost,'parts_cost',vparts,'total',vcost+vparts,'warranty',visw));
    end if;
  exception when others then null;
  end;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
          'Сервис ' || snum || ': работа завершена', coalesce(nullif(trim(p_solution),''),'Заявка закрыта'), 'apps/service/index.html');
  return query select true, 'Работа завершена';
end $$;

grant execute on function public.app_service_sla_scan(uuid)                                   to anon, authenticated;
grant execute on function public.app_service_ppr_scan(uuid)                                   to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Процесс сервиса: SLA-эскалация, ППР, затраты',
   'Контроль SLA: app_service_sla_scan находит открытые заявки с просроченным сроком решения, пишет событие, уведомляет руководство (директор/руководитель) и для критичных создаёт проблему (app_service_escalate). Связь с ТОиР: app_service_ppr_scan по планам с просроченной наработкой/сроком создаёт превентивные сервисные заявки (source=ppr, plan_id). Затраты: при завершении (app_service_complete) событие service_done уходит в app_integrations с полями cost/parts_cost/total/warranty для ERP.',
   'сервис SLA эскалация директор ППР ТОиР превентивная заявка затраты ERP интеграция')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Процесс сервиса: SLA-эскалация, ППР, затраты'
);
