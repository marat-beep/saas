-- ============================================================
-- 3DMP Service · 0040_hr_ref.sql  (v22.0 — переработка «Кадры/HR»)
-- Сотрудник ↔ пользователь системы (логин/роль), дата приёма, расширенные списки.
-- База знаний. Tenant-изоляция. Зависит от 0001..0039.
-- ============================================================

alter table public.app_employees add column if not exists user_login text;
alter table public.app_employees add column if not exists role       text;
alter table public.app_employees add column if not exists email      text;

-- ---------- Список сотрудников (расширенный) ----------
drop function if exists public.app_employees_list(uuid);
create or replace function public.app_employees_list(p_token uuid)
returns table (id uuid, full_name text, job text, dept text, phone text, email text, hired_at date,
               active boolean, user_login text, role text, shifts_month bigint, trainings_open bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.full_name, e.job, e.dept, e.phone, e.email, e.hired_at, e.active, e.user_login, e.role,
    (select count(*) from public.app_shifts sh where sh.employee_id = e.id and date_trunc('month', sh.shift_date) = date_trunc('month', current_date)),
    (select count(*) from public.app_trainings tr where tr.employee_id = e.id and tr.status <> 'passed')
    from public.app_employees e where (urole='admin' or e.tenant_id = ten) order by e.active desc, e.full_name;
end $$;

-- ---------- Сохранить сотрудника ----------
drop function if exists public.app_employee_save(uuid,uuid,text,text,text,text);
create or replace function public.app_employee_save(p_token uuid, p_id uuid, p_full_name text, p_position text, p_dept text, p_phone text,
  p_email text default null, p_hired_at date default null, p_user_login text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_full_name),'') = '' then return query select false,'Укажите ФИО'; return; end if;
  if p_id is null then
    insert into public.app_employees (tenant_id, full_name, job, dept, phone, email, hired_at, user_login, role)
    values (ten, trim(p_full_name), nullif(trim(p_position),''), nullif(trim(p_dept),''), nullif(trim(p_phone),''),
            nullif(trim(p_email),''), coalesce(p_hired_at, current_date), nullif(trim(p_user_login),''),
            (select u.role from public.app_users u where lower(u.login)=lower(trim(p_user_login)) and u.tenant_id = ten limit 1));
  else
    update public.app_employees set full_name=trim(p_full_name), job=nullif(trim(p_position),''),
      dept=nullif(trim(p_dept),''), phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''),
      hired_at=coalesce(p_hired_at, hired_at), user_login=nullif(trim(p_user_login),''),
      role=(select u.role from public.app_users u where lower(u.login)=lower(trim(p_user_login)) and u.tenant_id = ten limit 1)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Привязать сотрудника к пользователю системы ----------
create or replace function public.app_employee_link_user(p_token uuid, p_employee_id uuid, p_login text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select u.id into uid from public.app_users u where lower(u.login)=lower(trim(p_login)) and u.tenant_id = ten limit 1;
  if uid is null then return query select false,'Пользователь не найден в организации'; return; end if;
  update public.app_employees e set app_user_id = uid, user_login = (select u.login from public.app_users u where u.id = uid),
    role = (select u.role from public.app_users u where u.id = uid)
   where e.id = p_employee_id and (urole='admin' or e.tenant_id = ten);
  if not found then return query select false,'Сотрудник не найден'; return; end if;
  return query select true,'Сотрудник связан с пользователем';
end $$;

grant execute on function public.app_employees_list(uuid) to anon, authenticated;
grant execute on function public.app_employee_save(uuid,uuid,text,text,text,text,text,date,text) to anon, authenticated;
grant execute on function public.app_employee_link_user(uuid,uuid,text) to anon, authenticated;

-- ---------- База знаний: кадры ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кадры','Сотрудник и пользователь системы — в чём разница?',
   'Сотрудник — это кадровая запись (ФИО, должность, подразделение, телефон, дата приёма). Пользователь — учётная запись для входа (логин/пароль/роль). Свяжите их: в карточке сотрудника укажите логин пользователя — и роль/логин подтянутся автоматически. Так видно, кто за что отвечает и кто в системе.',
   'кадры сотрудник пользователь логин роль связь'),
  ('Кадры','Табель смен и обучение',
   'Вкладка «Смены» — табель по дням (дневная/ночная/выходной/отпуск/больничный) с часами. Вкладка «Обучение» — план и отметка прохождения. KPI кадров: сотрудники, смены и часы за месяц, обучение (план/пройдено).',
   'табель смены обучение часы KPI кадры')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Кадры');
