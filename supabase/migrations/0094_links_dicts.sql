-- ============================================================
-- 3DMP Service · 0094_links_dicts.sql  (v72 — Пункт 4: словари для модулей)
-- Единые справочники для выпадающих списков: виды статей ТЭО, процессы
-- маркетплейса, категории операций нормирования. Идемпотентно. 0001..0093.
-- ============================================================

do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; did uuid;
begin
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='teo_line_kind') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'teo_line_kind','Виды статей ТЭО',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'metal','Металл',10),(did,'consumables','Расходники',20),(did,'labor','Работы',30),(did,'service','Услуги',40),(did,'other','Прочее',50);
  end if;
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='marketplace_process') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'marketplace_process','Процессы (маркетплейс)',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'cnc','ЧПУ',10),(did,'edm','ЭЭО',20),(did,'grinding','Шлифование',30),(did,'heat','Термообработка',40),
      (did,'assembly','Сборка',50),(did,'engraving','Гравирование',60),(did,'other','Прочее',70);
  end if;
  if not exists (select 1 from public.app_dictionaries where tenant_id=A and lower(code)='norms_category') then
    insert into public.app_dictionaries (tenant_id, code, name, description) values (A,'norms_category','Категории операций',null) returning id into did;
    insert into public.app_dictionary_items (dict_id, value, label, sort) values
      (did,'milling','Фрезерная',10),(did,'turning','Токарная',20),(did,'edm','ЭЭО',30),(did,'grinding','Шлифование',40),
      (did,'locksmith','Слесарная',50),(did,'engraving','Гравирование',60),(did,'heat','Термообработка',70),(did,'other','Прочее',80);
  end if;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Связки: словари для модулей',
   'Типы статей ТЭО, процессы маркетплейса и категории операций нормирования берутся из настраиваемых справочников (dicts) через app_dict_items_by_code — единый источник значений и подписей.',
   'связки словари ТЭО маркетплейс нормирование app_dict_items_by_code')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Связки: словари для модулей');
