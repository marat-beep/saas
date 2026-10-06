-- ============================================================
-- 3DMP Service · 0073_norms_core.sql  (v51 — P14 «Нормирование PRO», Сессия C)
-- Ядро нормирования: операции и ставки (диапазоны по сложности), K-коэффициенты
-- (материал/точность/геометрия/оснастка), серийность, база аналогов + автоподбор,
-- расчёт нормы. Логика перенесена из «Нормирование PRO» (без копирования файлов).
-- База знаний. Зависит от 0001..0072.
-- ============================================================

create table if not exists public.app_norms_operations (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  code         text not null,
  name         text not null,
  category     text,                       -- milling|turning|edm|grinding|locksmith|engraving|heat|other
  machine_type text,
  unit         text default 'н/ч',
  note         text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists app_norms_operations_idx on public.app_norms_operations (tenant_id, active, category);
alter table public.app_norms_operations enable row level security;

create table if not exists public.app_norms_rates (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  operation_id uuid references public.app_norms_operations (id) on delete cascade,
  complexity   text not null default 'mid',   -- simple|mid|hard
  sale_min     numeric not null default 0,
  sale_max     numeric not null default 0,
  cost_ratio   numeric not null default 0.70
);
create index if not exists app_norms_rates_idx on public.app_norms_rates (operation_id);
alter table public.app_norms_rates enable row level security;

create table if not exists public.app_norms_kfactors (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  category   text not null,   -- material|accuracy|geometry|fixture
  name       text not null,
  value      numeric not null default 1,
  note       text
);
create index if not exists app_norms_kfactors_idx on public.app_norms_kfactors (tenant_id, category);
alter table public.app_norms_kfactors enable row level security;

create table if not exists public.app_norms_serial (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  label     text,
  qty_min   int not null default 1,
  qty_max   int,                       -- null = без верхней границы
  factor    numeric not null default 1
);
create index if not exists app_norms_serial_idx on public.app_norms_serial (tenant_id);
alter table public.app_norms_serial enable row level security;

create table if not exists public.app_analogs (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  material   text,
  operation  text,
  weight     numeric,
  dims       text,
  norm_base  numeric,
  tags       text,
  note       text,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists app_analogs_idx on public.app_analogs (tenant_id, material, operation);
alter table public.app_analogs enable row level security;

-- ---------- Операции ----------
create or replace function public.app_norms_ops_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, category text, machine_type text, unit text, active boolean, rates bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select o.id, o.code, o.name, o.category, o.machine_type, o.unit, o.active,
      (select count(*) from public.app_norms_rates r where r.operation_id=o.id)
    from public.app_norms_operations o
    where (urole='admin' or o.tenant_id=ten)
      and (qq='' or lower(o.name) like '%'||qq||'%' or lower(o.code) like '%'||qq||'%')
    order by o.category, o.name;
end $$;

create or replace function public.app_norms_op_save(p_token uuid, p_id uuid, p_code text, p_name text,
  p_category text, p_machine_type text, p_note text, p_active boolean default true)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; oid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','master') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_code),'')='' then raise exception 'Укажите код и название операции'; return; end if;
  if p_id is null then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, note, active)
    values (ten, upper(trim(p_code)), trim(p_name), nullif(trim(p_category),''), nullif(trim(p_machine_type),''), nullif(trim(p_note),''), coalesce(p_active,true))
    returning id into oid;
    return query select oid, 'Операция создана';
  else
    update public.app_norms_operations set code=upper(trim(p_code)), name=trim(p_name),
      category=nullif(trim(p_category),''), machine_type=nullif(trim(p_machine_type),''), note=nullif(trim(p_note),''), active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into oid;
    return query select oid, 'Операция обновлена';
  end if;
end $$;

-- ---------- Ставки ----------
create or replace function public.app_norms_rates_list(p_token uuid, p_operation_id uuid)
returns table (id uuid, complexity text, sale_min numeric, sale_max numeric, cost_ratio numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.complexity, r.sale_min, r.sale_max, r.cost_ratio
    from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id
    where r.operation_id=p_operation_id and (urole='admin' or o.tenant_id=ten)
    order by (case r.complexity when 'simple' then 1 when 'mid' then 2 else 3 end);
end $$;

create or replace function public.app_norms_rate_save(p_token uuid, p_id uuid, p_operation_id uuid, p_complexity text,
  p_sale_min numeric, p_sale_max numeric, p_cost_ratio numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','economist') then raise exception 'Недостаточно прав'; return; end if;
  if p_complexity not in ('simple','mid','hard') then raise exception 'Сложность: simple|mid|hard'; return; end if;
  if not exists (select 1 from public.app_norms_operations o where o.id=p_operation_id and (urole='admin' or o.tenant_id=ten)) then raise exception 'Операция не найдена'; return; end if;
  if p_id is null then
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio)
    values (ten, p_operation_id, p_complexity, coalesce(p_sale_min,0), coalesce(p_sale_max,0), coalesce(p_cost_ratio,0.7))
    returning id into rid;
    return query select rid, 'Ставка добавлена';
  else
    update public.app_norms_rates set complexity=p_complexity, sale_min=coalesce(p_sale_min,0),
      sale_max=coalesce(p_sale_max,0), cost_ratio=coalesce(p_cost_ratio,0.7)
     where id=p_id and operation_id=p_operation_id returning id into rid;
    return query select rid, 'Ставка обновлена';
  end if;
end $$;

create or replace function public.app_norms_rate_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_norms_rates r using public.app_norms_operations o
    where r.id=p_id and o.id=r.operation_id and (urole='admin' or o.tenant_id=ten);
  return query select true,'Ставка удалена';
end $$;

-- ---------- K-коэффициенты ----------
create or replace function public.app_norms_k_list(p_token uuid, p_category text default null)
returns table (id uuid, category text, name text, value numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select k.id, k.category, k.name, k.value, k.note
    from public.app_norms_kfactors k
    where (urole='admin' or k.tenant_id=ten) and (coalesce(p_category,'')='' or k.category=p_category)
    order by k.category, k.value;
end $$;

create or replace function public.app_norms_k_save(p_token uuid, p_id uuid, p_category text, p_name text, p_value numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; kid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if p_category not in ('material','accuracy','geometry','fixture') then raise exception 'Категория: material|accuracy|geometry|fixture'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_norms_kfactors (tenant_id, category, name, value, note)
    values (ten, p_category, trim(p_name), coalesce(p_value,1), nullif(trim(p_note),'')) returning id into kid;
    return query select kid, 'Коэффициент добавлен';
  else
    update public.app_norms_kfactors set category=p_category, name=trim(p_name), value=coalesce(p_value,1), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into kid;
    return query select kid, 'Коэффициент обновлён';
  end if;
end $$;

create or replace function public.app_norms_k_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_norms_kfactors where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Коэффициент удалён';
end $$;

-- ---------- Серийность ----------
create or replace function public.app_norms_serial_list(p_token uuid)
returns table (id uuid, label text, qty_min int, qty_max int, factor numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select s.id, s.label, s.qty_min, s.qty_max, s.factor from public.app_norms_serial s
    where (urole='admin' or s.tenant_id=ten) order by s.qty_min;
end $$;

create or replace function public.app_norms_serial_save(p_token uuid, p_id uuid, p_label text, p_qty_min int, p_qty_max int, p_factor numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if p_id is null then
    insert into public.app_norms_serial (tenant_id, label, qty_min, qty_max, factor)
    values (ten, nullif(trim(p_label),''), coalesce(p_qty_min,1), p_qty_max, coalesce(p_factor,1)) returning id into sid;
    return query select sid, 'Диапазон добавлен';
  else
    update public.app_norms_serial set label=nullif(trim(p_label),''), qty_min=coalesce(p_qty_min,1), qty_max=p_qty_max, factor=coalesce(p_factor,1)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Диапазон обновлён';
  end if;
end $$;

-- ---------- Аналоги ----------
create or replace function public.app_analogs_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, material text, operation text, weight numeric, dims text, norm_base numeric, tags text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select a.id, a.name, a.material, a.operation, a.weight, a.dims, a.norm_base, a.tags, a.created_at
    from public.app_analogs a
    where (urole='admin' or a.tenant_id=ten)
      and (qq='' or lower(a.name) like '%'||qq||'%' or lower(coalesce(a.material,'')) like '%'||qq||'%' or lower(coalesce(a.tags,'')) like '%'||qq||'%')
    order by a.created_at desc;
end $$;

create or replace function public.app_analog_save(p_token uuid, p_id uuid, p_name text, p_material text, p_operation text,
  p_weight numeric, p_dims text, p_norm_base numeric, p_tags text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; aid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','technologist','master','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите название аналога'; return; end if;
  if p_id is null then
    insert into public.app_analogs (tenant_id, name, material, operation, weight, dims, norm_base, tags, note)
    values (ten, trim(p_name), nullif(trim(p_material),''), nullif(trim(p_operation),''), p_weight, nullif(trim(p_dims),''), p_norm_base, nullif(trim(p_tags),''), nullif(trim(p_note),''))
    returning id into aid;
    return query select aid, 'Аналог добавлен';
  else
    update public.app_analogs set name=trim(p_name), material=nullif(trim(p_material),''), operation=nullif(trim(p_operation),''),
      weight=p_weight, dims=nullif(trim(p_dims),''), norm_base=p_norm_base, tags=nullif(trim(p_tags),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into aid;
    return query select aid, 'Аналог обновлён';
  end if;
end $$;

create or replace function public.app_analog_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_analogs where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Аналог удалён';
end $$;

-- ---------- Автоподбор аналога ----------
create or replace function public.app_analog_find(p_token uuid, p_material text, p_operation text, p_weight numeric default null)
returns table (id uuid, name text, material text, operation text, weight numeric, norm_base numeric, score numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.name, a.material, a.operation, a.weight, a.norm_base,
      round( (case when lower(coalesce(a.material,''))=lower(coalesce(p_material,'')) then 5 else 0 end)
           + (case when lower(coalesce(a.operation,''))=lower(coalesce(p_operation,'')) then 3 else 0 end)
           - (case when a.weight is not null and p_weight is not null and p_weight>0
                   then least(2, abs(a.weight-p_weight)/greatest(p_weight,1)*2) else 0 end), 2) as score
    from public.app_analogs a
    where (urole='admin' or a.tenant_id=ten)
    order by score desc nulls last, a.created_at desc
    limit 5;
end $$;

-- ---------- Расчёт нормы ----------
create or replace function public.app_norm_calc(p_token uuid, p_operation_id uuid, p_complexity text default 'mid',
  p_qty numeric default 1, p_kmaterial numeric default 1, p_kaccuracy numeric default 1,
  p_kgeometry numeric default 1, p_kfixture numeric default 1, p_base_override numeric default null)
returns table (operation text, complexity text, rate_sale numeric, rate_cost numeric, k_product numeric,
               serial_factor numeric, qty numeric, norm_sale numeric, norm_cost numeric, total_sale numeric, total_cost numeric, formula text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; oname text; rmin numeric; rmax numeric; c_ratio numeric; rsale numeric;
  kp numeric; sf numeric; q numeric; nsale numeric; ncost numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  q := greatest(coalesce(p_qty,1),1);
  select o.name into oname from public.app_norms_operations o where o.id=p_operation_id and (urole='admin' or o.tenant_id=ten);
  if oname is null then raise exception 'Операция не найдена'; end if;
  select r.sale_min, r.sale_max, r.cost_ratio into rmin, rmax, c_ratio
    from public.app_norms_rates r where r.operation_id=p_operation_id and r.complexity=coalesce(nullif(p_complexity,''),'mid');
  if rmin is null then rmin := 0; rmax := 0; c_ratio := 0.7; end if;
  rsale := case lower(coalesce(p_complexity,'mid'))
             when 'simple' then rmin
             when 'hard'   then rmax
             else (rmin+rmax)/2.0 end;
  if p_base_override is not null then rsale := p_base_override; end if;
  select s.factor into sf from public.app_norms_serial s
    where (urole='admin' or s.tenant_id=ten) and q >= s.qty_min and (s.qty_max is null or q <= s.qty_max)
    order by s.qty_min desc limit 1;
  sf := coalesce(sf,1);
  kp := coalesce(p_kmaterial,1)*coalesce(p_kaccuracy,1)*coalesce(p_kgeometry,1)*coalesce(p_kfixture,1);
  nsale := rsale * kp * sf;
  ncost := nsale * coalesce(c_ratio,0.7);
  return query select oname, coalesce(nullif(p_complexity,''),'mid'), round(rsale,2), round(rsale*coalesce(c_ratio,0.7),2),
    round(kp,4), round(sf,4), q, round(nsale,2), round(ncost,2), round(nsale*q,2), round(ncost*q,2),
    'норма = ставка('||coalesce(nullif(p_complexity,''),'mid')||') × K('||round(kp,3)||') × серийность('||round(sf,3)||')';
end $$;

create or replace function public.app_norms_kpi(p_token uuid)
returns table (operations bigint, rates bigint, kfactors bigint, analogs bigint, serial_ranges bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_norms_operations where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id where (urole='admin' or o.tenant_id=ten)),
    (select count(*) from public.app_norms_kfactors where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_analogs where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_norms_serial where (urole='admin' or tenant_id=ten));
end $$;

grant execute on function public.app_norms_ops_list(uuid,text) to anon, authenticated;
grant execute on function public.app_norms_op_save(uuid,uuid,text,text,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_norms_rates_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_rate_save(uuid,uuid,uuid,text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_norms_rate_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_k_list(uuid,text) to anon, authenticated;
grant execute on function public.app_norms_k_save(uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_norms_k_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_norms_serial_list(uuid) to anon, authenticated;
grant execute on function public.app_norms_serial_save(uuid,uuid,text,int,int,numeric) to anon, authenticated;
grant execute on function public.app_analogs_list(uuid,text) to anon, authenticated;
grant execute on function public.app_analog_save(uuid,uuid,text,text,text,numeric,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_analog_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_analog_find(uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_norm_calc(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_norms_kpi(uuid) to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
do $$
declare oid uuid;
begin
  if not exists (select 1 from public.app_norms_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, unit) values
      ('aaaaaaaa-0000-0000-0000-000000000001','MILL3','Фрезерная 3-осевая','milling','3-осевой ОЦ','н/ч') returning id into oid;
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio) values
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'simple', 8000, 12000, 0.70),
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'mid', 10000, 14000, 0.70),
      ('aaaaaaaa-0000-0000-0000-000000000001', oid, 'hard', 12000, 16000, 0.70);
  end if;
  if (select count(*) from public.app_norms_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') < 3 then
    insert into public.app_norms_operations (tenant_id, code, name, category, machine_type, unit)
    select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.cat, v.mt, 'н/ч'
    from (values
      ('MILL4','Фрезерная 4-осевая','milling','4-осевой ОЦ'),
      ('MILL5','Фрезерная 5-осевая','milling','5-осевой ОЦ'),
      ('TURN','Токарная','turning','токарный'),
      ('TURNMILL','Токарно-фрезерная','turning','токарно-фрезерный'),
      ('EDMWIRE','ЭЭО проволочная','edm','электроэрозионный'),
      ('EDMDIE','ЭЭО прошивная','edm','электроэрозионный'),
      ('EDMDRILL','ЭЭО сверлильная','edm','электроэрозионный'),
      ('GRINDFLAT','Шлифование плоское','grinding','плоскошлифовальный'),
      ('GRINDPROF','Шлифование профильное','grinding','профилешлифовальный'),
      ('LOCK','Слесарная','locksmith','верстак'),
      ('ENGR','Гравирование','engraving','лазерный маркер')
    ) as v(code,name,cat,mt)
    where not exists (select 1 from public.app_norms_operations o where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code=v.code);
  end if;
  if not exists (select 1 from public.app_norms_rates r join public.app_norms_operations o on o.id=r.operation_id where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code='TURN') then
    insert into public.app_norms_rates (tenant_id, operation_id, complexity, sale_min, sale_max, cost_ratio)
    select 'aaaaaaaa-0000-0000-0000-000000000001', o.id, v.cx, v.a, v.b, 0.70
    from public.app_norms_operations o
    cross join (values ('simple',5000,8000),('mid',6500,9500),('hard',8000,11000)) as v(cx,a,b)
    where o.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and o.code='TURN';
  end if;
  if not exists (select 1 from public.app_norms_kfactors where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_kfactors (tenant_id, category, name, value) values
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Сталь конструкционная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Сталь инструментальная',1.30),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Нержавеющая',1.40),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Алюминий',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','material','Титан',1.80),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Обычная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Повышенная',1.15),
      ('aaaaaaaa-0000-0000-0000-000000000001','accuracy','Высокая',1.35),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Простая',0.95),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Средняя',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','geometry','Сложная',1.25),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Без оснастки',1.10),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Универсальная',1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','fixture','Спецоснастка',0.90);
  end if;
  if not exists (select 1 from public.app_norms_serial where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_norms_serial (tenant_id, label, qty_min, qty_max, factor) values
      ('aaaaaaaa-0000-0000-0000-000000000001','Единичное',1,1,1.30),
      ('aaaaaaaa-0000-0000-0000-000000000001','Мелкая серия',2,5,1.00),
      ('aaaaaaaa-0000-0000-0000-000000000001','Средняя серия',6,50,0.85),
      ('aaaaaaaa-0000-0000-0000-000000000001','Массовое',51,null,0.75);
  end if;
  if not exists (select 1 from public.app_analogs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_analogs (tenant_id, name, material, operation, weight, dims, norm_base, tags, note) values
      ('aaaaaaaa-0000-0000-0000-000000000001','Пуансон вырубной','Сталь инструментальная','MILL3',12.5,'200×150×40',0.85,'штамп,пуансон','Аналог из архива'),
      ('aaaaaaaa-0000-0000-0000-000000000001','Матрица гибочная','Сталь инструментальная','MILL5',34.0,'400×250×80',1.60,'штамп,матрица',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Корпус пресс-формы','Сталь конструкционная','MILL4',52.0,'500×400×120',3.20,'пресс-форма,корпус',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Втулка направляющая','Сталь конструкционная','TURN',1.2,'Ø30×60',0.35,'втулка,направляющая',null),
      ('aaaaaaaa-0000-0000-0000-000000000001','Плита опорная','Сталь конструкционная','GRINDFLAT',8.0,'300×300×25',0.60,'плита,шлифование',null);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Нормирование','Ядро нормирования P14 (операции, ставки, K, серийность, аналоги)',
   'Модуль «Нормирование PRO»: справочник операций с диапазонами ставок по сложности (simple/mid/hard, sale_min…sale_max, cost_ratio); K-коэффициенты (материал/точность/геометрия/оснастка); коэффициенты серийности по количеству; база аналогов с автоподбором по материалу/операции/массе. Формула нормы: норма = ставка(сложность) × K_материала × K_точности × K_геометрии × K_оснастки × серийность. Себестоимость = норма × cost_ratio. Расчёт основан на логике проекта «Нормирование PRO», перенесён в мультитенантную модель 3DMP.',
   'нормирование нормирование pro P14 операции ставки K-коэффициент серийность аналоги автоподбор формула нормы')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Ядро нормирования P14 (операции, ставки, K, серийность, аналоги)');
