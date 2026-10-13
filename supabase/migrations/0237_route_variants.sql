-- ============================================================
-- 3DMP Service · 0237_route_variants.sql
-- Мастер техпроцесса: варианты техпроцесса на выбор — похожие типовые
-- маршруты (по форме детали) для альтернативы. Расширение 0233/0235/0236.
-- Идемпотентно. Зависит от 0001..0236.
-- ============================================================

create or replace function public.app_tech_route_variants(p_token uuid, p_code text)
returns table (code text, name text, material text, heat text, steps integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; sh text; mat text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select r.shape, r.material into sh, mat from public.app_ref_tech_routes r
   where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm) limit 1;
  if sh is null and mat is null then return; end if;
  return query
    select r.code, r.name, r.material, r.heat, coalesce(jsonb_array_length(coalesce(r.steps,'[]'::jsonb)),0)::int
      from public.app_ref_tech_routes r
     where (r.tenant_id is null or r.tenant_id = ten or adm)
       and r.code <> p_code
       and ((sh is not null and r.shape = sh) or (sh is null and mat is not null and r.material = mat))
     order by r.code;
end $$;

grant execute on function public.app_tech_route_variants(uuid,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Мастер техпроцесса: варианты техпроцесса на выбор',
   'На шаге «Предлагаемый техпроцесс» можно выбрать альтернативный типовой маршрут того же вида (форма/материал детали) — RPC app_tech_route_variants. При выборе варианта состав операций, нормы времени и итог пересчитываются; далее мастер создаёт маршрут/наряд/техкарту по выбранному варианту.',
   'мастер техпроцесса варианты техпроцесса альтернатива app_tech_route_variants выбор маршрута')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
