-- ============================================================
-- 3DMP Service · 0097_adoption.sql  (v75 — Партия I: карта внедрения)
-- app_adoption_map: по каждому модулю — включён ли (app_tenant_modules) и есть ли
-- фактические данные (используется). app_adoption_kpi. Зависит от 0001..0096.
-- ============================================================

create or replace function public.app_adoption_map(p_token uuid)
returns table (module text, enabled boolean, records bigint, used boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; m record; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  for m in
    select * from (values
      ('orders','app_orders'),('crm','app_customers'),('docs','app_documents'),('templates','app_doc_templates'),
      ('dicts','app_dictionaries'),('norms','app_norms_operations'),('calc','app_calc_saves'),
      ('slots','app_work_slots'),('setup','app_setups'),('lean','app_lean_actions'),
      ('partners','app_partners'),('equipment','app_equipment_catalog'),('staff','app_staff_crm'),
      ('config','app_config_options'),('reverse','app_reverse_orders'),('escrow','app_escrow_deals'),
      ('marketplace','app_market_listings'),('suppliers','app_suppliers'),('teo','app_teo'),
      ('labels','app_labels'),('engraving','app_engraving'),('files','app_files'),('iiot','app_iiot_readings')
    ) as t(mod, tbl)
  loop
    cnt := 0;
    if to_regclass('public.'||m.tbl) is not null then
      begin
        execute 'select count(*) from public.'||m.tbl||' where ($1 is null or tenant_id=$1)' into cnt using ten;
      exception when undefined_column then
        begin execute 'select count(*) from public.'||m.tbl into cnt; exception when others then cnt := 0; end;
      end;
    end if;
    return query select m.mod,
      coalesce((select tm.enabled from public.app_tenant_modules tm where tm.tenant_id=ten and tm.module=m.mod), false),
      cnt, cnt > 0;
  end loop;
end $$;

create or replace function public.app_adoption_kpi(p_token uuid)
returns table (modules_known bigint, enabled bigint, used bigint, progress_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; e bigint; u bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select count(*) filter (where enabled), count(*) filter (where used) into e, u from public.app_adoption_map(p_token);
  return query select 23::bigint, coalesce(e,0), coalesce(u,0), round(case when 23>0 then coalesce(u,0)::numeric/23*100 else 0 end, 0);
end $$;

grant execute on function public.app_adoption_map(uuid) to anon, authenticated;
grant execute on function public.app_adoption_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Карта внедрения (I)',
   'Экран «Карта внедрения»: по каждому модулю видно, включён ли он для предприятия (app_tenant_modules) и используется ли по факту (есть записи). Прогресс внедрения, рекомендованный следующий шаг по волнам. Помогает предприятию видеть, что уже работает, для чего и что включать дальше.',
   'внедрение карта adoption волны профиль предприятия онбординг прогресс')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Карта внедрения (I)');
