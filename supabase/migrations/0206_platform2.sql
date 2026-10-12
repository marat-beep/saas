-- ============================================================
-- 3DMP Service · 0206_platform2.sql  (X20 — Платформа/референсы 2.0)
-- Визуальная карта процесса (BPMN-lite) из маршрутов W10, калькулятор тарифов,
-- обзор единой НСИ, статистика справки. Идемпотентно. Зависит от 0001..0205.
-- ============================================================

create or replace function public.app_bpmn_map(p_token uuid, p_route_id uuid)
returns table (nodes jsonb, edges jsonb, step_count integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; arr jsonb; i integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_approval_routes where id = p_route_id and (adm or tenant_id = ten);
  if r.id is null then raise exception 'Маршрут не найден'; end if;
  arr := case when r.steps is null or jsonb_typeof(r.steps) <> 'array' then '[]'::jsonb else r.steps end;
  nodes := jsonb_build_array(jsonb_build_object('id','start','type','start','label','Старт')) ||
           coalesce((select jsonb_agg(jsonb_build_object('id','s'||(e->>'ord'), 'type','task', 'role', e->>'role', 'label', coalesce(e->>'name', e->>'role')))
                       from jsonb_array_elements(arr) e), '[]'::jsonb) ||
           jsonb_build_array(jsonb_build_object('id','end','type','end','label','Финиш'));
  edges := '[]'::jsonb;
  edges := edges || jsonb_build_array(jsonb_build_object('from','start','to','s'||coalesce(arr->0->>'ord','1')));
  for i in 0 .. (jsonb_array_length(arr) - 2) loop
    edges := edges || jsonb_build_array(jsonb_build_object('from','s'||(arr->i->>'ord'), 'to','s'||(arr->(i+1)->>'ord')));
  end loop;
  if jsonb_array_length(arr) > 0 then
    edges := edges || jsonb_build_array(jsonb_build_object('from','s'||(arr->(jsonb_array_length(arr)-1)->>'ord'), 'to','end'));
  end if;
  step_count := jsonb_array_length(arr);
  return query select nodes, edges, step_count;
end $$;

create or replace function public.app_tariff_calc(p_token uuid, p_plan_code text, p_seats integer, p_addons jsonb default '[]'::jsonb)
returns table (plan text, base numeric, seats numeric, addons numeric, total numeric, breakdown jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare pl record; seat_price numeric; seat_cost numeric; addon_cost numeric; br jsonb;
begin
  select * into pl from public.app_plans where code = p_plan_code;
  if pl.code is null then return query select null::text, null::numeric, null::numeric, null::numeric, null::numeric, '{}'::jsonb; return; end if;
  seat_price := coalesce((pl.features->>'seat_price')::numeric, 0);
  seat_cost := greatest(coalesce(p_seats,0) - coalesce(pl.max_users,0), 0) * seat_price;
  addon_cost := coalesce((select sum((e->>'price')::numeric) from jsonb_array_elements(case when jsonb_typeof(p_addons)='array' then p_addons else '[]'::jsonb end) e), 0);
  br := jsonb_build_object('plan', pl.name, 'base', pl.price, 'seats_over', greatest(coalesce(p_seats,0) - coalesce(pl.max_users,0),0), 'seat_price', seat_price, 'addons', addon_cost);
  return query select pl.code, pl.price, seat_cost, addon_cost, pl.price + seat_cost + addon_cost, br;
end $$;

create or replace function public.app_nsi_overview(p_token uuid)
returns table (ref text, cnt bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select 'Заказчики', count(*) from public.app_customers x where adm or x.tenant_id=ten
    union all select 'Поставщики', count(*) from public.app_suppliers x where adm or x.tenant_id=ten
    union all select 'Оборудование', count(*) from public.app_equipment x where adm or x.tenant_id=ten
    union all select 'Материалы', count(*) from public.app_materials x where adm or x.tenant_id=ten
    union all select 'Сотрудники', count(*) from public.app_employees x where adm or x.tenant_id=ten
    union all select 'Справочники', count(*) from public.app_dictionaries x where adm or x.tenant_id=ten
    union all select 'МДМ-связи', count(*) from public.app_mdm_links x where adm or x.tenant_id=ten;
end $$;

create or replace function public.app_help_stats(p_token uuid)
returns table (knowledge bigint, dictionaries bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_knowledge k where adm or k.tenant_id=ten),
    (select count(*) from public.app_dictionaries d where adm or d.tenant_id=ten);
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Платформа/референсы 2.0: карта процесса, тарифы, НСИ, справка (X20)',
   'Платформа 2.0: визуальная карта процесса (app_bpmn_map — nodes/edges из шагов маршрута app_approval_routes, reuse W15), калькулятор тарифов (app_tariff_calc — база + доп. места + доп. модули из app_plans), обзор единой НСИ (app_nsi_overview — заказчики/поставщики/оборудование/материалы/сотрудники/справочники/МДМ-связи), статистика справки (app_help_stats). Конструктор процессов — W15; МДМ — app_mdm_*.',
   'платформа процесс BPMN маршрут тариф калькулятор НСИ справочники справка MDM')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Платформа/референсы 2.0: карта процесса, тарифы, НСИ, справка (X20)'
);

-- ================= Права =================
grant execute on function public.app_bpmn_map(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tariff_calc(uuid,text,integer,jsonb) to anon, authenticated;
grant execute on function public.app_nsi_overview(uuid) to anon, authenticated;
grant execute on function public.app_help_stats(uuid) to anon, authenticated;
