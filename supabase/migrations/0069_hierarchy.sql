-- ============================================================
-- 3DMP Service · 0069_hierarchy.sql  (v47 — ЭПИК G: P13 подразделения и иерархия)
-- Дерево подразделений организации, руководители, связь сотрудников. База знаний.
-- Зависит от 0001..0068.
-- ============================================================

create table if not exists public.app_departments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  parent_id   uuid references public.app_departments (id) on delete set null,
  name        text not null,
  code        text,
  head        text,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_departments_idx on public.app_departments (tenant_id, parent_id);
alter table public.app_departments enable row level security;

-- Связь сотрудника с подразделением (если есть таблица сотрудников)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='app_employees') then
    alter table public.app_employees add column if not exists department_id uuid references public.app_departments (id) on delete set null;
  end if;
end $$;

create or replace function public.app_departments_list(p_token uuid, p_q text default null)
returns table (id uuid, parent_id uuid, name text, code text, head text, active boolean, employees bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.parent_id, d.name, d.code, d.head, d.active,
      (select count(*) from public.app_employees e where e.department_id=d.id)
    from public.app_departments d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.name) like '%'||qq||'%' or lower(coalesce(d.code,'')) like '%'||qq||'%' or lower(coalesce(d.head,'')) like '%'||qq||'%')
    order by d.name;
end $$;

create or replace function public.app_department_kpi(p_token uuid)
returns table (total bigint, root bigint, with_head bigint, max_depth int)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with recursive t as (
      select d.id, d.parent_id, 1 as depth from public.app_departments d
        where (urole='admin' or d.tenant_id=ten) and d.parent_id is null
      union all
      select d.id, d.parent_id, t.depth+1 from public.app_departments d join t on d.parent_id=t.id
    )
    select (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten) and parent_id is null),
      (select count(*) from public.app_departments where (urole='admin' or tenant_id=ten) and coalesce(head,'')<>''),
      coalesce((select max(depth) from t),0);
end $$;

create or replace function public.app_department_save(p_token uuid, p_id uuid, p_parent_id uuid, p_name text,
  p_code text, p_head text, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название подразделения'; return; end if;
  if p_parent_id = p_id and p_id is not null then raise exception 'Подразделение не может быть родителем само себе'; return; end if;
  if p_id is null then
    insert into public.app_departments (tenant_id, parent_id, name, code, head, note, active)
    values (ten, p_parent_id, trim(p_name), nullif(trim(p_code),''), nullif(trim(p_head),''), nullif(trim(p_note),''), coalesce(p_active,true))
    returning id into did;
    return query select did, 'Подразделение создано';
  else
    update public.app_departments set parent_id=p_parent_id, name=trim(p_name), code=nullif(trim(p_code),''),
      head=nullif(trim(p_head),''), note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Подразделение обновлено';
  end if;
end $$;

create or replace function public.app_department_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; kids int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*) into kids from public.app_departments where parent_id=p_id;
  if kids > 0 then return query select false,'Есть дочерние подразделения — сначала перенесите их'; return; end if;
  delete from public.app_departments where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Подразделение удалено';
end $$;

grant execute on function public.app_departments_list(uuid,text) to anon, authenticated;
grant execute on function public.app_department_kpi(uuid) to anon, authenticated;
grant execute on function public.app_department_save(uuid,uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_department_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо-структура (тенант A) ----------
do $$
declare d_gen uuid; d_prod uuid; d_mech uuid; d_qc uuid;
begin
  if not exists (select 1 from public.app_departments where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_departments (tenant_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001','Управление','ADM','Директор') returning id into d_gen;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Производство','PROD','Начальник цеха') returning id into d_prod;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_prod, 'Механообработка','MECH','Мастер') returning id into d_mech;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'ОТК','QC','Начальник ОТК') returning id into d_qc;
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Технологический отдел','TECH','Главный технолог');
    insert into public.app_departments (tenant_id, parent_id, name, code, head) values ('aaaaaaaa-0000-0000-0000-000000000001', d_gen, 'Снабжение','SUP','Начальник снабжения');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Подразделения и иерархия (P13)',
   'Модуль «Подразделения»: дерево структуры организации (родитель → потомки), код, руководитель, активность, число сотрудников. Сотрудники связываются с подразделением (app_employees.department_id). KPI: всего, корневых, с руководителем, глубина. Используется для разграничения и оргсхемы.',
   'подразделения иерархия оргструктура дерево отдел руководитель P13')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Подразделения и иерархия (P13)');
