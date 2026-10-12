-- ============================================================
-- 3DMP Service · 0219_tech_rules.sql
-- Wildcard-материал «любой/any», автонаполнение правил техподбора,
-- нормализация марок (латинская X → кириллица Х), больше нормативов.
-- Идемпотентно. Зависит от 0001..0218.
-- ============================================================

-- ---------- Нормализация марок: латинская X → Х ----------
update public.app_ref_material_grades
   set grade = replace(grade, 'X', 'Х')
 where tenant_id is null and grade like '%X%';
update public.app_ref_material_grades
   set grade = replace(grade, 'x', 'х')
 where tenant_id is null and grade like '%x%' and grade not like '%Х%';

-- ---------- Подбор: wildcard материала/признака ----------
create or replace function public.app_tech_recommend(p_token uuid, p_material text, p_feature text)
returns table (recommendation text, note text, matched_material text, matched_feature text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; mat text; ft text; feats text[];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  mat := lower(coalesce(trim(p_material),''));
  ft := lower(coalesce(trim(p_feature),''));
  select array_agg(distinct x) into feats from (
    select ft as x
    union select lower(s.ru) from public.app_kb_synonyms s where lower(s.ru)=ft or lower(s.en)=ft
    union select lower(s.en) from public.app_kb_synonyms s where lower(s.ru)=ft or lower(s.en)=ft
  ) u where coalesce(x,'') <> '';
  return query
    select r.recommendation, r.note, r.material, r.feature
    from public.app_tech_rules r
    where (urole='admin' or r.tenant_id = ten or r.tenant_id is null)
      and (lower(coalesce(r.material,'')) in ('','*','любой','any')
           or mat = ''
           or r.material ilike '%'||mat||'%' or mat ilike '%'||lower(r.material)||'%'
           or translate(lower(r.material),'xaceopykmt','хасеорукмт') ilike '%'||translate(mat,'xaceopykmt','хасеорукмт')||'%'
           or translate(mat,'xaceopykmt','хасеорукмт') ilike '%'||translate(lower(r.material),'xaceopykmt','хасеорукмт')||'%')
      and (lower(coalesce(r.feature,'')) in ('','*','любой','any')
           or ft = '' or lower(r.feature) = ft or ft like '%'||lower(r.feature)||'%' or lower(r.feature) = any(feats))
    order by
      (case when lower(coalesce(r.material,'')) in ('','*','любой','any') then 1 else 0 end) +
      (case when lower(coalesce(r.feature,'')) in ('','*','любой','any') then 1 else 0 end),
      r.recommendation
    limit 8;
end $$;

-- ---------- Автонаполнение правил по шаблонам ----------
create or replace function public.app_tech_rules_autofill(p_token uuid)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; cnt integer := 0; f record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'assistant')) then
    return query select false,'Нет прав',0; return;
  end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  for f in
    select * from (values
      ('отверстие','Сверлить/зенкеровать/развернуть под требуемый квалитет (H7 — развёртка, припуск 0.1-0.3 мм). Vc: сталь 25-30, алюминий 120-200.'),
      ('резьба','Сверлить под резьбу (М10→Ø8.5), метчик HSS-E, Vc 10-15, СОЖ, реверс для вывода.'),
      ('плоскость','Торцевое фрезерование: Vc 180-220, fz 0.1-0.2, ae 0.6D, ap 2-3, ТС (TiAlN).'),
      ('паз','Концевая фреза, попутное фрезерование, малые ae=0.3D, СОЖ, вывод стружки.'),
      ('точение','Точение: Vc по материалу (сталь 150-250, нерж 80-120, алюминий 300-800), подача 0.1-0.3 мм/об.'),
      ('фрезерование','Фрезерование: Vc по материалу, fz 0.03-0.2; для закалённых — твёрдое фрезерование (AlTiN).'),
      ('сверление','Сверление: S≈0.02·D, вывод стружки каждые 1-2D, при L/D>5 — ВТВ/СОЖ.'),
      ('шлифование','Шлифование: круг по материалу (25А/14А/64С/CBN/алмаз), Vk 30-35 м/с, обильная СОЖ, правка.'),
      ('5 осей','5-осевая: сферическая фреза, малые ae=0.1-0.3D, постоянная подача (HSC), избегать зарезов.'),
      ('электроэрозия','ЭЭО: проволока/электрод, МЭЗ по режиму; после — припуск под шлифование.'),
      ('фаска','Снять фаску 0.5×45° и заусенцы; скруглить кромки.'),
      ('биение','Минимизировать вылет инструмента, жёсткое базирование (≤0.02 мм).'),
      ('закал','После черновой → ТО → чистовая (шлифование/твёрдое фрезерование); учесть припуск под ТО.'),
      ('Ra 1.6','Ra 1.6: развёртывание/тонкое фрезерование/шлифование.'),
      ('Ra 0.8','Ra 0.8: шлифование/хонингование.'),
      ('Ra 0.4','Ra 0.4: тонкое шлифование/суперфиниш/полирование.')
    ) v(feat, rec)
  loop
    if not exists (select 1 from public.app_tech_rules r where r.tenant_id = ten and lower(coalesce(r.material,'')) in ('','*','любой') and lower(r.feature) = f.feat) then
      insert into public.app_tech_rules (tenant_id, material, feature, recommendation, note) values (ten, '*', f.feat, f.rec, 'Автоправило (шаблон)');
      cnt := cnt + 1;
    end if;
  end loop;
  return query select true, 'Добавлено правил: ' || cnt, cnt;
end $$;

-- ---------- Больше нормативов ----------
insert into public.app_ref_estd (tenant_id, code, title, scope, note)
select null, v.c, v.t, v.s, v.n from (values
 ('ISO 2768-1','Общие допуски линейных и угловых размеров','Неуказанные допуски (f/m/c/v)','Для чертежей без индивидуальных допусков.'),
 ('ГОСТ 2.104-2006','ЕСКД. Основные надписи','Штамп чертежа','Оформление чертежей.'),
 ('ГОСТ 2.106-96','ЕСКД. Текстовые документы','Спецификации/ведомости','—'),
 ('ГОСТ 2.109-73','ЕСКД. Основные требования к чертежам','Оформление','—'),
 ('ГОСТ 2.307-2011','ЕСКД. Нанесение размеров и предельных отклонений','Размеры/посадки','—'),
 ('ГОСТ 3.1502-85','ЕСТД. Формы и правила оформления документов ТО','Термообработка','—'),
 ('ГОСТ 3.1703-79','ЕСТД. Правила записи операций','Кодирование операций','—'),
 ('ГОСТ 25762-83','Обработка резанием. Термины и определения','Терминология','—'),
 ('ГОСТ 26645-85','Допуски литых заготовок','Литьё','—'),
 ('ГОСТ 5264-80','Ручная дуговая сварка. Соединения','Сварка','Если применимо.')
) v(c,t,s,n)
where not exists (select 1 from public.app_ref_estd e where e.tenant_id is null and e.code = v.c);

-- ---------- БЗ: нормативы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags from (values
 ('Стандарты','Общие допуски ISO 2768 / ГОСТ 30893','Классы: f (точный), m (средний), c (грубый), v (очень грубый). Для неуказанных размеров. Напр. 6-30 мм: f ±0.1, m ±0.2, c ±0.5, v ±1.0.','iso 2768 30893 общие допуски неуказанные f m c v'),
 ('Стандарты','Основная надпись (ГОСТ 2.104-2006)','Форма 1 — для чертежей, форма 2 — для текстовых. Графы: наименование, обозначение, масштаб, материал, масса.','гост 2.104 основная надпись штамп чертеж'),
 ('Стандарты','Нанесение размеров и отклонений (ГОСТ 2.307)','Предельные отклонения: H7/g6 и т.п.; неуказанные — по ISO 2768. Радиусы, фаски, шероховатость Ra.','2.307 размеры отклонения посадки шероховатость'),
 ('Стандарты','Обозначения ЧПУ (ГОСТ 25762/25726)','Термины обработки резанием и обозначения ЧПУ; кодирование операций по ЕСТД.','25762 25726 чпу термины кодирование')
) v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.tenant_id is null and k.question = v.question);

grant execute on function public.app_tech_recommend(uuid,text,text) to anon, authenticated;
grant execute on function public.app_tech_rules_autofill(uuid) to anon, authenticated;
