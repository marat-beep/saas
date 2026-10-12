-- ============================================================
-- 3DMP Service · 0227_assistant_cutting.sql
-- U2: ИИ-помощник ↔ режимы резания. RPC app_ref_cutting_find принимает
-- произвольный материал (марку/группу, RU/EN) и операцию, угадывает
-- группу материала и возвращает режимы. Идемпотентно. Зависит от 0001..0226.
-- ============================================================

create or replace function public.app_ref_cutting_find(p_token uuid, p_material text default null, p_operation text default null, p_limit int default 25)
returns table (material_group text, operation text, tool_type text, tool_material text, vc numeric, feed numeric, ap numeric, ae numeric, cooling text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; mm text; oo text; grp text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  mm := lower(coalesce(trim(p_material),'')); oo := lower(coalesce(trim(p_operation),''));
  grp := case
    when mm='' then null
    when mm like '%подшип%' or mm like '%bearing%' or mm like '%шх15%' then 'bearing'
    when mm like '%инстр%' or mm like '%tool%' or mm like '%р6м5%' or mm like '%х12%' or mm like '%хвг%' or mm like '%9хс%' or mm like '%у8%' or mm like '%у10%' or mm like '%hrc%' then 'tool_steel'
    when mm like '%нерж%' or mm like '%stainless%' or mm like '%12х18%' or mm like '%304%' or mm like '%316%' then 'stainless'
    when mm like '%алюм%' or mm like '%alum%' or mm like '%д16%' or mm like '%6061%' or mm like '%ад0%' or mm like '%силумин%' then 'aluminum'
    when mm like '%латун%' or mm like '%brass%' or mm like '%лс5%' then 'brass'
    when mm like '%бронз%' or mm like '%bronze%' or mm like '%бра%' then 'bronze'
    when mm like '%медь%' or mm like '%copper%' or mm like '%мед%' then 'copper'
    when mm like '%чугун%' or mm like '%cast%' or mm like '%сч2%' or mm like '%вч%' then 'cast_iron'
    when mm like '%титан%' or mm like '%titan%' or mm like '%вт6%' then 'titanium'
    when mm like '%пласт%' or mm like '%plastic%' or mm like '%полипро%' or mm like '%капролон%' then 'plastic'
    when mm like '%стал%' or mm like '%steel%' or mm like '%40х%' or mm like '%20х%' or mm like '%ст3%' or mm like '%30хгса%' or mm like '%45%' then 'steel'
    else null
  end;
  return query
    select c.material_group, c.operation, c.tool_type, c.tool_material, c.vc, c.feed, c.ap, c.ae, c.cooling, c.note
      from public.app_ref_cutting c
     where (c.tenant_id is null or c.tenant_id = ten)
       and (grp is null or c.material_group = grp)
       and (oo='' or lower(c.operation) like '%'||oo||'%'
            or lower(coalesce(c.tool_type,'')) like '%'||oo||'%'
            or lower(coalesce(c.tool_material,'')) like '%'||oo||'%')
     order by (case when c.material_group = grp then 0 else 1 end), c.material_group, c.operation
     limit greatest(coalesce(p_limit,25),1);
end $$;

grant execute on function public.app_ref_cutting_find(uuid,text,text,int) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('ИИ-помощник','Как открыть режимы резания из помощника',
   'В «ИИ-помощнике» на вкладке «Помощник» введите запрос и нажмите «📐 Режимы резания по запросу» — система угадает группу материала (по марке/названию, RU/EN) и покажет таблицу режимов из справочника app_ref_cutting (Vc, подача, ap/ae, инструмент, СОЖ). Кнопка «🔧 Подобрать технологию» переносит запрос в поле «Материал» подбора. Примеры: «режим фрезерования стали», «латунь точение», «хонингование сталь».',
   'ии помощник режимы резания справочник материал подбор фрезерование хонингование')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
