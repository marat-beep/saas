-- ============================================================
-- 3DMP Service · 0125_service_s4.sql  (S4 — роли/отчёты/снабжение/паспорт станка + тестовые данные)
-- Цифровой паспорт станка, отчёт сервиса за период, заявка на снабжение
-- для ремонта, демонстрационные данные. Идемпотентно. Зависит от 0001..0124.
-- ============================================================

-- ---------- Цифровой паспорт станка ----------
drop function if exists public.app_equipment_passport(uuid,uuid);
create or replace function public.app_equipment_passport(p_token uuid, p_equipment_id uuid)
returns table (id uuid, code text, name text, model text, kind text, status text, dept text, cost_hour numeric,
               warranty_number text, warranty_end date,
               requests_total bigint, requests_open bigint, requests_done bigint, last_repair timestamptz,
               mtbf_hours numeric, mttr_hours numeric,
               plans bigint, last_plan_kind text, last_plan_date date,
               iiot_last_ts timestamptz, iiot_last_metric text, iiot_last_value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.model, e.kind, e.status, e.dept, e.cost_hour,
           (select w.number from public.app_warranties w where w.equipment_id = e.id and w.active order by w.end_date desc nulls last limit 1),
           (select w.end_date from public.app_warranties w where w.equipment_id = e.id and w.active order by w.end_date desc nulls last limit 1),
           (select count(*) from public.app_service_requests r where r.equipment_id = e.id and (urole='admin' or r.tenant_id=ten)),
           (select count(*) from public.app_service_requests r where r.equipment_id = e.id and r.status not in ('done','cancelled') and (urole='admin' or r.tenant_id=ten)),
           (select count(*) from public.app_service_requests r where r.equipment_id = e.id and r.status='done' and (urole='admin' or r.tenant_id=ten)),
           (select max(coalesce(r.resolved_at, r.closed_at)) from public.app_service_requests r where r.equipment_id = e.id and (urole='admin' or r.tenant_id=ten)),
           (select round(avg(gap)/3600.0,1) from (
              select extract(epoch from (reported_at - lag(reported_at) over (order by reported_at))) as gap
                from public.app_service_requests r where r.equipment_id = e.id and r.status='done'
           ) g where gap is not null),
           (select round(avg(extract(epoch from (resolved_at - coalesce(reported_at, created_at)))/3600.0),1)
              from public.app_service_requests r where r.equipment_id = e.id and r.status='done' and r.resolved_at is not null),
           (select count(*) from public.app_mnt_plans p where p.equipment_id = e.id and coalesce(p.active,true)),
           (select p.kind from public.app_mnt_plans p where p.equipment_id = e.id order by p.next_due nulls last limit 1),
           (select p.last_done from public.app_mnt_plans p where p.equipment_id = e.id order by p.last_done desc nulls last limit 1),
           (select i.ts from public.app_iiot_readings i where i.machine = e.name order by i.ts desc limit 1),
           (select i.metric from public.app_iiot_readings i where i.machine = e.name order by i.ts desc limit 1),
           (select i.value from public.app_iiot_readings i where i.machine = e.name order by i.ts desc limit 1)
      from public.app_equipment e
     where e.id = p_equipment_id and (urole='admin' or e.tenant_id = ten);
end $$;

-- ---------- Отчёт сервиса за период ----------
drop function if exists public.app_service_report(uuid,date,date);
create or replace function public.app_service_report(p_token uuid, p_from date default null, p_to date default null)
returns table (number text, customer text, equipment text, title text, priority text, status text,
               reported_at timestamptz, resolved_at timestamptz, cost numeric, parts_cost numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; d1 date; d2 date;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  d1 := coalesce(p_from, current_date - 90);
  d2 := coalesce(p_to, current_date);
  return query
    select r.number, c.name, e.name, r.title, r.priority, r.status, r.reported_at, r.resolved_at,
           r.cost, r.parts_cost, coalesce(r.cost,0) + coalesce(r.parts_cost,0)
      from public.app_service_requests r
      left join public.app_customers c on c.id = r.customer_id
      left join public.app_equipment e on e.id = r.equipment_id
     where (urole='admin' or r.tenant_id = ten)
       and coalesce(r.reported_at, r.created_at)::date between d1 and d2
     order by coalesce(r.reported_at, r.created_at) desc;
end $$;

-- ---------- Заявка на снабжение для ремонта (закупка запчастей) ----------
drop function if exists public.app_service_supply_request(uuid,uuid,text,numeric,text);
create or replace function public.app_service_supply_request(
  p_token uuid, p_id uuid, p_material text, p_qty numeric, p_note text default null
) returns table (ok boolean, message text, tender_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; r record; tid uuid; ten2 uuid; q numeric;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_material), '') = '' then return query select false, 'Укажите материал/запчасть', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select s.number, s.tenant_id, s.equipment_id into r from public.app_service_requests s
   where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten);
  if r.number is null then return query select false, 'Заявка не найдена', null::uuid; return; end if;
  q := coalesce(nullif(p_qty,0), 1);
  ten2 := coalesce(r.tenant_id, ten);
  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, assignee, status, tenant_id)
  values ('Снабжение для ремонта ' || r.number, coalesce(nullif(trim(p_note),''),'Запчасти для сервисной заявки ' || r.number),
          'Запчасти', trim(p_material), q, 'шт', null, current_date + 10, null, null, 'open', ten2)
  returning tenders.id into tid;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten2, p_id, 'event', 'Заявка на снабжение: ' || trim(p_material) || ' × ' || q, ulogin);
  perform public.app_notif_roles_t(ten2, array['admin','owner','manager','supply','chief'],
          'Снабжение для ремонта ' || r.number, trim(p_material) || ' × ' || q, 'apps/procurement/index.html');
  return query select true, 'Заявка на снабжение создана', tid;
end $$;

grant execute on function public.app_equipment_passport(uuid,uuid)                        to anon, authenticated;
grant execute on function public.app_service_report(uuid,date,date)                      to anon, authenticated;
grant execute on function public.app_service_supply_request(uuid,uuid,text,numeric,text) to anon, authenticated;

-- ============================================================
--  Тестовые (демо) данные сервиса — тенант A
-- ============================================================
-- Дополнительные заявки разных статусов/приоритетов (если их ещё нет по заголовку)
insert into public.app_service_requests
  (tenant_id, number, customer_id, equipment_id, title, kind, status, priority, channel, source, is_warranty,
   contact, location, assigned_login, engineer, works, cost, reported_at, response_due, resolve_due, first_response_at, resolved_at, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
       'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0'),
       (select c.id from public.app_customers c where c.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by c.created_at limit 1),
       (select e.id from public.app_equipment e where e.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by e.created_at limit 1),
       v.title, v.kind, v.status, v.prio, v.chan, 'manual', v.warr, v.contact, v.place, v.eng, v.eng, v.works, v.cost,
       now() - make_interval(days => v.days_ago, hours => 3),
       now() - make_interval(days => v.days_ago) + interval '1 hour',
       now() - make_interval(days => v.days_ago) + interval '8 hours',
       case when v.status in ('in_progress','scheduled') then now() - make_interval(days => v.days_ago) + interval '40 minutes' else null end,
       case when v.status = 'done' then now() - make_interval(days => v.days_ago) + interval '6 hours' else null end,
       'service'
from (values
  ('Плановое ТО-2 шпиндельного узла','service','done','normal','phone',false,'+7 495 000-00-01','Цех 1','master','Регламент ТО-2 выполнен, заменена смазка',18000,12),
  ('Вибрация при разгоне шпинделя','repair','in_progress','high','iiot',false,'+7 495 000-00-02','Цех 1','master','Диагностика подшипников, замена',42000,3),
  ('Сбой смены инструмента','repair','done','critical','phone',true,'+7 495 000-00-03','Цех 2','master','Заменён датчик, калибровка',27000,20),
  ('Плановое ТО-1 направляющих','service','scheduled','low','email',false,'+7 495 000-00-04','Цех 1','master',null,9000,1),
  ('Перегрев шпинделя ALM 401','repair','in_progress','critical','iiot',true,'+7 495 000-00-05','Цех 1','master','Проверка системы охлаждения',31000,0)
) as v(title,kind,status,prio,chan,warr,contact,place,eng,works,cost,days_ago)
where not exists (
  select 1 from public.app_service_requests r
   where r.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and r.title = v.title
);

-- История для новых заявок
insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
select r.tenant_id, r.id, 'event', 'Заявка создана (' || r.priority || ')', 'service'
from public.app_service_requests r
where r.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_service_history h where h.request_id = r.id);

-- Выезды для заявок в работе/завершённых
insert into public.app_service_visits (tenant_id, request_id, engineer, planned_at, arrived_at, finished_at, status, place, work_report)
select r.tenant_id, r.id, coalesce(r.assigned_login,'master'),
       coalesce(r.reported_at, now()), case when r.status='done' then coalesce(r.reported_at, now()) + interval '30 minutes' else null end,
       case when r.status='done' then coalesce(r.resolved_at, now()) else null end,
       case when r.status='done' then 'done' when r.status='in_progress' then 'in_work' else 'assigned' end,
       r.location, case when r.status='done' then 'Работы выполнены, станок запущен' else null end
from public.app_service_requests r
where r.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and r.status in ('done','in_progress')
  and not exists (select 1 from public.app_service_visits v where v.request_id = r.id);

-- События истории по выездам
insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
select v.tenant_id, v.request_id, 'visit', 'Выезд: ' || v.status, v.engineer
from public.app_service_visits v
where v.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_service_history h where h.request_id = v.request_id and h.kind='visit');

-- Демо закупка запчастей для ремонта (снабжение)
insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, order_id, assignee, status, tenant_id)
select 'Снабжение для ремонта ЧПУ', 'Запчасти для сервисных заявок (подшипники, энкодеры).', 'Запчасти', 'Подшипник 6205', 10, 'шт', null, current_date + 14, null, null, 'open', 'aaaaaaaa-0000-0000-0000-000000000001'
where not exists (
  select 1 from public.tenders t where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and t.title = 'Снабжение для ремонта ЧПУ'
);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Сервис ЧПУ: роли, отчёты, паспорт станка, снабжение',
   'Содержимое по ролям: руководитель предприятия — дашборд/BI и KPI сервиса (SLA, MTTR, MTBF, FTFR, CSAT, затраты); главный инженер — паспорт станка (app_equipment_passport), история ремонтов и ТОиР, IIoT; начальник цеха — заявки/выезды цеха, загрузка инженеров (app_service_engineer_load); сервисный инженер — «Мои выезды» (app_service_my_visits, офлайн). Отчёты: app_service_report за период, выгрузка PDF/DOC/CSV (AppExport). Паспорт станка — цифровая карточка оборудования с гарантией, историей сервиса, MTBF/MTTR, ТОиР и телеметрией. Заявка на снабжение для ремонта — app_service_supply_request (создаёт закупку в тендерах).',
   'сервис роли руководитель главный инженер начальник цеха инженер отчёт PDF паспорт станка снабжение закупка')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Сервис ЧПУ: роли, отчёты, паспорт станка, снабжение'
);
