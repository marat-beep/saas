-- ============================================================
-- 3DMP Service · 0265_worktime.sql  (R4 · PROP-25 — WBS и учёт времени)
-- Иерархия работ проекта (app_wbs) + табели времени (app_timesheets) + сводка. Идемпотентно.
-- ============================================================

create table if not exists public.app_wbs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  project_id uuid,
  parent_id uuid,
  name text not null,
  ord int default 100,
  planned_hours numeric default 0,
  created_at timestamptz not null default now()
);
create index if not exists app_wbs_idx on public.app_wbs (tenant_id, project_id);

create table if not exists public.app_timesheets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  project_id uuid,
  wbs_id uuid,
  employee text,
  work_date date not null default current_date,
  hours numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_timesheets_idx on public.app_timesheets (tenant_id, project_id, work_date);

-- ---------- WBS ----------
create or replace function public.app_wbs_list(p_token uuid, p_project uuid)
returns table (id uuid, parent_id uuid, name text, ord int, planned_hours numeric, fact_hours numeric)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select w.id, w.parent_id, w.name, w.ord, w.planned_hours,
      coalesce((select sum(t.hours) from public.app_timesheets t where t.wbs_id = w.id), 0)
    from public.app_wbs w where (urole = 'admin' or w.tenant_id = ten) and (p_project is null or w.project_id = p_project)
    order by w.ord, w.name;
end $$;
grant execute on function public.app_wbs_list(uuid,uuid) to anon, authenticated;

create or replace function public.app_wbs_save(p_token uuid, p_id uuid, p_project uuid, p_parent uuid, p_name text, p_ord int, p_planned numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите название работы'; return; end if;
  if p_id is null then
    insert into public.app_wbs (tenant_id, project_id, parent_id, name, ord, planned_hours)
    values (ten, p_project, p_parent, p_name, coalesce(p_ord, 100), coalesce(p_planned, 0)) returning id into rid;
  else
    update public.app_wbs set project_id = p_project, parent_id = p_parent, name = p_name, ord = coalesce(p_ord, ord), planned_hours = coalesce(p_planned, planned_hours)
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_wbs_save(uuid,uuid,uuid,uuid,text,int,numeric) to anon, authenticated;

create or replace function public.app_wbs_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_timesheets where wbs_id = p_id and (urole = 'admin' or tenant_id = ten);
  delete from public.app_wbs where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_wbs_delete(uuid,uuid) to anon, authenticated;

-- ---------- Табели времени ----------
create or replace function public.app_timesheet_list(p_token uuid, p_project uuid)
returns table (id uuid, project_id uuid, wbs_id uuid, wbs_name text, employee text, work_date date, hours numeric, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, t.project_id, t.wbs_id, w.name, t.employee, t.work_date, t.hours, t.note
    from public.app_timesheets t left join public.app_wbs w on w.id = t.wbs_id
    where (urole = 'admin' or t.tenant_id = ten) and (p_project is null or t.project_id = p_project)
    order by t.work_date desc, t.created_at desc;
end $$;
grant execute on function public.app_timesheet_list(uuid,uuid) to anon, authenticated;

create or replace function public.app_timesheet_save(p_token uuid, p_id uuid, p_project uuid, p_wbs uuid, p_employee text, p_date date, p_hours numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_hours, 0) <= 0 then return query select false, 'Укажите часы'; return; end if;
  if p_id is null then
    insert into public.app_timesheets (tenant_id, project_id, wbs_id, employee, work_date, hours, note)
    values (ten, p_project, p_wbs, p_employee, coalesce(p_date, current_date), p_hours, p_note) returning id into rid;
  else
    update public.app_timesheets set project_id = p_project, wbs_id = p_wbs, employee = p_employee, work_date = coalesce(p_date, work_date), hours = p_hours, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_timesheet_save(uuid,uuid,uuid,uuid,text,date,numeric,text) to anon, authenticated;

create or replace function public.app_timesheet_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_timesheets where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_timesheet_delete(uuid,uuid) to anon, authenticated;
