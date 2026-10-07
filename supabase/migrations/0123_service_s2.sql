-- ============================================================
-- 3DMP Service · 0123_service_s2.sql  (S2 — Сервис ЧПУ: гарантии/контракты, запчасти, выезды)
-- Гарантии (app_warranties), сервисные контракты (app_service_contracts),
-- резерв запчастей под заявку (app_service_parts), мобильные выезды инженера.
-- Идемпотентно. Зависит от 0001..0122.
-- ============================================================

create table if not exists public.app_warranties (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  equipment_id  uuid references public.app_equipment (id) on delete cascade,
  customer_id   uuid references public.app_customers (id) on delete set null,
  number        text,
  provider      text not null default 'manufacturer',  -- dealer|manufacturer|internal
  start_date    date not null default current_date,
  end_date      date,
  coverage      text,
  terms         text,
  active        boolean not null default true,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_warranties_idx on public.app_warranties (tenant_id, equipment_id, end_date);

create table if not exists public.app_service_contracts (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid references public.tenants (id),
  customer_id      uuid references public.app_customers (id) on delete cascade,
  number           text,
  kind             text not null default 'service',  -- sla|service|extended_warranty
  start_date       date not null default current_date,
  end_date         date,
  response_sla_min integer,
  resolve_sla_min  integer,
  cost             numeric,
  terms            text,
  active           boolean not null default true,
  created_login    text,
  created_at       timestamptz not null default now()
);
create index if not exists app_service_contracts_idx on public.app_service_contracts (tenant_id, customer_id, end_date);

create table if not exists public.app_service_parts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  request_id    uuid not null references public.app_service_requests (id) on delete cascade,
  part_id       uuid references public.app_spare_parts (id) on delete set null,
  part_name     text,
  qty           numeric not null default 0,
  price         numeric default 0,
  cost          numeric default 0,
  status        text not null default 'reserved',  -- reserved|used|returned
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_service_parts_idx on public.app_service_parts (request_id);

alter table public.app_service_requests add column if not exists warranty_id uuid references public.app_warranties (id) on delete set null;
alter table public.app_service_requests add column if not exists contract_id uuid references public.app_service_contracts (id) on delete set null;
alter table public.app_service_requests add column if not exists parts_cost numeric not null default 0;

alter table public.app_warranties         enable row level security;
alter table public.app_service_contracts  enable row level security;
alter table public.app_service_parts      enable row level security;

-- ============================================================
--  Гарантии
-- ============================================================
drop function if exists public.app_warranty_list(uuid);
create or replace function public.app_warranty_list(p_token uuid)
returns table (id uuid, equipment_id uuid, equipment text, customer text, number text, provider text,
               start_date date, end_date date, active boolean, days_left integer, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.equipment_id, e.name, c.name, w.number, w.provider, w.start_date, w.end_date, w.active,
           case when w.end_date is not null then (w.end_date - current_date) else null end,
           case when not w.active then 'off'
                when w.start_date > current_date then 'planned'
                when w.end_date is not null and w.end_date < current_date then 'expired'
                else 'active' end
      from public.app_warranties w
      left join public.app_equipment e on e.id = w.equipment_id
      left join public.app_customers c on c.id = w.customer_id
     where (urole='admin' or w.tenant_id = ten)
     order by w.end_date desc nulls last;
end $$;

drop function if exists public.app_warranty_save(uuid,uuid,uuid,uuid,text,text,date,date,text,text,boolean);
create or replace function public.app_warranty_save(
  p_token uuid, p_id uuid, p_equipment_id uuid, p_customer_id uuid, p_number text, p_provider text,
  p_start_date date, p_end_date date, p_coverage text, p_terms text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; wid uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if p_equipment_id is null then return query select false, 'Выберите оборудование', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_warranties (tenant_id, equipment_id, customer_id, number, provider, start_date, end_date, coverage, terms, active, created_by, created_login)
    values (ten, p_equipment_id, p_customer_id, nullif(trim(p_number),''), coalesce(nullif(trim(p_provider),''),'manufacturer'),
            coalesce(p_start_date, current_date), p_end_date, nullif(trim(p_coverage),''), nullif(trim(p_terms),''), coalesce(p_active,true), uid, ulogin)
    returning app_warranties.id into wid;
  else
    update public.app_warranties w set equipment_id=p_equipment_id, customer_id=p_customer_id, number=nullif(trim(p_number),''),
      provider=coalesce(nullif(trim(p_provider),''),w.provider), start_date=coalesce(p_start_date,w.start_date), end_date=p_end_date,
      coverage=nullif(trim(p_coverage),''), terms=nullif(trim(p_terms),''), active=coalesce(p_active,w.active)
     where w.id=p_id and (public.app_is_platform_admin(p_token) or w.tenant_id=ten);
    if not found then return query select false, 'Гарантия не найдена', null::uuid; return; end if;
    wid := p_id;
  end if;
  return query select true, 'Гарантия сохранена', wid;
end $$;

drop function if exists public.app_warranty_delete(uuid,uuid);
create or replace function public.app_warranty_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_warranties w where w.id=p_id and (public.app_is_platform_admin(p_token) or w.tenant_id=ten);
  if not found then return query select false, 'Гарантия не найдена'; return; end if;
  return query select true, 'Гарантия удалена';
end $$;

-- ============================================================
--  Сервисные контракты
-- ============================================================
drop function if exists public.app_service_contract_list(uuid);
create or replace function public.app_service_contract_list(p_token uuid)
returns table (id uuid, customer_id uuid, customer text, number text, kind text, start_date date, end_date date,
               response_sla_min integer, resolve_sla_min integer, cost numeric, active boolean, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select k.id, k.customer_id, c.name, k.number, k.kind, k.start_date, k.end_date, k.response_sla_min, k.resolve_sla_min, k.cost, k.active,
           case when not k.active then 'off'
                when k.start_date > current_date then 'planned'
                when k.end_date is not null and k.end_date < current_date then 'expired'
                else 'active' end
      from public.app_service_contracts k
      left join public.app_customers c on c.id = k.customer_id
     where (urole='admin' or k.tenant_id = ten)
     order by k.end_date desc nulls last;
end $$;

drop function if exists public.app_service_contract_save(uuid,uuid,uuid,text,text,date,date,integer,integer,numeric,text,boolean);
create or replace function public.app_service_contract_save(
  p_token uuid, p_id uuid, p_customer_id uuid, p_number text, p_kind text, p_start_date date, p_end_date date,
  p_response_sla_min integer, p_resolve_sla_min integer, p_cost numeric, p_terms text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; kid uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if p_customer_id is null then return query select false, 'Выберите заказчика', null::uuid; return; end if;
  if p_kind is not null and p_kind not in ('sla','service','extended_warranty') then return query select false, 'Неизвестный тип контракта', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_service_contracts (tenant_id, customer_id, number, kind, start_date, end_date, response_sla_min, resolve_sla_min, cost, terms, active, created_login)
    values (ten, p_customer_id, nullif(trim(p_number),''), coalesce(nullif(trim(p_kind),''),'service'), coalesce(p_start_date,current_date), p_end_date,
            p_response_sla_min, p_resolve_sla_min, p_cost, nullif(trim(p_terms),''), coalesce(p_active,true), ulogin)
    returning app_service_contracts.id into kid;
  else
    update public.app_service_contracts k set customer_id=p_customer_id, number=nullif(trim(p_number),''),
      kind=coalesce(nullif(trim(p_kind),''),k.kind), start_date=coalesce(p_start_date,k.start_date), end_date=p_end_date,
      response_sla_min=p_response_sla_min, resolve_sla_min=p_resolve_sla_min, cost=p_cost, terms=nullif(trim(p_terms),''), active=coalesce(p_active,k.active)
     where k.id=p_id and (public.app_is_platform_admin(p_token) or k.tenant_id=ten);
    if not found then return query select false, 'Контракт не найден', null::uuid; return; end if;
    kid := p_id;
  end if;
  return query select true, 'Контракт сохранён', kid;
end $$;

drop function if exists public.app_service_contract_delete(uuid,uuid);
create or replace function public.app_service_contract_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_service_contracts k where k.id=p_id and (public.app_is_platform_admin(p_token) or k.tenant_id=ten);
  if not found then return query select false, 'Контракт не найден'; return; end if;
  return query select true, 'Контракт удалён';
end $$;

-- ============================================================
--  Карточка заявки v3 (со связями гарантии/контракта и стоимостью запчастей)
-- ============================================================
drop function if exists public.app_service_get(uuid,uuid);
create or replace function public.app_service_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, customer_id uuid, customer text, equipment_id uuid, equipment text, title text,
               kind text, status text, priority text, channel text, source text, is_warranty boolean,
               contact text, location text, fault_code text, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, closed_at timestamptz,
               labor_hours numeric, downtime_hours numeric, cost numeric, parts_cost numeric, works text, note text,
               root_cause text, solution text, satisfaction integer, warranty_id uuid, warranty_number text,
               contract_id uuid, contract_number text, sla_state text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.number, s.customer_id, c.name, s.equipment_id, e.name, s.title, s.kind, s.status, s.priority,
           s.channel, s.source, s.is_warranty, s.contact, s.location, s.fault_code, s.assigned_login, s.engineer,
           s.scheduled_date, s.reported_at, s.response_due, s.resolve_due, s.first_response_at, s.resolved_at, s.closed_at,
           s.labor_hours, s.downtime_hours, s.cost, s.parts_cost, s.works, s.note, s.root_cause, s.solution, s.satisfaction,
           s.warranty_id, w.number, s.contract_id, k.number,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    left join public.app_warranties w on w.id = s.warranty_id
    left join public.app_service_contracts k on k.id = s.contract_id
    where s.id = p_id and (urole='admin' or s.tenant_id = ten);
end $$;
grant execute on function public.app_service_get(uuid,uuid) to anon, authenticated;

-- ============================================================
--  Запчасти под заявку (резерв со склада запчастей)
-- ============================================================
drop function if exists public.app_service_parts_list(uuid,uuid);
create or replace function public.app_service_parts_list(p_token uuid, p_id uuid)
returns table (id uuid, part_id uuid, part text, unit text, qty numeric, price numeric, cost numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select sp.id, sp.part_id, coalesce(sp.part_name, p.name), p.unit, sp.qty, sp.price, sp.cost, sp.status, sp.created_at
      from public.app_service_parts sp
      left join public.app_spare_parts p on p.id = sp.part_id
     where sp.request_id = p_id and (urole='admin' or sp.tenant_id = ten)
     order by sp.created_at;
end $$;

drop function if exists public.app_service_part_add(uuid,uuid,uuid,numeric);
create or replace function public.app_service_part_add(p_token uuid, p_id uuid, p_part_id uuid, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; req record; sp record; c numeric;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  if p_qty is null or p_qty <= 0 then return query select false, 'Укажите количество > 0'; return; end if;
  ten := public.app_my_tenant(p_token);
  select r.id, r.tenant_id into req from public.app_service_requests r
   where r.id = p_id and (urole='admin' or r.tenant_id = ten);
  if req.id is null then return query select false, 'Заявка не найдена'; return; end if;
  select p.id, p.name, p.qty, p.price into sp from public.app_spare_parts p
   where p.id = p_part_id and p.active and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  if sp.id is null then return query select false, 'Запчасть не найдена'; return; end if;
  if p_qty > sp.qty then return query select false, 'Недостаточно запчасти на складе'; return; end if;
  c := p_qty * coalesce(sp.price, 0);
  update public.app_spare_parts set qty = qty - p_qty, updated_at = now() where id = sp.id;
  insert into public.app_service_parts (tenant_id, request_id, part_id, part_name, qty, price, cost, status, created_login)
  values (req.tenant_id, p_id, sp.id, sp.name, p_qty, coalesce(sp.price,0), c, 'reserved', ulogin);
  update public.app_service_requests set parts_cost = coalesce(parts_cost,0) + c, updated_at = now() where id = p_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (req.tenant_id, p_id, 'part', 'Зарезервирована запчасть: ' || sp.name || ' × ' || p_qty, ulogin);
  return query select true, 'Запчасть зарезервирована';
end $$;

drop function if exists public.app_service_part_remove(uuid,uuid);
create or replace function public.app_service_part_remove(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; rec record;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into rec from public.app_service_parts sp
   where sp.id = p_id and (public.app_is_platform_admin(p_token) or sp.tenant_id = ten);
  if rec.id is null then return query select false, 'Запись не найдена'; return; end if;
  if rec.part_id is not null then
    update public.app_spare_parts set qty = qty + rec.qty, updated_at = now() where id = rec.part_id;
  end if;
  delete from public.app_service_parts where id = p_id;
  update public.app_service_requests set parts_cost = greatest(coalesce(parts_cost,0) - coalesce(rec.cost,0), 0), updated_at = now() where id = rec.request_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (rec.tenant_id, rec.request_id, 'part', 'Возврат запчасти: ' || coalesce(rec.part_name,'') || ' × ' || rec.qty, ulogin);
  return query select true, 'Запчасть возвращена на склад';
end $$;

-- ============================================================
--  Мобильные выезды инженера (текущий пользователь)
-- ============================================================
drop function if exists public.app_service_my_visits(uuid,text);
create or replace function public.app_service_my_visits(p_token uuid, p_engineer text default null)
returns table (visit_id uuid, request_id uuid, number text, title text, equipment text, place text,
               status text, planned_at timestamptz, sla_state text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ulogin text; ten uuid; eng text;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  eng := coalesce(nullif(trim(p_engineer),''), ulogin);
  return query
    select v.id, r.id, r.number, r.title, e.name, coalesce(v.place, r.location), v.status, v.planned_at,
           case when r.status = 'done' then 'closed'
                when r.resolve_due is not null and r.resolve_due < now() then 'overdue'
                when r.resolve_due is not null and r.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end
      from public.app_service_visits v
      join public.app_service_requests r on r.id = v.request_id
      left join public.app_equipment e on e.id = r.equipment_id
     where (urole='admin' or v.tenant_id = ten)
       and (urole='admin' or lower(coalesce(v.engineer,'')) = lower(eng))
       and v.status not in ('cancelled','done')
     order by v.planned_at nulls last, v.created_at;
end $$;

-- ============================================================
--  Обновление app_service_save: авто-гарантия и SLA из контракта
-- ============================================================
create or replace function public.app_service_save(
  p_token uuid, p_id uuid, p_customer_id uuid, p_equipment_id uuid, p_title text, p_kind text,
  p_scheduled_date date, p_engineer text, p_works text, p_cost numeric, p_note text,
  p_priority text default null, p_channel text default null, p_is_warranty boolean default null,
  p_contact text default null, p_location text default null, p_assigned_login text default null
) returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid; snum text; pr text;
        respmin integer; resmin integer; wid uuid; kid uuid; cresp integer; cres integer; iswar boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','support') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите тему'; return; end if;
  pr := coalesce(nullif(trim(p_priority),''),'normal');
  if pr not in ('low','normal','high','critical') then raise exception 'Неверный приоритет'; return; end if;
  select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes(pr);

  -- авто-гарантия по оборудованию
  if p_equipment_id is not null then
    select w.id into wid from public.app_warranties w
     where w.equipment_id = p_equipment_id and w.active and w.start_date <= current_date
       and (w.end_date is null or w.end_date >= current_date)
     order by w.end_date desc nulls last limit 1;
  end if;
  iswar := (wid is not null) or coalesce(p_is_warranty, false);

  -- SLA из активного контракта заказчика
  if p_customer_id is not null then
    select k.id, k.response_sla_min, k.resolve_sla_min into kid, cresp, cres
      from public.app_service_contracts k
     where k.customer_id = p_customer_id and k.active and k.start_date <= current_date
       and (k.end_date is null or k.end_date >= current_date)
     order by k.end_date desc nulls last limit 1;
    if cresp is not null then respmin := cresp; end if;
    if cres is not null then resmin := cres; end if;
  end if;

  if p_id is null then
    snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
    insert into public.app_service_requests
      (tenant_id, number, customer_id, equipment_id, title, kind, priority, channel, is_warranty, warranty_id, contract_id,
       contact, location, scheduled_date, engineer, assigned_login, works, cost, note, reported_at, response_due, resolve_due, created_login)
    values (ten, snum, p_customer_id, p_equipment_id, trim(p_title), coalesce(nullif(trim(p_kind),''),'service'), pr,
            coalesce(nullif(trim(p_channel),''),'manual'), iswar, wid, kid,
            nullif(trim(p_contact),''), nullif(trim(p_location),''), p_scheduled_date, nullif(trim(p_engineer),''), nullif(trim(p_assigned_login),''),
            nullif(trim(p_works),''), p_cost, nullif(trim(p_note),''), now(),
            now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), ulogin)
    returning id into sid;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка создана (' || pr || (case when iswar then ', гарантия' else '' end) || ')', ulogin);
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief','master','support'],
            'Сервис: новая заявка ' || snum, trim(p_title), 'apps/service/index.html');
    return query select sid, snum, 'Заявка создана';
  else
    update public.app_service_requests set customer_id=p_customer_id, equipment_id=p_equipment_id, title=trim(p_title),
      kind=coalesce(nullif(trim(p_kind),''),kind), priority=pr, channel=coalesce(nullif(trim(p_channel),''),channel),
      is_warranty=iswar, warranty_id=coalesce(wid, warranty_id), contact=nullif(trim(p_contact),''), location=nullif(trim(p_location),''),
      scheduled_date=p_scheduled_date, engineer=nullif(trim(p_engineer),''), assigned_login=nullif(trim(p_assigned_login),''),
      works=nullif(trim(p_works),''), cost=p_cost, note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into sid, snum;
    insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
    values (ten, sid, 'event', 'Заявка изменена', ulogin);
    return query select sid, snum, 'Заявка обновлена';
  end if;
end $$;

grant execute on function public.app_warranty_list(uuid)                                   to anon, authenticated;
grant execute on function public.app_warranty_save(uuid,uuid,uuid,uuid,text,text,date,date,text,text,boolean) to anon, authenticated;
grant execute on function public.app_warranty_delete(uuid,uuid)                            to anon, authenticated;
grant execute on function public.app_service_contract_list(uuid)                           to anon, authenticated;
grant execute on function public.app_service_contract_save(uuid,uuid,uuid,text,text,date,date,integer,integer,numeric,text,boolean) to anon, authenticated;
grant execute on function public.app_service_contract_delete(uuid,uuid)                    to anon, authenticated;
grant execute on function public.app_service_parts_list(uuid,uuid)                         to anon, authenticated;
grant execute on function public.app_service_part_add(uuid,uuid,uuid,numeric)              to anon, authenticated;
grant execute on function public.app_service_part_remove(uuid,uuid)                        to anon, authenticated;
grant execute on function public.app_service_my_visits(uuid,text)                          to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_warranties (tenant_id, equipment_id, customer_id, number, provider, start_date, end_date, coverage, terms, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.id,
       (select c.id from public.app_customers c where c.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' order by c.created_at limit 1),
       'WR-' || lpad(row_number() over (order by e.created_at)::text, 4, '0'),
       'manufacturer', current_date - interval '180 days', current_date + interval '365 days', 'Полная гарантия производителя', 'Гарантийный ремонт при соблюдении регламента ТО.', true, 'service'
from public.app_equipment e
where e.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_warranties w where w.equipment_id = e.id)
  and (select count(*) from public.app_warranties w where w.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0
limit 2;

insert into public.app_service_contracts (tenant_id, customer_id, number, kind, start_date, end_date, response_sla_min, resolve_sla_min, cost, terms, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', c.id, 'SC-' || lpad(row_number() over (order by c.created_at)::text, 4, '0'),
       'sla', current_date - interval '30 days', current_date + interval '335 days', 240, 1440, 180000, 'SLA: реакция 4 ч, решение 24 ч.', true, 'service'
from public.app_customers c
where c.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_service_contracts k where k.customer_id = c.id)
  and (select count(*) from public.app_service_contracts k where k.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0
limit 1;

-- зарезервировать демо-запчасть по первой открытой заявке сервиса (если есть)
insert into public.app_service_parts (tenant_id, request_id, part_id, part_name, qty, price, cost, status, created_login)
select r.tenant_id, r.id, p.id, p.name, 1, p.price, p.price, 'reserved', 'service'
from public.app_service_requests r
join public.app_spare_parts p on p.tenant_id = r.tenant_id and p.name = 'Подшипник 6205'
where r.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and r.status not in ('done','cancelled')
  and p.qty >= 1
  and not exists (select 1 from public.app_service_parts sp where sp.request_id = r.id)
  and (select count(*) from public.app_service_parts sp where sp.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0
limit 1;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Гарантии, контракты и запчасти под заявку',
   'Гарантии (app_warranties): оборудование, поставщик (дилер/производитель/внутренний), период, покрытие. Контракты (app_service_contracts): SLA-реакция/решение в минутах. При создании заявки система автоматически определяет гарантию по оборудованию и подставляет SLA из активного контракта заказчика. Запчасти под заявку (app_service_parts) резервируются со склада запчастей ТОиР (app_spare_parts); возврат — app_service_part_remove; стоимость запчастей — parts_cost заявки. Мобильные выезды инженера — app_service_my_visits (мои незакрытые выезды).',
   'сервис гарантия warranty контракт SLA запчасти резерв выезд инженер мобильный')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Гарантии, контракты и запчасти под заявку'
);
