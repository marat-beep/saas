-- ============================================================
-- 3DMP Service · 0239_wizard_power.sql
-- «Мощный мастер»: корректировка норм от веса детали, поисковые
-- селекты (UI), просмотр МК/ОК, опции «нужна оснастка»/«электроды».
--  • app_ref_weight_norms + app_weight_factor — коэффициент по массе.
--  • app_route_from_typical v3 — учитывает вес (plan_min × фактор).
--  • app_tech_wizard_run v4 — вес + доп. опции (оснастка/электроды).
--  • app_master_manufacture v2 — прокидывает вес/опции.
--  • app_tech_route_variants v2 — варианты по форме И материалу.
-- Идемпотентно. Зависит от 0001..0238.
-- ============================================================

create table if not exists public.app_ref_weight_norms (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  kg_from    numeric not null default 0,
  kg_to      numeric,
  factor     numeric not null default 1,
  note       text,
  created_at timestamptz not null default now()
);
alter table public.app_ref_weight_norms enable row level security;

insert into public.app_ref_weight_norms (tenant_id, kg_from, kg_to, factor, note)
select null, v.a, v.b, v.f, v.note from (values
  (0,1,1.00,'мелкие детали'),
  (1,5,1.05,'до 5 кг'),
  (5,20,1.15,'5–20 кг'),
  (20,50,1.30,'20–50 кг'),
  (50,100,1.50,'50–100 кг'),
  (100,500,1.80,'100–500 кг'),
  (500,null,2.20,'крупные > 500 кг')
) as v(a,b,f,note)
where not exists (select 1 from public.app_ref_weight_norms n where n.tenant_id is null and n.kg_from = v.a);

create or replace function public.app_weight_factor(p_token uuid, p_kg numeric)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare adm boolean; ten uuid; f numeric;
begin
  if not public.app_production_allowed(p_token) then return 1; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if p_kg is null or p_kg <= 0 then return 1; end if;
  select n.factor into f from public.app_ref_weight_norms n
   where (n.tenant_id is null or n.tenant_id = ten or adm)
     and p_kg >= n.kg_from and (n.kg_to is null or p_kg < n.kg_to)
   order by n.kg_from desc limit 1;
  return coalesce(f, 1);
end $$;
grant execute on function public.app_weight_factor(uuid,numeric) to anon, authenticated;

-- ---------- app_route_from_typical v3: вес ----------
drop function if exists public.app_route_from_typical(uuid,text,text,numeric);
create or replace function public.app_route_from_typical(p_token uuid, p_code text, p_title text default null, p_qty numeric default 1, p_weight numeric default null)
returns table (ok boolean, message text, id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; tr record; st record; oid uuid; newid uuid; num text; s integer := 0; ttl text; qty numeric; nmin numeric; wf numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  if not public.app_can_edit(p_token, 'registry') then return query select false,'Нет прав на технологию', null::uuid, null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  qty := greatest(coalesce(p_qty,1),1);
  wf := public.app_weight_factor(p_token, p_weight);
  select * into tr from public.app_ref_tech_routes r where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm);
  if tr.id is null then return query select false,'Типовой маршрут не найден', null::uuid, null::text; return; end if;
  ttl := coalesce(nullif(trim(p_title),''), tr.name);
  num := 'RT-' || to_char(now(),'YYMMDD-HH24MI');
  insert into public.app_routes (tenant_id, number, name, status, qty)
  values (ten, num, left(ttl, 200), 'draft', qty) returning app_routes.id into newid;
  for st in select value as e from jsonb_array_elements(coalesce(tr.steps,'[]'::jsonb)) loop
    s := s + 1;
    select o.id into oid from public.app_operations o
      where (adm or o.tenant_id = ten) and lower(o.name) = lower(st.e->>'op') limit 1;
    if oid is null then
      insert into public.app_operations (tenant_id, code, name, kind)
      values (ten, upper(left(regexp_replace(st.e->>'op','[^A-Za-zА-Яа-я0-9]','','g'),20)), left(st.e->>'op',120), 'frezerny')
      returning app_operations.id into oid;
    end if;
    select coalesce(max(n.unit_min),0) into nmin from public.app_ref_op_norms n
      where lower(n.operation) = lower(st.e->>'op') and (n.tenant_id is null or n.tenant_id = ten);
    insert into public.app_route_steps (route_id, seq, operation_id, setup_min, unit_min, qty, plan_min, note)
    values (newid, s, oid, 0, coalesce(nmin,0), qty, round(coalesce(nmin,0) * qty * wf, 1),
            nullif(concat_ws(' · ',
              nullif('Обор.: ' || coalesce(st.e->>'equip',''),'Обор.: '),
              nullif('Припуск: ' || coalesce(st.e->>'allow',''),'Припуск: '),
              nullif('IT: ' || coalesce(st.e->>'acc',''),'IT: '),
              nullif('Ra: ' || coalesce(st.e->>'rough',''),'Ra: ')), ''));
  end loop;
  if p_weight is not null then update public.app_routes set note = 'Масса: ' || p_weight || ' кг (коэф. ' || wf || ')' where id = newid; end if;
  return query select true, 'Маршрут создан (' || s || ' операций' || case when p_weight is not null then ', коэф. веса ' || wf else '' end || ')', newid, num;
end $$;

-- ---------- app_tech_wizard_run v4: вес + опции ----------
drop function if exists public.app_tech_wizard_run(uuid,text,text,text,numeric,date,boolean,boolean,text);
create or replace function public.app_tech_wizard_run(
  p_token uuid, p_code text, p_title text,
  p_material text default null, p_qty numeric default 1, p_due date default null,
  p_make_naryad boolean default true, p_make_doc boolean default true, p_operation text default null,
  p_weight numeric default null, p_extras jsonb default null)
returns table (ok boolean, message text, route_id uuid, route_number text, steps integer, naryad_number text, doc_number text, plan_min numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text;
        rokm boolean; rmsg text; rid uuid; rnum text;
        oid uuid; ns integer; scnt integer; pmin numeric; wf numeric;
        nid uuid; nnum text; dnum text; ttl text; content text; ex text; exops text[];
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
  wf := public.app_weight_factor(p_token, p_weight);

  select r.ok, r.message, r.id, r.number into rokm, rmsg, rid, rnum
    from public.app_route_from_typical(p_token, p_code, ttl, greatest(coalesce(p_qty,1),1), p_weight) r;
  if not coalesce(rokm,false) or rid is null then
    return query select false, coalesce(rmsg,'Типовой маршрут не найден'),null::uuid,null::text,0,null::text,null::text,0::numeric; return;
  end if;
  update public.app_routes set qty = greatest(coalesce(p_qty,1),1),
         note = nullif(concat_ws(' · ',
                  nullif('Материал: ' || coalesce(p_material,''),'Материал: '),
                  nullif('Масса: ' || coalesce(p_weight::text,'') || ' кг','Масса:  кг'),
                  nullif('Коэф. веса: ' || wf,'Коэф. веса: 1')), '')
   where id = rid;

  -- уточняющая операция
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
      values (rid, ns, oid, 0,
              coalesce((select max(n.unit_min) from public.app_ref_op_norms n where lower(n.operation)=lower(trim(p_operation)) and (n.tenant_id is null or n.tenant_id=ten)),0),
              greatest(coalesce(p_qty,1),1),
              round(coalesce((select max(n.unit_min) from public.app_ref_op_norms n where lower(n.operation)=lower(trim(p_operation)) and (n.tenant_id is null or n.tenant_id=ten)),0) * greatest(coalesce(p_qty,1),1) * wf, 1),
              'Добавлено мастером');
    end if;
  end if;

  -- доп. опции: оснастка / электроды → операции в маршрут
  exops := array[]::text[];
  if p_extras is not null then
    for ex in select jsonb_array_elements_text(p_extras) loop
      if ex = 'tooling' then exops := exops || array['Проектирование оснастки','Изготовление оснастки'];
      elsif ex = 'electrodes' then exops := exops || array['Изготовление электродов'];
      elsif ex = 'prototype' then exops := exops || array['Изготовление прототипа'];
      end if;
    end loop;
  end if;
  foreach ex in array exops loop
    if not exists (select 1 from public.app_route_steps rs join public.app_operations o on o.id = rs.operation_id where rs.route_id = rid and lower(o.name) = lower(ex)) then
      select o.id into oid from public.app_operations o where (adm or o.tenant_id = ten) and lower(o.name) = lower(ex) limit 1;
      if oid is null then
        insert into public.app_operations (tenant_id, code, name, kind)
        values (ten, upper(left(regexp_replace(ex,'[^A-Za-zА-Яа-я0-9]','','g'),20)), left(ex,120), 'frezerny') returning id into oid;
      end if;
      select coalesce(max(rs.seq),0) + 1 into ns from public.app_route_steps rs where rs.route_id = rid;
      insert into public.app_route_steps (route_id, seq, operation_id, setup_min, unit_min, qty, plan_min, note)
      values (rid, ns, oid, 0, 0, greatest(coalesce(p_qty,1),1), 0, 'Опция мастера');
    end if;
  end loop;

  select count(*), coalesce(sum(plan_min),0) into scnt, pmin from public.app_route_steps where route_id = rid;

  if coalesce(p_make_naryad, true) then
    select n.id, n.number into nid, nnum from public.app_naryad_create(p_token, null, ttl, null, uname, p_due, 'normal', null) n;
    if nid is not null then update public.app_naryads set route_id = rid, plan_hours = round(coalesce(pmin,0)/60.0, 2) where id = nid; end if;
  end if;

  if coalesce(p_make_doc, true) then
    select string_agg(rs.seq || '. ' || coalesce(o.name,'—') || coalesce(' — ' || nullif(e.name,''), ''), chr(10) order by rs.seq)
      into content
      from public.app_route_steps rs
      left join public.app_operations o on o.id = rs.operation_id
      left join public.app_equipment e on e.id = rs.equipment_id
     where rs.route_id = rid;
    content := 'Техпроцесс: ' || ttl || chr(10) || 'Маршрут: ' || rnum
             || coalesce(' | материал: ' || p_material, '') || ' | партия: ' || greatest(coalesce(p_qty,1),1) || ' шт'
             || coalesce(' | масса: ' || p_weight::text || ' кг (коэф. ' || wf || ')', '')
             || ' | норма: ' || round(coalesce(pmin,0),1) || ' мин' || chr(10) || coalesce(content, '');
    select d.number into dnum from public.app_doc_create(p_token, 'techcard', 'Техкарта: ' || ttl, null, null, null, content) d;
    -- задание на оснастку (если запрошена оснастка)
    if p_extras is not null and p_extras ? 'tooling' then
      perform public.app_doc_create(p_token, 'other', 'Задание на оснастку: ' || ttl, null, null, null,
        'Задание на проектирование и изготовление оснастки для: ' || ttl || chr(10) || 'Маршрут: ' || rnum);
    end if;
  end if;

  return query select true,
    'Создано: маршрут ' || rnum || coalesce(' · наряд ' || nnum, '') || coalesce(' · документ ' || dnum, '')
      || ' · норма ' || round(coalesce(pmin,0),1) || ' мин' || case when wf <> 1 then ' (коэф. веса ' || wf || ')' else '' end,
    rid, rnum, scnt, nnum, dnum, pmin;
end $$;

-- ---------- app_master_manufacture v2 ----------
drop function if exists public.app_master_manufacture(uuid,text,text,text,numeric,date,text,boolean,boolean,boolean);
create or replace function public.app_master_manufacture(
  p_token uuid, p_code text, p_title text,
  p_material text default null, p_qty numeric default 1, p_due date default null, p_operation text default null,
  p_make_naryad boolean default true, p_make_tasks boolean default true, p_make_doc boolean default true,
  p_weight numeric default null, p_extras jsonb default null)
returns table (ok boolean, message text, route_id uuid, route_number text, steps integer, naryad_number text, doc_number text, jobs integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record; jc integer := 0; msg text;
begin
  if not public.app_production_allowed(p_token) then
    return query select false,'Доступ запрещён',null::uuid,null::text,0,null::text,null::text,0; return;
  end if;
  select * into r from public.app_tech_wizard_run(p_token, p_code, p_title, p_material, p_qty, p_due, p_make_naryad, p_make_doc, p_operation, p_weight, p_extras);
  if not coalesce(r.ok, false) then
    return query select false, coalesce(r.message,'Не удалось создать техпроцесс'), null::uuid, null::text, 0, null::text, null::text, 0; return;
  end if;
  msg := coalesce(r.message, 'Готово');
  if coalesce(p_make_tasks, true) then
    perform public.app_daily_job_build(p_token, current_date);
    select count(*) into jc from public.app_daily_job_list(p_token, current_date);
    msg := msg || ' · ССЗ: ' || jc;
  end if;
  return query select true, msg, r.route_id, r.route_number, r.steps, r.naryad_number, r.doc_number, jc;
end $$;

-- ---------- app_tech_route_variants v2: форма И материал ----------
drop function if exists public.app_tech_route_variants(uuid,text);
create or replace function public.app_tech_route_variants(p_token uuid, p_code text)
returns table (code text, name text, material text, heat text, shape text, steps integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; sh text; mat text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select r.shape, r.material into sh, mat from public.app_ref_tech_routes r
   where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm) limit 1;
  return query
    select r.code, r.name, r.material, r.heat, r.shape, coalesce(jsonb_array_length(coalesce(r.steps,'[]'::jsonb)),0)::int
      from public.app_ref_tech_routes r
     where (r.tenant_id is null or r.tenant_id = ten or adm)
       and r.code <> p_code
       and ((sh is not null and r.shape = sh) or (mat is not null and r.material = mat))
     order by (case when sh is not null and r.shape = sh then 0 else 1 end), r.code;
end $$;

grant execute on function public.app_route_from_typical(uuid,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_tech_wizard_run(uuid,text,text,text,numeric,date,boolean,boolean,text,numeric,jsonb) to anon, authenticated;
grant execute on function public.app_master_manufacture(uuid,text,text,text,numeric,date,text,boolean,boolean,boolean,numeric,jsonb) to anon, authenticated;
grant execute on function public.app_tech_route_variants(uuid,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Мастер техпроцесса: вес, оснастка, электроды, просмотр МК/ОК',
   'Мастер учитывает массу детали: коэффициент по массе (app_ref_weight_norms: до 1 кг ×1.0 … >500 кг ×2.2) множит норму времени (plan_min = норма × партия × коэф. веса). Опции: «нужна оснастка» добавляет операции «Проектирование оснастки» и «Изготовление оснастки» и документ «Задание на оснастку»; «электроды» добавляет «Изготовление электродов» (для прошивной ЭЭО). Тип детали и операции выбираются через поисковый селект с иконками; МК/ОК/ВО можно просмотреть в окне (без немедленной печати). RPC: app_weight_factor, app_route_from_typical v3, app_tech_wizard_run v4, app_master_manufacture v2, app_tech_route_variants v2.',
   'мастер техпроцесса вес масса оснастка электроды проектирование МК ОК просмотр иконки поиск app_weight_factor')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
