-- ============================================================
-- 3DMP Service · 0266_procurement.sql  (R4 · PROP-24 — закупки: план, скоринг, 3-way)
-- Периодический скоринг поставщиков + сверка «заказано ↔ получено» (2 из 3 сторон;
-- счётная сторона — в финансах). Идемпотентно.
-- ============================================================

create table if not exists public.app_supplier_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  supplier_id uuid,
  period date not null default current_date,
  delivery numeric default 0,   -- 0..5 срок поставки
  quality numeric default 0,    -- 0..5 качество
  price numeric default 0,      -- 0..5 цена
  score numeric,                -- среднее
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_supplier_scores_idx on public.app_supplier_scores (tenant_id, supplier_id, period);

create or replace function public.app_supplier_score_list(p_token uuid, p_supplier uuid)
returns table (id uuid, supplier_id uuid, period date, delivery numeric, quality numeric, price numeric, score numeric, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select sc.id, sc.supplier_id, sc.period, sc.delivery, sc.quality, sc.price, sc.score, sc.note
    from public.app_supplier_scores sc
    where (urole = 'admin' or sc.tenant_id = ten) and (p_supplier is null or sc.supplier_id = p_supplier)
    order by sc.period desc;
end $$;
grant execute on function public.app_supplier_score_list(uuid,uuid) to anon, authenticated;

create or replace function public.app_supplier_score_save(p_token uuid, p_id uuid, p_supplier uuid, p_period date, p_delivery numeric, p_quality numeric, p_price numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid; sc numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_supplier is null then return query select false, 'Выберите поставщика'; return; end if;
  sc := round((least(greatest(coalesce(p_delivery,0),0),5) + least(greatest(coalesce(p_quality,0),0),5) + least(greatest(coalesce(p_price,0),0),5)) / 3.0, 2);
  if p_id is null then
    insert into public.app_supplier_scores (tenant_id, supplier_id, period, delivery, quality, price, score, note)
    values (ten, p_supplier, coalesce(p_period, current_date), coalesce(p_delivery,0), coalesce(p_quality,0), coalesce(p_price,0), sc, p_note) returning id into rid;
  else
    update public.app_supplier_scores set supplier_id = p_supplier, period = coalesce(p_period, period), delivery = coalesce(p_delivery,0),
      quality = coalesce(p_quality,0), price = coalesce(p_price,0), score = sc, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Скоринг сохранён (итог ' || sc || ')';
end $$;
grant execute on function public.app_supplier_score_save(uuid,uuid,uuid,date,numeric,numeric,numeric,text) to anon, authenticated;

create or replace function public.app_supplier_score_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_supplier_scores where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_supplier_score_delete(uuid,uuid) to anon, authenticated;

-- 3-way (2 из 3): заказано (заявки закупки) ↔ получено (приход на склад) по материалу.
create or replace function public.app_three_way_match(p_token uuid)
returns table (material_id uuid, material text, ordered numeric, received numeric, diff numeric, ok boolean)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with pr as (select * from public.app_purchase_request_list(p_token, null)),
    agg as (select material_id, sum(qty) as qty, min(title) as title from pr group by material_id)
    select a.material_id, coalesce(m.name, a.title), round(a.qty, 2),
           coalesce((select sum(sm.qty) from public.app_stock_moves sm where sm.material_id = a.material_id and sm.kind = 'in'), 0),
           round(a.qty - coalesce((select sum(sm.qty) from public.app_stock_moves sm where sm.material_id = a.material_id and sm.kind = 'in'), 0), 2),
           (a.qty <= coalesce((select sum(sm.qty) from public.app_stock_moves sm where sm.material_id = a.material_id and sm.kind = 'in'), 0))
      from agg a left join public.app_materials m on m.id = a.material_id
      order by a.title;
end $$;
grant execute on function public.app_three_way_match(uuid) to anon, authenticated;
