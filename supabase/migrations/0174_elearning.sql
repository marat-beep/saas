-- ============================================================
-- 3DMP Service · 0174_elearning.sql  (W26 — e-Learning)
-- Курсы, уроки, назначения/прогресс, тесты и попытки; KPI.
-- Идемпотентно. Зависит от 0001..0173.
-- ============================================================

create table if not exists public.app_courses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text, name text not null, category text, hours numeric default 0, active boolean default true, description text, created_at timestamptz default now()
);
alter table public.app_courses enable row level security;

create table if not exists public.app_course_lessons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  course_id uuid references public.app_courses (id) on delete cascade,
  name text not null, ord integer default 1, minutes numeric default 0, content text, created_at timestamptz default now()
);
alter table public.app_course_lessons enable row level security;

create table if not exists public.app_course_enrollments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  course_id uuid references public.app_courses (id) on delete cascade,
  employee_login text, status text not null default 'assigned', progress integer default 0, score numeric,
  created_at timestamptz default now(), completed_at timestamptz
);
create index if not exists app_enroll_idx on public.app_course_enrollments (tenant_id, employee_login, status);
alter table public.app_course_enrollments enable row level security;

create table if not exists public.app_course_tests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  course_id uuid references public.app_courses (id) on delete cascade,
  name text not null, pass_score integer default 70, questions jsonb not null default '[]'::jsonb, created_at timestamptz default now()
);
alter table public.app_course_tests enable row level security;

create table if not exists public.app_test_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  test_id uuid references public.app_course_tests (id) on delete cascade,
  employee_login text, score integer default 0, passed boolean default false, answers jsonb default '{}'::jsonb, created_at timestamptz default now()
);
alter table public.app_test_attempts enable row level security;

-- ---------- Курсы ----------
create or replace function public.app_courses_list(p_token uuid)
returns table (id uuid, code text, name text, category text, hours numeric, active boolean, lessons bigint, enrolled bigint)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select c.id,c.code,c.name,c.category,c.hours,c.active,
    (select count(*) from public.app_course_lessons l where l.course_id=c.id),
    (select count(*) from public.app_course_enrollments e where e.course_id=c.id)
    from public.app_courses c where adm or c.tenant_id=ten order by c.name;
end $$;

create or replace function public.app_course_save(p_token uuid, p_id uuid, p_code text, p_name text, p_category text, p_hours numeric, p_active boolean, p_description text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите название курса',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_courses (tenant_id,code,name,category,hours,active,description) values (ten,nullif(trim(p_code),''),left(trim(p_name),160),nullif(trim(p_category),''),coalesce(p_hours,0),coalesce(p_active,true),nullif(trim(p_description),'')) returning id into newid;
    return query select true,'Курс создан',newid;
  else
    update public.app_courses c set code=nullif(trim(p_code),''),name=left(trim(p_name),160),category=nullif(trim(p_category),''),hours=coalesce(p_hours,c.hours),active=coalesce(p_active,c.active),description=nullif(trim(p_description),'')
     where c.id=p_id and (public.app_is_platform_admin(p_token) or c.tenant_id=ten) returning c.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Курс сохранён',newid;
  end if;
end $$;

create or replace function public.app_course_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_courses c where c.id=p_id and (public.app_is_platform_admin(p_token) or c.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Курс удалён';
end $$;

-- ---------- Уроки ----------
create or replace function public.app_course_lessons_list(p_token uuid, p_course_id uuid)
returns table (id uuid, name text, ord integer, minutes numeric, content text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select l.id,l.name,l.ord,l.minutes,l.content from public.app_course_lessons l where l.course_id=p_course_id and (adm or l.tenant_id=ten) order by l.ord;
end $$;

create or replace function public.app_course_lesson_save(p_token uuid, p_id uuid, p_course_id uuid, p_name text, p_ord integer, p_minutes numeric, p_content text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите урок',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_course_lessons (tenant_id,course_id,name,ord,minutes,content) values (ten,p_course_id,left(trim(p_name),160),coalesce(p_ord,1),coalesce(p_minutes,0),p_content) returning id into newid;
    return query select true,'Урок добавлен',newid;
  else
    update public.app_course_lessons l set name=left(trim(p_name),160),ord=coalesce(p_ord,l.ord),minutes=coalesce(p_minutes,l.minutes),content=p_content
     where l.id=p_id and (public.app_is_platform_admin(p_token) or l.tenant_id=ten) returning l.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Урок сохранён',newid;
  end if;
end $$;

create or replace function public.app_course_lesson_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_course_lessons l where l.id=p_id and (public.app_is_platform_admin(p_token) or l.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Урок удалён';
end $$;

-- ---------- Назначения ----------
create or replace function public.app_enrollments_list(p_token uuid, p_course_id uuid default null, p_employee text default null)
returns table (id uuid, course text, employee_login text, status text, progress integer, score numeric, completed_at timestamptz)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select e.id,c.name,e.employee_login,e.status,e.progress,e.score,e.completed_at
    from public.app_course_enrollments e left join public.app_courses c on c.id=e.course_id
   where (adm or e.tenant_id=ten) and (p_course_id is null or e.course_id=p_course_id) and (p_employee is null or p_employee='' or e.employee_login=p_employee)
   order by e.created_at desc;
end $$;

create or replace function public.app_enrollment_save(p_token uuid, p_id uuid, p_course_id uuid, p_employee text, p_status text, p_progress integer, p_score numeric)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_employee),'')='' then return query select false,'Укажите сотрудника',null::uuid; return; end if;
  st:=coalesce(nullif(trim(p_status),''),'assigned');
  if st not in ('assigned','in_progress','done') then return query select false,'Недопустимый статус',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_course_enrollments (tenant_id,course_id,employee_login,status,progress,score,completed_at)
    values (ten,p_course_id,trim(p_employee),st,least(greatest(coalesce(p_progress,0),0),100),p_score,case when st='done' then now() else null end) returning id into newid;
    return query select true,'Назначено',newid;
  else
    update public.app_course_enrollments e set course_id=coalesce(p_course_id,e.course_id),employee_login=trim(p_employee),status=st,progress=least(greatest(coalesce(p_progress,e.progress),0),100),score=coalesce(p_score,e.score),completed_at=case when st='done' then coalesce(e.completed_at,now()) else e.completed_at end
     where e.id=p_id and (public.app_is_platform_admin(p_token) or e.tenant_id=ten) returning e.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Сохранено',newid;
  end if;
end $$;

-- ---------- Тесты ----------
create or replace function public.app_course_tests_list(p_token uuid, p_course_id uuid default null)
returns table (id uuid, course text, name text, pass_score integer, questions jsonb)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select t.id,c.name,t.name,t.pass_score,t.questions from public.app_course_tests t left join public.app_courses c on c.id=t.course_id
   where (adm or t.tenant_id=ten) and (p_course_id is null or t.course_id=p_course_id) order by t.name;
end $$;

create or replace function public.app_course_test_save(p_token uuid, p_id uuid, p_course_id uuid, p_name text, p_pass integer, p_questions jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите название теста',null::uuid; return; end if;
  if p_questions is not null and jsonb_typeof(p_questions)<>'array' then return query select false,'Вопросы — массив',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_course_tests (tenant_id,course_id,name,pass_score,questions) values (ten,p_course_id,left(trim(p_name),160),least(greatest(coalesce(p_pass,70),0),100),coalesce(p_questions,'[]'::jsonb)) returning id into newid;
    return query select true,'Тест создан',newid;
  else
    update public.app_course_tests t set course_id=coalesce(p_course_id,t.course_id),name=left(trim(p_name),160),pass_score=least(greatest(coalesce(p_pass,t.pass_score),0),100),questions=coalesce(p_questions,t.questions)
     where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten) returning t.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Тест сохранён',newid;
  end if;
end $$;

create or replace function public.app_test_attempt_add(p_token uuid, p_test_id uuid, p_employee text, p_score integer, p_answers jsonb)
returns table (ok boolean, message text, id uuid, passed boolean)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; ps integer; pss boolean;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid,false; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  select coalesce(pass_score,70) into ps from public.app_course_tests where id=p_test_id and (public.app_is_platform_admin(p_token) or tenant_id=ten);
  if ps is null then return query select false,'Тест не найден',null::uuid,false; return; end if;
  pss := coalesce(p_score,0) >= ps;
  insert into public.app_test_attempts (tenant_id,test_id,employee_login,score,passed,answers) values (ten,p_test_id,trim(p_employee),coalesce(p_score,0),pss,coalesce(p_answers,'{}'::jsonb)) returning id into newid;
  return query select true, case when pss then 'Пройден' else 'Не пройден' end, newid, pss;
end $$;

create or replace function public.app_test_attempts_list(p_token uuid, p_test_id uuid default null, p_limit integer default 100)
returns table (id uuid, test text, employee_login text, score integer, passed boolean, created_at timestamptz)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select a.id,t.name,a.employee_login,a.score,a.passed,a.created_at from public.app_test_attempts a left join public.app_course_tests t on t.id=a.test_id
   where (adm or a.tenant_id=ten) and (p_test_id is null or a.test_id=p_test_id) order by a.created_at desc limit greatest(coalesce(p_limit,100),1);
end $$;

create or replace function public.app_elearning_kpi(p_token uuid)
returns table (courses bigint, active_courses bigint, lessons bigint, enrollments bigint, done bigint, tests bigint, attempts bigint, pass_rate numeric)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; tot bigint; ps bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  select count(*) into tot from public.app_test_attempts a where adm or a.tenant_id=ten;
  select count(*) into ps from public.app_test_attempts a where (adm or a.tenant_id=ten) and a.passed;
  return query select
    (select count(*) from public.app_courses c where adm or c.tenant_id=ten),
    (select count(*) from public.app_courses c where (adm or c.tenant_id=ten) and c.active),
    (select count(*) from public.app_course_lessons l where adm or l.tenant_id=ten),
    (select count(*) from public.app_course_enrollments e where adm or e.tenant_id=ten),
    (select count(*) from public.app_course_enrollments e where (adm or e.tenant_id=ten) and e.status='done'),
    (select count(*) from public.app_course_tests t where adm or t.tenant_id=ten),
    tot,
    case when tot>0 then round(ps::numeric/tot*100,1) end;
end $$;

-- ---------- Демо ----------
insert into public.app_courses (tenant_id, code, name, category, hours, active, description)
select 'aaaaaaaa-0000-0000-0000-000000000001','OT-01','Охрана труда: базовый курс','Охрана труда',4,true,'Вводный курс по ОТ'
where not exists (select 1 from public.app_courses where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='OT-01');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','e-Learning: курсы, уроки, назначения, тесты',
       'W26: курсы (app_courses), уроки (app_course_lessons), назначения и прогресс (app_course_enrollments: assigned→in_progress→done, % и оценка), тесты (app_course_tests: вопросы jsonb/порог) и попытки (app_test_attempts: результат/пройден), KPI (app_elearning_kpi: курс/назначения/доля сдачи). Модуль «Обучение» (apps/elearning).',
       'e-learning курсы уроки тесты аттестация обучение','Платформа'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='e-Learning: курсы, уроки, назначения, тесты');

-- ---------- Права ----------
grant execute on function public.app_courses_list(uuid) to anon, authenticated;
grant execute on function public.app_course_save(uuid,uuid,text,text,text,numeric,boolean,text) to anon, authenticated;
grant execute on function public.app_course_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_course_lessons_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_course_lesson_save(uuid,uuid,uuid,text,integer,numeric,text) to anon, authenticated;
grant execute on function public.app_course_lesson_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_enrollments_list(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_enrollment_save(uuid,uuid,uuid,text,text,integer,numeric) to anon, authenticated;
grant execute on function public.app_course_tests_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_course_test_save(uuid,uuid,uuid,text,integer,jsonb) to anon, authenticated;
grant execute on function public.app_test_attempt_add(uuid,uuid,text,integer,jsonb) to anon, authenticated;
grant execute on function public.app_test_attempts_list(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_elearning_kpi(uuid) to anon, authenticated;
