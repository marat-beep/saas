-- ============================================================
-- 3DMP Service · 0010_warehouse.sql  (v1.5 — склад и BOM)
-- Материалы, движения (приход/расход), спецификации изделия. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0009. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Материалы ----------
create table if not exists public.app_materials (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text,
  name       text not null,
  unit       text,
  price      numeric default 0,
  qty        numeric not null default 0,
  min_qty    numeric not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists app_materials_tenant_idx on public.app_materials (tenant_id);

-- ---------- Движения склада ----------
create table if not exists public.app_stock_moves (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  material_id uuid not null references public.app_materials (id) on delete cascade,
  kind        text not null,               -- in | out
  qty         numeric not null,
  price       numeric default 0,
  note        text,
  source      text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_stock_moves_mat_idx on public.app_stock_moves (material_id, created_at desc);

-- ---------- Спецификации (BOM) ----------
create table if not exists public.app_bom (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  order_id    uuid references public.app_orders (id) on delete set null,
  product     text not null,
  version     text default '1',
  note        text,
  created_by  uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_bom_tenant_idx on public.app_bom (tenant_id);

create table if not exists public.app_bom_lines (
  id          uuid primary key default gen_random_uuid(),
  bom_id      uuid not null references public.app_bom (id) on delete cascade,
  seq         integer default 0,
  item_type   text not null default 'material',  -- material | operation
  material_id uuid references public.app_materials (id) on delete set null,
  name        text not null,
  qty         numeric default 0,
  unit        text,
  norm_hours  numeric default 0
);
create index if not exists app_bom_lines_bom_idx on public.app_bom_lines (bom_id);

alter table public.app_materials   enable row level security;
alter table public.app_stock_moves enable row level security;
alter table public.app_bom         enable row level security;
alter table public.app_bom_lines   enable row level security;

-- ---------- Материалы: список ----------
drop function if exists public.app_material_list(uuid);
create or replace function public.app_material_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric, low boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty, (m.qty < m.min_qty) as low
    from public.app_materials m where (urole = 'admin' or m.tenant_id = ten) and m.active order by m.name;
end $$;

-- ---------- Материал: создать/изменить ----------
create or replace function public.app_material_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_unit text, p_price numeric, p_min_qty numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_materials (tenant_id, code, name, unit, price, min_qty)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_unit),''), coalesce(p_price,0), coalesce(p_min_qty,0));
  else
    update public.app_materials set code = nullif(trim(p_code),''), name = trim(p_name), unit = nullif(trim(p_unit),''),
      price = coalesce(p_price,0), min_qty = coalesce(p_min_qty,0), updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Движение (приход/расход) ----------
create or replace function public.app_stock_move(
  p_token uuid, p_material_id uuid, p_kind text, p_qty numeric, p_price numeric, p_note text, p_source text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; urole text; ten uuid; m public.app_materials; newqty numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into m from public.app_materials where id = p_material_id and (urole = 'admin' or tenant_id = ten);
  if m.id is null then return query select false,'Материал не найден'; return; end if;
  if p_kind not in ('in','out') then return query select false,'Неверный тип движения'; return; end if;
  if coalesce(p_qty,0) <= 0 then return query select false,'Количество должно быть > 0'; return; end if;

  newqty := case when p_kind = 'in' then m.qty + p_qty else m.qty - p_qty end;
  if newqty < 0 then return query select false,'Недостаточно на складе'; return; end if;

  insert into public.app_stock_moves (tenant_id, material_id, kind, qty, price, note, source, by_login)
  values (m.tenant_id, m.id, p_kind, p_qty, coalesce(p_price,0), nullif(trim(p_note),''), nullif(trim(p_source),''), ulogin);
  update public.app_materials set qty = newqty, updated_at = now() where id = m.id;

  if newqty < m.min_qty then
    perform public.app_notif_roles_t(m.tenant_id, array['admin','manager','owner'],
      'Низкий остаток: ' || m.name, 'Остаток ' || newqty || ' ' || coalesce(m.unit,'') || ' (мин ' || m.min_qty || ')', 'apps/warehouse/index.html');
  end if;
  return query select true,'Движение проведено';
end $$;

-- ---------- История движений ----------
drop function if exists public.app_stock_moves_list(uuid, uuid, integer);
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.kind, v.qty, v.price, v.note, v.by_login, v.created_at
    from public.app_stock_moves v join public.app_materials m on m.id = v.material_id
    where v.material_id = p_material_id and (urole = 'admin' or m.tenant_id = ten)
    order by v.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

-- ---------- BOM: список ----------
drop function if exists public.app_bom_list(uuid);
create or replace function public.app_bom_list(p_token uuid)
returns table (id uuid, product text, version text, order_number text, lines_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.product, b.version, o.number,
           (select count(*) from public.app_bom_lines l where l.bom_id = b.id), b.created_at
    from public.app_bom b left join public.app_orders o on o.id = b.order_id
    where (urole = 'admin' or b.tenant_id = ten)
    order by b.created_at desc;
end $$;

drop function if exists public.app_bom_lines_list(uuid, uuid);
create or replace function public.app_bom_lines_list(p_token uuid, p_bom_id uuid)
returns table (id uuid, seq integer, item_type text, name text, qty numeric, unit text, norm_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.seq, l.item_type, l.name, l.qty, l.unit, l.norm_hours
    from public.app_bom_lines l join public.app_bom b on b.id = l.bom_id
    where l.bom_id = p_bom_id and (urole = 'admin' or b.tenant_id = ten)
    order by l.seq, l.id;
end $$;

-- ---------- BOM: сохранить (шапка + позиции) ----------
create or replace function public.app_bom_save(
  p_token uuid, p_id uuid, p_order_id uuid, p_product text, p_version text, p_lines jsonb
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; bid uuid; ln jsonb; i integer := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;

  if p_id is null then
    insert into public.app_bom (tenant_id, order_id, product, version, created_by, created_login)
    values (ten, p_order_id, trim(p_product), coalesce(nullif(trim(p_version),''),'1'), uid, ulogin)
    returning app_bom.id into bid;
  else
    update public.app_bom set order_id = p_order_id, product = trim(p_product),
      version = coalesce(nullif(trim(p_version),''),'1'), updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten)
     returning app_bom.id into bid;
    delete from public.app_bom_lines where bom_id = bid;
  end if;

  if p_lines is not null then
    for ln in select * from jsonb_array_elements(p_lines) loop
      i := i + 1;
      insert into public.app_bom_lines (bom_id, seq, item_type, material_id, name, qty, unit, norm_hours)
      values (bid, i,
              coalesce(nullif(ln->>'item_type',''),'material'),
              nullif(ln->>'material_id','')::uuid,
              coalesce(nullif(ln->>'name',''),'—'),
              coalesce((ln->>'qty')::numeric,0),
              nullif(ln->>'unit',''),
              coalesce((ln->>'norm_hours')::numeric,0));
    end loop;
  end if;
  return query select bid, 'Спецификация сохранена';
end $$;

grant execute on function public.app_material_list(uuid) to anon, authenticated;
grant execute on function public.app_material_save(uuid,uuid,text,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_stock_moves_list(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_bom_list(uuid) to anon, authenticated;
grant execute on function public.app_bom_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_bom_save(uuid,uuid,uuid,text,text,jsonb) to anon, authenticated;

-- ---------- Демо-материалы (тенант A) ----------
insert into public.app_materials (tenant_id, code, name, unit, price, qty, min_qty)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.unit, v.price, v.qty, v.min_qty
from (values
  ('М-40Х','Сталь 40Х, круг', 'кг', 120, 500, 100),
  ('М-45','Сталь 45, круг', 'кг', 95, 800, 150),
  ('М-Д16Т','Алюминий Д16Т, лист', 'кг', 480, 120, 60),
  ('М-09Г2С','Сталь 09Г2С, лист 4 мм', 'лист', 5200, 40, 10)
) as v(code,name,unit,price,qty,min_qty)
where not exists (select 1 from public.app_materials where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001');
