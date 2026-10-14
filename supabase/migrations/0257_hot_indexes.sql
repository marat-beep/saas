-- ============================================================
-- 3DMP Service · 0257_hot_indexes.sql  (PROP-04 — производительность горячих списков)
-- Индексы по горячим фильтрам/сортировке (tenant-scoped) + серверный лимит
-- для крупных списков (заявки/наряды). Идемпотентно. Зависит от 0001..0256.
-- ============================================================

create index if not exists ix_orders_tenant_created on public.app_orders (tenant_id, created_at desc);
create index if not exists ix_orders_tenant_status  on public.app_orders (tenant_id, status);
create index if not exists ix_naryads_tenant_order  on public.app_naryads (tenant_id, order_id);
create index if not exists ix_naryads_tenant_status on public.app_naryads (tenant_id, status);
create index if not exists ix_naryads_tenant_due    on public.app_naryads (tenant_id, due_date);
create index if not exists ix_qc_measures_check     on public.app_qc_measures (tenant_id, check_id);
create index if not exists ix_qc_measures_ts        on public.app_qc_measures (tenant_id, ts desc);
create index if not exists ix_tasks_tenant_status   on public.app_tasks (tenant_id, status);
create index if not exists ix_tasks_assignee        on public.app_tasks (tenant_id, assignee_login, status);
create index if not exists ix_tasks_due             on public.app_tasks (tenant_id, due_date);
create index if not exists ix_integration_tenant_created on public.app_integration_log (tenant_id, created_at desc);
create index if not exists ix_integration_status    on public.app_integration_log (tenant_id, status);
create index if not exists ix_sessions_expires      on public.app_sessions (expires_at);
create index if not exists ix_sessions_user         on public.app_sessions (user_id);

-- ---------- Серверный лимит на крупные списки (защита от выгрузки всей таблицы) ----------
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text, due_date date, assignee text, amount numeric, order_type text, created_login text, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.order_type, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or public.app_role_is_staff(urole) or o.created_by = uid)
      and public.app_dept_ok(p_token, o.department_id)
    order by o.created_at desc
    limit 2000;
end $$;
grant execute on function public.app_order_list(uuid) to anon, authenticated;

create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text, wc_name text, assignee text, status text, priority text, plan_hours numeric, fact_hours numeric, ops_total bigint, ops_done bigint, start_date date, due_date date, created_at timestamp with time zone)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.order_id, o.number, n.route_id, r.number, w.name, n.assignee, n.status,
           n.priority, n.plan_hours, n.fact_hours,
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id),
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id and op.done),
           n.start_date, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
      and public.app_dept_ok(p_token, n.department_id)
    order by n.created_at desc
    limit 2000;
end $$;
grant execute on function public.app_naryad_list(uuid) to anon, authenticated;
