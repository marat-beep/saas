-- ============================================================
-- 3DMP Service · 0220_ref_assets.sql
-- Типовой парк оборудования (ЧПУ: 3/5-осевые, токарные, ЭЭО, шлифовальные)
-- и словари (операции, единицы, покрытия, термообработка, профессии, группы
-- материалов, приоритеты). Глобально (tenant_id = null). Зависит от 0001..0219.
-- ============================================================

-- ---------- Типовой парк оборудования ----------
insert into public.app_ref_machines (tenant_id, manufacturer, model, kind, axes, max_x, max_y, max_z, spindle_rpm, spindle_kw, accuracy, note)
select null, v.mf, v.model, v.kind, v.ax, v.x, v.y, v.z, v.rpm, v.kw, v.acc, v.note
from (values
 ('Типовой','Фрезерный вертикальный 3-осевой','frezerny',3,800,500,500,8000,15,0.010,'Универсальный ЧПУ для корпусных деталей.'),
 ('Типовой','Фрезерный портальный','frezerny',3,3000,1500,800,6000,30,0.015,'Крупные плиты, матрицы.'),
 ('Типовой','Обрабатывающий центр 5-осевой','frezerny',5,600,500,500,12000,25,0.005,'Сложные поверхности, формообразование.'),
 ('Типовой','Токарный с ЧПУ','tokarny',2,200,500,null,4000,15,0.010,'Валы, втулки, пуансоны.'),
 ('Типовой','Токарно-фрезерный центр','tokarny',5,300,600,null,5000,22,0.008,'За один установа, сложные тела вращения.'),
 ('Типовой','Проволочно-вырезной ЭЭО','edm',5,400,300,250,null,null,0.003,'Wire EDM: точность и чистота выше.'),
 ('Типовой','Копировально-прошивной ЭЭО','edm',3,500,400,400,null,null,0.005,'Sinker EDM: полости штампов.'),
 ('Типовой','Супердрель (ЭЭО-сверление)','edm',1,null,null,300,null,null,0.010,'Мелкие глубокие отверстия.'),
 ('Типовой','Плоскошлифовальный','shlifovalny',3,600,300,400,3000,7,0.003,'Базы, плоскости, точность IT6.'),
 ('Типовой','Круглошлифовальный','shlifovalny',2,null,null,750,null,7,0.003,'Валы, цилиндры (DхL).'),
 ('Типовой','Внутришлифовальный','shlifovalny',2,null,null,200,null,5,0.003,'Отверстия H7.'),
 ('Типовой','Сверлильно-фрезерный с ЧПУ','sverlilny',3,600,400,400,6000,7,0.020,'Отверстия, резьба, пазы.'),
 ('Типовой','Ленточнопильный','zagotov',3,800,400,null,null,3,null,'Резка заготовок +2-8 мм.'),
 ('Типовой','Гравировальный ЧПУ','graverka',3,600,400,200,24000,3,0.010,'Маркировка, клише, текстуры.'),
 ('Типовой','Вакуумная термическая печь','heat',null,null,null,null,null,60,null,'Закалка/отпуск/цементация HRC 58-62.'),
 ('Типовой','Гидравлический пресс','press',null,null,null,null,null,null,null,'Сборка/штамповка, усилие, т.')
) v(mf,model,kind,ax,x,y,z,rpm,kw,acc,note)
where not exists (select 1 from public.app_ref_machines m where m.tenant_id is null and m.model = v.model);

-- ---------- Словари ----------
insert into public.app_dictionaries (tenant_id, code, name, description)
select null, v.c, v.n, v.d from (values
 ('operations','Операции обработки','Технологические операции механообработки.'),
 ('units','Единицы измерения','шт/кг/м/мм/ч/компл и т.д.'),
 ('coatings','Покрытия инструмента','TiN/TiAlN/AlCrN/DLC…'),
 ('heat','Термообработка','Закалка/отпуск/цементация/азотирование…'),
 ('professions','Профессии','Оператор ЧПУ, наладчик, технолог…'),
 ('material_group','Группы материалов','Сталь/нерж/алюминий/титан…'),
 ('priority','Приоритеты','Срочный/Высокий/Обычный/Низкий.')
) v(c,n,d)
where not exists (select 1 from public.app_dictionaries dd where dd.tenant_id is null and lower(dd.code) = lower(v.c));

insert into public.app_dictionary_items (dict_id, value, label, sort, active)
select d.id, v.val, v.lbl, v.s, true
from public.app_dictionaries d
join (values
 ('operations','milling3','Фрезеровка 3-осевая',1),('operations','milling4','Фрезеровка 4-осевая',2),('operations','milling5','Фрезеровка 5-осевая',3),
 ('operations','turning','Токарная',4),('operations','turning_milling','Токарно-фрезерная',5),('operations','edm_wire','Эрозия проволочная',6),
 ('operations','edm_die','Эрозия прошивная',7),('operations','edm_drill','Супердрель',8),('operations','grinding_flat','Шлифование плоское',9),
 ('operations','grinding_profile','Шлифование профильное',10),('operations','locksmith','Слесарка/сборка',11),('operations','engraving','Гравировка/клише',12),
 ('units','pcs','шт',1),('units','kg','кг',2),('units','m','м',3),('units','mm','мм',4),('units','hour','ч',5),('units','set','компл',6),('units','l','л',7),('units','m2','м²',8),('units','m3','м³',9),
 ('coatings','TiN','TiN (нитрид титана)',1),('coatings','TiCN','TiCN',2),('coatings','TiAlN','TiAlN',3),('coatings','AlTiN','AlTiN',4),('coatings','AlCrN','AlCrN',5),('coatings','ZrN','ZrN',6),('coatings','DLC','DLC',7),
 ('heat','hardening','Закалка',1),('heat','tempering','Отпуск',2),('heat','carburizing','Цементация',3),('heat','nitriding','Азотирование',4),('heat','induction','Закалка ТВЧ',5),('heat','aging','Старение',6),('heat','annealing','Отжиг',7),
 ('professions','cnc_operator','Оператор ЧПУ',1),('professions','setter','Наладчик',2),('professions','technologist','Технолог',3),('professions','inspector','Контролёр ОТК',4),('professions','locksmith','Слесарь',5),('professions','toolmaker','Инструментальщик',6),('professions','master','Мастер',7),
 ('material_group','steel','Сталь конструкционная',1),('material_group','tool_steel','Сталь инструментальная',2),('material_group','stainless','Нержавеющая',3),('material_group','aluminum','Алюминий',4),('material_group','copper_alloy','Медь/латунь/бронза',5),('material_group','titanium','Титан',6),('material_group','cast_iron','Чугун',7),('material_group','plastic','Пластик/эластомер',8),
 ('priority','urgent','Срочный',1),('priority','high','Высокий',2),('priority','normal','Обычный',3),('priority','low','Низкий',4)
) v(code,val,lbl,s) on lower(d.code) = lower(v.code)
where d.tenant_id is null
  and not exists (select 1 from public.app_dictionary_items it where it.dict_id = d.id and it.value = v.val);

-- ---------- БЗ ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags from (values
 ('Производство','Типовой парк ЧПУ-оборудования','3-осевые фрезерные (корпусные), 5-осевые ОЦ (сложные поверхности), токарные/токарно-фрезерные, проволочная/прошивная ЭЭО, плоско-/кругло-/внутришлифовальные, супердрель, гравировальный, вакуумная печь, пресс. Точности: фрез. 0.01, 5-ось 0.005, ЭЭО 0.003-0.005, шлиф. 0.003.','оборудование ЧПУ 5 осей ЭЭО шлифование токарный парк'),
 ('Производство','Операции механообработки (справочник)','Фрезеровка 3/4/5-осевая, Токарная, Токарно-фрезерная, Эрозия проволочная/прошивная, Супердрель, Шлифование плоское/профильное, Слесарка/сборка, Гравировка. См. словарь «Операции обработки».','операции фрезеровка токарная ээо шлифование слесарка')
) v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.tenant_id is null and k.question = v.question);
