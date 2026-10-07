-- ============================================================
-- 3DMP Service · 0118_warehouse_wms.sql  (W3 — WMS: адресность и партии)
-- Адреса хранения, партии материалов, остатки по адресам/партиям,
-- размещение/перемещение/списание. Идемпотентно. Зависит от 0001..0117.
-- ============================================================

create table if not exists public.app_wh_addresses (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text not null,
  zone       text,
  rack       text,
  cell       text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, code)
);
create index if not exists app_wh_addresses_tenant_idx on public.app_wh_addresses (tenant_id, code);

alter table public.app_materials
  add column if not exists location_id uuid references public.app_wh_addresses (id) on delete set null;

create table if not exists public.app_material_lots (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  material_id   uuid not null references public.app_materials (id) on delete cascade,
  lot           text not null,
  supplier      text,
  qty           numeric not null default 0,
  price         numeric default 0,
  produced_at   date,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  unique (material_id, lot)
);
create index if not exists app_material_lots_idx on public.app_material_lots (tenant_id, material_id);

create table if not exists public.app_wh_stock (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  location_id uuid not null references public.app_wh_addresses (id) on delete cascade,
  material_id uuid not null references public.app_materials (id) on delete cascade,
  lot_id      uuid references public.app_material_lots (id) on delete set null,
  qty         numeric not null default 0,
  updated_at  timestamptz not null default now()
);
create index if not exists app_wh_stock_idx on public.app_wh_stock (tenant_id, location_id, material_id);

alter table public.app_wh_addresses  enable row level security;
alter table public.app_material_lots enable row level security;
alter table public.app_wh_stock      enable row level security;

-- ============================================================
--  Адреса хранения
-- ============================================================
drop function if exists public.app_wh_address_list(uuid);
create or replace function public.app_wh_address_list(p_token uuid)
returns table (id uuid, code text, zone text, rack text, cell text, active boolean, positions bigint, qty numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.code, a.zone, a.rack, a.cell, a.active,
           (select count(*) from public.app_wh_stock w where w.location_id = a.id and w.qty > 0),
           coalesce((select sum(w.qty) from public.app_wh_stock w where w.location_id = a.id), 0)
      from public.app_wh_addresses a
     where (urole = 'admin' or a.tenant_id = ten)
     order by a.code;
end $$;

drop function if exists public.app_wh_address_save(uuid,uuid,text,text,text,text,boolean);
create or replace function public.app_wh_address_save(
  p_token uuid, p_id uuid, p_code text, p_zone text, p_rack text, p_cell text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; aid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'warehouse', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_code), '') = '' then return query select false, 'Укажите код адреса', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_wh_addresses (tenant_id, code, zone, rack, cell, active)
    values (ten, trim(p_code), nullif(trim(p_zone),''), nullif(trim(p_rack),''), nullif(trim(p_cell),''), coalesce(p_active, true))
    returning app_wh_addresses.id into aid;
  else
    update public.app_wh_addresses a
       set code = trim(p_code), zone = nullif(trim(p_zone),''), rack = nullif(trim(p_rack),''),
           cell = nullif(trim(p_cell),''), active = coalesce(p_active, a.active)
     where a.id = p_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten);
    if not found then return query select false, 'Адрес не найден', null::uuid; return; end if;
    aid := p_id;
  end if;
  return query select true, 'Адрес сохранён', aid;
exception when unique_violation then
  return query select false, 'Адрес с таким кодом уже существует', null::uuid;
end $$;

drop function if exists public.app_wh_address_delete(uuid,uuid);
create or replace function public.app_wh_address_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; n bigint;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'warehouse', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select count(*) into n from public.app_wh_stock w
   where w.location_id = p_id and w.qty > 0
     and (public.app_is_platform_admin(p_token) or w.tenant_id = ten);
  if n > 0 then return query select false, 'На адресе есть остатки — сначала переместите'; return; end if;
  delete from public.app_wh_addresses a
   where a.id = p_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten);
  if not found then return query select false, 'Адрес не найден'; return; end if;
  return query select true, 'Адрес удалён';
end $$;

-- ============================================================
--  Партии и остатки по адресам
-- ============================================================
drop function if exists public.app_material_lot_list(uuid,uuid);
create or replace function public.app_material_lot_list(p_token uuid, p_material_id uuid default null)
returns table (id uuid, material_id uuid, material text, unit text, lot text, supplier text, qty numeric,
               stock_qty numeric, price numeric, produced_at date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.material_id, m.name, m.unit, l.lot, l.supplier, l.qty,
           coalesce((select sum(w.qty) from public.app_wh_stock w where w.lot_id = l.id), 0),
           l.price, l.produced_at, l.created_at
      from public.app_material_lots l
      join public.app_materials m on m.id = l.material_id
     where (urole = 'admin' or l.tenant_id = ten)
       and (p_material_id is null or l.material_id = p_material_id)
     order by l.created_at desc;
end $$;

drop function if exists public.app_wh_stock_list(uuid,uuid,uuid);
create or replace function public.app_wh_stock_list(p_token uuid, p_material_id uuid default null, p_location_id uuid default null)
returns table (id uuid, location_id uuid, address text, material_id uuid, material text, unit text,
               lot_id uuid, lot text, qty numeric, price numeric, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.location_id,
           a.code || case when a.zone is not null or a.rack is not null or a.cell is not null
                          then ' (' || coalesce(a.zone,'') || case when a.rack is not null then '/' || a.rack else '' end || case when a.cell is not null then '/' || a.cell else '' end || ')' else '' end,
           w.material_id, m.name, m.unit, w.lot_id, l.lot, w.qty,
           coalesce(l.price, m.price, 0), w.qty * coalesce(l.price, m.price, 0)
      from public.app_wh_stock w
      join public.app_wh_addresses a on a.id = w.location_id
      join public.app_materials m on m.id = w.material_id
      left join public.app_material_lots l on l.id = w.lot_id
     where w.qty > 0 and (urole = 'admin' or w.tenant_id = ten)
       and (p_material_id is null or w.material_id = p_material_id)
       and (p_location_id is null or w.location_id = p_location_id)
     order by a.code, m.name;
end $$;

-- Размещение: добавить материал (создав/найдя партию) на адрес.
drop function if exists public.app_wh_place(uuid,uuid,uuid,text,numeric,numeric,text);
create or replace function public.app_wh_place(
  p_token uuid, p_material_id uuid, p_location_id uuid, p_lot text, p_qty numeric, p_price numeric default 0, p_supplier text default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; lid uuid; sid uuid; lname text; mname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'warehouse', 'edit') then return query select false, 'Нет прав'; return; end if;
  if p_qty is null or p_qty <= 0 then return query select false, 'Укажите количество > 0'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_materials m where m.id = p_material_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten)) then
    return query select false, 'Материал не найден'; return; end if;
  if not exists (select 1 from public.app_wh_addresses a where a.id = p_location_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten)) then
    return query select false, 'Адрес не найден'; return; end if;

  lname := coalesce(nullif(trim(p_lot), ''), '—');
  select l.id into lid from public.app_material_lots l where l.material_id = p_material_id and l.lot = lname;
  if lid is null then
    insert into public.app_material_lots (tenant_id, material_id, lot, supplier, qty, price, created_login)
    values (ten, p_material_id, lname, nullif(trim(p_supplier),''), p_qty, coalesce(p_price,0), ulogin)
    returning app_material_lots.id into lid;
  else
    update public.app_material_lots l set qty = l.qty + p_qty,
           price = coalesce(nullif(p_price,0), l.price),
           supplier = coalesce(nullif(trim(p_supplier),''), l.supplier)
     where l.id = lid;
  end if;

  select w.id into sid from public.app_wh_stock w
   where w.location_id = p_location_id and w.material_id = p_material_id and w.lot_id is not distinct from lid;
  if sid is null then
    insert into public.app_wh_stock (tenant_id, location_id, material_id, lot_id, qty)
    values (ten, p_location_id, p_material_id, lid, p_qty);
  else
    update public.app_wh_stock w set qty = w.qty + p_qty, updated_at = now() where w.id = sid;
  end if;

  select m.name into mname from public.app_materials m where m.id = p_material_id;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','supply','chief','master'],
          'Размещение на склад', coalesce(mname,'') || ' · ' || p_qty::text || ' (' || lname || ')', 'apps/warehouse/index.html');
  return query select true, 'Размещено на адрес';
end $$;

-- Перемещение между адресами.
drop function if exists public.app_wh_move(uuid,uuid,uuid,numeric);
create or replace function public.app_wh_move(p_token uuid, p_stock_id uuid, p_to_location_id uuid, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; src record; sid uuid; q numeric;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'warehouse', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into src from public.app_wh_stock w
   where w.id = p_stock_id and (public.app_is_platform_admin(p_token) or w.tenant_id = ten);
  if src.id is null then return query select false, 'Остаток не найден'; return; end if;
  q := coalesce(p_qty, src.qty);
  if q <= 0 or q > src.qty then return query select false, 'Некорректное количество'; return; end if;
  if not exists (select 1 from public.app_wh_addresses a where a.id = p_to_location_id and a.tenant_id = src.tenant_id) then
    return query select false, 'Адрес назначения не найден'; return; end if;
  if p_to_location_id = src.location_id then return query select false, 'Адрес назначения совпадает с текущим'; return; end if;

  if q = src.qty then
    delete from public.app_wh_stock where id = src.id;
  else
    update public.app_wh_stock set qty = qty - q, updated_at = now() where id = src.id;
  end if;

  select w.id into sid from public.app_wh_stock w
   where w.location_id = p_to_location_id and w.material_id = src.material_id and w.lot_id is not distinct from src.lot_id;
  if sid is null then
    insert into public.app_wh_stock (tenant_id, location_id, material_id, lot_id, qty)
    values (src.tenant_id, p_to_location_id, src.material_id, src.lot_id, q);
  else
    update public.app_wh_stock set qty = qty + q, updated_at = now() where id = sid;
  end if;
  return query select true, 'Перемещено';
end $$;

-- Списание с адреса.
drop function if exists public.app_wh_stock_out(uuid,uuid,numeric);
create or replace function public.app_wh_stock_out(p_token uuid, p_stock_id uuid, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; src record; q numeric;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'warehouse', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into src from public.app_wh_stock w
   where w.id = p_stock_id and (public.app_is_platform_admin(p_token) or w.tenant_id = ten);
  if src.id is null then return query select false, 'Остаток не найден'; return; end if;
  q := coalesce(p_qty, src.qty);
  if q <= 0 or q > src.qty then return query select false, 'Некорректное количество'; return; end if;
  if q = src.qty then delete from public.app_wh_stock where id = src.id;
  else update public.app_wh_stock set qty = qty - q, updated_at = now() where id = src.id; end if;
  return query select true, 'Списано с адреса';
end $$;

drop function if exists public.app_wh_kpi(uuid);
create or replace function public.app_wh_kpi(p_token uuid)
returns table (addresses bigint, lots bigint, positions bigint, total_qty numeric, total_value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select
      (select count(*) from public.app_wh_addresses a where (urole = 'admin' or a.tenant_id = ten)),
      (select count(*) from public.app_material_lots l where (urole = 'admin' or l.tenant_id = ten)),
      (select count(*) from public.app_wh_stock w where w.qty > 0 and (urole = 'admin' or w.tenant_id = ten)),
      (select coalesce(sum(w.qty), 0) from public.app_wh_stock w where w.qty > 0 and (urole = 'admin' or w.tenant_id = ten)),
      (select coalesce(sum(w.qty * coalesce(l.price, m.price, 0)), 0)
         from public.app_wh_stock w
         join public.app_materials m on m.id = w.material_id
         left join public.app_material_lots l on l.id = w.lot_id
        where w.qty > 0 and (urole = 'admin' or w.tenant_id = ten));
end $$;

grant execute on function public.app_wh_address_list(uuid)                             to anon, authenticated;
grant execute on function public.app_wh_address_save(uuid,uuid,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_wh_address_delete(uuid,uuid)                      to anon, authenticated;
grant execute on function public.app_material_lot_list(uuid,uuid)                      to anon, authenticated;
grant execute on function public.app_wh_stock_list(uuid,uuid,uuid)                     to anon, authenticated;
grant execute on function public.app_wh_place(uuid,uuid,uuid,text,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_wh_move(uuid,uuid,uuid,numeric)                   to anon, authenticated;
grant execute on function public.app_wh_stock_out(uuid,uuid,numeric)                   to anon, authenticated;
grant execute on function public.app_wh_kpi(uuid)                                      to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_wh_addresses (tenant_id, code, zone, rack, cell)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.zone, v.rack, v.cell
from (values ('A-01-01','Зона A','Стеллаж 1','Ячейка 1'),
             ('A-01-02','Зона A','Стеллаж 1','Ячейка 2'),
             ('B-02-01','Зона B','Стеллаж 2','Ячейка 1')) as v(code,zone,rack,cell)
where not exists (
  select 1 from public.app_wh_addresses a
   where a.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and a.code = v.code
);

-- Разместить демо-партию первого доступного материала тенанта A на адрес A-01-01.
insert into public.app_material_lots (tenant_id, material_id, lot, supplier, qty, price, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', m.id, 'L-2601', 'Металлобаза', 50, m.price, 'supply'
from public.app_materials m
where m.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (
    select 1 from public.app_material_lots l where l.material_id = m.id and l.lot = 'L-2601'
  )
limit 1;

insert into public.app_wh_stock (tenant_id, location_id, material_id, lot_id, qty)
select 'aaaaaaaa-0000-0000-0000-000000000001', a.id, l.material_id, l.id, l.qty
from public.app_material_lots l
join public.app_wh_addresses a on a.tenant_id = l.tenant_id and a.code = 'A-01-01'
where l.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and l.lot = 'L-2601'
  and not exists (
    select 1 from public.app_wh_stock w where w.location_id = a.id and w.material_id = l.material_id and w.lot_id = l.id
  );

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','WMS — адресное хранение и партии',
   'Адресное хранение: адреса (app_wh_addresses: код, зона, стеллаж, ячейка), партии материалов (app_material_lots: номер, поставщик, цена, количество), остатки по адресам и партиям (app_wh_stock). Размещение (app_wh_place) создаёт/находит партию и кладёт материал на адрес; перемещение (app_wh_move) переносит количество между адресами; списание (app_wh_stock_out) уменьшает остаток. Остатки и стоимость — app_wh_stock_list, KPI — app_wh_kpi.',
   'WMS склад адрес ячейка стеллаж партия lot размещение перемещение остатки')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'WMS — адресное хранение и партии'
);
