-- ============================================================
-- 3DMP Service · 0186_perf.sql  (план v4, W44 «Производительность и масштаб»)
-- Индексы по горячим запросам (списки/фильтры/сортировки) для больших объёмов.
-- Идемпотентно. Зависит от 0001..0185.
-- ============================================================

-- Сессии и входы
create index if not exists app_sessions_token_user_idx on public.app_sessions (user_id, expires_at desc);
create index if not exists app_login_attempts_login_idx on public.app_login_attempts (login, created_at desc);
create index if not exists app_events_created_idx on public.app_events (created_at desc);

-- Заказы / наряды / производство
create index if not exists app_orders_tenant_status_idx on public.app_orders (tenant_id, status);
create index if not exists app_orders_created_idx on public.app_orders (created_at desc);
create index if not exists app_naryads_tenant_status_idx on public.app_naryads (tenant_id, status);
create index if not exists app_naryads_due_idx on public.app_naryads (due_date);
create index if not exists app_qc_checks_tenant_idx on public.app_qc_checks (tenant_id, created_at desc);
create index if not exists app_qc_measures_param_idx on public.app_qc_measures (param, ts desc);

-- Сервис / ИТ / логистика / задачи
create index if not exists app_service_req_tenant_status_idx on public.app_service_requests (tenant_id, status);
create index if not exists app_it_tickets_tenant_status_idx on public.app_it_tickets (tenant_id, status);
create index if not exists app_transport_tenant_status_idx on public.app_transport_orders (tenant_id, status);
create index if not exists app_tasks_tenant_status_idx on public.app_tasks (tenant_id, status);

-- Материалы / склад / интеграции
create index if not exists app_materials_tenant_idx on public.app_materials (tenant_id);
create index if not exists app_integration_log_status_idx on public.app_integration_log (status, created_at desc);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Администрирование','Производительность: индексы по горячим запросам',
 'W44: добавлены индексы для ускорения списков и фильтров больших объёмов — сессии/входы (app_sessions, app_login_attempts, app_events), заказы/наряды/ОТК (app_orders, app_naryads, app_qc_checks, app_qc_measures), сервис/ИТ/логистика/задачи (app_service_requests, app_it_tickets, app_transport_orders, app_tasks), материалы/интеграции (app_materials, app_integration_log). При росте данных пересматривать планы (EXPLAIN ANALYZE) и добавлять составные индексы.',
 'производительность индексы производительность масштаб большие списки explain'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Производительность: индексы по горячим запросам');
