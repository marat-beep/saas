-- ============================================================
-- 3DMP Service · 0267_shipping.sql  (R4 · PROP-23 — отгрузочные задания: сборка/упаковка/отгрузка)
-- Задания на отгрузку по заказу со статусами. Идемпотентно.
-- ============================================================

create table if not exists public.app_shipments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  number text,
  order_ref text,
  customer text,
  items_count int default 0,
  status text not null default 'new',  -- new|picking|packed|shipped
  assignee text,
  note text,
  created_at timestamptz not null default now(),
  shipped_at timestamptz
);
create index if not exists app_shipments_idx on public.app_shipments (tenant_id, status);

create or replace function public.app_shipment_list(p_token uuid)
returns table (id uuid, number text, order_ref text, customer text, items_count int, status text, assignee text, note text, created_at timestamptz, shipped_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select sh.id, sh.number, sh.order_ref, sh.customer, sh.items_count, sh.status, sh.assignee, sh.note, sh.created_at, sh.shipped_at
    from public.app_shipments sh where (urole = 'admin' or sh.tenant_id = ten) order by sh.created_at desc;
end $$;
grant execute on function public.app_shipment_list(uuid) to anon, authenticated;

create or replace function public.app_shipment_save(p_token uuid, p_id uuid, p_order_ref text, p_customer text, p_items int, p_assignee text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid; nnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    select 'ОТГ-' || lpad(((count(*) + 1)::text), 4, '0') into nnum from public.app_shipments where tenant_id = ten;
    insert into public.app_shipments (tenant_id, number, order_ref, customer, items_count, status, assignee, note)
    values (ten, nnum, p_order_ref, p_customer, coalesce(p_items, 0), 'new', p_assignee, p_note) returning id into rid;
  else
    update public.app_shipments set order_ref = p_order_ref, customer = p_customer, items_count = coalesce(p_items, items_count), assignee = p_assignee, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_shipment_save(uuid,uuid,text,text,int,text,text) to anon, authenticated;

create or replace function public.app_shipment_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new', 'picking', 'packed', 'shipped') then return query select false, 'Недопустимый статус'; return; end if;
  update public.app_shipments set status = p_status, shipped_at = case when p_status = 'shipped' then now() else shipped_at end
    where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Статус: ' || p_status;
end $$;
grant execute on function public.app_shipment_set_status(uuid,uuid,text) to anon, authenticated;

create or replace function public.app_shipment_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_shipments where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_shipment_delete(uuid,uuid) to anon, authenticated;
