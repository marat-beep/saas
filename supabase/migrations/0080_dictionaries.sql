-- ============================================================
-- 3DMP Service · 0080_dictionaries.sql  (v58 — Сессия J: настраиваемые справочники)
-- Универсальные справочники (ключ → значения-варианты) для самостоятельного
-- наполнения/редактирования: категории поставщиков, виды потерь, типы наладок,
-- виды упаковки, типы этикеток и любые другие. База знаний. Зависит от 0001..0079.
-- ============================================================

create table if not exists public.app_dictionaries (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text not null,
  name        text not null,
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists app_dictionaries_code_idx on public.app_dictionaries (tenant_id, lower(code));
create index if not exists app_dictionaries_idx on public.app_dictionaries (tenant_id, active);
alter table public.app_dictionaries enable row level security;

create table if not exists public.app_dictionary_items (
  id       uuid primary key default gen_random_uuid(),
  dict_id  uuid references public.app_dictionaries (id) on delete cascade,
  value    text not null,        -- код/значение (латиницей или как угодно)
  label    text not null,        -- отображаемое название
  sort     int default 100,
  active   boolean not null default true
);
create index if not exists app_dictionary_items_idx on public.app_dictionary_items (dict_id, sort);
alter table public.app_dictionary_items enable row level security;

-- ---------- Справочники ----------
create or replace function public.app_dicts_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, description text, active boolean, items bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.code, d.name, d.description, d.active,
      (select count(*) from public.app_dictionary_items i where i.dict_id=d.id)
    from public.app_dictionaries d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.name) like '%'||qq||'%' or lower(d.code) like '%'||qq||'%')
    order by d.name;
end $$;

create or replace function public.app_dict_save(p_token uuid, p_id uuid, p_code text, p_name text, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_code),'')='' or coalesce(trim(p_name),'')='' then raise exception 'Укажите код и название'; return; end if;
  if p_id is null then
    insert into public.app_dictionaries (tenant_id, code, name, description, active)
    values (ten, trim(p_code), trim(p_name), nullif(trim(p_description),''), coalesce(p_active,true)) returning id into did;
    return query select did, 'Справочник создан';
  else
    update public.app_dictionaries set code=trim(p_code), name=trim(p_name), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Справочник обновлён';
  end if;
end $$;

create or replace function public.app_dict_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_dictionaries where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Справочник удалён';
end $$;

-- ---------- Значения ----------
create or replace function public.app_dict_items_list(p_token uuid, p_dict_id uuid)
returns table (id uuid, value text, label text, sort int, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_dictionaries d where d.id=p_dict_id and (urole='admin' or d.tenant_id=ten)) then raise exception 'Справочник не найден'; end if;
  return query select i.id, i.value, i.label, i.sort, i.active from public.app_dictionary_items i
    where i.dict_id=p_dict_id order by i.sort, i.label;
end $$;

create or replace function public.app_dict_items_by_code(p_token uuid, p_code text)
returns table (value text, label text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select i.value, i.label
    from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id
    where (urole='admin' or d.tenant_id=ten) and lower(d.code)=lower(trim(p_code)) and d.active and i.active
    order by i.sort, i.label;
end $$;

create or replace function public.app_dict_item_save(p_token uuid, p_id uuid, p_dict_id uuid, p_value text, p_label text, p_sort int, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; iid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if not exists (select 1 from public.app_dictionaries d where d.id=p_dict_id and (urole='admin' or d.tenant_id=ten)) then raise exception 'Справочник не найден'; return; end if;
  if coalesce(trim(p_value),'')='' or coalesce(trim(p_label),'')='' then raise exception 'Укажите значение и название'; return; end if;
  if p_id is null then
    insert into public.app_dictionary_items (dict_id, value, label, sort, active)
    values (p_dict_id, trim(p_value), trim(p_label), coalesce(p_sort,100), coalesce(p_active,true)) returning id into iid;
    return query select iid, 'Значение добавлено';
  else
    update public.app_dictionary_items set value=trim(p_value), label=trim(p_label), sort=coalesce(p_sort,100), active=coalesce(p_active,active)
     where id=p_id and dict_id=p_dict_id returning id into iid;
    return query select iid, 'Значение обновлено';
  end if;
end $$;

create or replace function public.app_dict_item_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_dictionary_items i using public.app_dictionaries d
    where i.id=p_id and d.id=i.dict_id and (urole='admin' or d.tenant_id=ten);
  return query select true,'Значение удалено';
end $$;

create or replace function public.app_dicts_kpi(p_token uuid)
returns table (dicts bigint, items bigint, active_items bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_dictionaries where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id where (urole='admin' or d.tenant_id=ten)),
    (select count(*) from public.app_dictionary_items i join public.app_dictionaries d on d.id=i.dict_id where i.active and (urole='admin' or d.tenant_id=ten));
end $$;

grant execute on function public.app_dicts_list(uuid,text) to anon, authenticated;
grant execute on function public.app_dict_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_dict_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dict_items_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dict_items_by_code(uuid,text) to anon, authenticated;
grant execute on function public.app_dict_item_save(uuid,uuid,uuid,text,text,int,boolean) to anon, authenticated;
grant execute on function public.app_dict_item_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dicts_kpi(uuid) to anon, authenticated;

-- ---------- Сиды (тенант A) ----------
do $$
declare did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values
      ('aaaaaaaa-0000-0000-0000-000000000001','supplier_category','Категории поставщиков',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'металл','Металл',10),(did,'инструмент','Инструмент',20),(did,'комплектующие','Комплектующие',30),(did,'услуги','Услуги',40),(did,'прочее','Прочее',50);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','loss_type','Виды потерь') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'overproduction','Перепроизводство',10),(did,'waiting','Ожидание',20),(did,'transport','Транспортировка',30),
      (did,'overprocessing','Излишняя обработка',40),(did,'inventory','Запасы',50),(did,'motion','Движения',60),(did,'defects','Дефекты',70),(did,'other','Прочее',80);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','setup_type','Типы наладок') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'setup','Наладка',10),(did,'changeover','Переналадка',20),(did,'trial','Пробный пуск',30),(did,'adjust','Подналадка',40);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','package_kind','Виды упаковки') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'box','Коробка',10),(did,'pallet','Паллета',20),(did,'crate','Ящик',30),(did,'bag','Мешок',40),(did,'other','Прочее',50);
    insert into public.app_dictionaries (tenant_id, code, name) values ('aaaaaaaa-0000-0000-0000-000000000001','label_type','Типы этикеток') returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'cargo','Грузовая этикетка',10),(did,'position','Бирка позиции',20),(did,'tag','Манипуляционный знак',30);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Настраиваемые справочники',
   'Модуль «Справочники (настраиваемые)»: единый механизм списков/вариантов для самостоятельного наполнения — код справочника и значения (код → название, порядок, активность). Предзаполнены: категории поставщиков, виды потерь, типы наладок, виды упаковки, типы этикеток. Любой модуль может получать варианты через app_dict_items_by_code(code) и строить выпадающие списки из своих данных, а не из жёстко зашитых значений.',
   'настраиваемые справочники списки выпадающие словарь варианты app_dict_items_by_code')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Настраиваемые справочники');
