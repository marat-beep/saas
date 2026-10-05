-- ============================================================
-- 3DMP Service · 0049_ref_materials.sql  (v31.0 — справочник марок материалов)
-- Глобальный справочник марок (tenant_id null — общий для всех организаций):
-- группа, марка, ГОСТ, плотность, σв, твёрдость HB, цена, применение.
-- База знаний. Зависит от 0001..0048.
-- ============================================================

create table if not exists public.app_ref_material_grades (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  group_code text not null,      -- steel|tool_steel|stainless|aluminum|bronze|brass|copper|cast_iron|plastic|titanium
  grade      text not null,
  standard   text,
  density    numeric,
  tensile    numeric,            -- σв, МПа
  hardness   numeric,            -- HB (или HRC для инструментальных)
  price      numeric,            -- ₽/кг
  note       text,
  created_at timestamptz not null default now(),
  unique (tenant_id, group_code, grade)
);
create index if not exists app_ref_mat_grades_idx on public.app_ref_material_grades (group_code, grade);
alter table public.app_ref_material_grades enable row level security;

-- ---------- Список ----------
create or replace function public.app_ref_material_list(p_token uuid, p_group text default null, p_q text default null)
returns table (id uuid, group_code text, grade text, standard text, density numeric, tensile numeric,
               hardness numeric, price numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  qq := lower(coalesce(trim(p_q),''));
  return query
    select g.id, g.group_code, g.grade, g.standard, g.density, g.tensile, g.hardness, g.price, g.note
    from public.app_ref_material_grades g
    where (g.tenant_id is null or g.tenant_id = ten or urole='admin')
      and (p_group is null or p_group = '' or g.group_code = p_group)
      and (qq = '' or lower(g.grade) like '%'||qq||'%' or lower(coalesce(g.standard,'')) like '%'||qq||'%' or lower(coalesce(g.note,'')) like '%'||qq||'%')
    order by g.group_code, g.grade;
end $$;

-- ---------- Добавить/изменить (admin/owner/manager/technologist) ----------
create or replace function public.app_ref_material_save(p_token uuid, p_id uuid, p_group text, p_grade text,
  p_standard text, p_density numeric, p_tensile numeric, p_hardness numeric, p_price numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; gid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','technologist') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_grade),'') = '' then return query select false,'Укажите марку'; return; end if;

  if p_id is null then
    insert into public.app_ref_material_grades (tenant_id, group_code, grade, standard, density, tensile, hardness, price, note)
    values (null, coalesce(nullif(trim(p_group),''),'steel'), trim(p_grade), nullif(trim(p_standard),''),
            p_density, p_tensile, p_hardness, p_price, nullif(trim(p_note),''))
    returning app_ref_material_grades.id into gid;
  else
    update public.app_ref_material_grades set group_code = coalesce(nullif(trim(p_group),''), group_code),
      grade = trim(p_grade), standard = nullif(trim(p_standard),''), density = p_density, tensile = p_tensile,
      hardness = p_hardness, price = p_price, note = nullif(trim(p_note),'')
     where id = p_id and (tenant_id is null and urole in ('admin','owner') or tenant_id = ten)
     returning app_ref_material_grades.id into gid;
    if gid is null then return query select false,'Запись не найдена или нет прав'; return; end if;
  end if;
  return query select true,'Сохранено';
end $$;

grant execute on function public.app_ref_material_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_ref_material_save(uuid,uuid,text,text,text,numeric,numeric,numeric,numeric,text) to anon, authenticated;

-- ---------- Наполнение (глобальный справочник) ----------
insert into public.app_ref_material_grades (tenant_id, group_code, grade, standard, density, tensile, hardness, price, note)
select null, v.group_code, v.grade, v.standard, v.density, v.tensile, v.hardness, v.price, v.note
from (values
  ('steel','Сталь 20','ГОСТ 1050-2013',7.85,410,120,65,'Конструкционная, цементуемая'),
  ('steel','Сталь 45','ГОСТ 1050-2013',7.85,780,197,70,'Конструкционная улучшаемая'),
  ('steel','Сталь 3 (Ст3)','ГОСТ 380-2005',7.85,370,120,60,'Обычного качества'),
  ('steel','09Г2С','ГОСТ 19281-2014',7.85,490,150,75,'Низколегированная, конструкции'),
  ('steel','40Х','ГОСТ 4543-2016',7.82,980,217,85,'Легированная, валы/шестерни'),
  ('steel','40ХН','ГОСТ 4543-2016',7.82,1080,240,95,'Повышенная прочность'),
  ('steel','65Г','ГОСТ 14959-2016',7.85,1000,250,90,'Пружинная/рессорная'),
  ('tool_steel','У8','ГОСТ 1435-99',7.85,900,187,120,'Инструментальная углеродистая (HRC 60)'),
  ('tool_steel','У10','ГОСТ 1435-99',7.85,1000,200,125,'Инструментальная (HRC 62)'),
  ('tool_steel','9ХС','ГОСТ 5950-2000',7.8,1100,220,260,'Инструментальная легированная'),
  ('tool_steel','Х12МФ','ГОСТ 5950-2000',7.7,1100,230,320,'Штамповая холодной штамповки'),
  ('tool_steel','5ХНМ','ГОСТ 5950-2000',7.8,1200,240,300,'Штамповая горячей штамповки'),
  ('tool_steel','Р6М5','ГОСТ 19265-73',8.2,2000,255,750,'Быстрорежущая (HRC 63-65)'),
  ('stainless','12Х18Н10Т','ГОСТ 5632-2014',7.9,550,180,420,'Нержавеющая, пищевая/химстойкая'),
  ('stainless','20Х13','ГОСТ 5632-2014',7.7,650,200,300,'Нержавеющая, валы/лопатки'),
  ('bearing','ШХ15','ГОСТ 801-78',7.81,1200,210,180,'Подшипниковая'),
  ('aluminum','Д16Т','ГОСТ 4784-2019',2.78,440,120,450,'Авиаль, высокопрочная'),
  ('aluminum','АМг6','ГОСТ 4784-2019',2.64,340,95,420,'Алюминиево-магниевый сплав'),
  ('aluminum','АД31','ГОСТ 4784-2019',2.70,200,60,380,'Авиаль, профили'),
  ('bronze','БрАЖ9-4','ГОСТ 18175-78',7.5,550,120,950,'Бронза, втулки/направляющие'),
  ('brass','ЛС59-1','ГОСТ 15527-2004',8.5,470,130,800,'Латунь свинцовистая'),
  ('copper','М1','ГОСТ 859-2014',8.9,220,45,900,'Медь, электроды ЭЭО'),
  ('cast_iron','СЧ20','ГОСТ 1412-85',7.2,200,200,90,'Серый чугун'),
  ('cast_iron','ВЧ50','ГОСТ 7293-85',7.1,500,187,140,'Высокопрочный чугун'),
  ('plastic','ПА6 (полиамид)','—',1.14,80,null,550,'Втулки, зубчатки'),
  ('plastic','POM (полиацеталь)','—',1.41,70,null,700,'Точные детали, скольжение'),
  ('plastic','PTFE (фторопласт)','—',2.2,25,null,1200,'Химстойкие уплотнения'),
  ('titanium','ВТ6','ГОСТ 19807-91',4.43,950,230,3500,'Титановый сплав (Ti-6Al-4V)')
) as v(group_code, grade, standard, density, tensile, hardness, price, note)
where not exists (select 1 from public.app_ref_material_grades where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Материалы','Что содержит справочник марок материалов?',
   'Справочник марок (Справочники → вкладка «Марки»): группа, марка, ГОСТ, плотность, предел прочности σв, твёрдость HB/HRC, цена ₽/кг и применение. Используется в спецификациях (BOM), расчёте массы, себестоимости и подборе режимов резания.',
   'материалы марки справочник ГОСТ плотность прочность HB цена BOM'),
  ('Материалы','Как выбирать марку для штампов и оснастки?',
   'Для холодной штамповки — Х12МФ, для горячей — 5ХНМ, для режущего инструмента — Р6М5/У10, для направляющих и втулок — БрАЖ9-4/ШХ15, для электродов ЭЭО — М1. Плотность и прочность берутся из справочника для расчёта массы и нагружения.',
   'выбор марки штамп оснастка Х12МФ 5ХНМ Р6М5 электроды')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что содержит справочник марок материалов?');
