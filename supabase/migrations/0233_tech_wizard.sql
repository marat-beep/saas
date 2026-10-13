-- ============================================================
-- 3DMP Service · 0233_tech_wizard.sql
-- Мастер техпроцесса: пошаговый подбор технологии с автоматическим
-- созданием записей и документов.
--  • app_tech_wizard_options — справочные списки для шагов мастера
--    (тип детали / материал / операция).
--  • app_tech_wizard_run — создаёт маршрут из типового (+операцию),
--    наряд (опц.) и документ-техкарту (опц.), возвращает сводку.
-- Идемпотентно. Зависит от 0001..0232.
-- ============================================================

create or replace function public.app_tech_wizard_options(p_token uuid, p_kind text)
returns table (code text, name text, info text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; kk text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  kk := lower(coalesce(trim(p_kind),'part'));
  if kk = 'material' then
    return query select m.grade, m.grade, m.group_code
      from public.app_ref_material_list(p_token, null, null) m
     order by m.grade;
  elsif kk = 'operation' then
    return query select c.operation, c.operation, coalesce(max(c.tool_type),'')
      from public.app_ref_cutting_list(p_token, null, null) c
     where coalesce(c.operation,'') <> ''
     group by c.operation
     order by c.operation;
  else
    return query select r.code, r.name, concat_ws(' · ', nullif(r.shape,''), nullif(r.material,''), nullif(r.heat,''))
      from public.app_ref_tech_routes r
     where (r.tenant_id is null or r.tenant_id = ten or adm)
     order by r.code;
  end if;
end $$;

create or replace function public.app_tech_wizard_run(
  p_token uuid, p_code text, p_title text,
  p_material text default null, p_qty numeric default 1, p_due date default null,
  p_make_naryad boolean default true, p_make_doc boolean default true, p_operation text default null)
returns table (ok boolean, message text, route_id uuid, route_number text, steps integer, naryad_number text, doc_number text, plan_min numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text;
        rokm boolean; rmsg text; rid uuid; rnum text;
        oid uuid; ns integer; scnt integer; pmin numeric;
        nid uuid; nnum text; dnum text; ttl text; content text;
begin
  if not public.app_production_allowed(p_token) then
    return query select false,'Доступ запрещён',null::uuid,null::text,0,null::text,null::text,0::numeric; return;
  end if;
  if not (public.app_can_edit(p_token,'registry') or public.app_can_edit(p_token,'production')) then
    return query select false,'Нет прав на технологию',null::uuid,null::text,0,null::text,null::text,0::numeric; return;
  end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  ttl := coalesce(nullif(trim(p_title),''), 'Техпроцесс');

  -- 1) маршрут из типового
  select r.ok, r.message, r.id, r.number into rokm, rmsg, rid, rnum
    from public.app_route_from_typical(p_token, p_code, ttl) r;
  if not coalesce(rokm,false) or rid is null then
    return query select false, coalesce(rmsg,'Типовой маршрут не найден'),null::uuid,null::text,0,null::text,null::text,0::numeric; return;
  end if;
  update public.app_routes set qty = greatest(coalesce(p_qty,1),1),
         note = nullif('Материал: ' || coalesce(p_material,''), 'Материал: ')
   where id = rid;

  -- 2) уточняющая операция (добавляется, если её нет в маршруте)
  if coalesce(trim(p_operation),'') <> '' then
    if not exists (select 1 from public.app_route_steps rs join public.app_operations o on o.id = rs.operation_id
                   where rs.route_id = rid and lower(o.name) = lower(trim(p_operation))) then
      select o.id into oid from public.app_operations o
        where (adm or o.tenant_id = ten) and lower(o.name) = lower(trim(p_operation)) limit 1;
      if oid is null then
        insert into public.app_operations (tenant_id, code, name, kind)
        values (ten, upper(left(regexp_replace(trim(p_operation),'[^A-Za-zА-Яа-я0-9]','','g'),20)), left(trim(p_operation),120), 'frezerny')
        returning id into oid;
      end if;
      select coalesce(max(rs.seq),0) + 1 into ns from public.app_route_steps rs where rs.route_id = rid;
      insert into public.app_route_steps (route_id, seq, operation_id, setup_min, unit_min, qty, plan_min, note)
      values (rid, ns, oid, 0, 0, 1, 0, 'Добавлено мастером');
    end if;
  end if;

  select count(*), coalesce(sum(plan_min),0) into scnt, pmin from public.app_route_steps where route_id = rid;

  -- 3) наряд
  if coalesce(p_make_naryad, true) then
    select n.id, n.number into nid, nnum from public.app_naryad_create(p_token, null, ttl, null, uname, p_due, 'normal', null) n;
    if nid is not null then update public.app_naryads set route_id = rid where id = nid; end if;
  end if;

  -- 4) документ-техкарта
  if coalesce(p_make_doc, true) then
    select string_agg(rs.seq || '. ' || coalesce(o.name,'—') || coalesce(' — ' || nullif(e.name,''), ''), chr(10) order by rs.seq)
      into content
      from public.app_route_steps rs
      left join public.app_operations o on o.id = rs.operation_id
      left join public.app_equipment e on e.id = rs.equipment_id
     where rs.route_id = rid;
    content := 'Техпроцесс: ' || ttl || chr(10) || 'Маршрут: ' || rnum
             || coalesce(' | материал: ' || p_material, '') || ' | партия: ' || greatest(coalesce(p_qty,1),1) || ' шт'
             || chr(10) || coalesce(content, '');
    select d.number into dnum from public.app_doc_create(p_token, 'techcard', 'Техкарта: ' || ttl, null, null, null, content) d;
  end if;

  return query select true,
    'Создано: маршрут ' || rnum || coalesce(' · наряд ' || nnum, '') || coalesce(' · документ ' || dnum, ''),
    rid, rnum, scnt, nnum, dnum, pmin;
end $$;

grant execute on function public.app_tech_wizard_options(uuid,text) to anon, authenticated;
grant execute on function public.app_tech_wizard_run(uuid,text,text,text,numeric,date,boolean,boolean,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Мастер техпроцесса: пошаговый подбор и автосоздание записей',
   'Мастер техпроцесса ведёт по шагам: (1) тип детали (из типовых маршрутов), (2) материал и размер партии, (3) уточняющая операция (необязательно), (4) название/срок и опции создания. На выходе RPC app_tech_wizard_run автоматически: строит маршрут из типового (операции + шаги), при необходимости добавляет уточняющую операцию, создаёт наряд (app_naryad_create, привязка к маршруту) и документ-техкарту (app_doc_create, тип techcard с текстом операций). Запуск — кнопка «🧭 Мастер техпроцесса» в «Справочниках».
',
   'мастер техпроцесса подбор технологии автосоздание маршрут наряд техкарта app_tech_wizard компонент wizard')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
