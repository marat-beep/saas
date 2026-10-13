-- ============================================================
-- 3DMP Service · 0235_tech_wizard_preview.sql
-- Мастер техпроцесса: предпросмотр предлагаемого техпроцесса по типовому
-- маршруту (шаги: операция, оборудование, припуск/IT/Ra). Расширение 0233.
-- Идемпотентно. Зависит от 0001..0234.
-- ============================================================

create or replace function public.app_tech_wizard_preview(p_token uuid, p_code text)
returns table (seq integer, operation text, equipment text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select t.ord::integer,
           coalesce(t.e->>'op','—'),
           coalesce(nullif(t.e->>'equip',''), '—'),
           nullif(concat_ws(' · ',
             nullif('припуск ' || coalesce(t.e->>'allow',''), 'припуск '),
             nullif('IT ' || coalesce(t.e->>'acc',''), 'IT '),
             nullif('Ra ' || coalesce(t.e->>'rough',''), 'Ra ')), '')
      from public.app_ref_tech_routes r,
           jsonb_array_elements(coalesce(r.steps, '[]'::jsonb)) with ordinality as t(e, ord)
     where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm)
     order by t.ord;
end $$;

grant execute on function public.app_tech_wizard_preview(uuid,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Мастер техпроцесса: предпросмотр предлагаемого техпроцесса',
   'Перед созданием записей мастер показывает предлагаемый техпроцесс (шаг «Техпроцесс») — список операций с оборудованием и требованиями (припуск, IT, Ra) из типового маршрута (RPC app_tech_wizard_preview). После создания можно сразу напечатать документы ЕСТД (МК/ОК/ВО) по созданному маршруту — RPC app_route_mk/app_route_ok/app_route_vo.',
   'мастер техпроцесса предпросмотр предложенный техпроцесс ЕСТД МК ОК ВО печать app_tech_wizard_preview')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
