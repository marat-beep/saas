-- ============================================================
-- 3DMP Service · 0036_warehouse_ref.sql  (v18.0 — переработка «Склад»)
-- Движения со связью заявка/наряд, стоимость запаса, список нехватки,
-- связка «нехватка → закупка». База знаний. Tenant-изоляция.
-- Зависит от 0001..0035.
-- ============================================================

alter table public.app_stock_moves add column if not exists order_id  uuid references public.app_orders (id) on delete set null;
alter table public.app_stock_moves add column if not exists naryad_id uuid references public.app_naryads (id) on delete set null;
create index if not exists app_stock_moves_order_idx on public.app_stock_moves (order_id);

-- ---------- Материалы: список (со стоимостью запаса) ----------
drop function if exists public.app_material_list(uuid);
create or replace function public.app_material_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric,
               stock_value numeric, low boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty,
    round(coalesce(m.qty,0) * coalesce(m.price,0), 2), (m.qty < m.min_qty)
    from public.app_materials m where (urole = 'admin' or m.tenant_id = ten) and m.active order by m.name;
end $$;

-- ---------- Нехватка (ниже минимума) ----------
create or replace function public.app_stock_low(p_token uuid)
returns table (id uuid, code text, name text, unit text, price numeric, qty numeric, min_qty numeric, deficit numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.unit, m.price, m.qty, m.min_qty, round(m.min_qty - m.qty, 2)
    from public.app_materials m
    where (urole = 'admin' or m.tenant_id = ten) and m.active and m.qty < m.min_qty
    order by (m.qty - m.min_qty);
end $$;

-- ---------- Движение (приход/расход) со связью ----------
drop function if exists public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text);
create or replace function public.app_stock_move(
  p_token uuid, p_material_id uuid, p_kind text, p_qty numeric, p_price numeric, p_note text, p_source text,
  p_order_id uuid default null, p_naryad_id uuid default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
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

  insert into public.app_stock_moves (tenant_id, material_id, kind, qty, price, note, source, order_id, naryad_id, by_login)
  values (m.tenant_id, m.id, p_kind, p_qty, coalesce(p_price,0), nullif(trim(p_note),''), nullif(trim(p_source),''),
          p_order_id, p_naryad_id, ulogin);
  update public.app_materials set qty = newqty, updated_at = now() where id = m.id;

  if newqty < m.min_qty then
    perform public.app_notif_roles_t(m.tenant_id, array['admin','manager','owner','supply','director'],
      'Низкий остаток: ' || m.name, 'Остаток ' || newqty || ' ' || coalesce(m.unit,'') || ' (мин ' || m.min_qty || ')', 'apps/warehouse/index.html');
  end if;
  return query select true,'Движение проведено';
end $$;

-- ---------- История движений (со связями) ----------
drop function if exists public.app_stock_moves_list(uuid,uuid,integer);
create or replace function public.app_stock_moves_list(p_token uuid, p_material_id uuid, p_limit integer default 50)
returns table (id uuid, kind text, qty numeric, price numeric, note text, source text,
               order_id uuid, order_number text, naryad_id uuid, naryad_number text,
               by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.id, v.kind, v.qty, v.price, v.note, v.source,
    v.order_id, o.number, v.naryad_id, n.number, v.by_login, v.created_at
    from public.app_stock_moves v
    join public.app_materials m on m.id = v.material_id
    left join public.app_orders o on o.id = v.order_id
    left join public.app_naryads n on n.id = v.naryad_id
    where v.material_id = p_material_id and (urole = 'admin' or m.tenant_id = ten)
    order by v.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

grant execute on function public.app_material_list(uuid) to anon, authenticated;
grant execute on function public.app_stock_low(uuid) to anon, authenticated;
grant execute on function public.app_stock_move(uuid,uuid,text,numeric,numeric,text,text,uuid,uuid) to anon, authenticated;
grant execute on function public.app_stock_moves_list(uuid,uuid,integer) to anon, authenticated;

-- ---------- База знаний: склад ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','Как вести приход и расход материалов?',
   'В «Складе» откройте материал и проведите движение: приход или расход, количество, при необходимости заявку/наряд и комментарий. Остаток пересчитывается автоматически; при уходе ниже минимума приходит уведомление снабжению и руководству. Стоимость запаса = остаток × цена.',
   'склад приход расход остаток минимум стоимость'),
  ('Склад','Что делать при нехватке материала?',
   'Позиции ниже минимума показаны в блоке «Нехватка». По такой позиции нажмите «Создать закупку» — откроется предзаполненная закупка в снабжении (материал и рекомендуемое количество). Так замыкается цепочка: склад → закупка → приход.',
   'нехватка закупка снабжение материал минимум')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Склад');
