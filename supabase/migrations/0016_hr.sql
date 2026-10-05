-- ============================================================
-- 3DMP Service · 0016_hr.sql  (v2.3 — кадры и смены)
-- Сотрудники, смены/табель, обучение. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0015.
-- ============================================================

create table if not exists public.app_employees (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  app_user_id uuid references public.app_users (id) on delete set null,
  full_name   text not null,
  job    text,
  dept        text,
  phone       text,
  hired_at    date,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_employees_tenant_idx on public.app_employees (tenant_id);

create table if not exists public.app_shifts (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  employee_id uuid not null references public.app_employees (id) on delete cascade,
  shift_date  date not null,
  kind        text not null default 'day',   -- day | night | off | vacation | sick
  hours       numeric default 8,
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_shifts_idx on public.app_shifts (tenant_id, shift_date desc);

create table if not exists public.app_trainings (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  employee_id uuid references public.app_employees (id) on delete cascade,
  title       text not null,
  status      text not null default 'planned',  -- planned | passed
  train_date  date,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_trainings_idx on public.app_trainings (tenant_id, created_at desc);

alter table public.app_employees enable row level security;
alter table public.app_shifts    enable row level security;
alter table public.app_trainings enable row level security;

-- ---------- Сотрудники ----------
create or replace function public.app_employees_list(p_token uuid)
returns table (id uuid, full_name text, job text, dept text, phone text, active boolean, shifts_month bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.full_name, e.job, e.dept, e.phone, e.active,
    (select count(*) from public.app_shifts sh where sh.employee_id = e.id and date_trunc('month', sh.shift_date) = date_trunc('month', current_date))
    from public.app_employees e where (urole='admin' or e.tenant_id = ten) and e.active order by e.full_name;
end $$;

create or replace function public.app_employee_save(p_token uuid, p_id uuid, p_full_name text, p_position text, p_dept text, p_phone text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_full_name),'') = '' then return query select false,'Укажите ФИО'; return; end if;
  if p_id is null then
    insert into public.app_employees (tenant_id, full_name, job, dept, phone)
    values (ten, trim(p_full_name), nullif(trim(p_position),''), nullif(trim(p_dept),''), nullif(trim(p_phone),''));
  else
    update public.app_employees set full_name=trim(p_full_name), job=nullif(trim(p_position),''),
      dept=nullif(trim(p_dept),''), phone=nullif(trim(p_phone),'')
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Смены ----------
create or replace function public.app_shifts_list(p_token uuid, p_from date, p_to date)
returns table (id uuid, employee_id uuid, employee text, shift_date date, kind text, hours numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select sh.id, sh.employee_id, e.full_name, sh.shift_date, sh.kind, sh.hours, sh.note
    from public.app_shifts sh join public.app_employees e on e.id = sh.employee_id
    where (urole='admin' or sh.tenant_id = ten)
      and (p_from is null or sh.shift_date >= p_from) and (p_to is null or sh.shift_date <= p_to)
    order by sh.shift_date desc, e.full_name;
end $$;

create or replace function public.app_shift_add(p_token uuid, p_employee_id uuid, p_date date, p_kind text, p_hours numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select e.id into eid from public.app_employees e where e.id = p_employee_id and (ten is null or e.tenant_id = ten);
  if eid is null then return query select false,'Сотрудник не найден'; return; end if;
  if p_date is null then return query select false,'Укажите дату'; return; end if;
  insert into public.app_shifts (tenant_id, employee_id, shift_date, kind, hours, note, by_login)
  values (ten, eid, p_date, coalesce(nullif(trim(p_kind),''),'day'), coalesce(p_hours,8), nullif(trim(p_note),''), ulogin);
  return query select true,'Смена добавлена';
end $$;

create or replace function public.app_shift_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_shifts where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Смена удалена';
end $$;

-- ---------- Обучение ----------
create or replace function public.app_training_list(p_token uuid)
returns table (id uuid, employee text, title text, status text, train_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, e.full_name, t.title, t.status, t.train_date, t.created_at
    from public.app_trainings t join public.app_employees e on e.id = t.employee_id
    where (urole='admin' or t.tenant_id = ten) order by t.created_at desc;
end $$;

create or replace function public.app_training_add(p_token uuid, p_employee_id uuid, p_title text, p_status text, p_date date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; eid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  select e.id into eid from public.app_employees e where e.id = p_employee_id and (ten is null or e.tenant_id = ten);
  if eid is null then return query select false,'Сотрудник не найден'; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему обучения'; return; end if;
  insert into public.app_trainings (tenant_id, employee_id, title, status, train_date, note)
  values (ten, eid, trim(p_title), coalesce(nullif(trim(p_status),''),'planned'), p_date, nullif(trim(p_note),''));
  return query select true,'Обучение добавлено';
end $$;

create or replace function public.app_training_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_trainings set status = p_status where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус обновлён';
end $$;

-- ---------- KPI кадров ----------
create or replace function public.app_hr_kpi(p_token uuid)
returns table (employees bigint, shifts_month bigint, hours_month numeric, trainings_planned bigint, trainings_passed bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_employees e where e.active and (urole='admin' or e.tenant_id=ten)),
    (select count(*) from public.app_shifts sh where (urole='admin' or sh.tenant_id=ten) and date_trunc('month', sh.shift_date)=date_trunc('month', current_date)),
    (select coalesce(sum(sh.hours),0) from public.app_shifts sh where (urole='admin' or sh.tenant_id=ten) and date_trunc('month', sh.shift_date)=date_trunc('month', current_date)),
    (select count(*) from public.app_trainings t where t.status='planned' and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_trainings t where t.status='passed' and (urole='admin' or t.tenant_id=ten));
end $$;

grant execute on function public.app_employees_list(uuid) to anon, authenticated;
grant execute on function public.app_employee_save(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_shifts_list(uuid,date,date) to anon, authenticated;
grant execute on function public.app_shift_add(uuid,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_shift_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_training_list(uuid) to anon, authenticated;
grant execute on function public.app_training_add(uuid,uuid,text,text,date,text) to anon, authenticated;
grant execute on function public.app_training_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_hr_kpi(uuid) to anon, authenticated;

-- ---------- Демо-сотрудники ----------
insert into public.app_employees (tenant_id, full_name, job, dept)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.full_name, v.job, v.dept
from (values
  ('Кузнецов А.П.','Начальник цеха','Механообработка'),
  ('Орлов Д.В.','Мастер','Механообработка'),
  ('Петров В.С.','Оператор ЧПУ','Механообработка')
) as v(full_name,job,dept)
where not exists (select 1 from public.app_employees where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
