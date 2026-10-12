-- ============================================================
-- 3DMP Service · 0207_setup_wizard.sql
-- Мастер настройки/готовности (app_setup_steps, app_setup_readiness),
-- демо-данные по модулям (app_demo_status/seed/reset) с флагом is_demo.
-- Идемпотентно. Зависит от 0001..0206.
-- ============================================================

-- ---------- Метка демо-строк (по модулям) ----------
do $$
declare t text;
begin
  foreach t in array array['app_customers','app_suppliers','app_materials','app_equipment','app_work_centers',
                           'app_departments','app_employees','app_skills','app_orders','app_naryads',
                           'app_naryad_ops','app_qc_checks','app_defects','app_service_requests','app_projects',
                           'app_documents','app_courses']
  loop
    execute format('alter table public.%I add column if not exists is_demo boolean not null default false', t);
  end loop;
end $$;

alter table public.tenants add column if not exists is_demo boolean not null default false;
update public.tenants set is_demo = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';

create index if not exists app_customers_demo_idx on public.app_customers (tenant_id) where is_demo;
create index if not exists app_suppliers_demo_idx on public.app_suppliers (tenant_id) where is_demo;
create index if not exists app_materials_demo_idx on public.app_materials (tenant_id) where is_demo;
create index if not exists app_equipment_demo_idx on public.app_equipment (tenant_id) where is_demo;
create index if not exists app_orders_demo_idx on public.app_orders (tenant_id) where is_demo;
create index if not exists app_naryads_demo_idx on public.app_naryads (tenant_id) where is_demo;
create index if not exists app_service_requests_demo_idx on public.app_service_requests (tenant_id) where is_demo;

-- ---------- Шаги мастера ----------
create table if not exists public.app_setup_steps (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id) on delete cascade,
  step_key   text not null,
  status     text not null default 'planned',  -- planned|done|skipped
  note       text,
  by_login   text,
  updated_at timestamptz not null default now(),
  unique (tenant_id, step_key)
);
alter table public.app_setup_steps enable row level security;

-- ================= RPC: готовность справочников =================
create or replace function public.app_setup_readiness(p_token uuid)
returns table (key text, label text, module text, cnt bigint, target integer, ready boolean, link text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
  with r(k,lbl,mod,tgt,lnk) as (values
    ('departments','Подразделения','org',3,'apps/departments/index.html'),
    ('employees','Сотрудники','hr',1,'apps/hr/index.html'),
    ('customers','Заказчики','crm',1,'apps/crm/index.html'),
    ('suppliers','Поставщики','procurement',1,'apps/suppliers/index.html'),
    ('materials','Материалы','warehouse',1,'apps/warehouse/index.html'),
    ('equipment','Оборудование','equipment',1,'apps/equipment/index.html'),
    ('work_centers','Рабочие центры','production',1,'apps/production/index.html'),
    ('skills','Навыки','competences',1,'apps/competences/index.html'),
    ('templates','Шаблоны документов','templates',1,'apps/templates/index.html'),
    ('subscription','Тариф/подписка','billing',1,'apps/billing/index.html')
  )
  select r.k, r.lbl, r.mod, c.cnt, r.tgt, (c.cnt >= r.tgt), r.lnk
  from r
  cross join lateral (
    select case r.k
      when 'departments' then (select count(*) from public.app_departments x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'employees' then (select count(*) from public.app_employees x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'customers' then (select count(*) from public.app_customers x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'suppliers' then (select count(*) from public.app_suppliers x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'materials' then (select count(*) from public.app_materials x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'equipment' then (select count(*) from public.app_equipment x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'work_centers' then (select count(*) from public.app_work_centers x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'skills' then (select count(*) from public.app_skills x where (adm or x.tenant_id=ten) and not x.is_demo)
      when 'templates' then (select count(*) from public.app_doc_templates x where (adm or x.tenant_id=ten))
      when 'subscription' then (select count(*) from public.app_subscriptions x where (adm or x.tenant_id=ten))
      else 0 end as cnt
  ) c
  order by r.k;
end $$;

create or replace function public.app_setup_steps_list(p_token uuid)
returns table (step_key text, status text, note text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select s.step_key, s.status, s.note, s.updated_at
    from public.app_setup_steps s where (adm or s.tenant_id = ten) order by s.step_key;
end $$;

create or replace function public.app_setup_step_set(p_token uuid, p_key text, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав'; return;
  end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('planned','done','skipped') then return query select false,'Недопустимый статус'; return; end if;
  if coalesce(trim(p_key),'') = '' then return query select false,'Укажите шаг'; return; end if;
  insert into public.app_setup_steps (tenant_id, step_key, status, note, by_login, updated_at)
  values (ten, left(trim(p_key),80), st, nullif(trim(p_note),''), uname, now())
  on conflict (tenant_id, step_key) do update set status = excluded.status, note = excluded.note, by_login = excluded.by_login, updated_at = now();
  return query select true,'Шаг обновлён: ' || p_key;
end $$;

-- ================= RPC: демо-данные =================
create or replace function public.app_demo_status(p_token uuid)
returns table (module text, label text, rows bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
  with m(mod,lbl) as (values
    ('refs','Справочники (заказчики/поставщики/материалы/оборудование/РЦ/подразделения/навыки)'),
    ('hr','Персонал'),('orders','Заявки'),('production','Производство'),('qc','Качество'),
    ('service','Сервис'),('projects','Проекты'),('docs','Документы'),('courses','Обучение')
  )
  select m.mod, m.lbl,
    case m.mod
      when 'refs' then (select count(*) from public.app_customers x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_suppliers x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_materials x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_equipment x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_work_centers x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_departments x where (adm or x.tenant_id=ten) and x.is_demo)
                     + (select count(*) from public.app_skills x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'hr' then (select count(*) from public.app_employees x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'orders' then (select count(*) from public.app_orders x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'production' then (select count(*) from public.app_naryads x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'qc' then (select count(*) from public.app_qc_checks x where (adm or x.tenant_id=ten) and x.is_demo)
                  + (select count(*) from public.app_defects x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'service' then (select count(*) from public.app_service_requests x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'projects' then (select count(*) from public.app_projects x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'docs' then (select count(*) from public.app_documents x where (adm or x.tenant_id=ten) and x.is_demo)
      when 'courses' then (select count(*) from public.app_courses x where (adm or x.tenant_id=ten) and x.is_demo)
      else 0 end
  from m order by m.mod;
end $$;

create or replace function public.app_demo_seed(p_token uuid, p_module text)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; mod text; n integer := 0; nid uuid; d1 uuid; wid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав (нужны владелец/администратор)',0; return;
  end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  mod := lower(trim(coalesce(p_module,'')));

  if mod in ('refs','all') then
    insert into public.app_departments (tenant_id, name, code, head, is_demo)
    select ten, v.n, v.c, 'Демо', true from (values ('Производство','DEMO-PRO'),('ОТК','DEMO-QC')) v(n,c)
    where not exists (select 1 from public.app_departments x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    select id into d1 from public.app_departments where tenant_id=ten and is_demo order by created_at limit 1;
    insert into public.app_work_centers (tenant_id, name, active, is_demo)
    select ten, v.n, true, true from (values ('Фрезерный DEMO'),('Токарный DEMO')) v(n)
    where not exists (select 1 from public.app_work_centers x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    select id into wid from public.app_work_centers where tenant_id=ten and is_demo order by name limit 1;
    insert into public.app_customers (tenant_id, name, is_demo)
    select ten, v.n, true from (values ('Демо-Заказчик А'),('Демо-Заказчик Б')) v(n)
    where not exists (select 1 from public.app_customers x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    insert into public.app_suppliers (tenant_id, name, category, status, rating, is_demo)
    select ten, v.n, 'materials', 'accredited', 4, true from (values ('Демо-Поставщик А'),('Демо-Поставщик Б')) v(n)
    where not exists (select 1 from public.app_suppliers x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    insert into public.app_materials (tenant_id, code, name, unit, qty, min_qty, is_demo)
    select ten, v.c, v.n, v.u, 100, 10, true
    from (values ('DEMO-M1','Сталь 45 DEMO','кг'),('DEMO-M2','Алюминий Д16Т DEMO','кг'),('DEMO-M3','Фреза Ø10 DEMO','шт')) v(c,n,u)
    where not exists (select 1 from public.app_materials x where x.tenant_id=ten and x.is_demo and x.code=v.c);
    insert into public.app_equipment (tenant_id, name, kind, status, is_demo)
    select ten, v.n, 'frezerny', 'active', true from (values ('Станок DEMO-1'),('Станок DEMO-2')) v(n)
    where not exists (select 1 from public.app_equipment x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    insert into public.app_skills (tenant_id, code, name, category, is_demo)
    select ten, v.c, v.n, 'tech', true from (values ('DEMO-CNC','ЧПУ DEMO'),('DEMO-QC','ОТК DEMO'),('DEMO-WELD','Сварка DEMO')) v(c,n)
    where not exists (select 1 from public.app_skills x where x.tenant_id=ten and x.is_demo and x.code=v.c);
    n := n + 1;
  end if;

  if mod in ('hr','all') then
    insert into public.app_employees (tenant_id, full_name, job, dept, active, is_demo)
    select ten, v.n, v.j, v.dept, true, true
    from (values ('Демо Иванов','Оператор ЧПУ','Производство'),('Демо Петров','Мастер','Производство'),('Демо Сидоров','Контролёр ОТК','ОТК')) v(n,j,dept)
    where not exists (select 1 from public.app_employees x where x.tenant_id=ten and x.is_demo and x.full_name=v.n);
    n := n + 1;
  end if;

  if mod in ('orders','all') then
    insert into public.app_orders (tenant_id, number, title, status, priority, is_demo)
    select ten, 'DEMO-Z-' || v.i, v.n, 'new', 'normal', true
    from (values ('1','Демо-заявка: фрезеровка'),('2','Демо-заявка: токарка'),('3','Демо-заявка: оснастка')) v(i,n)
    where not exists (select 1 from public.app_orders x where x.tenant_id=ten and x.is_demo and x.number='DEMO-Z-'||v.i);
    n := n + 1;
  end if;

  if mod in ('production','all') then
    insert into public.app_naryads (tenant_id, number, title, wc_id, status, priority, is_demo)
    select ten, 'DEMO-N-' || v.i, v.n, wid, 'open', 'normal', true
    from (values ('1','Демо-наряд: партия А'),('2','Демо-наряд: партия Б')) v(i,n)
    where not exists (select 1 from public.app_naryads x where x.tenant_id=ten and x.is_demo and x.number='DEMO-N-'||v.i);
    insert into public.app_naryad_ops (naryad_id, operation, plan_hours, done, mes_status, is_demo)
    select nn.id, v.op, v.h, false, 'queue', true
    from public.app_naryads nn
    cross join (values ('Фрезерная DEMO', 2.0), ('Слесарная DEMO', 1.5)) v(op,h)
    where nn.tenant_id=ten and nn.is_demo
      and not exists (select 1 from public.app_naryad_ops o where o.naryad_id=nn.id and o.is_demo);
    n := n + 1;
  end if;

  if mod in ('qc','all') then
    insert into public.app_qc_checks (tenant_id, number, status, is_demo)
    select ten, 'DEMO-QC-' || v.i, 'draft', true from (values ('1'),('2')) v(i)
    where not exists (select 1 from public.app_qc_checks x where x.tenant_id=ten and x.is_demo and x.number='DEMO-QC-'||v.i);
    insert into public.app_defects (tenant_id, title, severity, status, is_demo)
    select ten, v.n, 'minor', 'open', true from (values ('Демо-дефект: задир'),('Демо-дефект: размер')) v(n)
    where not exists (select 1 from public.app_defects x where x.tenant_id=ten and x.is_demo and x.title=v.n);
    n := n + 1;
  end if;

  if mod in ('service','all') then
    insert into public.app_service_requests (tenant_id, title, kind, status, priority, is_demo)
    select ten, v.n, 'service', 'new', 'normal', true from (values ('Демо-сервис: выезд'),('Демо-сервис: наладка')) v(n)
    where not exists (select 1 from public.app_service_requests x where x.tenant_id=ten and x.is_demo and x.title=v.n);
    n := n + 1;
  end if;

  if mod in ('projects','all') then
    insert into public.app_projects (tenant_id, name, status, is_demo)
    select ten, v.n, 'active', true from (values ('Демо-проект: участок'),('Демо-проект: оснастка')) v(n)
    where not exists (select 1 from public.app_projects x where x.tenant_id=ten and x.is_demo and x.name=v.n);
    n := n + 1;
  end if;

  if mod in ('docs','all') then
    insert into public.app_documents (tenant_id, doc_type, number, title, status, is_demo)
    select ten, v.t, v.n, v.n, 'draft', true
    from (values ('DEMO-D-1','Демо-КП'),('DEMO-D-2','Демо-договор')) v(n,t)
    where not exists (select 1 from public.app_documents x where x.tenant_id=ten and x.is_demo and x.number=v.n);
    n := n + 1;
  end if;

  if mod in ('courses','all') then
    insert into public.app_courses (tenant_id, code, name, is_demo)
    select ten, 'DEMO-C-' || v.i, v.n, true
    from (values ('1','Демо-курс: Охрана труда'),('2','Демо-курс: ЧПУ')) v(i,n)
    where not exists (select 1 from public.app_courses x where x.tenant_id=ten and x.is_demo and x.code='DEMO-C-'||v.i);
    n := n + 1;
  end if;

  if n = 0 then return query select false,'Неизвестный или пустой модуль (refs/hr/orders/production/qc/service/projects/docs/courses/all)',0; return; end if;
  return query select true, 'Демо-данные добавлены (модулей: ' || n || ')', n;
end $$;

create or replace function public.app_demo_reset(p_token uuid, p_module text)
returns table (ok boolean, message text, deleted integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; mod text; d integer := 0; r integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав (нужны владелец/администратор)',0; return;
  end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  mod := lower(trim(coalesce(p_module,'')));

  if mod in ('production','refs','all') then
    delete from public.app_naryad_ops o using public.app_naryads n where o.naryad_id=n.id and (adm or n.tenant_id=ten) and o.is_demo;
    get diagnostics r = row_count; d := d + r;
    delete from public.app_naryads where (adm or tenant_id=ten) and is_demo;
    get diagnostics r = row_count; d := d + r;
  end if;
  if mod in ('qc','all') then
    delete from public.app_defects where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_qc_checks where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
  end if;
  if mod in ('orders','all') then delete from public.app_orders where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('service','all') then delete from public.app_service_requests where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('projects','all') then delete from public.app_projects where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('docs','all') then delete from public.app_documents where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('courses','all') then delete from public.app_courses where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('hr','refs','all') then delete from public.app_employees where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r; end if;
  if mod in ('refs','all') then
    delete from public.app_equipment where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_materials where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_suppliers where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_customers where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_work_centers where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_skills where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
    delete from public.app_departments where (adm or tenant_id=ten) and is_demo; get diagnostics r = row_count; d := d + r;
  end if;
  return query select true, 'Удалено демо-строк: ' || d, d;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Мастер настройки и демо-данные (0207)',
   'Мастер настройки: готовность справочников (app_setup_readiness — % по подразделениям/сотрудникам/заказчикам/поставщикам/материалам/оборудованию/РЦ/навыкам/шаблонам/тарифу), шаги (app_setup_steps_list/set). Демо-данные по модулям: app_demo_status (сколько демо-строк), app_demo_seed(module) и app_demo_reset(module) — строки помечаются is_demo и удаляются по флагу, реальные данные не затрагиваются. Модули: refs/hr/orders/production/qc/service/projects/docs/courses/all.',
   'мастер настройки готовность справочники демо-данные seed reset is_demo онбординг')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Мастер настройки и демо-данные (0207)'
);

-- ================= Права =================
grant execute on function public.app_setup_readiness(uuid) to anon, authenticated;
grant execute on function public.app_setup_steps_list(uuid) to anon, authenticated;
grant execute on function public.app_setup_step_set(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_demo_status(uuid) to anon, authenticated;
grant execute on function public.app_demo_seed(uuid,text) to anon, authenticated;
grant execute on function public.app_demo_reset(uuid,text) to anon, authenticated;
