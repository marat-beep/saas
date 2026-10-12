-- ============================================================
-- 3DMP Service · 0223_route_ok_vo.sql
-- Печать документов ЕСТД по маршруту: операционная карта (ОК) и
-- ведомость оснастки (ВО). Продолжение 0222 (маршрутная карта, МК).
-- Идемпотентно. Зависит от 0001..0222.
-- ============================================================

-- ---------- ОК: операционная карта (по шагам маршрута) ----------
create or replace function public.app_route_ok(p_token uuid, p_id uuid)
returns table (seq integer, operation text, equipment text, setup_min numeric, unit_min numeric, plan_min numeric, cost numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select rs.seq, coalesce(o.name,'—'), coalesce(e.name,'—'),
           rs.setup_min, rs.unit_min, rs.plan_min, rs.cost, rs.note
      from public.app_route_steps rs
      left join public.app_operations o on o.id = rs.operation_id
      left join public.app_equipment e on e.id = rs.equipment_id
     where rs.route_id = p_id
       and exists (select 1 from public.app_routes r where r.id = p_id and (adm or r.tenant_id = ten))
     order by rs.seq;
end $$;

-- ---------- ВО: ведомость оснастки (оборудование + инструмент по шагам) ----------
create or replace function public.app_route_vo(p_token uuid, p_id uuid)
returns table (seq integer, kind text, designation text, name text, standard text, qty numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select rs.seq, 'Оборудование'::text, coalesce(e.code,'—'), coalesce(e.name,'—'), null::text, 1::numeric, null::text
      from public.app_route_steps rs
      join public.app_equipment e on e.id = rs.equipment_id
      join public.app_routes r on r.id = rs.route_id
     where rs.route_id = p_id and (adm or r.tenant_id = ten)
    union all
    select rs.seq, coalesce(tl.tool_type,'Инструмент')::text, coalesce(tl.code,'—')::text, coalesce(tl.name,'—')::text,
           nullif(concat_ws(' · ', nullif(tl.material,''), nullif(tl.coating,'')), '')::text,
           coalesce(rt.qty,1)::numeric, rt.note::text
      from public.app_route_tools rt
      join public.app_route_steps rs on rs.id = rt.route_step_id
      join public.app_routes r on r.id = rs.route_id
      left join public.app_tool_life tl on tl.id = rt.tool_life_id
     where rs.route_id = p_id and (adm or r.tenant_id = ten)
    order by 1, 2;
end $$;

grant execute on function public.app_route_ok(uuid,uuid) to anon, authenticated;
grant execute on function public.app_route_vo(uuid,uuid) to anon, authenticated;
