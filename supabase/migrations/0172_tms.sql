-- ============================================================
-- 3DMP Service · 0172_tms.sql  (W23 — TMS / логистика)
-- Перевозчики, заявки на перевозку (рейсы) со статусами; KPI.
-- Идемпотентно. Зависит от 0001..0171.
-- ============================================================

create table if not exists public.app_carriers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  name text not null, inn text, contact text, rate numeric default 0, active boolean default true, note text, created_at timestamptz default now()
);
alter table public.app_carriers enable row level security;

create table if not exists public.app_transport_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  number text, direction text not null default 'out', counterparty text, cargo text, weight numeric,
  from_loc text, to_loc text, pickup_date date, deliver_date date, carrier_id uuid references public.app_carriers (id) on delete set null,
  vehicle text, driver text, cost numeric default 0, status text not null default 'planned', note text,
  created_login text, created_at timestamptz default now()
);
alter table public.app_transport_orders enable row level security;

create or replace function public.app_carriers_list(p_token uuid)
returns table (id uuid, name text, inn text, contact text, rate numeric, active boolean)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select c.id,c.name,c.inn,c.contact,c.rate,c.active from public.app_carriers c where adm or c.tenant_id=ten order by c.name;
end $$;

create or replace function public.app_carrier_save(p_token uuid, p_id uuid, p_name text, p_inn text, p_contact text, p_rate numeric, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_name),'')='' then return query select false,'Укажите перевозчика',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_carriers (tenant_id,name,inn,contact,rate,active) values (ten,left(trim(p_name),160),nullif(trim(p_inn),''),nullif(trim(p_contact),''),coalesce(p_rate,0),coalesce(p_active,true)) returning id into newid;
    return query select true,'Перевозчик добавлен',newid;
  else
    update public.app_carriers c set name=left(trim(p_name),160),inn=nullif(trim(p_inn),''),contact=nullif(trim(p_contact),''),rate=coalesce(p_rate,c.rate),active=coalesce(p_active,c.active)
     where c.id=p_id and (public.app_is_platform_admin(p_token) or c.tenant_id=ten) returning c.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Перевозчик сохранён',newid;
  end if;
end $$;

create or replace function public.app_carrier_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  delete from public.app_carriers c where c.id=p_id and (public.app_is_platform_admin(p_token) or c.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Перевозчик удалён';
end $$;

create or replace function public.app_transport_list(p_token uuid, p_status text default null)
returns table (id uuid, number text, direction text, counterparty text, cargo text, from_loc text, to_loc text, pickup_date date, deliver_date date, carrier text, cost numeric, status text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  st:=nullif(trim(coalesce(p_status,'')),'');
  return query select t.id,t.number,t.direction,t.counterparty,t.cargo,t.from_loc,t.to_loc,t.pickup_date,t.deliver_date,c.name,t.cost,t.status
    from public.app_transport_orders t left join public.app_carriers c on c.id=t.carrier_id
   where (adm or t.tenant_id=ten) and (st is null or t.status=st) order by t.created_at desc;
end $$;

create or replace function public.app_transport_save(p_token uuid, p_id uuid, p_number text, p_direction text, p_counterparty text, p_cargo text, p_weight numeric, p_from text, p_to text, p_pickup date, p_deliver date, p_carrier_id uuid, p_vehicle text, p_driver text, p_cost numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; dr text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  dr:=coalesce(nullif(trim(p_direction),''),'out');
  if dr not in ('in','out') then return query select false,'Направление: in/out',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_transport_orders (tenant_id,number,direction,counterparty,cargo,weight,from_loc,to_loc,pickup_date,deliver_date,carrier_id,vehicle,driver,cost,note,created_login)
    values (ten,nullif(trim(p_number),''),dr,nullif(trim(p_counterparty),''),nullif(trim(p_cargo),''),p_weight,nullif(trim(p_from),''),nullif(trim(p_to),''),p_pickup,p_deliver,p_carrier_id,nullif(trim(p_vehicle),''),nullif(trim(p_driver),''),coalesce(p_cost,0),nullif(trim(p_note),''),uname) returning id into newid;
    return query select true,'Заявка на перевозку создана',newid;
  else
    update public.app_transport_orders t set number=nullif(trim(p_number),''),direction=dr,counterparty=nullif(trim(p_counterparty),''),cargo=nullif(trim(p_cargo),''),weight=p_weight,from_loc=nullif(trim(p_from),''),to_loc=nullif(trim(p_to),''),pickup_date=p_pickup,deliver_date=p_deliver,carrier_id=p_carrier_id,vehicle=nullif(trim(p_vehicle),''),driver=nullif(trim(p_driver),''),cost=coalesce(p_cost,t.cost),note=nullif(trim(p_note),'')
     where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten) returning t.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Заявка сохранена',newid;
  end if;
end $$;

create or replace function public.app_transport_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten:=public.app_my_tenant(p_token);
  st:=lower(trim(coalesce(p_status,'')));
  if st not in ('planned','in_transit','done','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_transport_orders t set status=st where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

create or replace function public.app_tms_kpi(p_token uuid)
returns table (carriers bigint, orders bigint, planned bigint, in_transit bigint, done bigint, cost numeric)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm:=public.app_is_platform_admin(p_token); ten:=public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_carriers c where adm or c.tenant_id=ten),
    (select count(*) from public.app_transport_orders t where adm or t.tenant_id=ten),
    (select count(*) from public.app_transport_orders t where (adm or t.tenant_id=ten) and t.status='planned'),
    (select count(*) from public.app_transport_orders t where (adm or t.tenant_id=ten) and t.status='in_transit'),
    (select count(*) from public.app_transport_orders t where (adm or t.tenant_id=ten) and t.status='done'),
    (select coalesce(sum(t.cost),0) from public.app_transport_orders t where (adm or t.tenant_id=ten) and t.status<>'cancelled');
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Логистика','TMS: перевозчики и заявки на перевозку (рейсы)',
       'W23: перевозчики (app_carriers: ИНН/контакт/тариф), заявки на перевозку (app_transport_orders: направление in/out, груз/вес, откуда/куда, даты, перевозчик/ТС/водитель, стоимость, статусы planned→in_transit→done/cancelled), KPI (app_tms_kpi). Модуль «Логистика» (apps/logistics).',
       'TMS логистика перевозка рейс перевозчик груз','Логистика'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='TMS: перевозчики и заявки на перевозку (рейсы)');

-- ---------- Права ----------
grant execute on function public.app_carriers_list(uuid) to anon, authenticated;
grant execute on function public.app_carrier_save(uuid,uuid,text,text,text,numeric,boolean) to anon, authenticated;
grant execute on function public.app_carrier_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_transport_list(uuid,text) to anon, authenticated;
grant execute on function public.app_transport_save(uuid,uuid,text,text,text,text,numeric,text,text,date,date,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_transport_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_tms_kpi(uuid) to anon, authenticated;
