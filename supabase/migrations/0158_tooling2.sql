-- ============================================================
-- 3DMP Service · 0158_tooling2.sql  (W13 — Инструментальное хозяйство 2.0)
-- Поэкземплярный учёт инструмента (T1), адресное хранение/инвентаризация (T2),
-- цифровой каталог (T3), оснащение по техкартам (T4). Поверка СИ (T5) — reuse 0016/0092.
-- Идемпотентно. Зависит от 0001..0157.
-- ============================================================

-- ---------- T3: цифровой каталог инструмента ----------
create table if not exists public.app_tool_catalog (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  vendor      text,
  vendor_code text,
  name        text not null,
  tool_type   text,
  material    text,
  coating     text,
  diameter    numeric,
  geometry    jsonb not null default '{}'::jsonb,
  analogs     jsonb not null default '[]'::jsonb,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_tool_catalog_idx on public.app_tool_catalog (tenant_id, tool_type);
alter table public.app_tool_catalog enable row level security;

alter table public.app_tool_life add column if not exists catalog_id uuid references public.app_tool_catalog (id);

-- ---------- T1: экземпляры инструмента + история ----------
create table if not exists public.app_tool_items (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  tool_life_id  uuid references public.app_tool_life (id) on delete set null,
  serial        text,
  location_id   uuid references public.app_wh_addresses (id) on delete set null,
  status        text not null default 'on_stock',  -- on_stock|issued|on_machine|worn|scrapped
  resource_min  numeric,
  used_min      numeric not null default 0,
  machine       text,
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  holder_login  text,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_tool_items_idx on public.app_tool_items (tenant_id, status);
alter table public.app_tool_items enable row level security;

create table if not exists public.app_tool_events (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  item_id       uuid not null references public.app_tool_items (id) on delete cascade,
  kind          text not null,   -- create|issue|return|install|remove|resharpen|scrap|move|inventory
  machine       text,
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  holder_login  text,
  location_id   uuid references public.app_wh_addresses (id) on delete set null,
  used_min      numeric,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_tool_events_idx on public.app_tool_events (item_id, created_at desc);
alter table public.app_tool_events enable row level security;

-- ---------- T2: инвентаризация ----------
create table if not exists public.app_tool_inventory (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  status        text not null default 'open',   -- open|closed
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  closed_at     timestamptz
);
alter table public.app_tool_inventory enable row level security;

create table if not exists public.app_tool_inventory_lines (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references public.app_tool_inventory (id) on delete cascade,
  item_id           uuid references public.app_tool_items (id) on delete set null,
  expected_status   text,
  found_status      text,
  found_location_id uuid references public.app_wh_addresses (id) on delete set null,
  result            text,     -- ok|moved|status_changed|not_found
  checked_login     text,
  checked_at        timestamptz not null default now()
);
create index if not exists app_tool_inv_lines_idx on public.app_tool_inventory_lines (session_id);
alter table public.app_tool_inventory_lines enable row level security;

-- ---------- T4: оснащение по техкартам ----------
create table if not exists public.app_route_tools (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  route_step_id uuid not null references public.app_route_steps (id) on delete cascade,
  tool_life_id  uuid references public.app_tool_life (id) on delete set null,
  qty           numeric not null default 1,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists app_route_tools_idx on public.app_route_tools (route_step_id);
alter table public.app_route_tools enable row level security;

-- ================= RPC: экземпляры (T1) =================
create or replace function public.app_tool_item_list(p_token uuid, p_status text default null, p_q text default null)
returns table (id uuid, tool text, code text, serial text, status text, location text, machine text,
               holder_login text, used_min numeric, resource_min numeric, pct numeric, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select i.id, coalesce(tl.name,'') || coalesce(' ' || tl.code,''), tl.code, i.serial, i.status,
           a.code, i.machine, i.holder_login, i.used_min, coalesce(i.resource_min, tl.resource_min),
           case when coalesce(i.resource_min, tl.resource_min, 0) > 0
                then round(coalesce(i.used_min,0) / coalesce(i.resource_min, tl.resource_min) * 100, 1) end,
           i.updated_at
      from public.app_tool_items i
      left join public.app_tool_life tl on tl.id = i.tool_life_id
      left join public.app_wh_addresses a on a.id = i.location_id
     where (adm or i.tenant_id = ten)
       and (st is null or i.status = st)
       and (p_q is null or p_q = '' or i.serial ilike '%'||p_q||'%' or coalesce(tl.name,'') ilike '%'||p_q||'%' or coalesce(tl.code,'') ilike '%'||p_q||'%')
     order by i.updated_at desc;
end $$;

create or replace function public.app_tool_item_save(p_token uuid, p_id uuid, p_tool_life_id uuid, p_serial text, p_location_id uuid, p_resource_min numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_id is null then
    insert into public.app_tool_items (tenant_id, tool_life_id, serial, location_id, resource_min, note, status)
    values (ten, p_tool_life_id, nullif(trim(p_serial),''), p_location_id, p_resource_min, nullif(trim(p_note),''), 'on_stock')
    returning app_tool_items.id into newid;
    insert into public.app_tool_events (tenant_id, item_id, kind, location_id, note, created_login)
    values (ten, newid, 'create', p_location_id, 'Создан экземпляр', uname);
    return query select true,'Экземпляр создан', newid;
  else
    update public.app_tool_items i set tool_life_id = coalesce(p_tool_life_id, i.tool_life_id), serial = nullif(trim(p_serial),''),
           location_id = coalesce(p_location_id, i.location_id), resource_min = coalesce(p_resource_min, i.resource_min),
           note = nullif(trim(p_note),''), updated_at = now()
     where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten)
     returning i.id into newid;
    if newid is null then return query select false,'Экземпляр не найден', null::uuid; return; end if;
    return query select true,'Экземпляр сохранён', newid;
  end if;
end $$;

create or replace function public.app_tool_event(p_token uuid, p_item_id uuid, p_kind text, p_machine text, p_naryad_id uuid, p_location_id uuid, p_used_min numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; k text; i record; nst text; nholder text; nmachine text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into i from public.app_tool_items where id = p_item_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if i.id is null then return query select false,'Экземпляр не найден'; return; end if;
  k := lower(trim(coalesce(p_kind,'')));
  if k not in ('issue','return','install','remove','resharpen','scrap','move') then return query select false,'Недопустимая операция'; return; end if;

  if k = 'issue' then nst := 'issued'; nholder := uname; nmachine := i.machine;
  elsif k = 'install' then nst := 'on_machine'; nmachine := p_machine; nholder := i.holder_login;
  elsif k = 'remove' then nst := 'issued'; nmachine := null; nholder := i.holder_login;
  elsif k = 'return' then nst := 'on_stock'; nholder := null; nmachine := null;
  elsif k = 'scrap' then nst := 'scrapped'; nholder := null; nmachine := null;
  elsif k = 'resharpen' then nst := 'on_stock'; 
  else nst := i.status; nholder := i.holder_login; nmachine := i.machine; end if;

  update public.app_tool_items set status = nst,
         holder_login = nholder, machine = nmachine, naryad_id = coalesce(p_naryad_id, naryad_id),
         used_min = coalesce(used_min,0) + coalesce(p_used_min,0),
         location_id = case when k in ('return','move') then coalesce(p_location_id, location_id) else location_id end,
         updated_at = now()
   where id = p_item_id;

  insert into public.app_tool_events (tenant_id, item_id, kind, machine, naryad_id, holder_login, location_id, used_min, note, created_login)
  values (ten, p_item_id, k, nmachine, p_naryad_id, nholder, p_location_id, p_used_min, nullif(trim(p_note),''), uname);

  return query select true, 'Операция выполнена: ' || k;
end $$;

create or replace function public.app_tool_events_list(p_token uuid, p_item_id uuid)
returns table (kind text, machine text, holder_login text, location text, used_min numeric, note text, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select e.kind, e.machine, e.holder_login, a.code, e.used_min, e.note, e.created_login, e.created_at
      from public.app_tool_events e left join public.app_wh_addresses a on a.id = e.location_id
     where e.item_id = p_item_id and (adm or e.tenant_id = ten)
     order by e.created_at desc;
end $$;

create or replace function public.app_tool_items_kpi(p_token uuid)
returns table (total bigint, on_stock bigint, issued bigint, on_machine bigint, worn bigint, scrapped bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select
    count(*),
    count(*) filter (where i.status='on_stock'),
    count(*) filter (where i.status='issued'),
    count(*) filter (where i.status='on_machine'),
    count(*) filter (where i.status='worn'),
    count(*) filter (where i.status='scrapped')
    from public.app_tool_items i where adm or i.tenant_id = ten;
end $$;

-- ================= RPC: каталог (T3) =================
create or replace function public.app_tool_catalog_list(p_token uuid, p_q text default null, p_type text default null)
returns table (id uuid, vendor text, vendor_code text, name text, tool_type text, material text, coating text, diameter numeric, analogs jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.vendor, c.vendor_code, c.name, c.tool_type, c.material, c.coating, c.diameter, c.analogs
      from public.app_tool_catalog c
     where (adm or c.tenant_id = ten or c.tenant_id is null)
       and (p_q is null or p_q = '' or c.name ilike '%'||p_q||'%' or coalesce(c.vendor,'') ilike '%'||p_q||'%' or coalesce(c.vendor_code,'') ilike '%'||p_q||'%')
       and (p_type is null or p_type = '' or c.tool_type = p_type)
     order by c.vendor, c.name;
end $$;

create or replace function public.app_tool_catalog_save(p_token uuid, p_id uuid, p_vendor text, p_vendor_code text, p_name text, p_tool_type text, p_material text, p_coating text, p_diameter numeric, p_geometry jsonb, p_analogs jsonb, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_tool_catalog (tenant_id, vendor, vendor_code, name, tool_type, material, coating, diameter, geometry, analogs, note)
    values (ten, nullif(trim(p_vendor),''), nullif(trim(p_vendor_code),''), left(trim(p_name),160), nullif(trim(p_tool_type),''),
            nullif(trim(p_material),''), nullif(trim(p_coating),''), p_diameter, coalesce(p_geometry,'{}'::jsonb), coalesce(p_analogs,'[]'::jsonb), nullif(trim(p_note),''))
    returning app_tool_catalog.id into newid;
    return query select true,'Позиция каталога создана', newid;
  else
    update public.app_tool_catalog c set vendor = nullif(trim(p_vendor),''), vendor_code = nullif(trim(p_vendor_code),''),
           name = left(trim(p_name),160), tool_type = nullif(trim(p_tool_type),''), material = nullif(trim(p_material),''),
           coating = nullif(trim(p_coating),''), diameter = p_diameter, geometry = coalesce(p_geometry, c.geometry),
           analogs = coalesce(p_analogs, c.analogs), note = nullif(trim(p_note),'')
     where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten or c.tenant_id is null)
     returning c.id into newid;
    if newid is null then return query select false,'Позиция не найдена', null::uuid; return; end if;
    return query select true,'Позиция сохранена', newid;
  end if;
end $$;

-- ================= RPC: инвентаризация (T2) =================
create or replace function public.app_tool_inventory_list(p_token uuid)
returns table (id uuid, status text, note text, created_login text, created_at timestamptz, lines bigint, ok bigint, not_found bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.status, s.note, s.created_login, s.created_at,
           (select count(*) from public.app_tool_inventory_lines l where l.session_id = s.id),
           (select count(*) from public.app_tool_inventory_lines l where l.session_id = s.id and l.result = 'ok'),
           (select count(*) from public.app_tool_inventory_lines l where l.session_id = s.id and l.result = 'not_found')
      from public.app_tool_inventory s where adm or s.tenant_id = ten order by s.created_at desc;
end $$;

create or replace function public.app_tool_inventory_start(p_token uuid, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  insert into public.app_tool_inventory (tenant_id, note, created_login) values (ten, nullif(trim(p_note),''), uname)
  returning app_tool_inventory.id into newid;
  return query select true,'Инвентаризация начата', newid;
end $$;

create or replace function public.app_tool_inventory_scan(p_token uuid, p_session_id uuid, p_code text, p_location_id uuid, p_status text)
returns table (ok boolean, message text, item_id uuid, result text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; it record; res text; loc uuid; nst text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if not exists (select 1 from public.app_tool_inventory where id = p_session_id and status = 'open') then
    return query select false,'Сессия не найдена или закрыта', null::uuid, null::text; return;
  end if;
  select i.* into it from public.app_tool_items i
   where i.tenant_id = ten and (i.serial = trim(p_code) or i.id::text = trim(p_code)) limit 1;
  if it.id is null then
    insert into public.app_tool_inventory_lines (session_id, expected_status, found_status, found_location_id, result, checked_login)
    values (p_session_id, null, null, p_location_id, 'not_found', uname);
    return query select true,'Не найдено: ' || coalesce(p_code,''), null::uuid, 'not_found';
    return;
  end if;
  nst := coalesce(nullif(trim(p_status),''), it.status);
  loc := coalesce(p_location_id, it.location_id);
  res := case when nst = it.status and loc is not distinct from it.location_id then 'ok'
              when loc is distinct from it.location_id then 'moved' else 'status_changed' end;
  insert into public.app_tool_inventory_lines (session_id, item_id, expected_status, found_status, found_location_id, result, checked_login)
  values (p_session_id, it.id, it.status, nst, loc, res, uname);
  if res <> 'ok' then
    update public.app_tool_items set status = nst, location_id = loc, updated_at = now() where id = it.id;
  end if;
  return query select true, case res when 'ok' then 'Совпадает' when 'moved' then 'Перемещено' else 'Смена статуса' end, it.id, res;
end $$;

create or replace function public.app_tool_inventory_close(p_token uuid, p_session_id uuid)
returns table (ok boolean, message text, checked bigint, not_found bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer; chk bigint; nf bigint;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,0; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_tool_inventory set status='closed', closed_at=now() where id = p_session_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Сессия не найдена',0,0; return; end if;
  select count(*), count(*) filter (where result='not_found') into chk, nf from public.app_tool_inventory_lines where session_id = p_session_id;
  return query select true, 'Инвентаризация закрыта: проверено ' || chk || ', не найдено ' || nf, chk, nf;
end $$;

create or replace function public.app_tool_inventory_report(p_token uuid, p_session_id uuid)
returns table (item text, serial text, expected_status text, found_status text, result text, checked_login text, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(tl.name,'') || coalesce(' ' || tl.code,''), i.serial, l.expected_status, l.found_status, l.result, l.checked_login, l.checked_at
      from public.app_tool_inventory_lines l
      left join public.app_tool_items i on i.id = l.item_id
      left join public.app_tool_life tl on tl.id = i.tool_life_id
     where l.session_id = p_session_id
       and (adm or exists (select 1 from public.app_tool_inventory s where s.id = l.session_id and s.tenant_id = ten))
     order by l.checked_at desc;
end $$;

-- ================= RPC: оснащение по техкартам (T4) =================
create or replace function public.app_route_tool_list(p_token uuid, p_route_step_id uuid)
returns table (id uuid, tool text, tool_life_id uuid, qty numeric, note text, on_stock bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select rt.id, coalesce(tl.name,'') || coalesce(' ' || tl.code,''), rt.tool_life_id, rt.qty, rt.note,
           (select count(*) from public.app_tool_items i where i.tool_life_id = rt.tool_life_id and i.status = 'on_stock')
      from public.app_route_tools rt left join public.app_tool_life tl on tl.id = rt.tool_life_id
     where rt.route_step_id = p_route_step_id and (adm or rt.tenant_id = ten)
     order by tl.name;
end $$;

create or replace function public.app_route_tool_save(p_token uuid, p_id uuid, p_route_step_id uuid, p_tool_life_id uuid, p_qty numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_id is null then
    insert into public.app_route_tools (tenant_id, route_step_id, tool_life_id, qty, note)
    values (ten, p_route_step_id, p_tool_life_id, coalesce(p_qty,1), nullif(trim(p_note),''))
    returning app_route_tools.id into newid;
    return query select true,'Позиция оснащения добавлена', newid;
  else
    update public.app_route_tools rt set tool_life_id = p_tool_life_id, qty = coalesce(p_qty, rt.qty), note = nullif(trim(p_note),'')
     where rt.id = p_id and (public.app_is_platform_admin(p_token) or rt.tenant_id = ten)
     returning rt.id into newid;
    if newid is null then return query select false,'Позиция не найдена', null::uuid; return; end if;
    return query select true,'Позиция сохранена', newid;
  end if;
end $$;

create or replace function public.app_route_tool_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_route_tools rt where rt.id = p_id and (public.app_is_platform_admin(p_token) or rt.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Позиция не найдена'; return; end if;
  return query select true,'Позиция удалена';
end $$;

-- ---------- Демо ----------
insert into public.app_tool_catalog (tenant_id, vendor, vendor_code, name, tool_type, material, coating, diameter, analogs)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Sandvik', 'R390-016A16-11M', 'Фреза концевая R390 16мм', 'фреза', 'твердый сплав', 'PVD', 16, '[{"vendor":"Iscar","code":"HM90"}]'::jsonb
where not exists (select 1 from public.app_tool_catalog where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and vendor_code='R390-016A16-11M');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Инструментальное хозяйство 2.0: экземпляры, каталог, инвентаризация, оснащение',
   'W13: поэкземплярный учёт инструмента (app_tool_items: серийный номер, адрес хранения, статус on_stock/issued/on_machine/worn/scrapped, наработка/ресурс; история app_tool_events; операции app_tool_event issue/return/install/remove/resharpen/scrap/move); цифровой каталог (app_tool_catalog: производитель, геометрия, аналоги — параметрический поиск); инвентаризация (app_tool_inventory + scan/close, результаты ok/moved/status_changed/not_found); оснащение по техкартам (app_route_tools — подбор инструмента на операцию, ведомость с наличием). Поверка СИ — app_tool_save/verify/list (reuse). Модуль «Инструмент».',
   'инструмент экземпляр серийный выдача возврат каталог аналоги инвентаризация оснащение техкарта СИ')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Инструментальное хозяйство 2.0: экземпляры, каталог, инвентаризация, оснащение'
);

-- ---------- Права ----------
grant execute on function public.app_tool_item_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_tool_item_save(uuid,uuid,uuid,text,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_tool_event(uuid,uuid,text,text,uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_tool_events_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tool_items_kpi(uuid) to anon, authenticated;
grant execute on function public.app_tool_catalog_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_tool_catalog_save(uuid,uuid,text,text,text,text,text,text,numeric,jsonb,jsonb,text) to anon, authenticated;
grant execute on function public.app_tool_inventory_list(uuid) to anon, authenticated;
grant execute on function public.app_tool_inventory_start(uuid,text) to anon, authenticated;
grant execute on function public.app_tool_inventory_scan(uuid,uuid,text,uuid,text) to anon, authenticated;
grant execute on function public.app_tool_inventory_close(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tool_inventory_report(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_tool_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_tool_save(uuid,uuid,uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_route_tool_delete(uuid,uuid) to anon, authenticated;
