-- ============================================================
-- 3DMP Service · 0096_core_schema.sql  (v74 — Партия A: ядро платформы)
-- Движок схем (тип → поля), единый источник значений (ref_options), связи
-- между сущностями (links), включение модулей по предприятию (tenant_modules).
-- Зависит от 0001..0095.
-- ============================================================

create table if not exists public.app_schemas (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text not null,
  name        text not null,
  icon        text default '🧩',
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists app_schemas_uq on public.app_schemas (tenant_id, code);
alter table public.app_schemas enable row level security;

create table if not exists public.app_schema_fields (
  id            uuid primary key default gen_random_uuid(),
  schema_id     uuid references public.app_schemas (id) on delete cascade,
  code          text not null,
  label         text not null,
  field_type    text not null default 'text',  -- text|number|date|select|textarea|bool|ref|table
  options       text,
  ref_source    text,                          -- dict:code | orders | clients | partners | equipment | operations
  required      boolean not null default false,
  sort          int default 100,
  default_value text
);
create index if not exists app_schema_fields_idx on public.app_schema_fields (schema_id, sort);
alter table public.app_schema_fields enable row level security;

create table if not exists public.app_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  source_type text not null,
  source_id   uuid not null,
  target_type text not null,
  target_id   uuid not null,
  kind        text,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_links_src_idx on public.app_links (tenant_id, source_type, source_id);
create index if not exists app_links_tgt_idx on public.app_links (tenant_id, target_type, target_id);
alter table public.app_links enable row level security;

create table if not exists public.app_tenant_modules (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  module     text not null,
  enabled    boolean not null default true,
  enabled_at timestamptz not null default now()
);
create unique index if not exists app_tenant_modules_uq on public.app_tenant_modules (tenant_id, module);
alter table public.app_tenant_modules enable row level security;

-- ---------- Схемы ----------
create or replace function public.app_schemas_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, icon text, description text, active boolean, fields bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.code, s.name, s.icon, s.description, s.active,
      (select count(*) from public.app_schema_fields f where f.schema_id=s.id)
    from public.app_schemas s
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(s.code) like '%'||qq||'%')
    order by s.name;
end $$;

create or replace function public.app_schema_save(p_token uuid, p_id uuid, p_code text, p_name text, p_icon text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите код и название'; return; end if;
  if p_id is null then
    insert into public.app_schemas (tenant_id, code, name, icon, description, active)
    values (ten, lower(trim(p_code)), trim(p_name), coalesce(nullif(trim(p_icon),''),'🧩'), nullif(trim(p_description),''), coalesce(p_active,true)) returning id into sid;
    return query select sid, 'Схема создана';
  else
    update public.app_schemas set code=lower(trim(p_code)), name=trim(p_name), icon=coalesce(nullif(trim(p_icon),''),icon),
      description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Схема обновлена';
  end if;
end $$;

create or replace function public.app_schema_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_schemas where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Схема удалена';
end $$;

create or replace function public.app_schema_fields_list(p_token uuid, p_schema_id uuid)
returns table (id uuid, code text, label text, field_type text, options text, ref_source text, required boolean, sort int, default_value text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_schemas s where s.id=p_schema_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Схема не найдена'; end if;
  return query select f.id, f.code, f.label, f.field_type, f.options, f.ref_source, f.required, f.sort, f.default_value
    from public.app_schema_fields f where f.schema_id=p_schema_id order by f.sort, f.label;
end $$;

create or replace function public.app_schema_field_save(p_token uuid, p_id uuid, p_schema_id uuid, p_code text, p_label text,
  p_field_type text, p_options text, p_ref_source text, p_required boolean, p_sort int, p_default text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_schemas s where s.id=p_schema_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Схема не найдена'; return; end if;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_label),'')='' then raise exception 'Укажите код и подпись поля'; return; end if;
  if p_field_type not in ('text','number','date','select','textarea','bool','ref','table') then raise exception 'Неверный тип поля'; return; end if;
  if p_id is null then
    insert into public.app_schema_fields (schema_id, code, label, field_type, options, ref_source, required, sort, default_value)
    values (p_schema_id, trim(p_code), trim(p_label), p_field_type, nullif(trim(p_options),''), nullif(trim(p_ref_source),''), coalesce(p_required,false), coalesce(p_sort,100), nullif(trim(p_default),''))
    returning id into fid;
    return query select fid, 'Поле добавлено';
  else
    update public.app_schema_fields set code=trim(p_code), label=trim(p_label), field_type=p_field_type, options=nullif(trim(p_options),''),
      ref_source=nullif(trim(p_ref_source),''), required=coalesce(p_required,false), sort=coalesce(p_sort,100), default_value=nullif(trim(p_default),'')
     where id=p_id and schema_id=p_schema_id returning id into fid;
    return query select fid, 'Поле обновлено';
  end if;
end $$;

create or replace function public.app_schema_field_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_schema_fields f using public.app_schemas s
    where f.id=p_id and s.id=f.schema_id and (urole='admin' or s.tenant_id=ten);
  return query select true,'Поле удалено';
end $$;

-- ---------- Единый источник значений ----------
create or replace function public.app_ref_options(p_token uuid, p_kind text, p_code text default null)
returns table (value text, label text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; k text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); k := lower(coalesce(trim(p_kind),''));
  if k='dict' then
    return query select i.value, i.label from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id
      where (urole='admin' or d.tenant_id=ten) and lower(d.code)=lower(coalesce(p_code,'')) and d.active and i.active order by i.sort;
  elsif k='orders' then
    return query select o.id::text, o.number||' · '||coalesce(o.title,'') from public.app_orders o where (urole='admin' or o.tenant_id=ten) order by o.created_at desc limit 500;
  elsif k='clients' then
    return query select c.id::text, coalesce(c.name,'') from public.app_customers c where (urole='admin' or c.tenant_id=ten) order by c.name limit 500;
  elsif k='partners' then
    return query select p.id::text, p.name from public.app_partners p where (urole='admin' or p.tenant_id=ten) order by p.name limit 500;
  elsif k='equipment' then
    return query select e.id::text, e.name from public.app_equipment_catalog e where (urole='admin' or e.tenant_id=ten) order by e.name limit 500;
  elsif k='operations' then
    return query select o.id::text, o.code||' · '||o.name from public.app_norms_operations o where (urole='admin' or o.tenant_id=ten) order by o.name limit 500;
  else
    return;
  end if;
end $$;

-- ---------- Связи ----------
create or replace function public.app_links_list(p_token uuid, p_type text, p_id uuid)
returns table (id uuid, direction text, source_type text, source_id uuid, target_type text, target_id uuid, kind text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, 'out'::text, l.source_type, l.source_id, l.target_type, l.target_id, l.kind, l.note, l.created_at
      from public.app_links l where (urole='admin' or l.tenant_id=ten) and l.source_type=p_type and l.source_id=p_id
    union all
    select l.id, 'in'::text, l.source_type, l.source_id, l.target_type, l.target_id, l.kind, l.note, l.created_at
      from public.app_links l where (urole='admin' or l.tenant_id=ten) and l.target_type=p_type and l.target_id=p_id
    order by created_at desc;
end $$;

create or replace function public.app_link_add(p_token uuid, p_source_type text, p_source_id uuid, p_target_type text, p_target_id uuid, p_kind text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'builder', 'edit');
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_source_type),'')='' or coalesce(trim(p_target_type),'')='' then raise exception 'Укажите типы связи'; return; end if;
  insert into public.app_links (tenant_id, source_type, source_id, target_type, target_id, kind, note)
  values (ten, trim(p_source_type), p_source_id, trim(p_target_type), p_target_id, nullif(trim(p_kind),''), nullif(trim(p_note),''))
  returning id into lid;
  return query select lid, 'Связь добавлена';
end $$;

create or replace function public.app_link_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'builder','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_links where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Связь удалена';
end $$;

-- ---------- Модули предприятия ----------
create or replace function public.app_tenant_modules_list(p_token uuid)
returns table (module text, enabled boolean, enabled_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.module, m.enabled, m.enabled_at from public.app_tenant_modules m
    where (urole='admin' or m.tenant_id=ten) order by m.module;
end $$;

create or replace function public.app_tenant_module_set(p_token uuid, p_module text, p_enabled boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'platform','edit') then return query select false,'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_module),'')='' then return query select false,'Укажите модуль'; return; end if;
  insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
  values (ten, lower(trim(p_module)), coalesce(p_enabled,true), now())
  on conflict (tenant_id, module) do update set enabled=coalesce(p_enabled,true), enabled_at=now();
  return query select true,'Модуль обновлён';
end $$;

grant execute on function public.app_schemas_list(uuid,text) to anon, authenticated;
grant execute on function public.app_schema_save(uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_schema_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_schema_fields_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_schema_field_save(uuid,uuid,uuid,text,text,text,text,text,boolean,int,text) to anon, authenticated;
grant execute on function public.app_schema_field_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ref_options(uuid,text,text) to anon, authenticated;
grant execute on function public.app_links_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_link_add(uuid,text,uuid,text,uuid,text,text) to anon, authenticated;
grant execute on function public.app_link_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tenant_modules_list(uuid) to anon, authenticated;
grant execute on function public.app_tenant_module_set(uuid,text,boolean) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='contract') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'contract','Договор','📜','Договор подряда/поставки') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, required, sort) values
      (sid,'customer','Заказчик',       'ref',   true, 10),
      (sid,'contractor','Исполнитель',   'text',  true, 20),
      (sid,'subject','Предмет',          'text',  true, 30),
      (sid,'amount','Сумма',             'number',true, 40),
      (sid,'vat','НДС, %',               'number',false,50),
      (sid,'date_start','Начало',        'date',  false,60),
      (sid,'date_end','Окончание',       'date',  false,70),
      (sid,'payment','Порядок оплаты',   'textarea',false,80);
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'techcard','Техкарта','🗒','Технологическая карта') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'product','Изделие',          'text',  null,         true, 10),
      (sid,'material','Материал',        'ref',   'dict:material_kind', false,20),
      (sid,'operation','Операция',       'ref',   'operations', false,30),
      (sid,'machine','Оборудование',     'ref',   'equipment',  false,40),
      (sid,'norm_hours','Норма, н·ч',    'number',null,         false,50),
      (sid,'control','Контроль',         'textarea',null,       false,60);
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'kp','Коммерческое предложение','🧾','КП с позициями') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, required, sort) values
      (sid,'customer','Заказчик',    'ref',    true, 10),
      (sid,'valid_until','Действует до','date', false,20),
      (sid,'discount','Скидка, %',   'number', false,30),
      (sid,'items','Позиции',        'table',  false,40);
  end if;
  if not exists (select 1 from public.app_tenant_modules where tenant_id=A) then
    insert into public.app_tenant_modules (tenant_id, module, enabled)
    select A, m, true from (values
      ('auth'),('panel'),('dashboard'),('guide'),('orders'),('crm'),('tkp'),('docs'),('templates'),
      ('registry'),('bom'),('calc'),('norms'),('production'),('mes'),('terminal'),('qc'),('warehouse'),
      ('economics'),('hr'),('roles'),('dicts'),('files'),('builder'),('org'),('platform'),('admin')
    ) as t(m);
  end if;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Ядро платформы: схемы, источники, связи, модули предприятия',
   'Партия A: движок схем app_schemas/app_schema_fields (типы и поля — конструктор), единый источник значений app_ref_options (dict/orders/clients/partners/equipment/operations), связи app_links, включение модулей по предприятию app_tenant_modules. Используется во всех модулях для динамических форм, справочников, табличных частей и связей.',
   'ядро платформа схемы поля ref_options связи app_links tenant_modules конструктор')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Ядро платформы: схемы, источники, связи, модули предприятия');
