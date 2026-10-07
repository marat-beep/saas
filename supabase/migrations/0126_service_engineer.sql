-- ============================================================
-- 3DMP Service · 0126_service_engineer.sql  (выезды обезличенно, завершение работы, эскалация)
-- Доска выездов (все/команда), завершение работы с отчётом, эскалация
-- проблемы из заявки. Идемпотентно. Зависит от 0001..0125.
-- ============================================================

-- ---------- Доска выездов (обезличенно, по организации) ----------
drop function if exists public.app_service_visit_board(uuid,integer);
create or replace function public.app_service_visit_board(p_token uuid, p_days integer default 30)
returns table (visit_id uuid, request_id uuid, number text, title text, equipment text, customer text,
               priority text, status text, place text, engineer text, planned_at timestamptz, sla_state text, fault_code text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; d int;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  d := greatest(1, least(coalesce(p_days, 30), 365));
  return query
    select v.id, r.id, r.number, r.title, e.name, c.name, r.priority, v.status, coalesce(v.place, r.location), v.engineer, v.planned_at,
           case when r.status = 'done' then 'closed'
                when r.resolve_due is not null and r.resolve_due < now() then 'overdue'
                when r.resolve_due is not null and r.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           r.fault_code
      from public.app_service_visits v
      join public.app_service_requests r on r.id = v.request_id
      left join public.app_equipment e on e.id = r.equipment_id
      left join public.app_customers c on c.id = r.customer_id
     where (urole='admin' or v.tenant_id = ten)
       and (v.status not in ('done','cancelled') or v.created_at > now() - make_interval(days => d))
     order by (v.status = 'assigned') desc, coalesce(v.planned_at, v.created_at) desc;
end $$;

-- ---------- Завершение работы с отчётом (инженер) ----------
drop function if exists public.app_service_complete(uuid,uuid,text,text,numeric,numeric,numeric);
create or replace function public.app_service_complete(
  p_token uuid, p_id uuid, p_works text, p_solution text,
  p_labor_hours numeric default null, p_downtime_hours numeric default null, p_cost numeric default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; snum text; intg uuid;
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
    status = 'done',
    first_response_at = coalesce(first_response_at, now()),
    resolved_at = coalesce(resolved_at, now()),
    closed_at = coalesce(closed_at, now()),
    updated_at = now()
   where id = p_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, 'event', 'Работа завершена: ' || coalesce(nullif(trim(p_solution),''), coalesce(nullif(trim(p_works),''),'—')), ulogin);
  -- закрыть активные выезды
  update public.app_service_visits set status='done', finished_at=coalesce(finished_at, now()),
         work_report=coalesce(work_report, nullif(trim(p_solution),''))
   where request_id = p_id and status not in ('done','cancelled');
  -- событие в интеграции
  begin
    select i.id into intg from public.app_integrations i
     where i.active and i.kind in ('odata','webhook','edo') and (i.tenant_id is null or i.tenant_id = ten)
     order by (i.kind='odata') desc limit 1;
    if intg is not null then perform public.app_integration_enqueue(p_token, intg, 'out', jsonb_build_object('event','service_done','number',snum,'request_id',p_id)); end if;
  exception when others then null;
  end;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
          'Сервис ' || snum || ': работа завершена', coalesce(nullif(trim(p_solution),''),'Заявка закрыта'), 'apps/service/index.html');
  return query select true, 'Работа завершена';
end $$;

-- ---------- Эскалация проблемы из заявки ----------
drop function if exists public.app_service_escalate(uuid,uuid,text);
create or replace function public.app_service_escalate(p_token uuid, p_id uuid, p_note text default null)
returns table (ok boolean, message text, issue_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; r record; iid uuid; prio text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select s.id, s.number, s.title, s.priority, s.equipment_id, s.assigned_login, s.issue_id, s.tenant_id into r
    from public.app_service_requests s where s.id=p_id and (public.app_is_platform_admin(p_token) or s.tenant_id=ten);
  if r.number is null then return query select false, 'Заявка не найдена', null::uuid; return; end if;
  if r.issue_id is not null then return query select true, 'Заявка уже связана с проблемой', r.issue_id; return; end if;
  prio := case when r.priority='critical' then 'critical' when r.priority='high' then 'high' else 'normal' end;
  insert into public.app_issues (tenant_id, title, description, priority, source, status, assignee, equipment_id, escalated, escalated_at, created_login)
  values (coalesce(r.tenant_id,ten), 'Сервис ' || r.number || ': ' || coalesce(r.title,'проблема'),
          coalesce(nullif(trim(p_note),''), 'Проблема по сервисной заявке ' || r.number),
          prio, 'service', 'open', r.assigned_login, r.equipment_id, true, now(), ulogin)
  returning id into iid;
  update public.app_service_requests set issue_id = iid, updated_at = now() where id = p_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (coalesce(r.tenant_id,ten), p_id, 'event', 'Эскалация в проблему: ' || coalesce(nullif(trim(p_note),''),'—'), ulogin);
  perform public.app_notif_roles_t(coalesce(r.tenant_id,ten), array['admin','owner','manager','director','chief','master'],
          'Сервис ' || r.number || ': проблема', coalesce(nullif(trim(p_note),''),'Эскалация заявки'), 'apps/issues/index.html');
  return query select true, 'Проблема создана', iid;
end $$;

grant execute on function public.app_service_visit_board(uuid,integer)                       to anon, authenticated;
grant execute on function public.app_service_complete(uuid,uuid,text,text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_service_escalate(uuid,uuid,text)                        to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Работа инженера: выезд, отчёт, проблемы',
   'Доска выездов (app_service_visit_board) — все выезды организации (обезличенно), с заявкой, оборудованием, приоритетом и SLA. В окне заявки инженер имеет: полную информацию (заказчик, оборудование, место, контакт, код ошибки, SLA), историю, выезды, запчасти (app_service_part_add/remove), завершение работы с отчётом (app_service_complete: работы/решение/часы/простой/стоимость), эскалацию проблемы (app_service_escalate → app_issues), акт и паспорт станка, снабжение (app_service_supply_request).',
   'сервис инженер выезд отчёт завершение проблема эскалация запчасти акт паспорт')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Работа инженера: выезд, отчёт, проблемы'
);
