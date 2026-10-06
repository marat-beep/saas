-- ============================================================
-- 3DMP Service · 0110_competences.sql  (v95 — PLAN_MODERNIZATION, Партия J)
-- Компетенции и обучение: навыки (app_skills), уровни сотрудников
-- (app_staff_skills), план обучения (app_training_plan); матрица компетенций.
-- Идемпотентно. Зависит от 0001..0109.
-- ============================================================

create table if not exists public.app_skills (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text not null,
  name       text not null,
  category   text,
  max_level  int not null default 5,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists app_skills_uq on public.app_skills (tenant_id, code);
alter table public.app_skills enable row level security;

create table if not exists public.app_staff_skills (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  employee_id uuid references public.app_employees (id) on delete cascade,
  skill_id    uuid references public.app_skills (id) on delete cascade,
  level       int not null default 0,
  note        text,
  updated_at  timestamptz not null default now()
);
create unique index if not exists app_staff_skills_uq on public.app_staff_skills (employee_id, skill_id);
alter table public.app_staff_skills enable row level security;

create table if not exists public.app_training_plan (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  employee_id  uuid references public.app_employees (id) on delete cascade,
  skill_id     uuid references public.app_skills (id) on delete set null,
  target_level int,
  status       text not null default 'planned',  -- planned|in_progress|done
  due_date     date,
  note         text,
  created_at   timestamptz not null default now()
);
alter table public.app_training_plan enable row level security;

-- ---------- Навыки ----------
create or replace function public.app_skills_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, category text, max_level int, active boolean, staff int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select sk.id, sk.code, sk.name, sk.category, sk.max_level, sk.active,
           (select count(*)::int from public.app_staff_skills ss where ss.skill_id = sk.id)
    from public.app_skills sk
    where (urole='admin' or sk.tenant_id=ten)
      and (qq='' or lower(sk.name) like '%'||qq||'%' or lower(sk.code) like '%'||qq||'%')
    order by sk.category nulls last, sk.name;
end $$;

create or replace function public.app_skill_save(p_token uuid, p_id uuid, p_code text, p_name text, p_category text, p_max_level integer default 5, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите код и название'; return; end if;
  if p_id is null then
    insert into public.app_skills (tenant_id, code, name, category, max_level, active)
    values (ten, lower(trim(p_code)), trim(p_name), nullif(trim(p_category),''), greatest(coalesce(p_max_level,5),1), coalesce(p_active,true))
    returning id into sid;
    return query select sid, 'Навык создан';
  else
    update public.app_skills set code=lower(trim(p_code)), name=trim(p_name), category=nullif(trim(p_category),''),
      max_level=greatest(coalesce(p_max_level,5),1), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Навык обновлён';
  end if;
end $$;

create or replace function public.app_skill_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then return query select false,'Недостаточно прав'; return; end if;
  delete from public.app_skills where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Навык удалён';
end $$;

-- ---------- Матрица компетенций ----------
create or replace function public.app_competence_matrix(p_token uuid)
returns table (employee_id uuid, full_name text, dept text, role text, levels jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.full_name, e.dept, e.role,
           coalesce(jsonb_object_agg(sk.code, ss.level) filter (where sk.code is not null), '{}'::jsonb)
    from public.app_employees e
    left join public.app_staff_skills ss on ss.employee_id = e.id
    left join public.app_skills sk on sk.id = ss.skill_id
    where (urole='admin' or e.tenant_id=ten) and coalesce(e.active,true)
    group by e.id, e.full_name, e.dept, e.role
    order by e.full_name;
end $$;

create or replace function public.app_staff_skill_set(p_token uuid, p_employee_id uuid, p_skill_id uuid, p_level integer)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; mx int; lv int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','master','technologist','hr') then return query select false,'Недостаточно прав'; return; end if;
  select sk.max_level into mx from public.app_skills sk where sk.id=p_skill_id and (urole='admin' or sk.tenant_id=ten);
  if mx is null then return query select false,'Навык не найден'; return; end if;
  lv := greatest(0, least(coalesce(p_level,0), mx));
  if not exists (select 1 from public.app_employees e where e.id=p_employee_id and (urole='admin' or e.tenant_id=ten)) then
    return query select false,'Сотрудник не найден'; return;
  end if;
  insert into public.app_staff_skills (tenant_id, employee_id, skill_id, level, updated_at)
  values (ten, p_employee_id, p_skill_id, lv, now())
  on conflict (employee_id, skill_id) do update set level=excluded.level, updated_at=now();
  return query select true,'Уровень сохранён';
end $$;

-- ---------- План обучения ----------
create or replace function public.app_training_plan_list(p_token uuid)
returns table (id uuid, employee_id uuid, employee text, skill_id uuid, skill text, target_level int, status text, due_date date, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.employee_id, e.full_name, t.skill_id, sk.name, t.target_level, t.status, t.due_date, t.note
    from public.app_training_plan t
    left join public.app_employees e on e.id = t.employee_id
    left join public.app_skills sk on sk.id = t.skill_id
    where (urole='admin' or t.tenant_id=ten)
    order by t.due_date nulls last, t.created_at desc;
end $$;

create or replace function public.app_training_plan_save(p_token uuid, p_id uuid, p_employee_id uuid, p_skill_id uuid, p_target_level integer, p_status text, p_due_date date, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','master','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if p_employee_id is null then raise exception 'Выберите сотрудника'; return; end if;
  if coalesce(p_status,'') not in ('planned','in_progress','done') then raise exception 'Неверный статус'; return; end if;
  if p_id is null then
    insert into public.app_training_plan (tenant_id, employee_id, skill_id, target_level, status, due_date, note)
    values (ten, p_employee_id, p_skill_id, p_target_level, coalesce(p_status,'planned'), p_due_date, nullif(trim(p_note),''))
    returning id into tid;
    return query select tid, 'Пункт обучения добавлен';
  else
    update public.app_training_plan set employee_id=p_employee_id, skill_id=p_skill_id, target_level=p_target_level,
      status=p_status, due_date=p_due_date, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into tid;
    return query select tid, 'Пункт обучения обновлён';
  end if;
end $$;

grant execute on function public.app_skills_list(uuid,text) to anon, authenticated;
grant execute on function public.app_skill_save(uuid,uuid,text,text,text,integer,boolean) to anon, authenticated;
grant execute on function public.app_skill_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_competence_matrix(uuid) to anon, authenticated;
grant execute on function public.app_staff_skill_set(uuid,uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_training_plan_list(uuid) to anon, authenticated;
grant execute on function public.app_training_plan_save(uuid,uuid,uuid,uuid,integer,text,date,text) to anon, authenticated;

-- ---------- Демо: навыки (тенант A) ----------
insert into public.app_skills (tenant_id, code, name, category, max_level)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.c, v.n, v.cat, 5
from (values
  ('turner','Токарная обработка','Механообработка'),
  ('milling','Фрезерная обработка','Механообработка'),
  ('cnc_setup','Наладка ЧПУ','Механообработка'),
  ('grinding','Шлифование','Механообработка'),
  ('welding','Сварка','Сборка'),
  ('qc','Контроль ОТК','Качество'),
  ('tech_process','Разработка техпроцесса','Инжиниринг'),
  ('cnc_prog','Программирование ЧПУ','Инжиниринг')
) as v(c,n,cat)
where not exists (select 1 from public.app_skills where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Персонал','Компетенции и обучение (Партия J)',
   'Навыки задаются в app_skills (код/категория/макс. уровень). Уровни сотрудников хранятся в app_staff_skills; матрица компетенций (app_competence_matrix) показывает сотрудников × навыки. План обучения (app_training_plan) — целевой уровень, статус (planned/in_progress/done) и срок. Связано с оргструктурой (app_employees) и ролями.',
   'компетенции навыки обучение матрица персонал партия J app_skills app_competence_matrix app_training_plan')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Компетенции и обучение (Партия J)');
