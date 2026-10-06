-- ============================================================
-- 3DMP Service · 0026_naryad_route.sql  (v9.1 — маршрут → наряд)
-- Перенос маршрута в наряд: автогенерация операций наряда из шагов маршрута
-- (нормо-минуты → план-часы), связь наряд ↔ маршрут ↔ заявка.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0025.
-- ============================================================

-- ---------- Связь наряда с маршрутом ----------
alter table public.app_naryads   add column if not exists route_id uuid references public.app_routes (id) on delete set null;
alter table public.app_naryad_ops add column if not exists operation_id  uuid references public.app_operations (id) on delete set null;
alter table public.app_naryad_ops add column if not exists route_step_id uuid references public.app_route_steps (id) on delete set null;
create index if not exists app_naryads_route_idx on public.app_naryads (route_id);

-- ---------- Карточка наряда + маршрут ----------
drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz,
               route_id uuid, route_number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at,
    n.route_id, r.number
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    left join public.app_routes r on r.id = n.route_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

-- ---------- Создать наряд из маршрута (операции из шагов) ----------
create or replace function public.app_naryad_from_route(p_token uuid, p_route_id uuid, p_wc_id uuid, p_assignee text, p_due_date date)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uid uuid; ulogin text; rid uuid; rnum text; rname text; rorder uuid;
        target uuid; dwc uuid; nid uuid; nnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r.id, r.number, r.name, r.order_id into rid, rnum, rname, rorder
    from public.app_routes r where r.id = p_route_id and (urole='admin' or r.tenant_id = ten);
  if rid is null then raise exception 'Маршрут не найден'; end if;
  if exists (select 1 from public.app_naryads n where n.route_id = rid and n.status <> 'closed') then
    raise exception 'По маршруту уже есть активный наряд';
  end if;

  dwc := p_wc_id;
  if dwc is null then
    select e.wc_id into dwc
      from public.app_route_steps st join public.app_equipment e on e.id = st.equipment_id
      where st.route_id = rid and e.wc_id is not null order by st.seq limit 1;
  end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, route_id, tenant_id, title, wc_id, assignee, status, created_by, created_login)
  values (nnum, rorder, rid, ten, coalesce(rname, 'Маршрут') || ' · ' || rnum, dwc, nullif(trim(p_assignee),''), 'open', uid, ulogin)
  returning app_naryads.id into nid;

  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours, operation_id, route_step_id)
  select nid, st.seq, coalesce(o.name, 'Операция ' || st.seq), nullif(trim(p_assignee),''),
         round(st.plan_min / 60.0, 2), st.operation_id, st.id
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    where st.route_id = rid
    order by st.seq;

  update public.app_naryads n
     set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
         status = 'in_progress', updated_at = now()
   where n.id = nid;
  update public.app_routes r set status = 'active' where r.id = rid and r.status = 'draft';

  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Наряд ' || nnum || ' по маршруту ' || rnum, rname, 'apps/production/index.html');
  if nullif(trim(p_assignee),'') is not null then
    select u.id into target from public.app_users u
      where lower(u.login) = lower(trim(p_assignee)) and u.active and u.tenant_id = ten limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, rname, 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum, 'Наряд создан по маршруту';
end $$;

-- ---------- Наряды маршрута ----------
create or replace function public.app_route_naryads(p_token uuid, p_route_id uuid)
returns table (id uuid, number text, title text, status text, assignee text, plan_hours numeric, fact_hours numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.status, n.assignee, n.plan_hours, n.fact_hours, n.created_at
    from public.app_naryads n join public.app_routes r on r.id = n.route_id
    where n.route_id = p_route_id and (urole='admin' or r.tenant_id = ten)
    order by n.created_at desc;
end $$;

grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_from_route(uuid,uuid,uuid,text,date) to anon, authenticated;
grant execute on function public.app_route_naryads(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо (тенант A): наряд по демо-маршруту MR-00001
-- ============================================================
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        rid uuid; rorder uuid; rname text; rnum text; nid uuid; nnum text; dwc uuid;
begin
  select r.id, r.order_id, r.name, r.number into rid, rorder, rname, rnum
    from public.app_routes r where r.tenant_id = ten and r.number = 'MR-00001' limit 1;
  if rid is null then return; end if;
  if exists (select 1 from public.app_naryads where route_id = rid) then return; end if;

  select e.wc_id into dwc
    from public.app_route_steps st join public.app_equipment e on e.id = st.equipment_id
    where st.route_id = rid and e.wc_id is not null order by st.seq limit 1;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, route_id, tenant_id, title, wc_id, status, created_login)
  values (nnum, rorder, rid, ten, rname || ' · ' || rnum, dwc, 'in_progress', 'owner')
  returning id into nid;

  insert into public.app_naryad_ops (naryad_id, seq, operation, plan_hours, operation_id, route_step_id)
  select nid, st.seq, coalesce(o.name, 'Операция ' || st.seq), round(st.plan_min / 60.0, 2), st.operation_id, st.id
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    where st.route_id = rid order by st.seq;

  update public.app_naryads n
     set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = nid;
end $$;
