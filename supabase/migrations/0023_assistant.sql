-- ============================================================
-- 3DMP Service · 0023_assistant.sql  (v8.0 — ИИ-помощник)
-- База знаний и правиловой подбор технологии (без внешних API).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0022.
-- ============================================================

create table if not exists public.app_knowledge (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  category   text,
  question   text not null,
  answer     text not null,
  tags       text,
  created_at timestamptz not null default now()
);
create index if not exists app_kb_tenant_idx on public.app_knowledge (tenant_id);

create table if not exists public.app_tech_rules (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  material       text,          -- 'Сталь 40Х' | 'алюминий' | '*' (любой)
  feature        text,          -- 'отверстие' | 'паз' | 'резьба' | 'плоскость' | '*'
  recommendation text not null,
  note           text
);
create index if not exists app_tech_tenant_idx on public.app_tech_rules (tenant_id);

alter table public.app_knowledge enable row level security;
alter table public.app_tech_rules enable row level security;

-- ---------- База знаний ----------
create or replace function public.app_kb_list(p_token uuid)
returns table (id uuid, category text, question text, answer text, tags text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select k.id, k.category, k.question, k.answer, k.tags, k.created_at
    from public.app_knowledge k where (urole='admin' or k.tenant_id = ten) order by k.created_at desc;
end $$;

create or replace function public.app_kb_add(p_token uuid, p_category text, p_question text, p_answer text, p_tags text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_question),'') = '' or coalesce(trim(p_answer),'') = '' then
    return query select false,'Заполните вопрос и ответ'; return;
  end if;
  insert into public.app_knowledge (tenant_id, category, question, answer, tags)
  values (ten, nullif(trim(p_category),''), trim(p_question), trim(p_answer), nullif(trim(p_tags),''));
  return query select true,'Запись добавлена';
end $$;

-- простой «поиск» по базе знаний
create or replace function public.app_kb_search(p_token uuid, p_query text)
returns table (id uuid, category text, question text, answer text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; q text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  q := '%' || coalesce(trim(p_query),'') || '%';
  return query select k.id, k.category, k.question, k.answer
    from public.app_knowledge k
    where (urole='admin' or k.tenant_id = ten)
      and (k.question ilike q or k.answer ilike q or coalesce(k.tags,'') ilike q)
    order by k.created_at desc limit 20;
end $$;

-- ---------- Подбор технологии ----------
create or replace function public.app_tech_recommend(p_token uuid, p_material text, p_feature text)
returns table (recommendation text, note text, matched_material text, matched_feature text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select r.recommendation, r.note, r.material, r.feature
    from public.app_tech_rules r
    where (urole='admin' or r.tenant_id = ten)
      and (r.material is null or r.material = '*' or p_material ilike '%' || r.material || '%')
      and (r.feature is null or r.feature = '*' or p_feature = r.feature)
    order by (case when r.material = '*' or r.material is null then 1 else 0 end) + (case when r.feature='*' or r.feature is null then 1 else 0 end),
             r.recommendation
    limit 5;
end $$;

grant execute on function public.app_kb_list(uuid) to anon, authenticated;
grant execute on function public.app_kb_add(uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_kb_search(uuid,text) to anon, authenticated;
grant execute on function public.app_tech_recommend(uuid,text,text) to anon, authenticated;

-- ---------- Демо: база знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Обработка','Какую подачу выбрать для фрезерования алюминия Д16Т?','Для Д16Т используйте повышенную частоту вращения и охлаждение; подача на зуб 0.05–0.12 мм, СОЖ обязательна.','алюминий фрезеровка подача'),
  ('Обработка','Допуск на отверстие 12H7?','Поле H7 для Ø12: +0.000 / +0.018 мм. Контроль калибром или КИМ.','отверстие допуск H7'),
  ('Оснастка','Материал формообразующих для серийной пресс-формы?','Сталь 40Х с закалкой либо Х12МФ для повышенной стойкости.','пресс-форма сталь стойкость'),
  ('Качество','Периодичность поверки штангенциркуля?','Ежегодно (по графику поверки). Просрочку контролируем в разделе Качество/СМК.','поверка СИ штангенциркуль')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- Демо: правила подбора ----------
insert into public.app_tech_rules (tenant_id, material, feature, recommendation, note)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.material, v.feature, v.recommendation, v.note
from (values
  ('Сталь 40Х','отверстие','Сверление + развёртывание под H7','При закалке — после термообработки шлифовка'),
  ('Сталь 40Х','паз','Фрезерование концевой фрезой, черновой + чистовой проход','СОЖ, контроль размера 12H7'),
  ('алюминий','отверстие','Сверление на высоких оборотах, зенковка','Охлаждение обязательно, риск наростов'),
  ('*','резьба','Метрическая резьба по ГОСТ 24705, контроль калибром','Для серии — резьбофреза'),
  ('*','плоскость','Торцевое фрезерование или шлифовка','Шероховатость по требованию чертежа')
) as v(material,feature,recommendation,note)
where not exists (select 1 from public.app_tech_rules where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
