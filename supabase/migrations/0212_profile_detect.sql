-- ============================================================
-- 3DMP Service · 0212_profile_detect.sql
-- Авто-определение профиля организации по включённым модулям.
-- app_org_profile_detect → ближайший профиль + % соответствия.
-- Идемпотентно. Зависит от 0001..0211.
-- ============================================================

create or replace function public.app_org_profile_detect(p_token uuid)
returns table (code text, name text, match_pct numeric, matched integer, total integer, enabled_count integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; enb integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select count(*) into enb from public.app_tenant_modules m where (adm or m.tenant_id = ten) and m.enabled;
  return query
    select p.code, p.name,
           round(100.0 * c.matched / greatest(c.total, 1), 1),
           c.matched::int, c.total::int, enb
    from public.app_org_profiles p
    cross join lateral (
      select count(*) as matched, jsonb_array_length(p.modules) as total
        from jsonb_array_elements_text(p.modules) e
       where exists (select 1 from public.app_tenant_modules m
                      where m.module = e.value and (adm or m.tenant_id = ten) and m.enabled)
    ) c
    order by round(100.0 * c.matched / greatest(c.total, 1), 1) desc, c.matched desc, p.sort
    limit 1;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Авто-определение профиля организации (0212)',
   'app_org_profile_detect(token) возвращает ближайший профиль организации (code/name), % соответствия (match_pct), число совпавших модулей и всего. Используется в «Мастере настройки» (подсветка текущего профиля).',
   'профиль организации автоопределение соответствие мастер')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Авто-определение профиля организации (0212)'
);

grant execute on function public.app_org_profile_detect(uuid) to anon, authenticated;
