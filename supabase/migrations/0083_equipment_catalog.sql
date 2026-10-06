-- ============================================================
-- 3DMP Service · 0083_equipment_catalog.sql  (v61 — Сессия L: A11 «Каталог оборудования»)
-- Каталог оборудования к поставке/продаже: модели, производитель, тип, оси,
-- точность, цена, описание. База знаний. Зависит от 0001..0082.
-- ============================================================

create table if not exists public.app_equipment_catalog (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  name        text not null,
  brand       text,
  category    text,                 -- cnc|lathe|edm|grinding|press|measuring|other
  axes        int,
  accuracy    text,
  price       numeric default 0,
  currency    text default 'RUB',
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_equipment_catalog_idx on public.app_equipment_catalog (tenant_id, active, category);
alter table public.app_equipment_catalog enable row level security;

create or replace function public.app_equipment_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, name text, brand text, category text, axes int, accuracy text, price numeric, currency text, description text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select e.id, e.name, e.brand, e.category, e.axes, e.accuracy, e.price, e.currency, e.description, e.active
    from public.app_equipment_catalog e
    where (urole='admin' or e.tenant_id=ten)
      and (coalesce(p_category,'')='' or e.category=p_category)
      and (qq='' or lower(e.name) like '%'||qq||'%' or lower(coalesce(e.brand,'')) like '%'||qq||'%')
    order by e.active desc, e.brand, e.name;
end $$;

create or replace function public.app_equipment_save(p_token uuid, p_id uuid, p_name text, p_brand text, p_category text,
  p_axes int, p_accuracy text, p_price numeric, p_description text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите модель/название'; return; end if;
  if p_id is null then
    insert into public.app_equipment_catalog (tenant_id, name, brand, category, axes, accuracy, price, description, active)
    values (ten, trim(p_name), nullif(trim(p_brand),''), nullif(trim(p_category),''), p_axes, nullif(trim(p_accuracy),''), coalesce(p_price,0), nullif(trim(p_description),''), coalesce(p_active,true))
    returning id into eid;
    return query select eid, 'Позиция добавлена';
  else
    update public.app_equipment_catalog set name=trim(p_name), brand=nullif(trim(p_brand),''), category=nullif(trim(p_category),''),
      axes=p_axes, accuracy=nullif(trim(p_accuracy),''), price=coalesce(p_price,0), description=nullif(trim(p_description),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into eid;
    return query select eid, 'Позиция обновлена';
  end if;
end $$;

create or replace function public.app_equipment_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_equipment_catalog where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Позиция удалена';
end $$;

create or replace function public.app_equipment_kpi(p_token uuid)
returns table (total bigint, active bigint, categories bigint, price_min numeric, price_max numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where active),
    count(distinct category) filter (where category is not null),
    coalesce(min(price) filter (where price>0),0), coalesce(max(price),0)
    from public.app_equipment_catalog where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_equipment_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_equipment_save(uuid,uuid,text,text,text,int,text,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_equipment_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_equipment_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_equipment_catalog (tenant_id, name, brand, category, axes, accuracy, price, description)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.brand, v.cat, v.axes, v.acc, v.price, v.descr
from (values
  ('Feeler FTC-350Xl','Feeler','cnc',3,'±0.005 мм', 8500000, 'Вертикальный обрабатывающий центр'),
  ('Mitsubishi FA10-VS','Mitsubishi','edm',2,'±0.003 мм', 6200000, 'Проволочно-вырезной электроэрозионный'),
  ('Okamoto PSG-64B','Okamoto','grinding',0,'±0.002 мм', 4100000, 'Плоскошлифовальный станок'),
  ('DMG CTX beta 800','DMG MORI','lathe',4,'±0.005 мм', 14500000, 'Токарно-фрезерный с противошпинделем'),
  ('Zeiss Contura','Zeiss','measuring',0,'±0.001 мм', 7800000, 'КИМ (координатно-измерительная машина)')
) as v(name,brand,cat,axes,acc,price,descr)
where not exists (select 1 from public.app_equipment_catalog where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Каталог оборудования (A11)',
   'Модуль «Каталог оборудования»: витрина станков и оборудования к поставке — модель, производитель, тип (ЧПУ/токарные/ЭЭО/шлифование/прессы/измерения), число осей, точность, цена, описание. Позиции можно включать/выключать и использовать в продажах и КП.',
   'каталог оборудования поставка станки витрина цена A11')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Каталог оборудования (A11)');
