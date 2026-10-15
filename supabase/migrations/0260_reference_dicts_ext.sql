-- ============================================================
-- 3DMP Service · 0260_reference_dicts_ext.sql  (R5 · PROP-34, расширение реестра)
-- Расширяет app_seed_reference_dicts: стойки ЧПУ (модели), языки УП, G/M-коды,
-- группы материалов, стандарты (ЕСКД/ЕСТД/ОРД/ISO), материалы инструмента,
-- упаковка, разряды, причины отказа, категории затрат, единицы, валюты, налоги, Incoterms.
-- Полный реестр — docs/REFERENCE_DATA.md. Идемпотентно (create or replace). Зависит от 0080/0259.
-- ============================================================

create or replace function public.app_seed_reference_dicts(p_token uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; did uuid; cnt int := 0; d record; r record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if ten is null then raise exception 'Организация не определена'; end if;

  -- 1) словари (code → name)
  for d in select * from (values
      ('machine_kinds','Виды оборудования'),
      ('cnc_systems','Системы ЧПУ'),
      ('cnc_models','Модели стоек ЧПУ'),
      ('prog_langs','Языки и форматы УП'),
      ('g_codes','G-коды (ISO)'),
      ('m_codes','M-коды (ISO)'),
      ('tool_kinds','Виды инструмента'),
      ('tool_materials','Материалы режущей части'),
      ('material_groups','Группы материалов'),
      ('standards','Стандарты (ЕСКД/ЕСТД/ОРД/ISO)'),
      ('downtime_reasons','Причины простоев'),
      ('defect_kinds','Виды дефектов'),
      ('refuse_reasons','Причины отказа клиента'),
      ('cost_categories','Категории затрат'),
      ('packaging','Виды упаковки'),
      ('grades','Квалификации и разряды'),
      ('units','Единицы измерения'),
      ('currencies','Валюты'),
      ('tax_rates','Ставки налогов'),
      ('incoterms','Условия поставки (Incoterms)'),
      ('contact_channels','Каналы связи'),
      ('request_sources','Источники заявок')
    ) as v(code,name) loop
    select id into did from public.app_dictionaries where tenant_id = ten and lower(code) = lower(d.code) limit 1;
    if did is null then
      insert into public.app_dictionaries (tenant_id, code, name, description, active)
      values (ten, d.code, d.name, 'Базовый справочник (3DMP)', true) returning id into did;
      cnt := cnt + 1;
    end if;
  end loop;

  -- 2) элементы (dict_code → value,label,sort)
  for r in select * from (values
      ('machine_kinds','lathe','Токарный',10),('machine_kinds','mill','Фрезерный',20),('machine_kinds','drill','Сверлильный',30),
      ('machine_kinds','grind','Шлифовальный',40),('machine_kinds','edm','Электроэрозионный',50),('machine_kinds','laser','Лазерный',60),
      ('machine_kinds','press','Пресс',70),('machine_kinds','bend','Гибочный',80),
      ('cnc_systems','fanuc','FANUC',10),('cnc_systems','sinumerik','Siemens Sinumerik',20),('cnc_systems','heidenhain','Heidenhain',30),
      ('cnc_systems','mitsubishi','Mitsubishi',40),('cnc_systems','mazatrol','Mazak Mazatrol',50),('cnc_systems','osp','Okuma OSP',60),('cnc_systems','haas_ngc','Haas NGC',70),
      ('cnc_models','fanuc_0i','FANUC 0i',10),('cnc_models','fanuc_30i','FANUC 30i/31i',20),('cnc_models','sinumerik_828d','Sinumerik 828D',30),
      ('cnc_models','sinumerik_840d','Sinumerik 840D',40),('cnc_models','tnc_640','Heidenhain TNC 640',50),('cnc_models','m80','Mitsubishi M80',60),('cnc_models','p300','Okuma OSP-P300',70),
      ('prog_langs','iso6983','ISO-6983 (G-code)',10),('prog_langs','rs274','RS-274',20),('prog_langs','klartext','Heidenhain Klartext',30),
      ('prog_langs','mazatrol','Mazatrol',40),('prog_langs','shopmill','Sinumerik ShopMill/ShopTurn',50),('prog_langs','ips','Haas IPS (диалоговый)',60),
      ('g_codes','G00','G00 — ускоренное перемещение',10),('g_codes','G01','G01 — линейная интерполяция',20),('g_codes','G02','G02 — круговая (по ч.с.)',30),
      ('g_codes','G03','G03 — круговая (против ч.с.)',40),('g_codes','G04','G04 — пауза',50),('g_codes','G17','G17/18/19 — плоскости XY/XZ/YZ',60),
      ('g_codes','G20','G20/21 — дюймы/мм',70),('g_codes','G28','G28 — возврат в референт',80),('g_codes','G40','G40/41/42 — коррекция радиуса',90),
      ('g_codes','G43','G43 — коррекция длины инструмента',100),('g_codes','G54','G54–G59 — рабочие смещения',110),('g_codes','G80','G80–G89 — циклы обработки',120),
      ('g_codes','G90','G90/91 — абсолют/инкремент',130),('g_codes','G94','G94/95 — подача мин/об',140),('g_codes','G98','G98/99 — возврат в цикле',150),
      ('m_codes','M00','M00 — стоп',10),('m_codes','M01','M01 — опциональный стоп',20),('m_codes','M03','M03/04 — шпиндель вперёд/назад',30),
      ('m_codes','M05','M05 — стоп шпинделя',40),('m_codes','M06','M06 — смена инструмента',50),('m_codes','M08','M08/09 — СОЖ вкл/выкл',60),
      ('m_codes','M30','M02/M30 — конец программы',70),('m_codes','M98','M98/99 — вызов/возврат подпрограммы',80),
      ('tool_kinds','endmill','Концевая фреза',10),('tool_kinds','drill','Сверло',20),('tool_kinds','tap','Метчик',30),('tool_kinds','reamer','Развёртка',40),
      ('tool_kinds','turn_tool','Токарный резец',50),('tool_kinds','cutoff','Отрезной резец',60),('tool_kinds','boring','Расточная головка',70),
      ('tool_materials','hss','HSS (быстрорежущая)',10),('tool_materials','carbide','Твёрдый сплав',20),('tool_materials','cbn','CBN',30),('tool_materials','diamond','Алмаз',40),('tool_materials','ceramic','Керамика',50),
      ('material_groups','steel_carbon','Сталь конструкционная',10),('material_groups','steel_alloy','Сталь легированная',20),('material_groups','steel_tool','Сталь инструментальная',30),
      ('material_groups','stainless','Нержавеющая сталь',40),('material_groups','cast_iron','Чугун',50),('material_groups','aluminum','Алюминий',60),
      ('material_groups','copper','Медь/латунь',70),('material_groups','titanium','Титан',80),('material_groups','plastic','Пластмассы',90),
      ('standards','gost_eskd','ЕСКД (ГОСТ 2.xxx)',10),('standards','gost_estd','ЕСТД (ГОСТ 3.xxx)',20),('standards','gost_ord','ОРД (ГОСТ Р 7.0.97-2016)',30),
      ('standards','iso6983','ISO 6983 (ЧПУ)',40),('standards','iso9001','ISO 9001',50),
      ('downtime_reasons','no_material','Нет материала',10),('downtime_reasons','breakdown','Поломка',20),('downtime_reasons','setup','Переналадка',30),
      ('downtime_reasons','no_program','Нет программы',40),('downtime_reasons','no_operator','Нет оператора',50),('downtime_reasons','maintenance','Плановое ТО',60),
      ('defect_kinds','size','Размер',10),('defect_kinds','roughness','Шероховатость',20),('defect_kinds','crack','Трещина',30),('defect_kinds','scratch','Задир',40),
      ('defect_kinds','porosity','Раковина',50),('defect_kinds','runout','Биение',60),('defect_kinds','burr','Заусенец',70),
      ('refuse_reasons','price','Цена',10),('refuse_reasons','term','Срок',20),('refuse_reasons','quality','Качество',30),('refuse_reasons','competitors','Конкуренты',40),
      ('refuse_reasons','budget','Бюджет',50),('refuse_reasons','no_contact','Нет ответа',60),
      ('cost_categories','material','Материал',10),('cost_categories','labor','Оплата труда',20),('cost_categories','overhead','Накладные',30),('cost_categories','energy','Энергия',40),
      ('cost_categories','tooling','Инструмент',50),('cost_categories','depreciation','Амортизация',60),('cost_categories','transport','Транспорт',70),('cost_categories','other','Прочие',80),
      ('packaging','box','Коробка',10),('packaging','pallet','Паллета',20),('packaging','crate','Ящик',30),('packaging','frame','Обрешётка',40),('packaging','container','Контейнер',50),('packaging','none','Без упаковки',60),
      ('grades','grade1','1 разряд',10),('grades','grade2','2 разряд',20),('grades','grade3','3 разряд',30),('grades','grade4','4 разряд',40),('grades','grade5','5 разряд',50),('grades','grade6','6 разряд',60),
      ('grades','engineer','Инженер-технолог',70),('grades','master','Мастер',80),('grades','setter','Наладчик',90),('grades','cnc_op','Оператор ЧПУ',100),('grades','qc','Контролёр ОТК',110),
      ('units','pcs','шт',10),('units','kg','кг',20),('units','m','м',30),('units','mm','мм',40),('units','m2','м²',50),('units','m3','м³',60),
      ('units','l','л',70),('units','min','мин',80),('units','hour','ч',90),('units','set','комплект',100),
      ('currencies','RUB','Российский рубль',10),('currencies','USD','Доллар США',20),('currencies','EUR','Евро',30),('currencies','CNY','Юань',40),
      ('tax_rates','vat0','0 %',10),('tax_rates','vat5','5 %',20),('tax_rates','vat7','7 %',30),('tax_rates','vat10','10 %',40),('tax_rates','vat20','20 %',50),
      ('incoterms','EXW','EXW — самовывоз',10),('incoterms','FCA','FCA — франко-перевозчик',20),('incoterms','FOB','FOB — франко-борт',30),
      ('incoterms','CIF','CIF — стоимость, страхование, фрахт',40),('incoterms','DAP','DAP — поставка в месте',50),('incoterms','DDP','DDP — поставка с оплатой пошлин',60),
      ('contact_channels','phone','Телефон',10),('contact_channels','email','E-mail',20),('contact_channels','telegram','Telegram',30),('contact_channels','whatsapp','WhatsApp',40),('contact_channels','chat','Чат на сайте',50),
      ('request_sources','site','Сайт',10),('request_sources','phone','Телефон',20),('request_sources','email','E-mail',30),('request_sources','manager','Менеджер',40),('request_sources','dealer','Дилер',50),('request_sources','tender','Тендер',60)
    ) as v(dict_code, value, label, sort) loop
    select id into did from public.app_dictionaries where tenant_id = ten and lower(code) = lower(r.dict_code) limit 1;
    if did is not null and not exists (select 1 from public.app_dictionary_items i where i.dict_id = did and lower(i.value) = lower(r.value)) then
      insert into public.app_dictionary_items (dict_id, value, label, sort) values (did, r.value, r.label, r.sort);
    end if;
  end loop;

  return cnt;
end $$;

grant execute on function public.app_seed_reference_dicts(uuid) to anon, authenticated;
