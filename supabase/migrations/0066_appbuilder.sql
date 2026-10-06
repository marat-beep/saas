-- ============================================================
-- 3DMP Service · 0066_appbuilder.sql  (v44 — ЭПИК G: P2 App Builder)
-- Конструктор пользовательских сущностей: сущность → поля → записи.
-- Позволяет организации заводить свои справочники/журналы без разработки.
-- База знаний. Зависит от 0001..0065.
-- ============================================================

create table if not exists public.app_entities (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  name        text not null,
  code        text,
  icon        text default '🧩',
  description text,
  active      boolean not null default true,
  created_login text,
  created_at  timestamptz not null default now()
);
create index if not exists app_entities_idx on public.app_entities (tenant_id, active);
alter table public.app_entities enable row level security;

create table if not exists public.app_entity_fields (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid references public.app_entities (id) on delete cascade,
  name        text not null,
  code        text not null,
  field_type  text not null default 'text', -- text|number|date|select|bool|textarea
  options     text,                          -- для select: значения через запятую
  required    boolean not null default false,
  sort        int default 100
);
create index if not exists app_entity_fields_idx on public.app_entity_fields (entity_id);
alter table public.app_entity_fields enable row level security;

create table if not exists public.app_entity_records (
  id           uuid primary key default gen_random_uuid(),
  entity_id    uuid references public.app_entities (id) on delete cascade,
  tenant_id    uuid references public.tenants (id),
  data         jsonb not null default '{}'::jsonb,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_entity_records_idx on public.app_entity_records (entity_id, created_at desc);
alter table public.app_entity_records enable row level security;

-- ---------- Сущности ----------
create or replace function public.app_entity_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, code text, icon text, description text, active boolean,
               fields_count bigint, records_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select e.id, e.name, e.code, e.icon, e.description, e.active,
      (select count(*) from public.app_entity_fields f where f.entity_id=e.id),
      (select count(*) from public.app_entity_records r where r.entity_id=e.id),
      e.created_at
    from public.app_entities e
    where (urole='admin' or e.tenant_id=ten)
      and (qq='' or lower(e.name) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%')
    order by e.active desc, e.name;
end $$;

create or replace function public.app_entity_save(p_token uuid, p_id uuid, p_name text, p_code text,
  p_icon text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название сущности'; return; end if;
  if p_id is null then
    insert into public.app_entities (tenant_id, name, code, icon, description, active, created_login)
    values (ten, trim(p_name), nullif(trim(p_code),''), coalesce(nullif(trim(p_icon),''),'🧩'),
            nullif(trim(p_description),''), coalesce(p_active,true), ulogin)
    returning id into eid;
    return query select eid, 'Сущность создана';
  else
    update public.app_entities set name=trim(p_name), code=nullif(trim(p_code),''),
      icon=coalesce(nullif(trim(p_icon),''),icon), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into eid;
    return query select eid, 'Сущность обновлена';
  end if;
end $$;

-- ---------- Поля ----------
create or replace function public.app_entity_fields_list(p_token uuid, p_entity_id uuid)
returns table (id uuid, name text, code text, field_type text, options text, required boolean, sort int)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then
    raise exception 'Сущность не найдена';
  end if;
  return query select f.id, f.name, f.code, f.field_type, f.options, f.required, f.sort
    from public.app_entity_fields f where f.entity_id=p_entity_id order by f.sort, f.name;
end $$;

create or replace function public.app_entity_field_save(p_token uuid, p_id uuid, p_entity_id uuid,
  p_name text, p_code text, p_field_type text, p_options text, p_required boolean, p_sort int)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then raise exception 'Сущность не найдена'; return; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_code),'') = '' then raise exception 'Укажите название и код поля'; return; end if;
  if p_field_type not in ('text','number','date','select','bool','textarea') then raise exception 'Неверный тип поля'; return; end if;
  if p_id is null then
    insert into public.app_entity_fields (entity_id, name, code, field_type, options, required, sort)
    values (p_entity_id, trim(p_name), trim(p_code), p_field_type, nullif(trim(p_options),''), coalesce(p_required,false), coalesce(p_sort,100))
    returning id into fid;
    return query select fid, 'Поле добавлено';
  else
    update public.app_entity_fields set name=trim(p_name), code=trim(p_code), field_type=p_field_type,
      options=nullif(trim(p_options),''), required=coalesce(p_required,false), sort=coalesce(p_sort,100)
     where id=p_id and entity_id=p_entity_id returning id into fid;
    return query select fid, 'Поле обновлено';
  end if;
end $$;

create or replace function public.app_entity_field_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_entity_fields f using public.app_entities e
    where f.id=p_id and e.id=f.entity_id and (urole='admin' or e.tenant_id=ten);
  return query select true,'Поле удалено';
end $$;

-- ---------- Записи ----------
create or replace function public.app_entity_records_list(p_token uuid, p_entity_id uuid, p_q text default null)
returns table (id uuid, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select r.id, r.data, r.created_login, r.created_at
    from public.app_entity_records r
    where r.entity_id=p_entity_id and (urole='admin' or r.tenant_id=ten)
      and (qq='' or lower(r.data::text) like '%'||qq||'%')
    order by r.created_at desc;
end $$;

create or replace function public.app_entity_record_save(p_token uuid, p_id uuid, p_entity_id uuid, p_data jsonb)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_entities e where e.id=p_entity_id and (urole='admin' or e.tenant_id=ten)) then raise exception 'Сущность не найдена'; return; end if;
  if p_id is null then
    insert into public.app_entity_records (entity_id, tenant_id, data, created_login)
    values (p_entity_id, ten, coalesce(p_data,'{}'::jsonb), ulogin) returning id into rid;
    return query select rid, 'Запись добавлена';
  else
    update public.app_entity_records set data=coalesce(p_data,'{}'::jsonb)
     where id=p_id and entity_id=p_entity_id and (urole='admin' or tenant_id=ten) returning id into rid;
    return query select rid, 'Запись обновлена';
  end if;
end $$;

create or replace function public.app_entity_record_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_entity_records where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Запись удалена';
end $$;

grant execute on function public.app_entity_list(uuid,text) to anon, authenticated;
grant execute on function public.app_entity_save(uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_entity_fields_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_entity_field_save(uuid,uuid,uuid,text,text,text,text,boolean,int) to anon, authenticated;
grant execute on function public.app_entity_field_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_entity_records_list(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_entity_record_save(uuid,uuid,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_entity_record_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо-сущность (тенант A) ----------
do $$
declare eid uuid;
begin
  if not exists (select 1 from public.app_entities where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='VISIT') then
    insert into public.app_entities (tenant_id, name, code, icon, description, created_login)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'Журнал посещений', 'VISIT', '📓', 'Учёт посещений подрядчиков', 'owner')
    returning id into eid;
    insert into public.app_entity_fields (entity_id, name, code, field_type, options, required, sort) values
      (eid, 'Дата', 'date', 'date', null, true, 10),
      (eid, 'ФИО', 'name', 'text', null, true, 20),
      (eid, 'Организация', 'org', 'text', null, false, 30),
      (eid, 'Цель визита', 'goal', 'select', 'обслуживание,доставка,переговоры,инспекция', false, 40),
      (eid, 'Примечание', 'note', 'textarea', null, false, 50);
    insert into public.app_entity_records (entity_id, tenant_id, data, created_login)
    values (eid, 'aaaaaaaa-0000-0000-0000-000000000001',
      jsonb_build_object('date', to_char(current_date,'YYYY-MM-DD'), 'name', 'Петров П.П.', 'org', 'ООО «Инструмент-Про»', 'goal', 'обслуживание', 'note', 'Наладка станка'),
      'owner');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','App Builder — свои справочники и журналы (P2)',
   'Модуль «Конструктор приложений»: без разработки создаются пользовательские сущности — задаются поля (текст, число, дата, список, флаг, текстarea) и ведутся записи. Подходит для журналов, реестров, дополнительных справочников предприятия. Данные изолированы по организации.',
   'app builder конструктор сущности поля записи журнал справочник P2')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='App Builder — свои справочники и журналы (P2)');
