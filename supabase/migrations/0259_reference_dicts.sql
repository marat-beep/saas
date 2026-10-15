-- ============================================================
-- 3DMP Service · 0259_reference_dicts.sql  (R5 · базовые справочники)
-- RPC-сид базовых настраиваемых справочников ДЛЯ ТЕКУЩЕЙ организации (tenant),
-- идемпотентно (повтор не создаёт дублей). Список — docs/REFERENCE_DATA.md.
-- Вызывается из «Справочники» кнопкой «Загрузить базовые». Зависит от 0080.
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
      ('tool_kinds','Виды инструмента'),
      ('downtime_reasons','Причины простоев'),
      ('defect_kinds','Виды дефектов'),
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
      ('machine_kinds','lathe','Токарный',10),
      ('machine_kinds','mill','Фрезерный',20),
      ('machine_kinds','drill','Сверлильный',30),
      ('machine_kinds','grind','Шлифовальный',40),
      ('machine_kinds','edm','Электроэрозионный',50),
      ('machine_kinds','laser','Лазерный',60),
      ('machine_kinds','press','Пресс',70),
      ('machine_kinds','bend','Гибочный',80),
      ('cnc_systems','fanuc','FANUC',10),
      ('cnc_systems','sinumerik','Siemens Sinumerik',20),
      ('cnc_systems','heidenhain','Heidenhain',30),
      ('cnc_systems','mitsubishi','Mitsubishi',40),
      ('cnc_systems','mazatrol','Mazak Mazatrol',50),
      ('cnc_systems','osp','Okuma OSP',60),
      ('cnc_systems','haas_ngc','Haas NGC',70),
      ('tool_kinds','endmill','Концевая фреза',10),
      ('tool_kinds','drill','Сверло',20),
      ('tool_kinds','tap','Метчик',30),
      ('tool_kinds','reamer','Развёртка',40),
      ('tool_kinds','turn_tool','Токарный резец',50),
      ('tool_kinds','cutoff','Отрезной резец',60),
      ('tool_kinds','boring','Расточная головка',70),
      ('downtime_reasons','no_material','Нет материала',10),
      ('downtime_reasons','breakdown','Поломка',20),
      ('downtime_reasons','setup','Переналадка',30),
      ('downtime_reasons','no_program','Нет программы',40),
      ('downtime_reasons','no_operator','Нет оператора',50),
      ('downtime_reasons','maintenance','Плановое ТО',60),
      ('defect_kinds','size','Размер',10),
      ('defect_kinds','roughness','Шероховатость',20),
      ('defect_kinds','crack','Трещина',30),
      ('defect_kinds','scratch','Задир',40),
      ('defect_kinds','porosity','Раковина',50),
      ('defect_kinds','runout','Биение',60),
      ('defect_kinds','burr','Заусенец',70),
      ('contact_channels','phone','Телефон',10),
      ('contact_channels','email','E-mail',20),
      ('contact_channels','telegram','Telegram',30),
      ('contact_channels','whatsapp','WhatsApp',40),
      ('contact_channels','chat','Чат на сайте',50),
      ('request_sources','site','Сайт',10),
      ('request_sources','phone','Телефон',20),
      ('request_sources','email','E-mail',30),
      ('request_sources','manager','Менеджер',40),
      ('request_sources','dealer','Дилер',50),
      ('request_sources','tender','Тендер',60)
    ) as v(dict_code, value, label, sort) loop
    select id into did from public.app_dictionaries where tenant_id = ten and lower(code) = lower(r.dict_code) limit 1;
    if did is not null and not exists (select 1 from public.app_dictionary_items i where i.dict_id = did and lower(i.value) = lower(r.value)) then
      insert into public.app_dictionary_items (dict_id, value, label, sort) values (did, r.value, r.label, r.sort);
    end if;
  end loop;

  return cnt;
end $$;

grant execute on function public.app_seed_reference_dicts(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Справка','Базовые справочники: виды оборудования, системы ЧПУ, инструмент, причины простоев, дефекты',
   'В «Настраиваемых справочниках» есть кнопка «Загрузить базовые»: она создаёт для организации типовые справочники — виды оборудования, системы ЧПУ (FANUC, Sinumerik, Heidenhain, Mitsubishi, Mazatrol, OSP, Haas), виды инструмента, причины простоев, виды дефектов, каналы связи, источники заявок. Повторный запуск не создаёт дублей.',
   'справочники базовые оборудование ЧПУ инструмент простои дефекты каналы заявки сид')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
