-- ============================================================
-- 3DMP Service · 0269_hr_payroll.sql  (R4 · PROP-21 — расчёт зарплаты и подбор)
-- Ведомости зарплаты (period/сотрудник/оклад/премия/удержание/итог) и подбор (вакансии/кандидаты). Идемпотентно.
-- ============================================================

create table if not exists public.app_payroll (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  period date not null default date_trunc('month', current_date)::date,
  employee text not null,
  base numeric not null default 0,
  bonus numeric not null default 0,
  deduction numeric not null default 0,
  total numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_payroll_idx on public.app_payroll (tenant_id, period);

create or replace function public.app_payroll_list(p_token uuid)
returns table (id uuid, period date, employee text, base numeric, bonus numeric, deduction numeric, total numeric, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.period, p.employee, p.base, p.bonus, p.deduction, p.total, p.note
    from public.app_payroll p where (urole = 'admin' or p.tenant_id = ten) order by p.period desc, p.employee;
end $$;
grant execute on function public.app_payroll_list(uuid) to anon, authenticated;

create or replace function public.app_payroll_save(p_token uuid, p_id uuid, p_period date, p_employee text, p_base numeric, p_bonus numeric, p_deduction numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_employee), '') = '' then return query select false, 'Укажите сотрудника'; return; end if;
  if p_id is null then
    insert into public.app_payroll (tenant_id, period, employee, base, bonus, deduction, total, note)
    values (ten, coalesce(p_period, date_trunc('month', current_date)::date), p_employee, coalesce(p_base,0), coalesce(p_bonus,0), coalesce(p_deduction,0),
            coalesce(p_base,0) + coalesce(p_bonus,0) - coalesce(p_deduction,0), p_note) returning id into rid;
  else
    update public.app_payroll set period = coalesce(p_period, period), employee = p_employee, base = coalesce(p_base,0), bonus = coalesce(p_bonus,0),
      deduction = coalesce(p_deduction,0), total = coalesce(p_base,0) + coalesce(p_bonus,0) - coalesce(p_deduction,0), note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_payroll_save(uuid,uuid,date,text,numeric,numeric,numeric,text) to anon, authenticated;

create or replace function public.app_payroll_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_payroll where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_payroll_delete(uuid,uuid) to anon, authenticated;

-- ---------- Подбор ----------
create table if not exists public.app_vacancies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  title text not null,
  dept text,
  status text not null default 'open',   -- open|closed
  opened_at date not null default current_date,
  created_at timestamptz not null default now()
);
create table if not exists public.app_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  vacancy_id uuid,
  name text not null,
  stage text not null default 'new',   -- new|interview|offer|hired|rejected
  note text,
  created_at timestamptz not null default now()
);

create or replace function public.app_vacancy_list(p_token uuid)
returns table (id uuid, title text, dept text, status text, opened_at date, candidates bigint)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.title, v.dept, v.status, v.opened_at,
      (select count(*) from public.app_candidates c where c.vacancy_id = v.id)
    from public.app_vacancies v where (urole = 'admin' or v.tenant_id = ten) order by v.opened_at desc;
end $$;
grant execute on function public.app_vacancy_list(uuid) to anon, authenticated;

create or replace function public.app_vacancy_save(p_token uuid, p_id uuid, p_title text, p_dept text, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then return query select false, 'Укажите вакансию'; return; end if;
  if p_id is null then
    insert into public.app_vacancies (tenant_id, title, dept, status) values (ten, p_title, p_dept, coalesce(p_status, 'open')) returning id into rid;
  else
    update public.app_vacancies set title = p_title, dept = p_dept, status = coalesce(p_status, status) where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_vacancy_save(uuid,uuid,text,text,text) to anon, authenticated;

create or replace function public.app_candidate_list(p_token uuid, p_vacancy uuid)
returns table (id uuid, vacancy_id uuid, name text, stage text, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.vacancy_id, c.name, c.stage, c.note
    from public.app_candidates c where (urole = 'admin' or c.tenant_id = ten) and (p_vacancy is null or c.vacancy_id = p_vacancy) order by c.created_at desc;
end $$;
grant execute on function public.app_candidate_list(uuid,uuid) to anon, authenticated;

create or replace function public.app_candidate_save(p_token uuid, p_id uuid, p_vacancy uuid, p_name text, p_stage text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите имя'; return; end if;
  if p_id is null then
    insert into public.app_candidates (tenant_id, vacancy_id, name, stage, note) values (ten, p_vacancy, p_name, coalesce(p_stage, 'new'), p_note) returning id into rid;
  else
    update public.app_candidates set vacancy_id = p_vacancy, name = p_name, stage = coalesce(p_stage, stage), note = p_note where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_candidate_save(uuid,uuid,uuid,text,text,text) to anon, authenticated;

create or replace function public.app_candidate_set_stage(p_token uuid, p_id uuid, p_stage text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_candidates set stage = p_stage where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Этап обновлён';
end $$;
grant execute on function public.app_candidate_set_stage(uuid,uuid,text) to anon, authenticated;
