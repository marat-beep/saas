-- ============================================================
-- 3DMP Service · 0217_ref_standards2.sql
-- Двуязычный поиск (RU/EN + синонимы), новые справочники (шероховатость,
-- твёрдость HRC/HB/HV, покрытия), список признаков, больше БЗ.
-- Идемпотентно. Зависит от 0001..0216.
-- ============================================================

-- ---------- Синонимы RU↔EN ----------
create table if not exists public.app_kb_synonyms (
  id uuid primary key default gen_random_uuid(),
  ru text not null, en text not null,
  unique (ru, en)
);
alter table public.app_kb_synonyms enable row level security;

insert into public.app_kb_synonyms (ru, en)
select v.r, v.e from (values
 ('допуск','tolerance'),('посадка','fit'),('квалитет','grade'),('зазор','clearance'),('натяг','interference'),
 ('резьба','thread'),('метчик','tap'),('сверло','drill'),('сверление','drilling'),('развёртка','ream'),('развертывание','reaming'),
 ('фреза','mill'),('фрезерование','milling'),('точение','turning'),('резец','tool'),('шлифование','grinding'),('круг','wheel'),
 ('скорость резания','cutting speed'),('обороты','rpm'),('подача','feed'),('съём','mrr'),
 ('сталь','steel'),('нержавеющая','stainless'),('алюминий','aluminum'),('титан','titanium'),('чугун','cast iron'),
 ('шероховатость','roughness'),('закалка','hardening'),('отпуск','tempering'),('цементация','carburizing'),('азотирование','nitriding'),
 ('чпу','cnc'),('электроэрозия','edm'),('ээо','edm'),('проволока','wire'),('5 осей','5 axis'),('пятиосевая','5 axis'),
 ('покрытие','coating'),('сож','coolant'),('твёрдость','hardness'),('твердость','hardness'),('масса','mass'),('вес','weight'),
 ('заготовка','blank'),('труба','pipe'),('круг заготовка','round bar'),('пластина','insert'),('твердосплав','carbide'),
 ('термообработка','heat treatment'),('поверхность','surface'),('отверстие','hole'),('паз','slot'),('фаска','chamfer'),
 ('стандарт','standard'),('аналог','analog'),('марка','grade'),('плотность','density'),('прочность','strength')
) v(r,e)
where not exists (select 1 from public.app_kb_synonyms s where s.ru = v.r and s.en = v.e);

-- ---------- Шероховатость: Ra → метод ----------
create table if not exists public.app_ref_roughness (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  ra numeric not null, rz numeric, method text, note text,
  created_at timestamptz not null default now(),
  unique (tenant_id, ra)
);
alter table public.app_ref_roughness enable row level security;
insert into public.app_ref_roughness (tenant_id, ra, rz, method, note)
select null, v.ra, v.rz, v.m, v.n from (values
 (25.0,100.0,'Черновое точение/фрезерование','Грубая обработка, припуск.'),
 (12.5,50.0,'Получерновое точение/фрезерование','Основные размеры.'),
 (6.3,25.0,'Черновое шлифование/чистовое фрезерование','Посадочные поверхности.'),
 (3.2,12.5,'Чистовое точение/фрезерование','Общего назначения.'),
 (1.6,6.3,'Развёртывание/тонкое фрезерование/шлифование','Плотные посадки H7.'),
 (0.8,3.2,'Шлифование/хонингование','Прецизионные поверхности.'),
 (0.4,1.6,'Тонкое шлифование/суперфиниш','Высокая точность.'),
 (0.2,0.8,'Полирование/суперфиниш/притирка','Зеркальные поверхности.'),
 (0.1,0.4,'Доводка/полирование','Оптика, калибры.'),
 (0.05,0.2,'Доводка алмазная','Зеркальная точность.')
) v(ra,rz,m,n)
where not exists (select 1 from public.app_ref_roughness r where r.tenant_id is null and r.ra = v.ra);

-- ---------- Твёрдость: HRC↔HB↔HV (приближённо) ----------
create table if not exists public.app_ref_hardness (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  hrc numeric, hb numeric, hv numeric, note text,
  unique (tenant_id, hrc)
);
alter table public.app_ref_hardness enable row level security;
insert into public.app_ref_hardness (tenant_id, hrc, hb, hv, note)
select null, v.c, v.b, v.v, v.n from (values
 (20,238,240,'Цементованные/улучшенные стали.'),
 (25,266,270,'—'),
 (30,302,310,'—'),
 (35,345,360,'—'),
 (40,392,410,'Улучшенные 40Х.'),
 (45,446,470,'—'),
 (50,513,540,'Закалка ТВЧ.'),
 (55,595,620,'Инструмент.'),
 (58,640,675,'Х12МФ (штампы).'),
 (60,680,720,'У8А/У10А, CBN-шлифование.'),
 (62,712,760,'Р6М5 (HSS).'),
 (65,760,830,'Быстрорезы, твёрдое фрезерование.')
) v(c,b,v,n)
where not exists (select 1 from public.app_ref_hardness h where h.tenant_id is null and h.hrc = v.c);

-- ---------- Покрытия инструмента ----------
create table if not exists public.app_ref_coatings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text not null, name text, hardness_hv integer, max_temp integer, application text, note text,
  unique (tenant_id, code)
);
alter table public.app_ref_coatings enable row level security;
insert into public.app_ref_coatings (tenant_id, code, name, hardness_hv, max_temp, application, note)
select null, v.c, v.n, v.hv, v.t, v.a, v.note from (values
 ('TiN','Нитрид титана',2300,600,'Сверление, метчики, универсально','Базовое покрытие.'),
 ('TiCN','Карбонитрид титана',3000,400,'Фрезерование стали','Выше износ.'),
 ('TiAlN','Нитрид титан-алюминия',3300,800,'Скоростное фрезерование/сверление','Жаростойкое; сталь/нерж.'),
 ('AlTiN','Нитрид алюминий-титана',3500,900,'Твёрдое фрезерование HRC>45','Высокая жаростойкость.'),
 ('AlCrN','Нитрид алюминий-хрома',3200,1100,'Фрезы, титан/жаропроч.','Окислостойкое.'),
 ('CrN','Нитрид хрома',2000,700,'Цветные/титан','Антифрикц.'),
 ('ZrN','Нитрид циркония',2800,600,'Алюминий/латунь','Полированный.'),
 ('DLC','Алмазоподобный углерод',4000,400,'Алюминий, композиты, граф.','Низкий коэф. трения.'),
 ('PVD-Ag/soft','Мягкие покрытия',null,600,'Алюминий/титан','Противоналипание.'),
 ('Без покрытия','Полированный/острый',1600,600,'Алюминий/магний','Макс. острота кромки.')
) v(c,n,hv,t,a,note)
where not exists (select 1 from public.app_ref_coatings cc where cc.tenant_id is null and cc.code = v.c);

-- ---------- RPC новых справочников и признаков ----------
create or replace function public.app_ref_roughness_list(p_token uuid)
returns table (id uuid, ra numeric, rz numeric, method text, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.ra, r.rz, r.method, r.note from public.app_ref_roughness r
   where (r.tenant_id is null or r.tenant_id = ten or adm) order by r.ra desc;
end $$;

create or replace function public.app_ref_hardness_list(p_token uuid)
returns table (id uuid, hrc numeric, hb numeric, hv numeric, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select h.id, h.hrc, h.hb, h.hv, h.note from public.app_ref_hardness h
   where (h.tenant_id is null or h.tenant_id = ten or adm) order by h.hrc;
end $$;

create or replace function public.app_ref_coatings_list(p_token uuid)
returns table (id uuid, code text, name text, hardness_hv integer, max_temp integer, application text, note text)
language plpgsql security definer set search_path = public as $$
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select c.id, c.code, c.name, c.hardness_hv, c.max_temp, c.application, c.note from public.app_ref_coatings c
   where (c.tenant_id is null or c.tenant_id = ten or adm) order by c.code;
end $$;

create or replace function public.app_tech_features_list(p_token uuid)
returns table (feature text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select distinct r.feature from public.app_tech_rules r
    where coalesce(r.feature,'') not in ('','*') order by r.feature;
end $$;

-- ---------- Двуязычный поиск БЗ ----------
create or replace function public.app_kb_search(p_token uuid, p_query text)
returns table (id uuid, category text, question text, answer text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; q text; toks text[]; exp text[];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  q := lower(coalesce(trim(p_query),''));
  if q = '' then
    return query select k.id, k.category, k.question, k.answer from public.app_knowledge k
     where (urole='admin' or k.tenant_id = ten or k.tenant_id is null) order by k.created_at desc limit 20;
    return;
  end if;
  toks := string_to_array(q, ' ');
  select array_agg(distinct x) into exp from (
    select unnest(toks) as x
    union select lower(s.en) from public.app_kb_synonyms s, unnest(toks) t where lower(s.ru) = t or lower(s.en) = t
    union select lower(s.ru) from public.app_kb_synonyms s, unnest(toks) t where lower(s.ru) = t or lower(s.en) = t
  ) u where length(x) >= 2;
  if exp is null then exp := toks; end if;
  return query
    select k.id, k.category, k.question, k.answer
      from public.app_knowledge k
     where (urole='admin' or k.tenant_id = ten or k.tenant_id is null)
       and (k.question ilike '%'||q||'%' or k.answer ilike '%'||q||'%' or coalesce(k.tags,'') ilike '%'||q||'%'
            or exists (select 1 from unnest(exp) e(tok)
                        where lower(k.question) like '%'||e.tok||'%' or lower(k.answer) like '%'||e.tok||'%' or lower(coalesce(k.tags,'')) like '%'||e.tok||'%'))
     order by (k.question ilike '%'||q||'%') desc,
              (select count(*) from unnest(exp) e(tok)
                where lower(k.question) like '%'||e.tok||'%' or lower(k.answer) like '%'||e.tok||'%' or lower(coalesce(k.tags,'')) like '%'||e.tok||'%') desc,
              k.created_at desc
     limit 20;
end $$;

-- ---------- Подбор: учёт синонимов признака ----------
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
      and (coalesce(r.material,'*') in ('*','') or mat = ''
           or r.material ilike '%'||mat||'%' or mat ilike '%'||lower(r.material)||'%'
           or translate(lower(r.material),'xaceopykmt','хасеорукмт') ilike '%'||translate(mat,'xaceopykmt','хасеорукмт')||'%'
           or translate(mat,'xaceopykmt','хасеорукмт') ilike '%'||translate(lower(r.material),'xaceopykmt','хасеорукмт')||'%')
      and (coalesce(r.feature,'*') in ('*','') or ft = '' or lower(r.feature) = ft or ft like '%'||lower(r.feature)||'%' or lower(r.feature) = any(feats))
    order by
      (case when coalesce(r.material,'*') in ('*','') then 1 else 0 end) +
      (case when coalesce(r.feature,'*') in ('*','') then 1 else 0 end),
      r.recommendation
    limit 6;
end $$;

-- ---------- Больше БЗ (двуязычные теги) ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags from (values
 ('Обработка','Ra и Rz: соответствие и методы (roughness)','Ra ≈ (Rz)/4..6. Ra25→черновая; Ra6.3→получистовая; Ra1.6→развёртывание/шлифование; Ra0.4→тонкое шлифование; Ra0.2→полирование. roughness surface finish Ra Rz','roughness Ra Rz шероховатость surface finish'),
 ('Обработка','Твёрдость: перевод HRC↔HB↔HV','HRC40≈HB392≈HV410; HRC50≈HB513≈HV540; HRC60≈HB680≈HV720. Перевод приближённый (hardness conversion).','hardness HRC HB HV твёрдость перевод'),
 ('Обработка','Покрытия инструмента и применение (coatings)','TiN—универсально; TiCN—сталь; TiAlN—скоростное; AlTiN—твёрдое фрезерование; AlCrN—жаропроч.; ZrN—алюминий; DLC—алюминий/композиты. coatings PVD TiN TiAlN AlTiN AlCrN DLC','coatings покрытие TiN TiAlN AlTiN AlCrN DLC PVD'),
 ('Обработка','Твёрдый сплав vs HSS (carbide vs HSS)','HSS (Р6М5/Р18) — гибкий, дешёвый, до Vc 30-40; твердосплав — Vc в 3-5 раз выше, но хрупкий; для ЧПУ и закалённых — только ТС. carbide HSS твердосплав быстрорез','carbide hss твердосплав быстрорежущая фреза сверло'),
 ('Обработка','Режимы сверления: подача и вывод стружки (drilling)','S=0.02·D (мм/об) для стали; вывод стружки каждые 1-2D; Vc HSS 25-30, ТС 80-120; при deep-hole (L/D>5) — сверление с СОЖ ВТВ. drilling feed hole сверление','drilling сверление подача вывод стружки deep hole'),
 ('Обработка','Метчики и резьба: последовательность (tapping)','Сверло→зенкер(фаска)→метчик. Vc 10-15 (сталь), метчик HSS-E, реверс для вывода. Форма канавок: прямой—сквозная, винтовые—глухая. tapping thread метчик резьба','tapping метчик резьба сверло фаска'),
 ('Обработка','Развёртывание и точность H7 (reaming)','Припуск 0.1-0.3 мм; Vc 5-15, подача 0.5-1.5 мм/об; обильная СОЖ; достижимо Ra1.6 и H7. reaming развёртка H7 точность','reaming развёртывание H7 припуск'),
 ('Обработка','Зубообработка/хонингование/протягивание','Зубодолбление/фрезерование червячной фрезой; хонингование — доводка отверстий; протягивание — высокая производительность шлицев/отверстий. hobbing honing broaching зубообработка','зубообработка хонингование протягивание gear honing broaching'),
 ('Обработка','GD&T: базы, допуски формы/расположения','Плоскостность/цилиндричность/позиционный допуск (True Position Ø). Базы A/B/C. Обозначения на чертеже ISO 1101. GD&T position datum цилиндричность позиционный','GD&T позиционный допуск базы формы расположения ISO 1101'),
 ('Обработка','Титановые сплавы: особенности обработки (titanium)','Низкая теплопроводность → жар в кромке; малые Vc (30-60), острая кромка, обильная СОЖ, риск возгорания стружки; не «тереть». titanium титан ВТ6 обработка','titanium титан ВТ6 Ti-6Al-4V обработка')
) v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.tenant_id is null and k.question = v.question);

grant execute on function public.app_ref_roughness_list(uuid) to anon, authenticated;
grant execute on function public.app_ref_hardness_list(uuid) to anon, authenticated;
grant execute on function public.app_ref_coatings_list(uuid) to anon, authenticated;
grant execute on function public.app_tech_features_list(uuid) to anon, authenticated;
grant execute on function public.app_kb_search(uuid,text) to anon, authenticated;
grant execute on function public.app_tech_recommend(uuid,text,text) to anon, authenticated;
