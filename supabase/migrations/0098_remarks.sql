-- ============================================================
-- 3DMP Service · 0098_remarks.sql  (v77 — модуль «Замечания к странице»)
-- Таблица app_page_remarks + RPC. Tenant-изоляция. Зависит от 0001..0097.
-- ============================================================

create table if not exists public.app_page_remarks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  module        text,
  url           text,
  x             numeric not null default 0,
  y             numeric not null default 0,
  role          text not null default 'employee',
  role_name     text,
  author        text,
  type          text,
  text          text,
  resolved      boolean not null default false,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_page_remarks_idx on public.app_page_remarks (tenant_id, module, created_at desc);
alter table public.app_page_remarks enable row level security;

create or replace function public.app_remark_list(p_token uuid, p_module text default null, p_url text default null)
returns table (id uuid, module text, url text, x numeric, y numeric, role text, role_name text, author text, type text, text text, resolved boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.module, r.url, r.x, r.y, r.role, r.role_name, r.author, r.type, r.text, r.resolved, r.created_at
    from public.app_page_remarks r
    where (urole='admin' or r.tenant_id=ten)
      and (coalesce(p_module,'')='' or r.module=p_module)
      and (coalesce(p_url,'')='' or r.url=p_url)
    order by r.created_at desc;
end $$;

create or replace function public.app_remark_create(p_token uuid, p_module text, p_url text, p_x numeric, p_y numeric,
  p_role text, p_role_name text, p_author text, p_type text, p_text text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_page_remarks (tenant_id, module, url, x, y, role, role_name, author, type, text, created_login)
  values (ten, nullif(trim(p_module),''), nullif(trim(p_url),''), coalesce(p_x,0), coalesce(p_y,0),
          coalesce(nullif(trim(p_role),''),'employee'), nullif(trim(p_role_name),''), nullif(trim(p_author),''),
          nullif(trim(p_type),''), nullif(trim(p_text),''), ulogin)
  returning id into rid;
  return query select rid, 'Замечание сохранено';
end $$;

create or replace function public.app_remark_resolve(p_token uuid, p_id uuid, p_resolved boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_page_remarks set resolved=coalesce(p_resolved,false), updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_remark_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_page_remarks where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Замечание удалено';
end $$;

create or replace function public.app_remark_delete_all(p_token uuid, p_module text default null, p_url text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_page_remarks r
   where (urole='admin' or r.tenant_id=ten)
     and (coalesce(p_module,'')='' or r.module=p_module)
     and (coalesce(p_url,'')='' or r.url=p_url);
  return query select true,'Замечания удалены';
end $$;

grant execute on function public.app_remark_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_remark_create(uuid,text,text,numeric,numeric,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_remark_resolve(uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.app_remark_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_remark_delete_all(uuid,text,text) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Замечания к странице (модуль)',
   'Модуль «Замечания к странице»: визуальные замечания поверх снимка страницы (метки в %), роли сотрудник/клиент, типы, статусы; экспорт PDF (снимок+метки+таблица). Данные — app_page_remarks через RPC; без backend используется демо-режим (localStorage) и mock-снимок.',
   'замечания страница remarks метки PDF bug-mode снимок')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Замечания к странице (модуль)');
