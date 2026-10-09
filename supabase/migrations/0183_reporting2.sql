-- ============================================================
-- 3DMP Service · 0183_reporting2.sql  (план v4, W41 «Отчётность/BI 2.0»)
-- Дашборд KPI по контурам, расписание рассылки отчётов (постановка в очередь
-- интеграций), запуск по расписанию. Идемпотентно. Зависит от 0001..0182.
-- ============================================================

-- ---------- Дашборд KPI по контурам ----------
create or replace function public.app_dashboard_kpis(p_token uuid)
returns table (contour text, metric text, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select 'Заказы'::text, 'Всего'::text, count(*)::numeric from public.app_orders o where (urole='admin' or o.tenant_id = ten)
    union all select 'Заказы', 'В работе', count(*)::numeric from public.app_orders o where o.status <> 'closed' and (urole='admin' or o.tenant_id = ten)
    union all select 'Производство', 'Наряды активные', count(*)::numeric from public.app_naryads n where n.status not in ('done','closed') and (urole='admin' or n.tenant_id = ten)
    union all select 'Качество', 'Проверки ОТК', count(*)::numeric from public.app_qc_checks q where (urole='admin' or q.tenant_id = ten)
    union all select 'Склад', 'Ниже минимума', count(*)::numeric from public.app_materials m where m.qty < m.min_qty and m.min_qty > 0 and (urole='admin' or m.tenant_id = ten)
    union all select 'Сервис', 'Открытые заявки', count(*)::numeric from public.app_service_requests r where r.status <> 'closed' and (urole='admin' or r.tenant_id = ten)
    union all select 'Закупки', 'Тендеры открытые', count(*)::numeric from public.tenders t where t.status = 'open' and (urole='admin' or t.tenant_id = ten)
    union all select 'Логистика', 'Рейсы активные', count(*)::numeric from public.app_transport_orders tr where tr.status <> 'done' and (urole='admin' or tr.tenant_id = ten)
    union all select 'ИТ-сервис', 'Открытые тикеты', count(*)::numeric from public.app_it_tickets it where it.status <> 'closed' and (urole='admin' or it.tenant_id = ten)
    union all select 'Задачи', 'В работе', count(*)::numeric from public.app_tasks tk where tk.status in ('new','in_progress') and (urole='admin' or tk.tenant_id = ten)
    union all select 'Интеграции', 'В очереди', count(*)::numeric from public.app_integration_log il where il.status in ('pending','error','failed') and (urole='admin' or il.tenant_id = ten);
end $$;
grant execute on function public.app_dashboard_kpis(uuid) to anon, authenticated;

-- ---------- Расписание рассылки отчётов ----------
create table if not exists public.app_report_schedules (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  name        text not null,
  module      text not null,
  format      text not null default 'pdf',   -- pdf|csv|xls
  period      text not null default 'daily', -- daily|weekly|monthly
  channel     text not null default 'email', -- email|telegram|webhook
  target      text,
  enabled     boolean not null default true,
  last_run_at timestamptz,
  next_run_at timestamptz not null default now(),
  created_by  text,
  created_at  timestamptz not null default now()
);
create index if not exists app_report_schedules_due_idx on public.app_report_schedules (enabled, next_run_at);
alter table public.app_report_schedules enable row level security;

create or replace function public.app_report_schedules_list(p_token uuid)
returns table (id uuid, name text, module text, format text, period text, channel text, target text,
               enabled boolean, last_run_at timestamptz, next_run_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query select s.id, s.name, s.module, s.format, s.period, s.channel, s.target, s.enabled, s.last_run_at, s.next_run_at
    from public.app_report_schedules s where s.tenant_id = ten order by s.name;
end $$;

create or replace function public.app_report_schedule_save(p_token uuid, p_id uuid, p_name text, p_module text,
  p_format text, p_period text, p_channel text, p_target text, p_enabled boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uname text; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select s.urole, s.ulogin into urole, uname from public.app_session_user(p_token) s;
  if urole not in ('admin','owner','manager','economist','director') then return query select false,'Недостаточно прав',null::uuid; return; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_module),'')='' then return query select false,'Укажите название и модуль',null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_report_schedules (tenant_id, name, module, format, period, channel, target, enabled, next_run_at, created_by)
    values (ten, trim(p_name), trim(p_module), coalesce(nullif(trim(p_format),''),'pdf'), coalesce(nullif(trim(p_period),''),'daily'),
            coalesce(nullif(trim(p_channel),''),'email'), nullif(trim(p_target),''), coalesce(p_enabled,true), now(), uname)
    returning app_report_schedules.id into nid;
  else
    update public.app_report_schedules set name=trim(p_name), module=trim(p_module),
           format=coalesce(nullif(trim(p_format),''),format), period=coalesce(nullif(trim(p_period),''),period),
           channel=coalesce(nullif(trim(p_channel),''),channel), target=nullif(trim(p_target),''),
           enabled=coalesce(p_enabled,enabled), next_run_at=case when coalesce(p_enabled,enabled) then now() else next_run_at end
     where id=p_id and tenant_id=ten returning app_report_schedules.id into nid;
    if nid is null then return query select false,'Расписание не найдено',null::uuid; return; end if;
  end if;
  return query select true,'Расписание сохранено',nid;
end $$;

create or replace function public.app_report_schedule_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole not in ('admin','owner','manager','economist','director') then return query select false,'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_report_schedules where id=p_id and tenant_id=ten;
  if not found then return query select false,'Расписание не найдено'; return; end if;
  return query select true,'Расписание удалено';
end $$;

-- Постановка отчёта в очередь интеграций и расчёт следующего запуска
create or replace function public.app_report_schedule_run(p_token uuid, p_id uuid)
returns table (ok boolean, message text, next_run_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; r record; nx timestamptz; n int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into r from public.app_report_schedules where id = p_id and tenant_id = ten;
  if r.id is null then return query select false,'Расписание не найдено',null; return; end if;
  n := (select count(*) from public.app_module_report(p_token, r.module));  -- проверка доступности данных
  insert into public.app_integration_log (tenant_id, kind, direction, status, payload, message)
  values (ten, 'report', 'out', 'pending',
          jsonb_build_object('schedule', r.name, 'module', r.module, 'format', r.format, 'channel', r.channel, 'target', r.target),
          'Плановая рассылка отчёта');
  nx := case r.period when 'weekly' then now() + interval '7 days' when 'monthly' then now() + interval '30 days' else now() + interval '1 day' end;
  update public.app_report_schedules set last_run_at = now(), next_run_at = nx where id = r.id;
  perform public.app_log_event(p_token, 'Рассылка отчёта', r.name || ' → ' || r.channel);
  return query select true, 'Отчёт поставлен в очередь', nx;
end $$;

-- Обработка всех просроченных расписаний (для планировщика/крона)
create or replace function public.app_report_run_due(p_token uuid)
returns table (ok boolean, message text, cnt integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; r record; n int := 0;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in select * from public.app_report_schedules where tenant_id = ten and enabled and next_run_at <= now() loop
    insert into public.app_integration_log (tenant_id, kind, direction, status, payload, message)
    values (ten, 'report', 'out', 'pending',
            jsonb_build_object('schedule', r.name, 'module', r.module, 'format', r.format, 'channel', r.channel, 'target', r.target),
            'Плановая рассылка отчёта (due)');
    update public.app_report_schedules
       set last_run_at = now(),
           next_run_at = case r.period when 'weekly' then now() + interval '7 days' when 'monthly' then now() + interval '30 days' else now() + interval '1 day' end
     where id = r.id;
    n := n + 1;
  end loop;
  return query select true, 'Обработано расписаний: ' || n, n;
end $$;

grant execute on function public.app_report_schedules_list(uuid) to anon, authenticated;
grant execute on function public.app_report_schedule_save(uuid,uuid,text,text,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_report_schedule_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_report_schedule_run(uuid,uuid) to anon, authenticated;
grant execute on function public.app_report_run_due(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Администрирование','Отчётность 2.0: дашборд KPI и расписание рассылки',
 'W41: дашборд KPI по контурам (app_dashboard_kpis: заказы, производство, качество, склад, сервис, закупки, логистика, ИТ, задачи, интеграции). Расписание рассылки отчётов (app_report_schedules: list/save/delete/run; app_report_run_due для планировщика): отчёт по модулю ставится в очередь интеграций (app_integration_log, kind=report) и отправляется активным каналом (e-mail/Telegram/webhook). Экспорт — PDF/CSV/XLS(X) в модулях и конструкторе отчётов.',
 'отчётность bi дашборд kpi расписание рассылка отчёт xls app_dashboard_kpis app_report_schedules'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Отчётность 2.0: дашборд KPI и расписание рассылки');
