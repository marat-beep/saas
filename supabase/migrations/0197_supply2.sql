-- ============================================================
-- 3DMP Service · 0197_supply2.sql  (X14 — Склад/снабжение 2.0)
-- Заявки на закупку (app_purchase_requests), автозаявка по минимуму (app_reorder_scan),
-- закупка из BOM (app_procure_from_bom), штрихкод-перемещение (app_wh_scan_move).
-- Идемпотентно. Зависит от 0001..0196.
-- ============================================================

create table if not exists public.app_purchase_requests (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  source        text not null default 'manual',  -- reorder|bom|service|manual
  material_id   uuid references public.app_materials (id) on delete set null,
  title         text not null,
  qty           numeric not null default 0,
  unit          text,
  status        text not null default 'draft',   -- draft|submitted|approved|ordered|closed|cancelled
  tender_id     uuid references public.tenders (id) on delete set null,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_purchase_requests_idx on public.app_purchase_requests (tenant_id, status);
alter table public.app_purchase_requests enable row level security;

-- ================= RPC: заявки на закупку =================
create or replace function public.app_purchase_request_list(p_token uuid, p_status text default null)
returns table (id uuid, source text, title text, qty numeric, unit text, status text, material_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select r.id, r.source, r.title, r.qty, r.unit, r.status, r.material_id, r.created_at
      from public.app_purchase_requests r
     where (adm or r.tenant_id = ten) and (st is null or r.status = st)
     order by r.created_at desc;
end $$;

create or replace function public.app_purchase_request_save(p_token uuid, p_id uuid, p_material_id uuid, p_title text, p_qty numeric, p_unit text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'procurement') then return query select false,'Нет прав на снабжение', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите наименование', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_purchase_requests (tenant_id, source, material_id, title, qty, unit, note, created_login)
    values (ten, 'manual', p_material_id, left(trim(p_title),200), coalesce(p_qty,0), nullif(trim(p_unit),''), nullif(trim(p_note),''), uname)
    returning app_purchase_requests.id into newid;
    return query select true,'Заявка на закупку создана', newid;
  else
    update public.app_purchase_requests r set material_id = p_material_id, title = left(trim(p_title),200),
           qty = coalesce(p_qty,r.qty), unit = nullif(trim(p_unit),''), note = nullif(trim(p_note),'')
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten)
     returning r.id into newid;
    if newid is null then return query select false,'Заявка не найдена', null::uuid; return; end if;
    return query select true,'Заявка сохранена', newid;
  end if;
end $$;

create or replace function public.app_purchase_request_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'procurement') then return query select false,'Нет прав на снабжение'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('draft','submitted','approved','ordered','closed','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_purchase_requests r set status = st where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Заявка не найдена'; return; end if;
  return query select true,'Статус: ' || st;
end $$;

-- ================= RPC: автозаявки =================
create or replace function public.app_reorder_scan(p_token uuid)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'procurement') then return query select false,'Нет прав на снабжение', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  for rec in
    select m.id, m.code, m.name, m.unit, round(m.min_qty - m.qty, 2) as deficit
      from public.app_materials m
     where (adm or m.tenant_id = ten) and m.active and m.qty < m.min_qty
       and not exists (select 1 from public.app_purchase_requests r
                        where r.material_id = m.id and r.source = 'reorder' and r.status in ('draft','submitted','approved','ordered'))
  loop
    insert into public.app_purchase_requests (tenant_id, source, material_id, title, qty, unit, note, created_login)
    values (ten, 'reorder', rec.id, rec.name, rec.deficit, rec.unit, 'Автозаявка по минимуму (' || coalesce(rec.code,'') || ')', uname);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Автозаявок по минимуму: ' || cnt, cnt;
end $$;

create or replace function public.app_procure_from_bom(p_token uuid, p_bom_id uuid)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'procurement') then return query select false,'Нет прав на снабжение', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_bom b where b.id = p_bom_id and (adm or b.tenant_id = ten)) then
    return query select false,'Спецификация не найдена', 0; return;
  end if;
  select s.ulogin into uname from public.app_session_user(p_token) s;
  for rec in
    select l.material_id, l.name, l.qty, l.unit
      from public.app_bom_lines l
     where l.bom_id = p_bom_id and l.item_type = 'material' and coalesce(l.qty,0) > 0
  loop
    insert into public.app_purchase_requests (tenant_id, source, material_id, title, qty, unit, note, created_login)
    values (ten, 'bom', rec.material_id, rec.name, rec.qty, rec.unit, 'Потребность по спецификации', uname);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Заявок из спецификации: ' || cnt, cnt;
end $$;

-- ================= RPC: штрихкод-перемещение =================
create or replace function public.app_wh_scan_move(p_token uuid, p_code text, p_to_location_id uuid, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; mat record; src record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'warehouse') then return query select false,'Нет прав на склад'; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_to_location_id is null then return query select false,'Укажите целевую ячейку (скан)'; return; end if;
  select m.id, m.name into mat from public.app_materials m
   where (public.app_is_platform_admin(p_token) or m.tenant_id = ten)
     and (lower(m.code) = lower(trim(p_code)) or lower(m.name) = lower(trim(p_code))) limit 1;
  if mat.id is null then return query select false,'Материал по коду не найден: ' || coalesce(p_code,''); return; end if;
  select w.id, w.qty into src from public.app_wh_stock w
   where w.material_id = mat.id and (public.app_is_platform_admin(p_token) or w.tenant_id = ten) and w.qty > 0
   order by w.qty desc limit 1;
  if src.id is null then return query select false,'Нет остатка на складе для ' || mat.name; return; end if;
  return query select r.ok, r.message from public.app_wh_move(p_token, src.id, p_to_location_id, coalesce(p_qty, src.qty)) r;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','Склад/снабжение 2.0: автозаявки, BOM, штрихкод-склад (X14)',
   'Склад/снабжение 2.0: заявки на закупку (app_purchase_requests + save/list/set_status, статусы draft→submitted→approved→ordered→closed), автозаявка по минимуму (app_reorder_scan — материалы ниже минимума → черновик закупки, без дублей), закупка из спецификации (app_procure_from_bom — потребность BOM → заявки), штрихкод-перемещение (app_wh_scan_move — скан кода материала → перемещение в целевую ячейку через app_wh_move). Связи: производство (BOM наряда), сервис (запчасти), логистика, финансы.',
   'склад снабжение закупка автозаявка минимум BOM штрихкод перемещение инвентаризация')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Склад/снабжение 2.0: автозаявки, BOM, штрихкод-склад (X14)'
);

-- ================= Права =================
grant execute on function public.app_purchase_request_list(uuid,text) to anon, authenticated;
grant execute on function public.app_purchase_request_save(uuid,uuid,uuid,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_purchase_request_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_reorder_scan(uuid) to anon, authenticated;
grant execute on function public.app_procure_from_bom(uuid,uuid) to anon, authenticated;
grant execute on function public.app_wh_scan_move(uuid,text,uuid,numeric) to anon, authenticated;
