-- ============================================================
-- 3DMP Service · 0199_competences2.sql  (X2 — Компетенции и обучение 2.0)
-- Профили должностей (app_job_profiles), дефицит навыков (app_skill_gap_scan),
-- сертификаты и сроки (app_certificates + scan), авто-назначение курсов.
-- Идемпотентно. Зависит от 0001..0198.
-- ============================================================

create table if not exists public.app_job_profiles (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  title          text not null,
  dept           text,
  role           text,
  requirements   jsonb not null default '[]'::jsonb,  -- [{"code":"cnc","level":4}]
  active         boolean not null default true,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_job_profiles_idx on public.app_job_profiles (tenant_id, title);
alter table public.app_job_profiles enable row level security;

create table if not exists public.app_certificates (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  employee_id   uuid references public.app_employees (id) on delete cascade,
  name          text not null,
  number        text,
  skill_code    text,
  issued_at     date,
  expires_at    date,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_certificates_idx on public.app_certificates (tenant_id, expires_at);
alter table public.app_certificates enable row level security;

-- ================= RPC: профили должностей =================
create or replace function public.app_job_profile_list(p_token uuid)
returns table (id uuid, title text, dept text, role text, requirements jsonb, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select p.id, p.title, p.dept, p.role, p.requirements, p.active
    from public.app_job_profiles p where (adm or p.tenant_id = ten) order by p.title;
end $$;

create or replace function public.app_job_profile_save(p_token uuid, p_id uuid, p_title text, p_dept text, p_role text, p_requirements jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; req jsonb;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'competences') then return query select false,'Нет прав на компетенции', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите должность', null::uuid; return; end if;
  req := case when p_requirements is null or jsonb_typeof(p_requirements) <> 'array' then '[]'::jsonb else p_requirements end;
  if p_id is null then
    insert into public.app_job_profiles (tenant_id, title, dept, role, requirements, created_login)
    values (ten, left(trim(p_title),160), nullif(trim(p_dept),''), nullif(trim(p_role),''), req, uname)
    returning app_job_profiles.id into newid;
    return query select true,'Профиль должности создан', newid;
  else
    update public.app_job_profiles p set title = left(trim(p_title),160), dept = nullif(trim(p_dept),''),
           role = nullif(trim(p_role),''), requirements = req
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Профиль не найден', null::uuid; return; end if;
    return query select true,'Профиль сохранён', newid;
  end if;
end $$;

-- ================= RPC: дефицит навыков =================
create or replace function public.app_skill_gap_scan(p_token uuid)
returns table (employee_id uuid, full_name text, emp_position text, profile_title text, skill_code text, skill_name text, required integer, actual integer, gap integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    with prof as (
      select p.title, p.role, p.requirements
        from public.app_job_profiles p where (adm or p.tenant_id = ten) and p.active
    ),
    req as (
      select prof.title as ptitle, prof.role as prole,
             (e->>'code') as scode, coalesce((e->>'level')::int, 0) as lvl
        from prof, jsonb_array_elements(prof.requirements) e
    )
    select e.id, e.full_name, e.job, r.ptitle, sk.code, sk.name, r.lvl,
           coalesce(ss.level, 0), greatest(r.lvl - coalesce(ss.level,0), 0)
      from public.app_employees e
      join req r on (lower(coalesce(e.job,'')) = lower(r.ptitle) or (r.prole is not null and e.role = r.prole))
      join public.app_skills sk on sk.code = r.scode and (adm or sk.tenant_id = ten)
      left join public.app_staff_skills ss on ss.employee_id = e.id and ss.skill_id = sk.id
     where (adm or e.tenant_id = ten) and coalesce(e.active,true)
       and greatest(r.lvl - coalesce(ss.level,0), 0) > 0
     order by e.full_name, sk.name;
end $$;

-- ================= RPC: сертификаты =================
create or replace function public.app_cert_list(p_token uuid, p_employee_id uuid default null)
returns table (id uuid, employee_id uuid, employee text, name text, number text, issued_at date, expires_at date, days_left integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.employee_id, e.full_name, c.name, c.number, c.issued_at, c.expires_at,
           case when c.expires_at is null then null else (c.expires_at - current_date) end
      from public.app_certificates c left join public.app_employees e on e.id = c.employee_id
     where (adm or c.tenant_id = ten) and (p_employee_id is null or c.employee_id = p_employee_id)
     order by c.expires_at nulls last;
end $$;

create or replace function public.app_cert_save(p_token uuid, p_id uuid, p_employee_id uuid, p_name text, p_number text, p_issued date, p_expires date, p_skill_code text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'competences') then return query select false,'Нет прав', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' or p_employee_id is null then return query select false,'Укажите сотрудника и название', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_certificates (tenant_id, employee_id, name, number, skill_code, issued_at, expires_at, note, created_login)
    values (ten, p_employee_id, left(trim(p_name),200), nullif(trim(p_number),''), nullif(trim(p_skill_code),''), p_issued, p_expires, nullif(trim(p_note),''), uname)
    returning app_certificates.id into newid;
    return query select true,'Сертификат добавлен', newid;
  else
    update public.app_certificates c set employee_id = p_employee_id, name = left(trim(p_name),200), number = nullif(trim(p_number),''),
           skill_code = nullif(trim(p_skill_code),''), issued_at = p_issued, expires_at = p_expires, note = nullif(trim(p_note),'')
     where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten)
     returning c.id into newid;
    if newid is null then return query select false,'Сертификат не найден', null::uuid; return; end if;
    return query select true,'Сертификат сохранён', newid;
  end if;
end $$;

create or replace function public.app_cert_scan(p_token uuid, p_days integer default 30)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  for rec in
    select c.name, c.expires_at, e.full_name, e.user_login
      from public.app_certificates c join public.app_employees e on e.id = c.employee_id
     where (adm or c.tenant_id = ten) and c.expires_at is not null
       and c.expires_at between current_date and current_date + greatest(coalesce(p_days,30),1)
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','hr','chief'], 'Сертификат истекает: ' || rec.full_name,
      rec.name || ' — до ' || to_char(rec.expires_at,'DD.MM.YYYY'), 'apps/competences/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Сертификатов к продлению: ' || cnt;
end $$;

-- ================= RPC: авто-назначение курса по дефициту =================
create or replace function public.app_training_auto_assign(p_token uuid, p_course_id uuid, p_min_gap integer default 1)
returns table (ok boolean, message text, assigned integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'elearning') then return query select false,'Нет прав на обучение', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_courses c where c.id = p_course_id and (adm or c.tenant_id = ten)) then
    return query select false,'Курс не найден', 0; return;
  end if;
  for rec in
    select distinct g.employee_id, e.user_login
      from public.app_skill_gap_scan(p_token) g join public.app_employees e on e.id = g.employee_id
     where g.gap >= coalesce(p_min_gap,1) and e.user_login is not null
       and not exists (select 1 from public.app_course_enrollments en
                        where en.course_id = p_course_id and en.employee_login = e.user_login and en.status <> 'completed')
  loop
    insert into public.app_course_enrollments (tenant_id, course_id, employee_login, status, progress)
    values (ten, p_course_id, rec.user_login, 'assigned', 0);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Назначено курсов по дефициту: ' || cnt, cnt;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Персонал','Компетенции и обучение 2.0: профили, дефицит, сертификаты, авто-назначение (X2)',
   'Компетенции 2.0: профили должностей (app_job_profiles — требования [{code,level}] по должности/роли), авторасчёт дефицита (app_skill_gap_scan — матрица компетенций минус профиль), сертификаты и сроки (app_certificates + app_cert_list/save; app_cert_scan — напоминания об истечении), авто-назначение курса по дефициту (app_training_auto_assign — enrollments). Связи: safety (допуски), hr (должность), elearning (курсы).',
   'компетенции профиль должности дефицит навыки сертификат срок обучение курс авто-назначение')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Компетенции и обучение 2.0: профили, дефицит, сертификаты, авто-назначение (X2)'
);

-- ================= Права =================
grant execute on function public.app_job_profile_list(uuid) to anon, authenticated;
grant execute on function public.app_job_profile_save(uuid,uuid,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_skill_gap_scan(uuid) to anon, authenticated;
grant execute on function public.app_cert_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_cert_save(uuid,uuid,uuid,text,text,date,date,text,text) to anon, authenticated;
grant execute on function public.app_cert_scan(uuid,integer) to anon, authenticated;
grant execute on function public.app_training_auto_assign(uuid,uuid,integer) to anon, authenticated;
