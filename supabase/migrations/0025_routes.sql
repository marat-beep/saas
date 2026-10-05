-- ============================================================
-- 3DMP Service · 0025_routes.sql  (v9.0 — маршруты по техпроцессу)
-- Связь: шаблон техпроцесса → маршрут изготовления → нормирование → себестоимость.
-- Нормирование: app_norms связывается с операциями (operation_id).
-- Себестоимость: работы (нормо-часы × ставка) + материал + накладные 15% (как в 0013).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0024.
-- ============================================================

-- ---------- Связь нормирования с операциями ----------
alter table public.app_norms add column if not exists operation_id uuid references public.app_operations (id) on delete set null;
create index if not exists app_norms_op_idx on public.app_norms (operation_id);

update public.app_norms n set operation_id = o.id
  from public.app_operations o
  where n.operation_id is null
    and n.tenant_id = o.tenant_id
    and lower(trim(o.name)) = lower(trim(n.operation));

-- ---------- Маршруты изготовления ----------
create sequence if not exists public.app_route_seq;

create table if not exists public.app_routes (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  name          text not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  template_id   uuid references public.app_process_templates (id) on delete set null,
  material_id   uuid references public.app_materials (id) on delete set null,
  qty           numeric not null default 1,
  mat_qty       numeric not null default 0,       -- норма расхода материала на изделие
  status        text not null default 'draft',    -- draft | active | done
  work_cost     numeric not null default 0,
  material_cost numeric not null default 0,
  overhead      numeric not null default 0,
  total_min     numeric not null default 0,
  total_cost    numeric not null default 0,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_routes_tenant_idx on public.app_routes (tenant_id, created_at desc);
create index if not exists app_routes_order_idx  on public.app_routes (order_id);
alter table public.app_routes enable row level security;

create table if not exists public.app_route_steps (
  id           uuid primary key default gen_random_uuid(),
  route_id     uuid not null references public.app_routes (id) on delete cascade,
  seq          integer default 0,
  operation_id uuid references public.app_operations (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  norm_id      uuid references public.app_norms (id) on delete set null,
  setup_min    numeric not null default 0,
  unit_min     numeric not null default 0,
  qty          numeric not null default 1,
  plan_min     numeric not null default 0,
  rate_hour    numeric not null default 0,
  cost         numeric not null default 0,
  note         text
);
create index if not exists app_route_steps_idx on public.app_route_steps (route_id, seq);
alter table public.app_route_steps enable row level security;

-- ============================================================
--  RPC
-- ============================================================

-- Расчёт норм по шагам шаблона (нормирование): план-минуты и стоимость работ.
-- Ставка: приоритет — операция, затем связанная норма, затем нормочас оборудования.
create or replace function public.app_route_calc(p_token uuid, p_id uuid, p_qty numeric)
returns table (seq integer, operation text, equipment text, norm_source text,
               setup_min numeric, unit_min numeric, qty numeric, plan_min numeric, rate_hour numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_process_templates t where t.id = p_id and (urole='admin' or t.tenant_id = ten)) then
    raise exception 'Шаблон не найден';
  end if;
  q := greatest(coalesce(p_qty,1), 0);
  return query
    select st.seq, o.name, e.name,
           case when o.id is null then 'шаблон'
                when exists (select 1 from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten)) then 'норма'
                else 'операция' end,
           coalesce(o.setup_min, 0),
           coalesce(nullif(o.unit_min,0), st.plan_min, 0),
           q,
           coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                    e.cost_hour, 0),
           round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
                 * coalesce(nullif(o.base_rate,0),
                            (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                            e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = p_id
    order by st.seq;
end $$;

-- Итоговый расчёт себестоимости по шаблону: работы + материал + накладные.
create or replace function public.app_route_cost(p_token uuid, p_id uuid, p_qty numeric, p_material_id uuid, p_mat_qty numeric)
returns table (step_count bigint, total_min numeric, work_cost numeric, material_cost numeric, overhead numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q numeric; mq numeric; price numeric; rwork numeric; rmin numeric; rcnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_process_templates t where t.id = p_id and (urole='admin' or t.tenant_id = ten)) then
    raise exception 'Шаблон не найден';
  end if;
  q := greatest(coalesce(p_qty,1), 0);

  with rs as (
    select coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q as pm,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                    e.cost_hour, 0) as rt
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = p_id
  )
  select count(*), coalesce(sum(pm),0), coalesce(sum(round(pm/60.0*rt,2)),0)
    into rcnt, rmin, rwork from rs;

  price := 0;
  if p_material_id is not null then
    select m.price into price from public.app_materials m where m.id = p_material_id and (urole='admin' or m.tenant_id = ten);
  end if;
  mq := coalesce(p_mat_qty, 0);

  step_count := rcnt;
  total_min := rmin;
  work_cost := rwork;
  material_cost := round(coalesce(price,0) * mq * q, 2);
  overhead := round((work_cost + material_cost) * 0.15, 2);
  total := round((work_cost + material_cost) * 1.15, 2);
  return next;
end $$;

-- Создать маршрут из шаблона техпроцесса (со снимком норм и расчётом).
create or replace function public.app_route_from_tpl(p_token uuid, p_id uuid, p_order_id uuid, p_qty numeric,
  p_material_id uuid, p_mat_qty numeric, p_name text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; uid uuid; ulogin text; q numeric; rid uuid; rnum text; tname text; tmat uuid;
        vcnt bigint; vmin numeric; vwork numeric; vmat numeric; vovh numeric; vtot numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.name, t.material_id into tname, tmat from public.app_process_templates t
    where t.id = p_id and (urole='admin' or t.tenant_id = ten);
  if tname is null then raise exception 'Шаблон не найден'; end if;
  q := greatest(coalesce(p_qty,1), 0);

  select c.step_count, c.total_min, c.work_cost, c.material_cost, c.overhead, c.total
    into vcnt, vmin, vwork, vmat, vovh, vtot
    from public.app_route_cost(p_token, p_id, q, coalesce(p_material_id, tmat), p_mat_qty) c;

  rnum := 'MR-' || lpad(nextval('public.app_route_seq')::text, 5, '0');
  insert into public.app_routes (tenant_id, number, name, order_id, template_id, material_id, qty, mat_qty,
      status, work_cost, material_cost, overhead, total_min, total_cost, note, created_by, created_login)
  values (ten, rnum, coalesce(nullif(trim(p_name),''), tname || ' ×' || q), p_order_id, p_id,
      coalesce(p_material_id, tmat), q, coalesce(p_mat_qty,0), 'draft', vwork, vmat, vovh, vmin, vtot,
      nullif(trim(p_note),''), uid, ulogin)
  returning app_routes.id into rid;

  insert into public.app_route_steps (route_id, seq, operation_id, equipment_id, norm_id, setup_min, unit_min, qty, plan_min, rate_hour, cost)
  select rid, st.seq, st.operation_id, st.equipment_id,
         (select n.id from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
         coalesce(o.setup_min, 0),
         coalesce(nullif(o.unit_min,0), st.plan_min, 0),
         q,
         coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
         coalesce(nullif(o.base_rate,0),
                  (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                  e.cost_hour, 0),
         round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
               * coalesce(nullif(o.base_rate,0),
                          (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and (urole='admin' or n.tenant_id = ten) order by n.id limit 1),
                          e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
   where st.template_id = p_id;

  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Маршрут ' || rnum,
    coalesce(nullif(trim(p_name),''), tname), 'apps/registry/index.html');
  return query select rid, rnum, 'Маршрут создан';
end $$;

-- Список маршрутов.
create or replace function public.app_route_list(p_token uuid)
returns table (id uuid, number text, name text, template_name text, order_number text, qty numeric, status text,
               step_count bigint, total_min numeric, work_cost numeric, material_cost numeric, overhead numeric,
               total_cost numeric, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.name, t.name, o.number, r.qty, r.status,
           (select count(*) from public.app_route_steps st where st.route_id = r.id),
           r.total_min, r.work_cost, r.material_cost, r.overhead, r.total_cost, r.created_at
    from public.app_routes r
    left join public.app_process_templates t on t.id = r.template_id
    left join public.app_orders o on o.id = r.order_id
    where (urole='admin' or r.tenant_id = ten)
    order by r.created_at desc;
end $$;

-- Карточка маршрута.
create or replace function public.app_route_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, name text, template_name text, order_id uuid, order_number text,
               material_name text, qty numeric, mat_qty numeric, status text,
               total_min numeric, work_cost numeric, material_cost numeric, overhead numeric, total_cost numeric,
               note text, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.name, t.name, r.order_id, o.number, m.name, r.qty, r.mat_qty, r.status,
           r.total_min, r.work_cost, r.material_cost, r.overhead, r.total_cost, r.note, r.created_login, r.created_at
    from public.app_routes r
    left join public.app_process_templates t on t.id = r.template_id
    left join public.app_orders o on o.id = r.order_id
    left join public.app_materials m on m.id = r.material_id
    where r.id = p_id and (urole='admin' or r.tenant_id = ten);
end $$;

-- Шаги маршрута (снимок норм).
create or replace function public.app_route_steps_list(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, equipment text, norm_source text,
               setup_min numeric, unit_min numeric, qty numeric, plan_min numeric, rate_hour numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select st.id, st.seq, o.name, e.name,
           case when st.norm_id is not null then 'норма' else 'операция' end,
           st.setup_min, st.unit_min, st.qty, st.plan_min, st.rate_hour, st.cost
    from public.app_route_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    join public.app_routes r on r.id = st.route_id
    where st.route_id = p_id and (urole='admin' or r.tenant_id = ten)
    order by st.seq;
end $$;

-- Смена статуса маршрута.
create or replace function public.app_route_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; rnum text; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := case when p_status in ('draft','active','done') then p_status else null end;
  if st is null then return query select false,'Недопустимый статус'; return; end if;
  select r.number into rnum from public.app_routes r where r.id = p_id and (urole='admin' or r.tenant_id = ten);
  if rnum is null then return query select false,'Маршрут не найден'; return; end if;
  update public.app_routes r set status = st where r.id = p_id;
  if st = 'done' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Маршрут ' || rnum || ' завершён', '', 'apps/registry/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

-- Себестоимость маршрутов заказа (связь маршрут → заказ → экономика).
create or replace function public.app_order_routes_cost(p_token uuid, p_order_id uuid)
returns table (route_count bigint, total_min numeric, work_cost numeric, material_cost numeric, total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; oten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select o.tenant_id into oten from public.app_orders o where o.id = p_order_id;
  if oten is null or not (urole='admin' or oten = ten) then raise exception 'Доступ запрещён'; end if;
  return query
    select count(*), coalesce(sum(r.total_min),0), coalesce(sum(r.work_cost),0),
           coalesce(sum(r.material_cost),0), coalesce(sum(r.total_cost),0)
    from public.app_routes r where r.order_id = p_order_id;
end $$;

grant execute on function public.app_route_calc(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_route_cost(uuid,uuid,numeric,uuid,numeric) to anon, authenticated;
grant execute on function public.app_route_from_tpl(uuid,uuid,uuid,numeric,uuid,numeric,text,text) to anon, authenticated;
grant execute on function public.app_route_list(uuid) to anon, authenticated;
grant execute on function public.app_route_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_steps_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_order_routes_cost(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Демо-данные (тенант A): маршрут из техпроцесса TP-01 «Кронштейн», 10 шт.
-- ============================================================
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        tpl uuid; mat uuid; ord uuid; rid uuid;
        q numeric := 10; mq numeric := 12.5; price numeric := 0;
        vcnt bigint; vmin numeric; vwork numeric; vmat numeric; vovh numeric; vtot numeric;
begin
  if exists (select 1 from public.app_routes where tenant_id = ten) then return; end if;
  select t.id, t.material_id into tpl, mat
    from public.app_process_templates t
    where t.tenant_id = ten and t.code = 'TP-01' limit 1;
  if tpl is null then return; end if;
  select id into ord from public.app_orders where tenant_id = ten order by created_at limit 1;
  select coalesce(price,0) into price from public.app_materials where id = mat;

  with rs as (
    select coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q as pm,
           coalesce(nullif(o.base_rate,0),
                    (select n.rate_hour from public.app_norms n where n.operation_id = o.id and n.tenant_id = ten order by n.id limit 1),
                    e.cost_hour, 0) as rt
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    where st.template_id = tpl
  )
  select count(*), coalesce(sum(pm),0), coalesce(sum(round(pm/60.0*rt,2)),0)
    into vcnt, vmin, vwork from rs;
  vmat := round(price * mq * q, 2);
  vovh := round((vwork + vmat) * 0.15, 2);
  vtot := round((vwork + vmat) * 1.15, 2);

  insert into public.app_routes (tenant_id, number, name, order_id, template_id, material_id, qty, mat_qty,
      status, work_cost, material_cost, overhead, total_min, total_cost, note, created_login)
  values (ten, 'MR-' || lpad(nextval('public.app_route_seq')::text, 5, '0'), 'Кронштейн ×' || q, ord, tpl, mat, q, mq,
      'active', vwork, vmat, vovh, vmin, vtot, 'Демо-маршрут по TP-01', 'owner')
  returning id into rid;

  insert into public.app_route_steps (route_id, seq, operation_id, equipment_id, norm_id, setup_min, unit_min, qty, plan_min, rate_hour, cost)
  select rid, st.seq, st.operation_id, st.equipment_id,
         (select n.id from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
         coalesce(o.setup_min, 0),
         coalesce(nullif(o.unit_min,0), st.plan_min, 0),
         q,
         coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q,
         coalesce(nullif(o.base_rate,0),
                  (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
                  e.cost_hour, 0),
         round((coalesce(o.setup_min,0) + coalesce(nullif(o.unit_min,0), st.plan_min,0) * q) / 60.0
               * coalesce(nullif(o.base_rate,0),
                          (select n.rate_hour from public.app_norms n where n.operation_id = st.operation_id and n.tenant_id = ten order by n.id limit 1),
                          e.cost_hour, 0), 2)
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
   where st.template_id = tpl;
end $$;
