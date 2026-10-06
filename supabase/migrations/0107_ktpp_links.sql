-- ============================================================
-- 3DMP Service · 0107_ktpp_links.sql  (v92 — PLAN_MODERNIZATION, Партия D)
-- КТПП: НСИ ↔ спецификация ↔ маршрут ↔ УП.
--   * маршрут из спецификации (BOM: операции → шаги маршрута);
--   * техкарта-документ из маршрута (через схемы 0105);
--   * УП (NC) из маршрута + связь route↔nc (app_links).
-- Идемпотентно. Зависит от 0001..0106.
-- ============================================================

-- ---------- Маршрут из спецификации ----------
create or replace function public.app_route_from_bom(p_token uuid, p_bom_id uuid, p_name text default null)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; b record; rnum text; rid uuid; i int := 0; ln record; mat uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id and (urole='admin' or b0.tenant_id=ten);
  if b.id is null then raise exception 'Спецификация не найдена'; return; end if;
  select bl.material_id into mat from public.app_bom_lines bl
    where bl.bom_id = p_bom_id and bl.item_type='material' and bl.material_id is not null order by bl.seq limit 1;
  rnum := 'RT-' || lpad(nextval('public.app_route_seq')::text, 5, '0');
  insert into public.app_routes (tenant_id, number, name, order_id, material_id, qty, status, created_by, created_login)
  values (ten, rnum, coalesce(nullif(trim(p_name),''), 'Маршрут: ' || coalesce(b.product,'')), b.order_id, mat, b.qty, 'draft', uid, ulogin)
  returning app_routes.id into rid;
  for ln in select * from public.app_bom_lines bl where bl.bom_id = p_bom_id and bl.item_type='operation' order by bl.seq loop
    i := i + 1;
    insert into public.app_route_steps (route_id, seq, operation_id, qty, unit_min, plan_min)
    values (rid, i, ln.operation_id, coalesce(b.qty,1), coalesce(ln.norm_hours,0)*60, coalesce(ln.norm_hours,0)*60*coalesce(b.qty,1));
  end loop;
  begin perform public.app_route_calc(p_token, rid, coalesce(b.qty,1)); exception when others then null; end;
  return query select rid, rnum, 'Маршрут создан из спецификации (шагов: ' || i::text || ')';
end $$;

-- ---------- Техкарта-документ из маршрута ----------
create or replace function public.app_doc_from_route(p_token uuid, p_route_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; r record; sid uuid; did uuid; dnum text; body text; ln record; cnt int := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r0.* into r from public.app_routes r0 where r0.id = p_route_id and (urole='admin' or r0.tenant_id=ten);
  if r.id is null then raise exception 'Маршрут не найден'; return; end if;
  select sc.id into sid from public.app_schemas sc where sc.code='techcard' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'TC-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  body := 'Технологическая карта ' || coalesce(r.number,'') || ' от ' || to_char(current_date,'DD.MM.YYYY') || E'\n' || coalesce(r.name,'') || E'\n\n';
  for ln in
    select st.seq, coalesce(o.name,'') as opname, coalesce(e.name,'') as eqname, st.plan_min, st.cost
      from public.app_route_steps st
      left join public.app_operations o on o.id = st.operation_id
      left join public.app_equipment e on e.id = st.equipment_id
      where st.route_id = p_route_id order by st.seq
  loop
    cnt := cnt + 1;
    body := body || ln.seq::text || '. ' || ln.opname || (case when ln.eqname <> '' then '  (' || ln.eqname || ')' else '' end) ||
            '  ·  ' || coalesce(ln.plan_min,0)::text || ' мин  ·  ' || round(coalesce(ln.cost,0),2)::text || ' ₽' || E'\n';
  end loop;
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'techcard', dnum, 'Техкарта: ' || coalesce(r.name,''), r.order_id, 'draft', body,
          jsonb_build_object('product', coalesce(r.name,''), 'norm_hours', coalesce(r.total_min,0)/60),
          sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Техкарта: ' || coalesce(r.name,''), body, ulogin);
  return query select did, dnum, 'Техкарта создана из маршрута';
end $$;

-- ---------- УП (NC) из маршрута + связь ----------
create or replace function public.app_nc_from_route(p_token uuid, p_route_id uuid, p_program_no text, p_equipment_id uuid default null)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; urole text; ten uuid; r record; nid uuid; pno text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select r0.* into r from public.app_routes r0 where r0.id = p_route_id and (urole='admin' or r0.tenant_id=ten);
  if r.id is null then raise exception 'Маршрут не найден'; return; end if;
  pno := coalesce(nullif(trim(p_program_no), ''), 'UP-' || coalesce(r.number,''));
  insert into public.app_nc_programs (tenant_id, order_id, equipment_id, detail, program_no, version, status, created_login)
  values (ten, r.order_id, p_equipment_id, r.name, pno, 1, 'draft', ulogin)
  returning app_nc_programs.id into nid;
  insert into public.app_links (tenant_id, source_type, source_id, target_type, target_id, kind, note)
  values (ten, 'route', p_route_id, 'nc', nid, 'up', 'УП по маршруту ' || coalesce(r.number,''));
  return query select nid, 'УП привязана к маршруту';
end $$;

grant execute on function public.app_route_from_bom(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_from_route(uuid,uuid) to anon, authenticated;
grant execute on function public.app_nc_from_route(uuid,uuid,text,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('КТПП','Связка НСИ ↔ спецификация ↔ маршрут ↔ УП (Партия D)',
   'Маршрут из спецификации: app_route_from_bom переносит операции спецификации в шаги маршрута (нормо-часы → план-минуты) и связывает маршрут с заявкой/материалом. Техкарта: app_doc_from_route формирует документ-техкарту (TC-) со шагами (операция, оборудование, минуты, стоимость). УП: app_nc_from_route создаёт программу NC и связывает её с маршрутом (app_links route↔nc). Так НСИ (оборудование/операции/материалы) → спецификация → маршрут → УП/техкарта образуют единую цепочку КТПП.',
   'КТПП спецификация маршрут УП NC техкарта НСИ связки партия D app_route_from_bom app_doc_from_route app_nc_from_route')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Связка НСИ ↔ спецификация ↔ маршрут ↔ УП (Партия D)');
