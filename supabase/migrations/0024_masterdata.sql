-- ============================================================
-- 3DMP Service · 0024_masterdata.sql  (функциональная модель: справочники)
-- Связная модель: оборудование ↔ операции ↔ материалы ↔ шаблоны техпроцессов.
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0023.
-- ============================================================

-- ---------- Оборудование ----------
create table if not exists public.app_equipment (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  model       text,
  kind        text not null default 'frezerny', -- frezerny|tokarny|lazer|sverlilny|shlifovalny|edm|sborka
  axis        integer,
  max_x       numeric, max_y numeric, max_z numeric,
  accuracy    numeric,
  power       numeric,
  cost_hour   numeric default 0,
  dept        text,
  wc_id       uuid references public.app_work_centers (id) on delete set null,
  status      text not null default 'active',   -- active|maintenance|off
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_equipment_tenant_idx on public.app_equipment (tenant_id, kind);
alter table public.app_equipment enable row level security;

-- ---------- Материалы: расширение свойств ----------
alter table public.app_materials add column if not exists material_group text;  -- сталь|алюминий|латунь|титан|пластик
alter table public.app_materials add column if not exists grade text;          -- марка
alter table public.app_materials add column if not exists standard text;       -- ГОСТ/ТУ
alter table public.app_materials add column if not exists density numeric;     -- кг/дм³

-- ---------- Операции (справочник) ----------
create table if not exists public.app_operations (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  kind        text not null default 'frezerny', -- тип оборудования (совместимость)
  setup_min   numeric default 0,
  unit_min    numeric default 0,
  base_rate   numeric default 0,
  unit        text default 'шт',
  description text,
  created_at  timestamptz not null default now()
);
create index if not exists app_operations_tenant_idx on public.app_operations (tenant_id, kind);
alter table public.app_operations enable row level security;

-- ---------- Шаблоны техпроцессов ----------
create table if not exists public.app_process_templates (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  code         text,
  name         text not null,
  product_type text,
  material_id  uuid references public.app_materials (id) on delete set null,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_process_tpl_tenant_idx on public.app_process_templates (tenant_id);
alter table public.app_process_templates enable row level security;

create table if not exists public.app_process_steps (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references public.app_process_templates (id) on delete cascade,
  seq          integer default 0,
  operation_id uuid references public.app_operations (id) on delete set null,
  equipment_id uuid references public.app_equipment (id) on delete set null,
  material_id  uuid references public.app_materials (id) on delete set null,
  plan_min     numeric default 0,
  note         text
);
create index if not exists app_process_steps_tpl_idx on public.app_process_steps (template_id, seq);
alter table public.app_process_steps enable row level security;

-- ============================================================
--  RPC
-- ============================================================
create or replace function public.app_equipment_list(p_token uuid)
returns table (id uuid, code text, name text, model text, kind text, axis integer, max_x numeric, max_y numeric, max_z numeric,
               accuracy numeric, cost_hour numeric, dept text, status text, wc_name text, ops_count bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.model, e.kind, e.axis, e.max_x, e.max_y, e.max_z, e.accuracy, e.cost_hour, e.dept, e.status,
           w.name,
           (select count(*) from public.app_operations o where o.kind = e.kind and (urole='admin' or o.tenant_id = ten))
    from public.app_equipment e left join public.app_work_centers w on w.id = e.wc_id
    where (urole='admin' or e.tenant_id = ten)
    order by e.kind, e.name;
end $$;

create or replace function public.app_equipment_save(p_token uuid, p_id uuid, p_code text, p_name text, p_model text, p_kind text,
  p_axis integer, p_max_x numeric, p_max_y numeric, p_max_z numeric, p_accuracy numeric, p_cost_hour numeric, p_dept text, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_equipment (tenant_id, code, name, model, kind, axis, max_x, max_y, max_z, accuracy, cost_hour, dept, status)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_model),''), coalesce(nullif(trim(p_kind),''),'frezerny'),
            p_axis, p_max_x, p_max_y, p_max_z, p_accuracy, coalesce(p_cost_hour,0), nullif(trim(p_dept),''), coalesce(nullif(trim(p_status),''),'active'));
  else
    update public.app_equipment set code=nullif(trim(p_code),''), name=trim(p_name), model=nullif(trim(p_model),''),
      kind=coalesce(nullif(trim(p_kind),''),kind), axis=p_axis, max_x=p_max_x, max_y=p_max_y, max_z=p_max_z, accuracy=p_accuracy,
      cost_hour=coalesce(p_cost_hour,0), dept=nullif(trim(p_dept),''), status=coalesce(nullif(trim(p_status),''),status)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_operations_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, setup_min numeric, unit_min numeric, base_rate numeric, unit text, equipment_count bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.code, o.name, o.kind, o.setup_min, o.unit_min, o.base_rate, o.unit,
           (select count(*) from public.app_equipment e where e.kind = o.kind and (urole='admin' or e.tenant_id = ten))
    from public.app_operations o where (urole='admin' or o.tenant_id = ten) order by o.kind, o.name;
end $$;

create or replace function public.app_operation_save(p_token uuid, p_id uuid, p_code text, p_name text, p_kind text, p_setup numeric, p_unit_min numeric, p_rate numeric, p_unit text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_operations (tenant_id, code, name, kind, setup_min, unit_min, base_rate, unit)
    values (ten, nullif(trim(p_code),''), trim(p_name), coalesce(nullif(trim(p_kind),''),'frezerny'), coalesce(p_setup,0), coalesce(p_unit_min,0), coalesce(p_rate,0), coalesce(nullif(trim(p_unit),''),'шт'));
  else
    update public.app_operations set code=nullif(trim(p_code),''), name=trim(p_name), kind=coalesce(nullif(trim(p_kind),''),kind),
      setup_min=coalesce(p_setup,0), unit_min=coalesce(p_unit_min,0), base_rate=coalesce(p_rate,0), unit=coalesce(nullif(trim(p_unit),''),unit)
     where id=p_id and (ten is null or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_process_list(p_token uuid)
returns table (id uuid, code text, name text, product_type text, material_name text, steps_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.code, t.name, t.product_type, m.name,
           (select count(*) from public.app_process_steps st where st.template_id = t.id), t.created_at
    from public.app_process_templates t left join public.app_materials m on m.id = t.material_id
    where (urole='admin' or t.tenant_id = ten) order by t.created_at desc;
end $$;

create or replace function public.app_process_get(p_token uuid, p_id uuid)
returns table (id uuid, code text, name text, product_type text, material_name text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, t.code, t.name, t.product_type, m.name, t.note
    from public.app_process_templates t left join public.app_materials m on m.id = t.material_id
    where t.id = p_id and (urole='admin' or t.tenant_id = ten);
end $$;

create or replace function public.app_process_steps_list(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, equipment text, material text, plan_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select st.id, st.seq, o.name, e.name, m.name, st.plan_min, st.note
    from public.app_process_steps st
    left join public.app_operations o on o.id = st.operation_id
    left join public.app_equipment e on e.id = st.equipment_id
    left join public.app_materials m on m.id = st.material_id
    join public.app_process_templates t on t.id = st.template_id
    where st.template_id = p_id and (urole='admin' or t.tenant_id = ten)
    order by st.seq;
end $$;

create or replace function public.app_process_create(p_token uuid, p_code text, p_name text, p_product_type text, p_material_id uuid, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название'; end if;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_product_type),''), p_material_id, nullif(trim(p_note),''))
  returning app_process_templates.id into tid;
  return query select tid, 'Шаблон создан';
end $$;

create or replace function public.app_process_add_step(p_token uuid, p_id uuid, p_operation_id uuid, p_equipment_id uuid, p_material_id uuid, p_plan_min numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; seqn integer; tid uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.id into tid from public.app_process_templates t where t.id = p_id and (ten is null or t.tenant_id = ten);
  if tid is null then return query select false,'Шаблон не найден'; return; end if;
  select coalesce(max(st.seq),0)+1 into seqn from public.app_process_steps st where st.template_id = p_id;
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, material_id, plan_min, note)
  values (p_id, seqn, p_operation_id, p_equipment_id, p_material_id, coalesce(p_plan_min,0), nullif(trim(p_note),''));
  return query select true,'Шаг добавлен';
end $$;

-- расширенный список материалов (с характеристиками)
create or replace function public.app_materials_reg(p_token uuid)
returns table (id uuid, code text, name text, material_group text, grade text, standard text, density numeric, unit text, price numeric, qty numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select m.id, m.code, m.name, m.material_group, m.grade, m.standard, m.density, m.unit, m.price, m.qty
    from public.app_materials m where (urole='admin' or m.tenant_id = ten) order by m.name;
end $$;

grant execute on function public.app_equipment_list(uuid) to anon, authenticated;
grant execute on function public.app_equipment_save(uuid,uuid,text,text,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_operations_list(uuid) to anon, authenticated;
grant execute on function public.app_operation_save(uuid,uuid,text,text,text,numeric,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_process_list(uuid) to anon, authenticated;
grant execute on function public.app_process_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_steps_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_create(uuid,text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.app_process_add_step(uuid,uuid,uuid,uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_materials_reg(uuid) to anon, authenticated;

-- ============================================================
--  Наполнение (связные демо-данные, тенант A)
-- ============================================================
-- Оборудование (с привязкой к рабочим центрам по коду)
insert into public.app_equipment (tenant_id, code, name, model, kind, axis, max_x, max_y, max_z, accuracy, cost_hour, dept, wc_id, status)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.model, v.kind, v.axis, v.mx, v.my, v.mz, v.acc, v.cost, v.dept,
       (select w.id from public.app_work_centers w where w.code = v.wc and w.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' limit 1), 'active'
from (values
  ('EQ-01','Фрезерный ЧПУ DMU-50','DMU-50','frezerny',5,500,400,400,0.01,3500,'Механообработка','WC-01'),
  ('EQ-02','Токарный с ЧПУ Haas ST-20','ST-20','tokarny',2,300,0,500,0.02,3000,'Механообработка','WC-02'),
  ('EQ-03','Лазерный комплекс 3 кВт','FiberCut-3','lazer',2,3000,1500,0,0.1,4200,'Резка','WC-03'),
  ('EQ-04','Слесарная/сборка','Верстак-1','sborka',0,0,0,0,0,1800,'Сборка','WC-04'),
  ('EQ-05','Вертикально-сверлильный','2Н135','sverlilny',1,35,0,0,0.05,1200,'Механообработка',null),
  ('EQ-06','Плоскошлифовальный','3Г71','shlifovalny',3,630,200,320,0.005,2200,'Механообработка',null),
  ('EQ-07','Электроэрозионный','EA-12','edm',3,400,300,300,0.01,3800,'Механообработка',null)
) as v(code,name,model,kind,axis,mx,my,mz,acc,cost,dept,wc)
where not exists (select 1 from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- Материалы: характеристики
update public.app_materials set material_group='сталь', grade='40Х', standard='ГОСТ 4543-2016', density=7.85 where code='М-40Х' and material_group is null;
update public.app_materials set material_group='сталь', grade='45', standard='ГОСТ 1050-2013', density=7.85 where code='М-45' and material_group is null;
update public.app_materials set material_group='алюминий', grade='Д16Т', standard='ГОСТ 4784-2019', density=2.78 where code='М-Д16Т' and material_group is null;
update public.app_materials set material_group='сталь', grade='09Г2С', standard='ГОСТ 19281-2014', density=7.85 where code='М-09Г2С' and material_group is null;

-- Операции
insert into public.app_operations (tenant_id, code, name, kind, setup_min, unit_min, base_rate, unit, description)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.kind, v.setup, v.unit_min, v.rate, v.unit, v.descr
from (values
  ('OP-01','Фрезеровка черновая','frezerny',20,12,3500,'шт','Снятие основного припуска'),
  ('OP-02','Фрезеровка чистовая','frezerny',15,8,3500,'шт','По допуску чертежа'),
  ('OP-03','Токарная черновая','tokarny',18,10,3000,'шт','Обдирка'),
  ('OP-04','Токарная чистовая','tokarny',15,7,3000,'шт','Чистовой проход'),
  ('OP-05','Сверление','sverlilny',5,3,1200,'отв','По разметке/ЧПУ'),
  ('OP-06','Лазерная резка','lazer',10,3,4200,'лист','Контурный раскрой'),
  ('OP-07','Плоское шлифование','shlifovalny',12,6,2200,'шт','Достижение точности'),
  ('OP-08','Электроэрозия','edm',25,15,3800,'шт','Каналы/фасонные полости'),
  ('OP-09','Слесарная доводка','sborka',5,15,1800,'шт','Зачистка, пригонка'),
  ('OP-10','Сборка узла','sborka',10,25,1800,'шт','Финальная сборка')
) as v(code,name,kind,setup,unit_min,rate,unit,descr)
where not exists (select 1 from public.app_operations where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- Шаблоны техпроцессов + шаги
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        t1 uuid; t2 uuid; t3 uuid;
        m40 uuid; m45 uuid; m09 uuid;
begin
  if exists (select 1 from public.app_process_templates where tenant_id = ten) then return; end if;
  select id into m40 from public.app_materials where tenant_id=ten and code='М-40Х';
  select id into m45 from public.app_materials where tenant_id=ten and code='М-45';
  select id into m09 from public.app_materials where tenant_id=ten and code='М-09Г2С';

  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-01', 'Кронштейн', 'корпусная деталь', m40, 'Типовой маршрут корпусных деталей') returning id into t1;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-02', 'Вал', 'тел вращения', m45, 'Токарный маршрут') returning id into t2;
  insert into public.app_process_templates (tenant_id, code, name, product_type, material_id, note)
  values (ten, 'TP-03', 'Листовая деталь', 'плоская деталь', m09, 'Лазерный раскрой') returning id into t3;

  -- Шаги: операция + рекомендованное оборудование (по kind)
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 1, o.id, e.id, 45 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-01' and e.code='EQ-01';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 2, o.id, e.id, 40 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-02' and e.code='EQ-01';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 3, o.id, e.id, 25 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-05' and e.code='EQ-05';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t1, 4, o.id, e.id, 30 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-09' and e.code='EQ-04';

  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 1, o.id, e.id, 35 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-03' and e.code='EQ-02';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 2, o.id, e.id, 30 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-04' and e.code='EQ-02';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t2, 3, o.id, e.id, 25 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-07' and e.code='EQ-06';

  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t3, 1, o.id, e.id, 12 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-06' and e.code='EQ-03';
  insert into public.app_process_steps (template_id, seq, operation_id, equipment_id, plan_min)
  select t3, 2, o.id, e.id, 20 from public.app_operations o, public.app_equipment e
    where o.tenant_id=ten and e.tenant_id=ten and o.code='OP-09' and e.code='EQ-04';
end $$;
