-- ============================================================
-- 3DMP Service · 0218_estd.sql
-- ЕСТД (ГОСТ 3.1118-82, 3.1103-2011, 3.1129-93, 3.1130-93): справочник,
-- типовые технологические маршруты «матрица/пуансон», проектирование
-- электродов ЭЭО и технологической оснастки; ЕСТД-шаблоны документов.
-- Источник содержательного блока — промт-документ по матрицам/пуансонам.
-- Идемпотентно. Зависит от 0001..0217.
-- ============================================================

-- ---------- ЕСТД: стандарты ----------
create table if not exists public.app_ref_estd (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null, title text, scope text, note text,
  created_at timestamptz not null default now(),
  unique (tenant_id, code)
);
alter table public.app_ref_estd enable row level security;
insert into public.app_ref_estd (tenant_id, code, title, scope, note)
select null, v.c, v.t, v.s, v.n from (values
 ('ГОСТ 3.1118-82','ЕСТД. Формы и правила оформления маршрутных карт','Маршрутная карта (МК), форма 2','Основной документ маршрута обработки.'),
 ('ГОСТ 3.1103-2011','ЕСТД. Основные положения','Термины, построение документов','Базовый стандарт ЕСТД.'),
 ('ГОСТ 3.1129-93','ЕСТД. Общие правила записи информации','Запись операций/переходов','Операционная карта, переходы.'),
 ('ГОСТ 3.1130-93','ЕСТД. Формы и правила оформления ведомостей','Ведомости оснастки/материалов','ВО, ВМ.'),
 ('ГОСТ 3.1404-86','ЕСТД. Обработка резанием','Кодирование операций ЧПУ','Операции механообработки.'),
 ('ГОСТ 2.108-68','ЕСКД. Спецификация','Состав изделия/оснастки','Для приспособлений.'),
 ('ГОСТ 12195-66','Призмы опорные','Оснастка: базирование','Цилиндрические детали.'),
 ('ГОСТ 13340-68','Опоры постоянные','Оснастка: установочные','С плоской головкой.'),
 ('ГОСТ 13345-78','Установы угловые','Оснастка: установка','—'),
 ('ГОСТ 4735-69','Прихваты откидные','Оснастка: зажим','Закрепление.'),
 ('ГОСТ 12947-67','Плиты базовые','Оснастка: корпус','База приспособления.')
) v(c,t,s,n)
where not exists (select 1 from public.app_ref_estd e where e.tenant_id is null and e.code = v.c);

-- ---------- Типовые технологические маршруты ----------
create table if not exists public.app_ref_tech_routes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null, name text, shape text, material text, heat text, steps jsonb, note text,
  unique (tenant_id, code)
);
alter table public.app_ref_tech_routes enable row level security;
insert into public.app_ref_tech_routes (tenant_id, code, name, shape, material, heat, steps, note)
select null, v.c, v.n, v.sh, v.m, v.h, v.st::jsonb, v.note from (values
 ('1А','Квадратная деталь, сталь с ТО','Квадрат','Сталь','есть','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+5-8","acc":"—","rough":"—"},
   {"op":"Фрезерная черновая","equip":"CNC-фрезерный","allow":"2-3","acc":"IT12-IT14","rough":"Ra 12.5"},
   {"op":"Термообработка","equip":"Вакуумная печь","allow":"—","acc":"HRC 58-62","rough":"—"},
   {"op":"Фрезерная чистовая","equip":"CNC (HSC)","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"},
   {"op":"Шлифование чистовое","equip":"Плоскошлифовальный","allow":"0.1-0.3","acc":"IT6-IT7","rough":"Ra 0.4"},
   {"op":"Проволочная ЭЭО","equip":"Wire EDM","allow":"0.05-0.3","acc":"IT6-IT7","rough":"Ra 0.8"},
   {"op":"Прошивная ЭЭО","equip":"Sinker EDM","allow":"0.1-0.5","acc":"IT8-IT9","rough":"Ra 1.6"},
   {"op":"Слесарная обработка","equip":"Ручная","allow":"—","acc":"—","rough":"Ra 0.2-0.4"}]','Матрица/пуансон квадратные.'),
 ('1Б','Квадратная деталь, сталь без ТО','Квадрат','Сталь','нет','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+3-5","acc":"—","rough":"—"},
   {"op":"Фрезерная чистовая","equip":"CNC-фрезерный","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"},
   {"op":"Шлифование чистовое","equip":"Плоскошлифовальный","allow":"0.1-0.2","acc":"IT6-IT7","rough":"Ra 0.4"},
   {"op":"Проволочная ЭЭО","equip":"Wire EDM","allow":"0.05-0.2","acc":"IT6-IT7","rough":"Ra 0.8"},
   {"op":"Прошивная ЭЭО","equip":"Sinker EDM","allow":"0.1-0.3","acc":"IT8-IT9","rough":"Ra 1.6"},
   {"op":"Слесарная обработка","equip":"Ручная","allow":"—","acc":"—","rough":"Ra 0.2-0.4"}]','—'),
 ('1В','Электрод квадратный (графит/медь)','Квадрат','Графит/медь','нет','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+2-3","acc":"—","rough":"—"},
   {"op":"Фрезерная чистовая","equip":"CNC-фрезерный","allow":"0.1-0.3","acc":"IT7-IT8","rough":"Ra 0.8-1.6"},
   {"op":"Шлифование (опция)","equip":"Плоскошлифовальный","allow":"0.05-0.1","acc":"IT6-IT7","rough":"Ra 0.2-0.4"},
   {"op":"Проволочная ЭЭО (опция)","equip":"Wire EDM","allow":"0.05-0.1","acc":"IT6-IT7","rough":"Ra 0.4-0.8"}]','Фрезерование графита Vc 300-600, аспирация, MQL.'),
 ('2А','Круглая деталь, сталь с ТО','Круг','Сталь','есть','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+3-5","acc":"—","rough":"—"},
   {"op":"Токарная черновая","equip":"Токарный ЧПУ","allow":"1.5-3","acc":"IT12-IT14","rough":"Ra 12.5"},
   {"op":"Термообработка","equip":"Вакуумная печь","allow":"—","acc":"HRC 58-62","rough":"—"},
   {"op":"Токарная чистовая","equip":"Токарный ЧПУ (CBN)","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"},
   {"op":"Шлифование чистовое","equip":"Круглошлифовальный","allow":"0.1-0.3","acc":"IT6-IT7","rough":"Ra 0.4"},
   {"op":"Проволочная ЭЭО","equip":"Wire EDM","allow":"0.05-0.2","acc":"IT6-IT7","rough":"Ra 0.8"},
   {"op":"Прошивная ЭЭО","equip":"Sinker EDM","allow":"0.1-0.3","acc":"IT8-IT9","rough":"Ra 1.6"},
   {"op":"Слесарная обработка","equip":"Ручная","allow":"—","acc":"—","rough":"Ra 0.2-0.4"}]','Пуансон круглый, вал, втулка.'),
 ('2Б','Круглая деталь, без ТО','Круг','Сталь/цветмет','нет','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+2-4","acc":"—","rough":"—"},
   {"op":"Токарная чистовая","equip":"Токарный ЧПУ","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"},
   {"op":"Шлифование чистовое","equip":"Круглошлифовальный","allow":"0.1-0.2","acc":"IT6-IT7","rough":"Ra 0.4"},
   {"op":"Проволочная ЭЭО","equip":"Wire EDM","allow":"0.05-0.2","acc":"IT6-IT7","rough":"Ra 0.8"},
   {"op":"Прошивная ЭЭО","equip":"Sinker EDM","allow":"0.1-0.3","acc":"IT8-IT9","rough":"Ra 1.6"}]','—'),
 ('2В','Электрод круглый (графит/медь)','Круг','Графит/медь','нет','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+2-3","acc":"—","rough":"—"},
   {"op":"Токарная чистовая","equip":"Токарный ЧПУ","allow":"0.1-0.3","acc":"IT7-IT8","rough":"Ra 0.8-1.6"},
   {"op":"Шлифование (опция)","equip":"Круглошлифовальный","allow":"0.05-0.1","acc":"IT6-IT7","rough":"Ra 0.2-0.4"},
   {"op":"Проволочная ЭЭО (опция)","equip":"Wire EDM","allow":"0.05-0.1","acc":"IT6-IT7","rough":"Ra 0.4-0.8"}]','—'),
 ('3','Квадратная деталь из дюрали (старение)','Квадрат','Д16Т','есть (старение)','[
   {"op":"Заготовительная","equip":"Ленточнопильный","allow":"+3-5","acc":"—","rough":"—"},
   {"op":"Фрезерная черновая","equip":"CNC-фрезерный","allow":"1.5-3","acc":"IT12-IT14","rough":"Ra 12.5"},
   {"op":"Термообработка (старение)","equip":"Печь","allow":"—","acc":"HB 100-130","rough":"—"},
   {"op":"Фрезерная чистовая","equip":"CNC (HSC)","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"},
   {"op":"Шлифование","equip":"Плоскошлифовальный","allow":"0.1-0.2","acc":"IT6-IT7","rough":"Ra 0.4"},
   {"op":"Слесарная обработка","equip":"Ручная","allow":"—","acc":"—","rough":"Ra 0.2-0.4"}]','—'),
 ('4','Полиуретановые валы','Круг','Полиуретан','нет','[
   {"op":"Токарная чистовая","equip":"Токарный ЧПУ","allow":"0.2-0.5","acc":"IT7-IT9","rough":"Ra 1.6"}]','Без ТО.')
) v(c,n,sh,m,h,st,note)
where not exists (select 1 from public.app_ref_tech_routes r where r.tenant_id is null and r.code = v.c);

-- ---------- Электроды ЭЭО (материалы/зазоры/крепление) ----------
create table if not exists public.app_ref_edm (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  category text not null, name text not null, value text, note text,
  unique (tenant_id, category, name)
);
alter table public.app_ref_edm enable row level security;
insert into public.app_ref_edm (tenant_id, category, name, value, note)
select null, v.c, v.n, v.val, v.note from (values
 ('material','Графит','стойкость высокая; обраб. отличная','Универсальный; фрезерование.'),
 ('material','Медь','стойкость средняя; обраб. хорошая','Чистовые режимы.'),
 ('material','Медно-графит','стойкость высокая','Спецрежимы.'),
 ('material','Вольфрам','стойкость очень высокая; обраб. сложная','Микрообработка; шлифование.'),
 ('gap','Черновой','МЭЗ 0.3-0.5 мм; IT10-IT12','Большой съём.'),
 ('gap','Получистовой','МЭЗ 0.15-0.3 мм; IT8-IT9','—'),
 ('gap','Чистовой','МЭЗ 0.05-0.15 мм; IT6-IT7','—'),
 ('gap','Финишный','МЭЗ 0.02-0.05 мм; IT5-IT6','—'),
 ('mounting','Цанговый патрон','точность 0.01-0.02 мм','Круглые электроды.'),
 ('mounting','Призматический зажим','точность 0.01-0.03 мм','Квадратные электроды.'),
 ('mounting','Резьбовое соединение','точность 0.05-0.1 мм','Крупные электроды.'),
 ('mounting','Магнитный патрон','точность 0.02-0.05 мм','Графитовые электроды.'),
 ('mounting','Специальная оправка','точность 0.005-0.01 мм','Сложные электроды.')
) v(c,n,val,note)
where not exists (select 1 from public.app_ref_edm e where e.tenant_id is null and e.category = v.c and e.name = v.n);

-- ---------- Оснастка (элементы/базирование/безопасность) ----------
create table if not exists public.app_ref_fixtures (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  category text not null, name text not null, purpose text, material text, standard text, note text,
  unique (tenant_id, category, name)
);
alter table public.app_ref_fixtures enable row level security;
insert into public.app_ref_fixtures (tenant_id, category, name, purpose, material, standard, note)
select null, v.c, v.n, v.p, v.m, v.std, v.note from (values
 ('element','Опоры установочные','Базирование заготовки','Сталь 20Х/У8А HRC56-60','—','Погрешность ≤0.02 мм.'),
 ('element','Зажимные устройства','Закрепление','Сталь 45/40Х','—','—'),
 ('element','Направляющие элементы','Ориентация инструмента','У8А/ХВГ','—','Кондукторные втулки.'),
 ('element','Корпус','Несущая конструкция','СЧ20/45','—','Жёсткость.'),
 ('element','Делительные устройства','Поворот/фиксация','40Х/20ХНМ','—','—'),
 ('element','Приводы','Механизация зажима','—','—','Пневмо-/гидроцилиндры.'),
 ('element','Призмы','Базирование цилиндра','—','ГОСТ 12195-66','Круглые детали.'),
 ('element','Опоры постоянные','Установочные','—','ГОСТ 13340-68','Плоские головки.'),
 ('element','Установы угловые','Установка','—','ГОСТ 13345-78','—'),
 ('element','Прихваты откидные','Зажим','—','ГОСТ 4735-69','—'),
 ('element','Плиты базовые','Корпус/база','—','ГОСТ 12947-67','—'),
 ('basing','Фрезерная (квадрат)','Плоскость+бок+торец (6 ст.св.)','—','—','Призмы+прихваты; ε≤0.03 мм.'),
 ('basing','Токарная (круг)','Наружный цилиндр+торец','—','—','Патрон+центр; люнет при L/D>10.'),
 ('safety','Коэффициент запаса K','2.5-3.0 черновая; 1.5-2.0 чистовая/шлифование','—','—','Q=K·P/(f·i); f=0.1-0.15.'),
 ('safety','Усилия ручных зажимов','Эксцентрик ≤220 Н; гайка-барашек ≤100 Н','—','—','Безопасность.')
) v(c,n,p,m,std,note)
where not exists (select 1 from public.app_ref_fixtures f where f.tenant_id is null and f.category = v.c and f.name = v.n);

-- ---------- RPC ----------
create or replace function public.app_ref_estd_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, title text, scope text, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid; q text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  q := lower(coalesce(trim(p_q),''));
  return query select e.id, e.code, e.title, e.scope, e.note from public.app_ref_estd e
   where (e.tenant_id is null or e.tenant_id = ten or adm)
     and (q='' or lower(e.code||' '||coalesce(e.title,'')||' '||coalesce(e.scope,'')) like '%'||q||'%')
   order by e.code;
end $$;

create or replace function public.app_ref_tech_routes_list(p_token uuid)
returns table (id uuid, code text, name text, shape text, material text, heat text, steps jsonb, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.code, r.name, r.shape, r.material, r.heat, r.steps, r.note from public.app_ref_tech_routes r
   where (r.tenant_id is null or r.tenant_id = ten or adm) order by r.code;
end $$;

create or replace function public.app_ref_edm_list(p_token uuid, p_category text default null)
returns table (id uuid, category text, name text, value text, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid; cat text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  cat := nullif(trim(coalesce(p_category,'')),'');
  return query select e.id, e.category, e.name, e.value, e.note from public.app_ref_edm e
   where (e.tenant_id is null or e.tenant_id = ten or adm) and (cat is null or e.category = cat)
   order by e.category, e.name;
end $$;

create or replace function public.app_ref_fixtures_list(p_token uuid, p_category text default null)
returns table (id uuid, category text, name text, purpose text, material text, standard text, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid; cat text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  cat := nullif(trim(coalesce(p_category,'')),'');
  return query select f.id, f.category, f.name, f.purpose, f.material, f.standard, f.note from public.app_ref_fixtures f
   where (f.tenant_id is null or f.tenant_id = ten or adm) and (cat is null or f.category = cat)
   order by f.category, f.name;
end $$;

-- ---------- ЕСТД-шаблоны документов ----------
insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
select null, 'techcard', v.n, v.b, true from (values
 ('Маршрутная карта (ГОСТ 3.1118-82, форма 2)',
'МАРШРУТНАЯ КАРТА (ГОСТ 3.1118-82)
Деталь: {title}   Чертеж: {number}   Материал: {material}
Заготовка: {blank}   Масса: {mass}

| № | Операция | Оборудование | Припуск | Точность (IT) | Ra |
|---|----------|--------------|---------|---------------|----|
| 1 | Заготовительная | {equip1} | {allow1} | — | — |
| 2 | {op2} | {equip2} | {allow2} | {it2} | {ra2} |
| 3 | Термообработка | {furnace} | — | {hrc} | — |
| … | … | … | … | … | … |

Разработал: {author}   Проверил: {checker}   Дата: {date}'),
 ('Операционная карта (ГОСТ 3.1129-93)',
'ОПЕРАЦИОННАЯ КАРТА (ГОСТ 3.1129-93)
Операция: {op} № {op_no}   Оборудование: {equip}   Приспособление: {fixture}
Инструмент: {tool}   СОЖ: {coolant}

| № перехода | Содержание перехода | Режимы (Vc, S, t) | Ra |
|------------|---------------------|-------------------|----|
| 1 | Установить и закрепить | — | — |
| 2 | {transition2} | Vc={vc}, S={feed}, t={ap} | {ra} |'),
 ('Ведомость оснастки (ГОСТ 3.1130-93)',
'ВЕДОМОСТЬ ОСНАСТКИ (ГОСТ 3.1130-93)
Изделие: {title}

| Обозначение | Наименование | ГОСТ | Кол-во |
|-------------|--------------|------|--------|
| {code1} | {name1} | {gost1} | {qty1} |')
) v(n,b)
where not exists (select 1 from public.app_doc_templates t where t.tenant_id is null and t.name = v.n);

-- ---------- БЗ: ЕСТД и проектирование ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags from (values
 ('ЕСТД','Что такое ЕСТД и основные ГОСТы','ЕСТД — Единая система технологической документации. Основные: ГОСТ 3.1103-2011 (положения), 3.1118-82 (маршрутная карта МК), 3.1129-93 (правила записи), 3.1130-93 (ведомости), 3.1404-86 (обработка резанием). estd естд маршрутная карта МК ведомость ГОСТ 3.1118 3.1103','ЕСТД маршрутная карта ведомость ГОСТ 3.1118 3.1103 документация'),
 ('ЕСТД','Состав и формы технологических документов','МК (маршрутная карта, форма 2 ГОСТ 3.1118-82), ОК (операционная карта), ВО (ведомость оснастки, ГОСТ 3.1130-93), ВМ (ведомость материалов), титульный лист. Заполняются по переходам с режимами.','ЕСТД маршрутная операционная карта ведомость оснастки материалов'),
 ('Обработка','Типовые маршруты «матрица/пуансон»','Квадрат со ТО (1А): заготовка→фрез.черн.→ТО→фрез.чист.(HSC)→шлиф.→Wire EDM→Sinker EDM→слесарн. Круг со ТО (2А): заготовка→ток.черн.→ТО→ток.чист.(CBN)→круглошлиф.→ЭЭО. Без ТО — 1Б/2Б. Электрод — 1В/2В. Дюраль — 3 (старение), полиуретан — 4.','маршрут матрица пуансон штамп ЭЭО Wire Sinker HSC CBN'),
 ('Обработка','Проектирование электродов ЭЭО: МЭЗ и количество','МЭЗ=(d_отв−d_эл)/2; черновой 0.3-0.5, получистовой 0.15-0.3, чистовой 0.05-0.15, финишный 0.02-0.05 мм. Материал: графит (универс.), медь (чистов.), медно-графит, вольфрам (микро). Кол-во: черновых 1, получист. 1-2, чист. 1-2, финишный 1; усадка графита 0.1-0.5%.','электрод ЭЭО МЭЗ зазор графит медь износ усадка'),
 ('Обработка','Фрезерование графита (электроды)','Vc 300-600 м/мин, ТС с алмазным покрытием, сухая обработка/MQL, мощная аспирация, СИЗ (респиратор).','графит фрезерование электрод алмаз аспирация MQL'),
 ('Обработка','Проектирование приспособлений: базирование','Правило 6 степеней свободы: плоскость(3)+направляющая(2)+опорная(1). Установочные элементы (опоры, призмы ГОСТ 12195-66, штыри 13340-68), зажим (прихваты 4735-69). ε базирования ≤0.02, закрепления ≤0.01, суммарно ≤0.03 мм.','приспособление базирование 6 степеней призмы прихваты оснастка'),
 ('Обработка','Расчёт усилия закрепления и точности приспособления','Усилие: Q=K·P/(f·i), K=2.5-3.0 (черн.), 1.5-2.0 (чист./шлиф.), f=0.1-0.15, i — число точек. Точность: ΣY=√(Σб²+Σз²+Σпр²) ≤ 0.3-0.5 допуска детали.','усилие закрепления расчёт точность приспособления коэффициент запаса'),
 ('Обработка','Оснастка ЭЭО (Wire/Sinker)','Wire: точность установки ≤0.005 мм, призматические/цанговые зажимы, магнитные плиты. Sinker: точность электрода ≤0.01 мм, быстросменные патроны, подвод рабочей жидкости, отвод продуктов эрозии.','оснастка ЭЭО Wire EDM Sinker крепление электрода зажим')
) v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.tenant_id is null and k.question = v.question);

grant execute on function public.app_ref_estd_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_tech_routes_list(uuid) to anon, authenticated;
grant execute on function public.app_ref_edm_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ref_fixtures_list(uuid,text) to anon, authenticated;
