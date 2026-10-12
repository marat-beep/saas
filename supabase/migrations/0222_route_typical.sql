-- ============================================================
-- 3DMP Service · 0222_route_typical.sql
-- Генерация технологического маршрута из типового (app_ref_tech_routes).
-- Создаёт маршрут и операции шагов (при отсутствии — создаёт операцию).
-- Идемпотентно. Зависит от 0001..0221.
-- ============================================================

create or replace function public.app_route_from_typical(p_token uuid, p_code text, p_title text default null)
returns table (ok boolean, message text, id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; tr record; st record; oid uuid; newid uuid; num text; s integer := 0; ttl text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  if not public.app_can_edit(p_token, 'registry') then return query select false,'Нет прав на технологию', null::uuid, null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select * into tr from public.app_ref_tech_routes r where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm);
  if tr.id is null then return query select false,'Типовой маршрут не найден', null::uuid, null::text; return; end if;
  ttl := coalesce(nullif(trim(p_title),''), tr.name);
  num := 'RT-' || to_char(now(),'YYMMDD-HH24MI');
  insert into public.app_routes (tenant_id, number, name, status, qty)
  values (ten, num, left(ttl, 200), 'draft', 1) returning app_routes.id into newid;
  for st in select value as e from jsonb_array_elements(coalesce(tr.steps,'[]'::jsonb)) loop
    s := s + 1;
    select o.id into oid from public.app_operations o
      where (adm or o.tenant_id = ten) and lower(o.name) = lower(st.e->>'op') limit 1;
    if oid is null then
      insert into public.app_operations (tenant_id, code, name, kind)
      values (ten, upper(left(regexp_replace(st.e->>'op','[^A-Za-zА-Яа-я0-9]','','g'),20)), left(st.e->>'op',120), 'frezerny')
      returning app_operations.id into oid;
    end if;
    insert into public.app_route_steps (route_id, seq, operation_id, setup_min, unit_min, qty, plan_min, note)
    values (newid, s, oid, 0, 0, 1, 0,
            nullif(concat_ws(' · ',
              nullif('Обор.: ' || coalesce(st.e->>'equip',''),'Обор.: '),
              nullif('Припуск: ' || coalesce(st.e->>'allow',''),'Припуск: '),
              nullif('IT: ' || coalesce(st.e->>'acc',''),'IT: '),
              nullif('Ra: ' || coalesce(st.e->>'rough',''),'Ra: ')), ''));
  end loop;
  return query select true, 'Маршрут создан (' || s || ' операций)', newid, num;
end $$;

-- МК (маршрутная карта ЕСТД) — данные для печати
create or replace function public.app_route_mk(p_token uuid, p_id uuid)
returns table (seq integer, operation text, equipment text, plan_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select rs.seq, coalesce(o.name,'—'), coalesce(e.name,'—'), rs.plan_min, rs.note
      from public.app_route_steps rs
      left join public.app_operations o on o.id = rs.operation_id
      left join public.app_equipment e on e.id = rs.equipment_id
     where rs.route_id = p_id
       and exists (select 1 from public.app_routes r where r.id = p_id and (adm or r.tenant_id = ten))
     order by rs.seq;
end $$;

grant execute on function public.app_route_from_typical(uuid,text,text) to anon, authenticated;
grant execute on function public.app_route_mk(uuid,uuid) to anon, authenticated;
