-- ============================================================
-- 3DMP Service · 0022_quality_system.sql  (v7.0 — качество/СМК)
-- Средства измерений (поверка) и трассируемость. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0021.
-- ============================================================

create table if not exists public.app_measuring_tools (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  serial        text,
  tool_type     text,
  location      text,
  last_verified date,
  next_verified date,
  created_at    timestamptz not null default now()
);
create index if not exists app_tools_tenant_idx on public.app_measuring_tools (tenant_id);

create table if not exists public.app_traceability (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  item        text not null,
  serial      text,
  order_id    uuid references public.app_orders (id) on delete set null,
  passport_id uuid references public.app_passports (id) on delete set null,
  material    text,
  operator    text,
  note        text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_trace_tenant_idx on public.app_traceability (tenant_id, created_at desc);

alter table public.app_measuring_tools enable row level security;
alter table public.app_traceability    enable row level security;

-- ---------- Средства измерений ----------
create or replace function public.app_tools_list(p_token uuid)
returns table (id uuid, name text, serial text, tool_type text, location text,
               last_verified date, next_verified date, status text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.name, t.serial, t.tool_type, t.location, t.last_verified, t.next_verified,
      case when t.next_verified is null then 'none'
           when t.next_verified < current_date then 'expired'
           when t.next_verified < current_date + 30 then 'due'
           else 'ok' end
    from public.app_measuring_tools t
    where (urole='admin' or t.tenant_id = ten)
    order by case when t.next_verified is null then 1 else 0 end, t.next_verified;
end $$;

create or replace function public.app_tool_save(p_token uuid, p_id uuid, p_name text, p_serial text, p_tool_type text, p_location text, p_last date, p_next date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_measuring_tools (tenant_id, name, serial, tool_type, location, last_verified, next_verified)
    values (ten, trim(p_name), nullif(trim(p_serial),''), nullif(trim(p_tool_type),''), nullif(trim(p_location),''), p_last, p_next);
  else
    update public.app_measuring_tools set name=trim(p_name), serial=nullif(trim(p_serial),''), tool_type=nullif(trim(p_tool_type),''),
      location=nullif(trim(p_location),''), last_verified=p_last, next_verified=p_next
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_tool_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_measuring_tools where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Удалено';
end $$;

-- ---------- Трассируемость ----------
create or replace function public.app_trace_list(p_token uuid)
returns table (id uuid, item text, serial text, order_number text, material text, operator text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select tr.id, tr.item, tr.serial, o.number, tr.material, tr.operator, tr.by_login, tr.created_at
    from public.app_traceability tr left join public.app_orders o on o.id = tr.order_id
    where (urole='admin' or tr.tenant_id = ten) order by tr.created_at desc;
end $$;

create or replace function public.app_trace_add(p_token uuid, p_item text, p_serial text, p_order_id uuid, p_passport_id uuid, p_material text, p_operator text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_item),'') = '' then return query select false,'Укажите изделие/партию'; return; end if;
  insert into public.app_traceability (tenant_id, item, serial, order_id, passport_id, material, operator, note, by_login)
  values (ten, trim(p_item), nullif(trim(p_serial),''), p_order_id, p_passport_id, nullif(trim(p_material),''), nullif(trim(p_operator),''), nullif(trim(p_note),''), ulogin);
  return query select true,'Запись добавлена';
end $$;

-- ---------- KPI ----------
create or replace function public.app_quality_kpi(p_token uuid)
returns table (tools bigint, expired bigint, due bigint, trace_records bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_measuring_tools t where (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_measuring_tools t where t.next_verified < current_date and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_measuring_tools t where t.next_verified >= current_date and t.next_verified < current_date+30 and (urole='admin' or t.tenant_id=ten)),
    (select count(*) from public.app_traceability tr where (urole='admin' or tr.tenant_id=ten));
end $$;

grant execute on function public.app_tools_list(uuid) to anon, authenticated;
grant execute on function public.app_tool_save(uuid,uuid,text,text,text,text,date,date) to anon, authenticated;
grant execute on function public.app_tool_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_trace_list(uuid) to anon, authenticated;
grant execute on function public.app_trace_add(uuid,text,text,uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_quality_kpi(uuid) to anon, authenticated;

-- ---------- Демо-СИ ----------
insert into public.app_measuring_tools (tenant_id, name, serial, tool_type, location, last_verified, next_verified)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.serial, v.tool_type, v.location, (current_date - 300), (current_date + v.plus)
from (values
  ('Штангенциркуль ШЦ-125','SN-001','Штангенциркуль','ОТК', 20),
  ('Микрометр МК-25','SN-002','Микрометр','ОТК', -5),
  ('КИМ-стойка','SN-003','КИМ','Цех', 120)
) as v(name,serial,tool_type,location,plus)
where not exists (select 1 from public.app_measuring_tools where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
