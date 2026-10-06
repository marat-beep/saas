-- ============================================================
-- 3DMP Service · 0050_ref_tech.sql  (v31.1 — технические справочники, пакет 1)
-- Режимы резания, режущий инструмент, каталог оборудования (по данным предприятия).
-- Глобальные справочники (tenant_id null). База знаний. Зависит от 0001..0049.
-- ============================================================

-- ---------- Режимы резания ----------
create table if not exists public.app_ref_cutting (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  material_group text not null,
  operation text not null,
  tool_type text,
  tool_material text,
  vc numeric, feed numeric, ap numeric, ae numeric,
  cooling text, note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_cutting_idx on public.app_ref_cutting (material_group, operation);
alter table public.app_ref_cutting enable row level security;

-- ---------- Режущий инструмент ----------
create table if not exists public.app_ref_tools (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  tool_type text not null,
  designation text,
  material text,
  coating text,
  diameter numeric,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_tools_idx on public.app_ref_tools (tool_type);
alter table public.app_ref_tools enable row level security;

-- ---------- Каталог оборудования ----------
create table if not exists public.app_ref_machines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  manufacturer text,
  model text not null,
  kind text,
  axes integer,
  max_x numeric, max_y numeric, max_z numeric,
  spindle_rpm integer, spindle_kw numeric,
  accuracy numeric, price numeric, note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_machines_idx on public.app_ref_machines (kind);
alter table public.app_ref_machines enable row level security;

-- ---------- RPC ----------
create or replace function public.app_ref_cutting_list(p_token uuid, p_group text default null, p_q text default null)
returns table (id uuid, material_group text, operation text, tool_type text, tool_material text,
               vc numeric, feed numeric, ap numeric, ae numeric, cooling text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select c.id, c.material_group, c.operation, c.tool_type, c.tool_material, c.vc, c.feed, c.ap, c.ae, c.cooling, c.note
    from public.app_ref_cutting c
    where (c.tenant_id is null or c.tenant_id = ten)
      and (p_group is null or p_group='' or c.material_group = p_group)
      and (qq='' or lower(c.operation) like '%'||qq||'%' or lower(coalesce(c.tool_type,'')) like '%'||qq||'%' or lower(coalesce(c.note,'')) like '%'||qq||'%')
    order by c.material_group, c.operation;
end $$;

create or replace function public.app_ref_tools_list(p_token uuid, p_q text default null)
returns table (id uuid, tool_type text, designation text, material text, coating text, diameter numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.tool_type, t.designation, t.material, t.coating, t.diameter, t.note
    from public.app_ref_tools t
    where (t.tenant_id is null or t.tenant_id = ten)
      and (qq='' or lower(t.tool_type) like '%'||qq||'%' or lower(coalesce(t.designation,'')) like '%'||qq||'%' or lower(coalesce(t.material,'')) like '%'||qq||'%')
    order by t.tool_type, t.diameter;
end $$;

create or replace function public.app_ref_machines_list(p_token uuid, p_q text default null)
returns table (id uuid, manufacturer text, model text, kind text, axes integer, max_x numeric, max_y numeric, max_z numeric,
               spindle_rpm integer, spindle_kw numeric, accuracy numeric, price numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select m.id, m.manufacturer, m.model, m.kind, m.axes, m.max_x, m.max_y, m.max_z, m.spindle_rpm, m.spindle_kw, m.accuracy, m.price, m.note
    from public.app_ref_machines m
    where (m.tenant_id is null or m.tenant_id = ten)
      and (qq='' or lower(m.model) like '%'||qq||'%' or lower(coalesce(m.manufacturer,'')) like '%'||qq||'%' or lower(coalesce(m.kind,'')) like '%'||qq||'%')
    order by m.kind, m.model;
end $$;

grant execute on function public.app_ref_cutting_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_tools_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_machines_list(uuid,text) to anon, authenticated;

-- ---------- Наполнение: режимы резания ----------
insert into public.app_ref_cutting (tenant_id, material_group, operation, tool_type, tool_material, vc, feed, ap, ae, cooling, note)
select null, v.mg, v.op, v.tt, v.tm, v.vc, v.feed, v.ap, v.ae, v.cool, v.note
from (values
  ('steel','Фрезерование','Концевая фреза','твердосплав',120,0.05,2,10,'СОЖ эмульсия','Черновая, сталь конструкционная'),
  ('steel','Фрезерование','Концевая фреза','твердосплав+TIAIN',200,0.03,0.5,10,'СОЖ эмульсия','Чистовая'),
  ('steel','Точение','Резец проходной','твердосплав',180,0.25,2,null,'СОЖ эмульсия','Черновая'),
  ('steel','Точение','Резец проходной','твердосплав',260,0.10,0.5,null,'СОЖ эмульсия','Чистовая'),
  ('steel','Сверление','Сверло спиральное','HSS-Co',25,0.15,null,null,'СОЖ эмульсия',''),
  ('steel','Сверление','Сверло спиральное','твердосплав',70,0.20,null,null,'СОЖ эмульсия',''),
  ('tool_steel','Фрезерование','Концевая фреза','твердосплав+TIAIN',80,0.04,1,8,'СОЖ эмульсия','HRC до 32'),
  ('tool_steel','Фрезерование','Концевая фреза','твердосплав+ALCRN',50,0.03,0.5,6,'СОЖ эмульсия','HRC 32-45'),
  ('tool_steel','ЭЭО проволочная','Проволока латунная',null,null,null,null,null,'диэлектрик','Ø0.25 мм, HRC>45'),
  ('tool_steel','Шлифование','Круг шлифовальный','электрокорунд',30,null,0.02,null,'СОЖ','Плоское/круглое'),
  ('stainless','Точение','Резец проходной','твердосплав',90,0.15,1.5,null,'СОЖ эмульсия','Нержавейка, склонность к наклёпу'),
  ('stainless','Фрезерование','Концевая фреза','твердосплав',70,0.04,1,8,'СОЖ эмульсия',''),
  ('aluminum','Фрезерование','Концевая фреза','твердосплав',300,0.10,3,12,'СОЖ эмульсия/туман','Высокие обороты'),
  ('aluminum','Точение','Резец проходной','твердосплав',400,0.30,2,null,'СОЖ эмульсия',''),
  ('aluminum','Сверление','Сверло спиральное','HSS',60,0.20,null,null,'СОЖ эмульсия',''),
  ('cast_iron','Фрезерование','Торцевая фреза','твердосплав',150,0.15,2,30,'без СОЖ/туман',''),
  ('cast_iron','Точение','Резец проходной','твердосплав',120,0.25,2,null,'без СОЖ',''),
  ('bronze','Точение','Резец проходной','твердосплав',200,0.20,1.5,null,'СОЖ эмульсия','Втулки/направляющие'),
  ('plastic','Фрезерование','Концевая фреза','HSS',300,0.15,3,15,'без СОЖ','Охлаждение воздухом')
) as v(mg, op, tt, tm, vc, feed, ap, ae, cool, note)
where not exists (select 1 from public.app_ref_cutting where tenant_id is null);

-- ---------- Наполнение: инструмент ----------
insert into public.app_ref_tools (tenant_id, tool_type, designation, material, coating, diameter, note)
select null, v.tool_type, v.designation, v.material, v.coating, v.diameter, v.note
from (values
  ('Концевая фреза','ФК 10×20×75','твердосплав','TIAIN',10,'4 зуба'),
  ('Концевая фреза','ФК 6×20×60','твердосплав','ALCRN',6,'4 зуба'),
  ('Концевая фреза','ФК 12×30×80','твердосплав','TIAIN',12,'4 зуба'),
  ('Торцевая фреза','ФТ 63','твердосплав','TIAIN',63,'5 пластин'),
  ('Сверло','Ø8.5 HSS-Co','HSS-Co','—',8.5,'под М10'),
  ('Сверло','Ø10.2 HSS-Co','HSS-Co','—',10.2,'под М12'),
  ('Метчик','М10×1.5','HSS','—',10,'машинный'),
  ('Метчик','М12×1.75','HSS','—',12,'машинный'),
  ('Развёртка','Ø12 H7','HSS','—',12,'ручная/машинная'),
  ('Резец','DCGT 11T3','твердосплав','TIAIN',null,'точение чист.'),
  ('Резец','CNMG 120408','твердосплав','CVD',null,'точение черн.'),
  ('Проволока ЭЭО','Ø0.25 латунь','латунь','—',0.25,'проволочно-вырезной'),
  ('Электрод ЭЭО','медь М1 Ø10','медь','—',10,'прошивной'),
  ('Круг шлифовальный','ПП 250×25','электрокорунд','—',250,'плоское шлифование')
) as v(tool_type, designation, material, coating, diameter, note)
where not exists (select 1 from public.app_ref_tools where tenant_id is null);

-- ---------- Наполнение: оборудование ----------
insert into public.app_ref_machines (tenant_id, manufacturer, model, kind, axes, max_x, max_y, max_z, spindle_rpm, spindle_kw, accuracy, price, note)
select null, v.man, v.model, v.kind, v.ax, v.x, v.y, v.z, v.rpm, v.kw, v.acc, v.price, v.note
from (values
  ('Feeler','FTC-350Xl','Токарный ЧПУ',2,350,0,500,4000,15,0.010,4500000,'Токарная обработка'),
  ('Focus','Focus Turn','Токарный ЧПУ',2,300,0,450,4500,11,0.010,3200000,'Токарная обработка'),
  ('Chevalier','QP2440','Фрезерный ЧПУ',3,1000,500,500,8000,7.5,0.010,3500000,'Фрезерная обработка'),
  ('Pinnacle','SV-65','Фрезерный ЧПУ',3,1270,635,610,8000,11,0.010,4200000,'Фрезерная обработка'),
  ('Chevalier','QP2440-L','Фрезерный ЧПУ',3,1200,600,600,8000,11,0.008,4600000,'Фрезерная, длинные детали'),
  ('Chevalier','QP5x-400','Фрезерный ЧПУ',3,800,500,400,10000,7.5,0.008,3800000,'Прецизионная фрезерная'),
  ('Chevalier','SMART B-1224 II','Плоскошлифовальный',2,600,300,0,3000,5.5,0.005,2800000,'Плоское шлифование'),
  ('WASINO','GLS-130AN','Круглошлифовальный',2,300,0,500,2000,7.5,0.005,3900000,'Круглое шлифование'),
  ('Overbeck','400RU','Внутришлифовальный',2,200,0,300,4000,5.5,0.003,4200000,'Внутреннее шлифование'),
  ('FCL','FCL-1220','Шлифовальный',2,500,250,0,3000,5.5,0.005,2200000,'Шлифование'),
  ('Mitsubishi','FA10-VS','ЭЭО проволочно-вырезной',5,400,320,250,0,0,0.005,5200000,'Проволочная ЭЭО'),
  ('Mitsubishi','BA-8','ЭЭО прошивной',2,400,300,300,0,0,0.005,4800000,'Прошивная ЭЭО'),
  ('Sodick','Aa300','ЭЭО прошивной',2,300,250,250,0,0,0.004,4400000,'Прошивная ЭЭО'),
  ('Sodick','A325','ЭЭО прошивной',2,350,300,300,0,0,0.004,4900000,'Прошивная ЭЭО'),
  ('INGERSOLL','Gantry 500','ЭЭО/обрабатывающий',3,500,400,400,0,0,0.005,6500000,'Крупногабаритная ЭЭО')
) as v(man, model, kind, ax, x, y, z, rpm, kw, acc, price, note)
where not exists (select 1 from public.app_ref_machines where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Режимы резания','Что содержит справочник режимов резания?',
   'Таблица «материал × операция → инструмент, Vc (м/мин), подача, глубина, СОЖ». Используется для подбора режимов, расчёта времени обработки и стоимости. Значения — стартовые, уточняются по каталогам инструмента.',
   'режимы резания Vc подача глубина СОЖ материал операция'),
  ('Инструмент','Каталог режущего инструмента',
   'Фрезы, свёрла, метчики, развёртки, резцы, проволока/электроды ЭЭО, шлифкруги — с материалом (HSS/HSS-Co/твердосплав), покрытием (TIAIN/ALCRN) и диаметром. Основа для заявок на закупку и карт наладки.',
   'инструмент фрезы сверла метчики резцы ЭЭО покрытие'),
  ('Оборудование','Каталог станков предприятия',
   'Реальные модели: Feeler FTC-350Xl, Chevalier QP2440/QP2440-L/QP5x-400/SMART B-1224 II, Pinnacle SV-65, WASINO GLS-130AN, Overbeck 400RU, Mitsubishi FA10-VS/BA-8, Sodick Aa300/A325, INGERSOLL Gantry 500. Хода, шпиндель, точность, стоимость — для подбора оборудования под операцию.',
   'оборудование станки Feeler Chevalier Pinnacle WASINO Overbeck Mitsubishi Sodick')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что содержит справочник режимов резания?');
