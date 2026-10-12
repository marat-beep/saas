-- ============================================================
-- 3DMP Service · 0187_hr2.sql  (X1 — Кадры 2.0)
-- Штатное расписание (app_staffing), плановый график смен (app_shift_schedule),
-- отсутствия (app_absences), синхронизация отпусков с КЭДО (app_hr_docs),
-- дашборд кадров (app_hr_dashboard). Идемпотентно. Зависит от 0001..0186.
-- ============================================================

-- ---------- Данные ----------
create table if not exists public.app_staffing (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  department_id uuid references public.app_departments (id) on delete set null,
  department    text,
  position      text not null,
  rate          numeric default 1,
  salary        numeric,
  headcount     integer default 1,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_staffing_idx on public.app_staffing (tenant_id, department_id);
alter table public.app_staffing enable row level security;

create table if not exists public.app_shift_schedule (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  employee_id   uuid not null references public.app_employees (id) on delete cascade,
  department_id uuid references public.app_departments (id) on delete set null,
  shift_date    date not null,
  shift_type    text not null default '1',   -- 1|2|3|day|night|off
  hours         numeric default 8,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_shift_schedule_idx on public.app_shift_schedule (tenant_id, shift_date);
create unique index if not exists app_shift_schedule_uniq on public.app_shift_schedule (tenant_id, employee_id, shift_date, shift_type);
alter table public.app_shift_schedule enable row level security;

create table if not exists public.app_absences (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  employee_id   uuid not null references public.app_employees (id) on delete cascade,
  department_id uuid references public.app_departments (id) on delete set null,
  kind          text not null default 'vacation',  -- vacation|sick|leave|unpaid|other
  date_from     date not null,
  date_to       date not null,
  status        text not null default 'requested', -- requested|approved|rejected|closed
  hr_doc_id     uuid references public.app_hr_docs (id) on delete set null,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_absences_idx on public.app_absences (tenant_id, status, date_from);
alter table public.app_absences enable row level security;

-- ---------- Поля к существующим ----------
alter table public.app_employees add column if not exists fired_at date;
alter table public.app_shifts    add column if not exists department_id uuid references public.app_departments (id) on delete set null;

update public.app_shifts s set department_id = e.department_id
  from public.app_employees e
 where e.id = s.employee_id and s.department_id is null and e.department_id is not null;

create sequence if not exists public.app_hr_absence_seq;

-- ================= RPC: штатное расписание =================
create or replace function public.app_staffing_list(p_token uuid)
returns table (id uuid, department_id uuid, department text, pos_title text, rate numeric, salary numeric,
               headcount integer, fact bigint, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select st.id, st.department_id, coalesce(d.name, st.department), st.position, st.rate, st.salary, st.headcount,
           (select count(*) from public.app_employees e where e.department_id = st.department_id and e.active and (adm or e.tenant_id = ten)),
           st.note
      from public.app_staffing st
      left join public.app_departments d on d.id = st.department_id
     where (adm or st.tenant_id = ten)
       and public.app_dept_ok(p_token, st.department_id)
     order by coalesce(d.name, st.department), st.position;
end $$;

create or replace function public.app_staffing_save(p_token uuid, p_id uuid, p_department_id uuid, p_department text,
  p_position text, p_rate numeric, p_salary numeric, p_count integer, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; dep uuid; dname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку кадров', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_position),'') = '' then return query select false,'Укажите должность', null::uuid; return; end if;
  dep := p_department_id;
  if dep is not null then select d.name into dname from public.app_departments d where d.id = dep and (public.app_is_platform_admin(p_token) or d.tenant_id = ten); end if;
  if p_id is null then
    insert into public.app_staffing (tenant_id, department_id, department, position, rate, salary, headcount, note, created_login)
    values (ten, dep, coalesce(dname, nullif(trim(p_department),'')), left(trim(p_position),160),
            coalesce(p_rate,1), p_salary, coalesce(p_count,1), nullif(trim(p_note),''), uname)
    returning app_staffing.id into newid;
    return query select true,'Строка штата добавлена', newid;
  else
    update public.app_staffing st set department_id = dep, department = coalesce(dname, nullif(trim(p_department),'')),
           position = left(trim(p_position),160), rate = coalesce(p_rate,1), salary = p_salary,
           headcount = coalesce(p_count,1), note = nullif(trim(p_note),'')
     where st.id = p_id and (public.app_is_platform_admin(p_token) or st.tenant_id = ten)
     returning st.id into newid;
    if newid is null then return query select false,'Строка штата не найдена', null::uuid; return; end if;
    return query select true,'Строка штата сохранена', newid;
  end if;
end $$;

create or replace function public.app_staffing_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку кадров'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_staffing st where st.id = p_id and (public.app_is_platform_admin(p_token) or st.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Строка штата не найдена'; return; end if;
  return query select true,'Строка штата удалена';
end $$;

-- ================= RPC: плановый график смен =================
create or replace function public.app_shift_schedule_list(p_token uuid, p_from date default null, p_to date default null, p_department uuid default null)
returns table (id uuid, employee_id uuid, employee text, department text, shift_date date, shift_type text, hours numeric,
               note text, absence text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.employee_id, e.full_name, coalesce(d.name, e.dept), s.shift_date, s.shift_type, s.hours, s.note,
           (select a.kind from public.app_absences a
             where a.employee_id = s.employee_id and a.status = 'approved'
               and s.shift_date between a.date_from and a.date_to limit 1)
      from public.app_shift_schedule s
      join public.app_employees e on e.id = s.employee_id
      left join public.app_departments d on d.id = s.department_id
     where (adm or s.tenant_id = ten)
       and public.app_dept_ok(p_token, s.department_id)
       and (p_from is null or s.shift_date >= p_from)
       and (p_to   is null or s.shift_date <= p_to)
       and (p_department is null or s.department_id = p_department)
     order by s.shift_date, e.full_name;
end $$;

create or replace function public.app_shift_schedule_save(p_token uuid, p_id uuid, p_employee_id uuid, p_date date,
  p_shift_type text, p_hours numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; dep uuid; st text; conflict_kind text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку графика', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_date is null then return query select false,'Укажите дату смены', null::uuid; return; end if;
  select e.department_id into dep from public.app_employees e where e.id = p_employee_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten);
  if not exists (select 1 from public.app_employees e where e.id = p_employee_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten)) then
    return query select false,'Сотрудник не найден', null::uuid; return;
  end if;
  st := coalesce(nullif(trim(p_shift_type),''),'1');
  -- Конфликт: сотрудник в утверждённом отсутствии
  select a.kind into conflict_kind from public.app_absences a
   where a.employee_id = p_employee_id and a.status = 'approved' and p_date between a.date_from and a.date_to limit 1;
  if conflict_kind is not null then
    return query select false, 'Сотрудник в отсутствии (' || conflict_kind || ') — смена не поставлена', null::uuid; return;
  end if;
  if p_id is null then
    if exists (select 1 from public.app_shift_schedule s where s.employee_id = p_employee_id and s.shift_date = p_date and s.shift_type = st and s.tenant_id = ten) then
      return query select false,'Такая смена уже есть', null::uuid; return;
    end if;
    insert into public.app_shift_schedule (tenant_id, employee_id, department_id, shift_date, shift_type, hours, note, created_login)
    values (ten, p_employee_id, dep, p_date, st, coalesce(p_hours,8), nullif(trim(p_note),''), uname)
    returning app_shift_schedule.id into newid;
    return query select true,'Смена поставлена в график', newid;
  else
    update public.app_shift_schedule s set employee_id = p_employee_id, department_id = dep, shift_date = p_date,
           shift_type = st, hours = coalesce(p_hours,8), note = nullif(trim(p_note),'')
     where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten)
     returning s.id into newid;
    if newid is null then return query select false,'Смена не найдена', null::uuid; return; end if;
    return query select true,'Смена графика сохранена', newid;
  end if;
exception when unique_violation then
  return query select false,'Такая смена уже есть', null::uuid;
end $$;

create or replace function public.app_shift_schedule_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку графика'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_shift_schedule s where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Смена не найдена'; return; end if;
  return query select true,'Смена удалена из графика';
end $$;

-- ================= RPC: отсутствия =================
create or replace function public.app_absence_list(p_token uuid, p_status text default null)
returns table (id uuid, employee_id uuid, employee text, department text, kind text, date_from date, date_to date,
               days integer, status text, hr_doc_number text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select a.id, a.employee_id, e.full_name, coalesce(d.name, e.dept), a.kind, a.date_from, a.date_to,
           (a.date_to - a.date_from + 1)::int, a.status, hd.number, a.note
      from public.app_absences a
      join public.app_employees e on e.id = a.employee_id
      left join public.app_departments d on d.id = a.department_id
      left join public.app_hr_docs hd on hd.id = a.hr_doc_id
     where (adm or a.tenant_id = ten)
       and public.app_dept_ok(p_token, a.department_id)
       and (st is null or a.status = st)
     order by a.date_from desc;
end $$;

create or replace function public.app_absence_save(p_token uuid, p_id uuid, p_employee_id uuid, p_kind text,
  p_from date, p_to date, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; dep uuid; kd text; st text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку отсутствий', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select e.id, e.department_id into eid, dep from public.app_employees e where e.id = p_employee_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten);
  if eid is null then return query select false,'Сотрудник не найден', null::uuid; return; end if;
  if p_from is null or p_to is null then return query select false,'Укажите период', null::uuid; return; end if;
  if p_to < p_from then return query select false,'Дата окончания раньше начала', null::uuid; return; end if;
  kd := coalesce(nullif(trim(p_kind),''),'vacation');
  if kd not in ('vacation','sick','leave','unpaid','other') then return query select false,'Недопустимый вид отсутствия', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'requested');
  if st not in ('requested','approved','rejected','closed') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  -- Пересечение с другим отсутствием
  if exists (select 1 from public.app_absences a where a.employee_id = p_employee_id and a.tenant_id = ten
              and a.status in ('requested','approved') and (p_id is null or a.id <> p_id)
              and daterange(a.date_from, a.date_to, '[]') && daterange(p_from, p_to, '[]')) then
    return query select false,'Период пересекается с другим отсутствием', null::uuid; return;
  end if;
  if p_id is null then
    insert into public.app_absences (tenant_id, employee_id, department_id, kind, date_from, date_to, status, note, created_login)
    values (ten, p_employee_id, dep, kd, p_from, p_to, st, nullif(trim(p_note),''), uname)
    returning app_absences.id into newid;
    return query select true,'Отсутствие добавлено', newid;
  else
    update public.app_absences a set employee_id = p_employee_id, department_id = dep, kind = kd,
           date_from = p_from, date_to = p_to, status = st, note = nullif(trim(p_note),'')
     where a.id = p_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten)
     returning a.id into newid;
    if newid is null then return query select false,'Отсутствие не найдено', null::uuid; return; end if;
    return query select true,'Отсутствие сохранено', newid;
  end if;
end $$;

create or replace function public.app_absence_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; a record; ulog text; au uuid; num text; did uuid; dtype text; ttl text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('requested','approved','rejected','closed') then return query select false,'Недопустимый статус'; return; end if;
  select * into a from public.app_absences where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if a.id is null then return query select false,'Отсутствие не найдено'; return; end if;
  update public.app_absences set status = st where id = p_id;
  -- Утверждение отпуска → кадровый приказ в КЭДО (app_hr_docs) + уведомление сотруднику
  if st = 'approved' and a.hr_doc_id is null then
    select e.user_login into ulog from public.app_employees e where e.id = a.employee_id;
    dtype := case a.kind when 'vacation' then 'vacation' when 'sick' then 'sick' else 'order' end;
    num := 'HR-' || lpad(nextval('public.app_hr_absence_seq')::text, 5, '0');
    ttl := case a.kind when 'vacation' then 'Приказ об отпуске' when 'sick' then 'Приказ (больничный)'
                       when 'leave' then 'Приказ (отгул)' when 'unpaid' then 'Приказ (без сохранения ЗП)' else 'Приказ' end;
    insert into public.app_hr_docs (tenant_id, employee_login, doc_type, title, number, status, payload, created_login)
    values (ten, ulog, dtype, ttl, num, 'sent',
            jsonb_build_object('absence_id', p_id, 'from', a.date_from, 'to', a.date_to, 'kind', a.kind), a.created_login)
    returning app_hr_docs.id into did;
    update public.app_absences set hr_doc_id = did where id = p_id;
    if ulog is not null then
      select u.id into au from public.app_users u where u.login = ulog and u.tenant_id = ten limit 1;
      if au is not null then perform public.app_notif_send(au, 'Кадровый документ на ознакомление', ttl || ' ' || num, 'apps/kedo/index.html'); end if;
    end if;
    return query select true,'Отсутствие утверждено, приказ отправлен в КЭДО (' || num || ')';
    return;
  end if;
  return query select true,'Статус обновлён: ' || st;
end $$;

create or replace function public.app_absence_scan(p_token uuid)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; rec record; uid uuid; cnt integer := 0;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  -- Окончание отсутствий в ближайшие 3 дня и просроченные заявки на согласование
  for rec in
    select a.id, e.full_name, a.kind, a.date_to, a.date_from, a.status, e.user_login
      from public.app_absences a join public.app_employees e on e.id = a.employee_id
     where (adm or a.tenant_id = ten)
       and ((a.status = 'approved' and a.date_to between current_date and current_date + 3)
         or (a.status = 'requested' and a.date_from <= current_date + 1))
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','hr'],
      'Кадры: ' || rec.full_name || ' — ' || rec.kind,
      'Отсутствие ' || to_char(rec.date_from,'DD.MM') || '–' || to_char(rec.date_to,'DD.MM') || ' (' || rec.status || ')',
      'apps/hr/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Уведомлений по отсутствиям: ' || cnt;
end $$;

-- ================= RPC: дашборд кадров =================
create or replace function public.app_hr_dashboard(p_token uuid)
returns table (employees bigint, active bigint, hired_month bigint, fired_month bigint, fired_year bigint,
               turnover_pct numeric, on_vacation_now bigint, absences_pending bigint, shifts_plan_month bigint,
               staffing_positions bigint, staffing_headcount bigint, staffing_fact bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_employees e where adm or e.tenant_id = ten),
    (select count(*) from public.app_employees e where e.active and (adm or e.tenant_id = ten)),
    (select count(*) from public.app_employees e where e.hired_at >= date_trunc('month', current_date) and (adm or e.tenant_id = ten)),
    (select count(*) from public.app_employees e where e.fired_at >= date_trunc('month', current_date) and (adm or e.tenant_id = ten)),
    (select count(*) from public.app_employees e where e.fired_at >= date_trunc('year', current_date) and (adm or e.tenant_id = ten)),
    round(100.0 * (select count(*) from public.app_employees e where e.fired_at >= date_trunc('year', current_date) and (adm or e.tenant_id = ten))
          / greatest(1, (select count(*) from public.app_employees e where (e.active or e.fired_at >= date_trunc('year', current_date)) and (adm or e.tenant_id = ten))), 1),
    (select count(*) from public.app_absences a where a.status = 'approved' and current_date between a.date_from and a.date_to and (adm or a.tenant_id = ten)),
    (select count(*) from public.app_absences a where a.status = 'requested' and (adm or a.tenant_id = ten)),
    (select count(*) from public.app_shift_schedule s where date_trunc('month', s.shift_date) = date_trunc('month', current_date) and (adm or s.tenant_id = ten)),
    (select count(*) from public.app_staffing st where adm or st.tenant_id = ten),
    (select coalesce(sum(st.headcount),0) from public.app_staffing st where adm or st.tenant_id = ten),
    (select count(*) from public.app_employees e where e.active and (adm or e.tenant_id = ten));
end $$;

-- ================= Демо =================
insert into public.app_staffing (tenant_id, department, position, rate, salary, headcount, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.dep, v.pos, v.rate, v.salary, v.cnt, 'owner'
from (values
  ('Механообработка','Оператор ЧПУ', 1, 90000, 3),
  ('Механообработка','Мастер',      1, 120000, 1),
  ('Механообработка','Начальник цеха', 1, 150000, 1)
) as v(dep,pos,rate,salary,cnt)
where not exists (select 1 from public.app_staffing where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_shift_schedule (tenant_id, employee_id, shift_date, shift_type, hours, created_login)
select e.tenant_id, e.id, current_date, '1', 8, 'owner'
from public.app_employees e
where e.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and e.active
  and not exists (select 1 from public.app_shift_schedule s where s.employee_id = e.id and s.shift_date = current_date)
limit 2;

insert into public.app_absences (tenant_id, employee_id, kind, date_from, date_to, status, note, created_login)
select e.tenant_id, e.id, 'vacation', current_date + 30, current_date + 43, 'requested', 'Плановый отпуск', 'owner'
from public.app_employees e
where e.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and e.active
  and not exists (select 1 from public.app_absences a where a.employee_id = e.id)
limit 1;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кадры','Штатное расписание, график смен и отсутствия (X1)',
   'Кадры 2.0: штатное расписание (app_staffing — подразделение/должность/ставка/оклад/плановая численность; факт считается по активным сотрудникам), плановый график смен (app_shift_schedule — сотрудник×дата×смена 1/2/3), отсутствия (app_absences — отпуск/больничный/отгул/без сохранения ЗП, статусы requested→approved/rejected/closed). RPC: app_staffing_list/save/delete, app_shift_schedule_list/save/delete, app_absence_list/save/set_status/scan, app_hr_dashboard. График проверяет конфликт: смена не ставится на период утверждённого отсутствия. При утверждении отпуска автоматически создаётся кадровый приказ в КЭДО (app_hr_docs) и уведомляется сотрудник. Дашборд: численность, приём/увольнение за месяц, текучесть за год, в отпуске сейчас, заявки на согласование.',
   'кадры штат штатное расписание график смен отпуск больничный отсутствие текучесть КЭДО приказ дашборд')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Штатное расписание, график смен и отсутствия (X1)'
);

-- ================= Права =================
grant execute on function public.app_staffing_list(uuid) to anon, authenticated;
grant execute on function public.app_staffing_save(uuid,uuid,uuid,text,text,numeric,numeric,integer,text) to anon, authenticated;
grant execute on function public.app_staffing_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_shift_schedule_list(uuid,date,date,uuid) to anon, authenticated;
grant execute on function public.app_shift_schedule_save(uuid,uuid,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_shift_schedule_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_absence_list(uuid,text) to anon, authenticated;
grant execute on function public.app_absence_save(uuid,uuid,uuid,text,date,date,text,text) to anon, authenticated;
grant execute on function public.app_absence_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_absence_scan(uuid) to anon, authenticated;
grant execute on function public.app_hr_dashboard(uuid) to anon, authenticated;
