-- ============================================================
-- 3DMP Service · 0051_ref_norms.sql  (v31.2 — технические справочники, пакет 2)
-- Посадки ISO 286, крепёж/стандартные изделия, термообработка/покрытия, СОЖ/смазки,
-- реестр процессов предприятия (АД/ПР/ВСП). Глобальные справочники. База знаний.
-- Зависит от 0001..0050.
-- ============================================================

-- ---------- Посадки ISO 286 ----------
create table if not exists public.app_ref_fits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  nominal numeric not null,
  designation text not null,
  kind text,                -- clearance | transition | interference
  hole_dev text, shaft_dev text,
  clearance_max numeric, clearance_min numeric,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_fits_idx on public.app_ref_fits (kind);
alter table public.app_ref_fits enable row level security;

-- ---------- Крепёж / стандартные изделия ----------
create table if not exists public.app_ref_fasteners (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  standard text,
  size text,
  material text, coating text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_fasteners enable row level security;

-- ---------- Термообработка / покрытия ----------
create table if not exists public.app_ref_heat (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  material_group text,
  hardness text, depth text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_heat enable row level security;

-- ---------- СОЖ / смазки ----------
create table if not exists public.app_ref_fluids (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null,
  name text,
  purpose text, concentration text, note text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_fluids enable row level security;

-- ---------- Реестр процессов ----------
create table if not exists public.app_ref_processes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null,
  name text not null,
  category text,            -- Административный | Производственный | Вспомогательный
  stages text, inputs text, outputs text, executors text, tools text, time_norm text,
  sort integer default 0,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_processes_idx on public.app_ref_processes (category, sort);
alter table public.app_ref_processes enable row level security;

-- ---------- RPC ----------
create or replace function public.app_ref_fits_list(p_token uuid, p_kind text default null, p_q text default null)
returns table (id uuid, nominal numeric, designation text, kind text, hole_dev text, shaft_dev text, clearance_max numeric, clearance_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.nominal, f.designation, f.kind, f.hole_dev, f.shaft_dev, f.clearance_max, f.clearance_min, f.note
    from public.app_ref_fits f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (p_kind is null or p_kind='' or f.kind = p_kind)
      and (qq='' or lower(f.designation) like '%'||qq||'%')
    order by f.nominal, f.designation;
end $$;

create or replace function public.app_ref_fasteners_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, standard text, size text, material text, coating text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.kind, f.standard, f.size, f.material, f.coating, f.note
    from public.app_ref_fasteners f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (qq='' or lower(f.kind) like '%'||qq||'%' or lower(coalesce(f.standard,'')) like '%'||qq||'%' or lower(coalesce(f.size,'')) like '%'||qq||'%')
    order by f.kind, f.size;
end $$;

create or replace function public.app_ref_heat_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, material_group text, hardness text, depth text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select h.id, h.kind, h.material_group, h.hardness, h.depth, h.note
    from public.app_ref_heat h
    where (h.tenant_id is null or h.tenant_id = ten)
      and (qq='' or lower(h.kind) like '%'||qq||'%' or lower(coalesce(h.material_group,'')) like '%'||qq||'%')
    order by h.kind;
end $$;

create or replace function public.app_ref_fluids_list(p_token uuid, p_q text default null)
returns table (id uuid, kind text, name text, purpose text, concentration text, note text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select f.id, f.kind, f.name, f.purpose, f.concentration, f.note
    from public.app_ref_fluids f
    where (f.tenant_id is null or f.tenant_id = ten)
      and (qq='' or lower(f.kind) like '%'||qq||'%' or lower(coalesce(f.name,'')) like '%'||qq||'%')
    order by f.kind, f.name;
end $$;

create or replace function public.app_ref_processes_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, code text, name text, category text, stages text, inputs text, outputs text, executors text, tools text, time_norm text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select p.id, p.code, p.name, p.category, p.stages, p.inputs, p.outputs, p.executors, p.tools, p.time_norm
    from public.app_ref_processes p
    where (p.tenant_id is null or p.tenant_id = ten)
      and (p_category is null or p_category='' or p.category = p_category)
      and (qq='' or lower(p.code) like '%'||qq||'%' or lower(p.name) like '%'||qq||'%' or lower(coalesce(p.executors,'')) like '%'||qq||'%')
    order by p.sort, p.code;
end $$;

grant execute on function public.app_ref_fits_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_fasteners_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_heat_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_fluids_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_processes_list(uuid,text,text) to anon, authenticated;

-- ---------- Наполнение: посадки (пример Ø20) ----------
insert into public.app_ref_fits (tenant_id, nominal, designation, kind, hole_dev, shaft_dev, clearance_max, clearance_min, note)
select null, v.n, v.d, v.k, v.hd, v.sd, v.cmax, v.cmin, v.note
from (values
  (20,'H7/h6','clearance','+0.021/0','0/-0.013',0.034,0.013,'Плотная, центрирование'),
  (20,'H7/g6','clearance','+0.021/0','-0.007/-0.020',0.041,0.007,'Скользящая, смазка'),
  (20,'H7/f7','clearance','+0.021/0','-0.020/-0.041',0.062,0.020,'Ходовая'),
  (20,'H7/e8','clearance','+0.021/0','-0.040/-0.073',0.094,0.040,'Легкоходовая'),
  (20,'H8/d9','clearance','+0.033/0','-0.065/-0.117',0.150,0.065,'Свободная'),
  (20,'H7/k6','transition','+0.021/0','+0.015/+0.002',0.019,-0.015,'Напряжённая'),
  (20,'H7/n6','transition','+0.021/0','+0.028/+0.015',0.006,-0.028,'Плотная переходная'),
  (20,'H7/p6','interference','+0.021/0','+0.035/+0.022',-0.001,-0.035,'Прессовая лёгкая'),
  (20,'H7/s6','interference','+0.021/0','+0.048/+0.035',-0.014,-0.048,'Прессовая'),
  (20,'H11/h11','clearance','+0.130/0','0/-0.130',0.260,0.000,'Грубая')
) as v(n, d, k, hd, sd, cmax, cmin, note)
where not exists (select 1 from public.app_ref_fits where tenant_id is null);

-- ---------- Наполнение: крепёж ----------
insert into public.app_ref_fasteners (tenant_id, kind, standard, size, material, coating, note)
select null, v.kind, v.std, v.size, v.mat, v.coat, v.note
from (values
  ('Болт','ГОСТ 7798-70','М8×30','сталь 8.8','цинк','крепёж общий'),
  ('Болт','ГОСТ 7798-70','М10×40','сталь 8.8','цинк',''),
  ('Гайка','ГОСТ 5915-70','М8','сталь 8','цинк',''),
  ('Гайка','ГОСТ 5915-70','М10','сталь 8','цинк',''),
  ('Шайба','ГОСТ 11371-78','8','сталь','цинк',''),
  ('Винт','ГОСТ 17473-80','М6×20','сталь','оксид','с полукруглой головкой'),
  ('Шпилька','ГОСТ 22032-76','М10×60','сталь 8.8','цинк',''),
  ('Шпонка призматическая','ГОСТ 23360-78','6×6×20','сталь 45','—',''),
  ('Штифт цилиндрический','ГОСТ 3128-70','Ø6×30','сталь','—','фиксация'),
  ('Подшипник','ГОСТ 3478-2012','6204','подшипниковая сталь','—','20×47×14'),
  ('Подшипник','ГОСТ 3478-2012','6205','подшипниковая сталь','—','25×52×15'),
  ('Пружина сжатия','ГОСТ 13764-86','—','65Г','—','по каталогу'),
  ('Кольцо стопорное','ГОСТ 13940-86','Ø20','пружинная сталь','—','')
) as v(kind, std, size, mat, coat, note)
where not exists (select 1 from public.app_ref_fasteners where tenant_id is null);

-- ---------- Наполнение: термообработка/покрытия ----------
insert into public.app_ref_heat (tenant_id, kind, material_group, hardness, depth, note)
select null, v.kind, v.mg, v.hard, v.depth, v.note
from (values
  ('Отжиг','углеродистые/легированные стали','—','—','снятие напряжений, снижение твёрдости'),
  ('Нормализация','конструкционные стали','HB 170-220','—','структурная подготовка'),
  ('Закалка','инструментальные стали','HRC 58-63','—','нагрев + охлаждение'),
  ('Отпуск','инструментальные стали','HRC по назначению','—','после закалки'),
  ('Улучшение','конструкционные стали','HB 220-280','—','закалка + высокий отпуск'),
  ('Цементация','стали 20/20Х','HRC 56-62','0.8-1.2 мм','науглероживание поверхности'),
  ('Азотирование','легированные стали','HV 700-1000','0.2-0.5 мм','высокая поверхностная твёрдость'),
  ('ТВЧ','стали 45/40Х','HRC 50-56','1-3 мм','поверхностная закалка'),
  ('Гальваника (цинк)','любые','—','8-12 мкм','антикоррозия'),
  ('Оксидирование','любые','—','1-3 мкм','декоративно-защитное')
) as v(kind, mg, hard, depth, note)
where not exists (select 1 from public.app_ref_heat where tenant_id is null);

-- ---------- Наполнение: СОЖ/смазки ----------
insert into public.app_ref_fluids (tenant_id, kind, name, purpose, concentration, note)
select null, v.kind, v.name, v.purpose, v.conc, v.note
from (values
  ('СОЖ эмульсия','СОЖ эмульсионная','Точение/фрезерование/сверление', '5-10%','разбавление водой'),
  ('СОЖ синтетическая','СОЖ синтетическая','Высокие скорости, чистота','3-8%','биостойкая'),
  ('СОЖ полусинтетическая','СОЖ полусинтетика','Универсально','5-10%','баланс свойств'),
  ('СОЖ масляная','Масло СОЖ','Резьбонарезание, тяжёлые режимы','—','масляный туман'),
  ('Диэлектрик ЭЭО','Диэлектрик','Проволочная/прошивная ЭЭО','—','деионизованная вода/масло'),
  ('Масло','И-20А','Гидравлика, смазка','—',''),
  ('Масло','ИГСП','Направляющие','—',''),
  ('Смазка','Литол-24','Подшипники, узлы','—',''),
  ('Смазка','Циатим-201','Точные узлы','—','')
) as v(kind, name, purpose, conc, note)
where not exists (select 1 from public.app_ref_fluids where tenant_id is null);

-- ---------- Наполнение: реестр процессов ----------
insert into public.app_ref_processes (tenant_id, code, name, category, stages, inputs, outputs, executors, tools, time_norm, sort)
select null, v.code, v.name, v.cat, v.stages, v.inp, v.out, v.exec, v.tools, v.tn, v.srt
from (values
  ('АД.01','Прием заявок','Административный','Получение заявки → проверка КД → анализ → уточнение → запуск обработки','Первичные данные, чертежи (pdf/jpeg), 3D (.step/.x_t/.m3d), ТЗ','Заявка с комплектом документации','Менеджер/секретарь','ПК, e-mail','150 мин + 4К',1),
  ('АД.05','Обработка запросов на выполнение работ','Административный','Анализ → направление на производство → ТЭО → утверждение','Запрос','ТЭО, КП','Менеджер, начальник производства, гендиректор','ПК, e-mail','90 мин + 2К',2),
  ('АД.02','Выставление ТКП, счёта, договора, спецификации, калькуляции','Административный','Подготовка ТКП → отправка → оформление документов → архив','ТЭО','ТКП, счёт, договор, спецификация, калькуляция','Менеджер, бухгалтерия','ПК, e-mail','135 мин + 5К',3),
  ('АД.03','Подписание договоров','Административный','Проект → согласование → подпись → распоряжение о старте','Заявка, ТКП','Подписанный договор','Менеджер, юрист, гендиректор','ПК','145 мин + 4К',4),
  ('АД.06','Запуск заказов в работу','Административный','Старт (оплата/договор) → СХД → распоряжение → задания','Подписанный договор/оплата','Распоряжение, задания','Ответственный, начальник производства','e-mail','145 мин + 4К',5),
  ('АД.04','Обратная связь и рекламации','Административный','Опрос → ответ → анализ → корректирующие действия','Отгруженная продукция','Отзыв/рекламация, статистика','Менеджер','ПК','100 мин + 3К',6),
  ('АД.07','Кадровые документы, ОТ, воинский учёт','Административный','Запрос данных → согласия → досье','—','Досье, документы','Уполномоченный, кадры','ПК','140 мин + 4К',7),
  ('ПР.21','Внесение заказа в MES, сохранение на сервере','Производственный','Внесение данных в MES/СХД','Данные заказа','Заказ в MES','Менеджер','MES, ПК','—',8),
  ('ПР.01','Технологический расчёт: материалы и трудоёмкость','Производственный','Анализ → технология → время → ТЭО','Заявка','ТЭО, перечень материалов','Технолог, начальник производства','ПК','210 мин + 4К',9),
  ('ПР.02','Конструкторская разработка','Производственный','Модель в сборке → КД деталей → утверждение','Заявка','Конструкторская документация','Главный конструктор','CAD','—',10),
  ('ПР.03','Разработка управляющей программы (УП)','Производственный','Проверка → согласование технологии → написание → апробация','Комплект КД','УП, карта наладки','Инженер-программист','CAM','275 мин + 2Х',11),
  ('ПР.04','Закупка материалов и инструмента','Производственный','Перечень → анализ поставщиков → счета → приёмка → закрытие','Задание на закупку','Материалы/инструмент','Снабженец, бухгалтерия','e-mail, ЭДО','320 мин + 9К',12),
  ('ПР.05','Наладка станка','Производственный','Установка оснастки → привязка → пробный прогон','Задание, УП','Налаженный станок','Оператор ЧПУ','Станок','R',13),
  ('ПР.06','Заготовительная операция','Производственный','Резка/правка заготовок','Материал','Заготовки','Заготовитель','Отрезной станок','R',14),
  ('ПР.07','Токарная обработка','Производственный','Точение по УП/чертежу','Заготовка','Деталь после точения','Оператор ЧПУ','Feeler/Focus','R',15),
  ('ПР.08','Фрезерная обработка','Производственный','Фрезерование по УП','Заготовка','Деталь после фрезеровки','Оператор ЧПУ','Chevalier/Pinnacle','R',16),
  ('ПР.09','Шлифование','Производственный','Плоское/круглое/внутреннее шлифование','Деталь','Деталь после шлифования','Оператор','Chevalier/WASINO/Overbeck','R',17),
  ('ПР.10','Проволочная ЭЭО','Производственный','Вырезка контура проволокой','Деталь','Контур вырезан','Оператор ЭЭО','Mitsubishi FA10-VS','R',18),
  ('ПР.11','Прошивная ЭЭО','Производственный','Прошивка электродом','Деталь, электрод','Полость/отверстие','Оператор ЭЭО','Mitsubishi BA-8/Sodick','R',19),
  ('ПР.13','Гравирование','Производственный','Подготовка → гравирование → контроль','Деталь, задание','Маркировка выполнена','Оператор','Гравировальная установка','R',20),
  ('ПР.15','Вулканизация','Производственный','Подготовка → вулканизация','Деталь/резина','Соединение','Оператор','Вулканизатор','R',21),
  ('ПР.16','Термообработка','Производственный','Передача → обработка → контроль твёрдости','Деталь','Термообработанная деталь','Внешняя организация','Печь','R',22),
  ('ПР.12','Слесарная обработка','Производственный','Доводка, пригонка, сборка','Деталь','Деталь/узел','Слесарь','Верстак','R',23),
  ('ПР.14','Сборочная операция','Производственный','Сборка узла/штампа → примерка','Детали','Собранный узел/штамп','Слесарь-сборщик','—','R',24),
  ('ПР.22','Составление отчётов о работе','Производственный','Сбор данных → отчёт','Данные','Отчёт','Все сотрудники','ПК','—',25),
  ('ПР.24','Формирование отгрузочных документов','Производственный','Комплектование → отгрузочные документы','Готовая продукция','Отгрузочные документы','Ответственный','ПК','R',26),
  ('ПР.25','Маркировка и упаковка продукции','Производственный','Упаковка → маркировка (этикетки/бирки)','Продукция','Упакованная маркированная продукция','Упаковщик','Тара, этикетки','R',27),
  ('ПР.17','Обслуживание','Производственный','ППР, ТО оборудования','Оборудование','Работоспособное оборудование','Операторы, сервис','—','R',28),
  ('ПР.18','Сервис','Производственный','Выезд/поддержка','Заявка','Обслуженный клиент','Сервисный инженер','—','R',29),
  ('ПР.19','Ремонт','Производственный','Диагностика → ремонт','Неисправность','Отремонтированное оборудование','Сервисный инженер','—','R',30),
  ('ПР.20','Парко-хозяйственная деятельность (ПХД)','Производственный','Хозработы','—','—','Операторы','—','R',31),
  ('ПР.23','Служебная переписка','Производственный','Переписка по работе','—','—','Все сотрудники','e-mail','—',32),
  ('ВСП.01','Прием/отправка писем по e-mail','Вспомогательный','Обработка почты','—','—','Все сотрудники','e-mail','—',33),
  ('ВСП.02','Прием корреспонденции и грузов (СДЭК, Деловые линии)','Вспомогательный','Приём груза','Груз','Полученный груз','Ответственный','ТК','К',34),
  ('ВСП.03','Отправка корреспонденции и грузов','Вспомогательный','Упаковка → отправка ТК','Груз','Отправление','Ответственный','ТК','К',35)
) as v(code, name, cat, stages, inp, out, exec, tools, tn, srt)
where not exists (select 1 from public.app_ref_processes where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Посадки ISO 286','Как пользоваться справочником посадок?',
   'Таблица посадок ISO 286 (пример Ø20): тип (зазор/переход/натяг), отклонения отверстия и вала, макс/мин зазор. Используется в КД и ОТК для выбора и контроля посадок.',
   'посадки ISO 286 зазор натяг отклонения квалитет'),
  ('Крепёж','Стандартные изделия',
   'Крепёж по ГОСТ: болты, гайки, шайбы, винты, шпильки, шпонки, штифты, подшипники, пружины, стопорные кольца — с материалом и покрытием. Для спецификаций и закупок.',
   'крепёж ГОСТ болт гайка шайба шпонка подшипник'),
  ('Термообработка','Виды термообработки и покрытий',
   'Отжиг, нормализация, закалка, отпуск, улучшение, цементация, азотирование, ТВЧ, гальваника, оксидирование — с твёрдостью и глубиной. Термообработка на предприятии выполняется сторонней организацией.',
   'термообработка закалка цементация азотирование ТВЧ покрытие'),
  ('СОЖ','СОЖ и смазки',
   'СОЖ (эмульсия/синтетика/полусинтетика/масляная), диэлектрик для ЭЭО, масла И-20А/ИГСП, смазки Литол-24/Циатим-201 — назначение и концентрация.',
   'СОЖ масло смазка диэлектрик эмульсия'),
  ('Процессы','Реестр процессов предприятия',
   'Процессы АД (административные), ПР (производственные) и ВСП (вспомогательные) с этапами, входами/выходами, исполнителями, инструментами и нормой времени (K/W/F/R/X). Основа регламентов и матрицы ответственности.',
   'процессы АД ПР ВСП этапы исполнители регламент')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как пользоваться справочником посадок?');
