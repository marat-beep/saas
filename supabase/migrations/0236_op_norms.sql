-- ============================================================
-- 3DMP Service · 0236_op_norms.sql
-- Нормы времени операций (app_ref_op_norms) и авто-расчёт норм в маршрутах.
-- app_route_from_typical теперь проставляет unit_min/plan_min по нормам и партии;
-- предпросмотр мастера показывает норму; run передаёт партию.
-- Идемпотентно. Зависит от 0001..0235.
-- ============================================================

create table if not exists public.app_ref_op_norms (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  operation  text not null,
  unit_min   numeric not null default 0,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_op_norms_idx on public.app_ref_op_norms (operation);
alter table public.app_ref_op_norms enable row level security;

insert into public.app_ref_op_norms (tenant_id, operation, unit_min, note)
select null, v.op, v.m, v.note from (values
  ('Заготовительная',8,'Резка/отрезка заготовки'),
  ('Резка',5,null),('Резка (ленточнопильная)',5,null),
  ('Токарная черновая',20,null),('Токарная чистовая',14,null),('Токарная',16,null),('Токарная (наружная)',16,null),
  ('Фрезерная черновая',22,null),('Фрезерная чистовая',18,null),('Фрезерная',16,null),('Фрезерная чистовая (HSC)',24,null),
  ('Сверлильная',6,null),('Координатно-сверлильная',10,null),('Расточная',12,null),('Резьбонарезание',8,null),
  ('Зубофрезерная',26,null),('Зубодолбёжная',24,null),('Зубошлифование',28,null),('Зубошлифовальная',28,null),
  ('Зачистка кромок',4,null),('Слесарная',6,null),('Слесарная доводка',8,null),('Маркировка',3,null),('Сборка',12,null),
  ('Термообработка',30,null),('Закалка ТВЧ',25,null),('Цементация',40,null),('Азотирование',40,null),
  ('Анодирование',20,null),('Нанесение покрытия',20,null),
  ('Шлифование',16,null),('Шлифование плоское',16,null),('Плоское шлифование',16,null),('Шлифование круглое',18,null),
  ('Круглошлифовальная',18,null),('Внутреннее шлифование',20,null),('Хонингование',22,null),('Притирка',18,null),('Полирование',14,null),
  ('Гибка',6,null),('Штамповка',8,null),('Правка',5,null),('Сварка',15,null),('Гравирование',5,null),
  ('Контроль ОТК',5,null),('Измерения на КИМ',8,null)
) as v(op,m,note)
where not exists (select 1 from public.app_ref_op_norms n where n.tenant_id is null and n.operation = v.op);

create or replace function public.app_op_norms_list(p_token uuid, p_q text default null)
returns table (id uuid, operation text, unit_min numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select n.id, n.operation, n.unit_min, n.note
    from public.app_ref_op_norms n
   where (n.tenant_id is null or n.tenant_id = ten or adm)
     and (qq='' or lower(n.operation) like '%'||qq||'%')
   order by n.operation;
end $$;

create or replace function public.app_op_norm_save(p_token uuid, p_operation text, p_unit_min numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token,'registry') then return query select false,'Нет прав на справочники'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_operation),'') = '' then return query select false,'Укажите операцию'; return; end if;
  select n.id into nid from public.app_ref_op_norms n where n.tenant_id is null and lower(n.operation)=lower(trim(p_operation)) limit 1;
  if nid is null then
    insert into public.app_ref_op_norms (tenant_id, operation, unit_min, note)
    values (null, trim(p_operation), greatest(coalesce(p_unit_min,0),0), nullif(trim(p_note),''));
    return query select true,'Норма добавлена';
  else
    update public.app_ref_op_norms set unit_min = greatest(coalesce(p_unit_min,unit_min),0), note = nullif(trim(p_note),note) where id = nid;
    return query select true,'Норма обновлена';
  end if;
end $$;

grant execute on function public.app_op_norms_list(uuid,text) to anon, authenticated;
grant execute on function public.app_op_norm_save(uuid,text,numeric,text) to anon, authenticated;

-- ---------- app_route_from_typical v2: нормы + партия ----------
drop function if exists public.app_route_from_typical(uuid,text,text);
create or replace function public.app_route_from_typical(p_token uuid, p_code text, p_title text default null, p_qty numeric default 1)
returns table (ok boolean, message text, id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; tr record; st record; oid uuid; newid uuid; num text; s integer := 0; ttl text; qty numeric; nmin numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  if not public.app_can_edit(p_token, 'registry') then return query select false,'Нет прав на технологию', null::uuid, null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  qty := greatest(coalesce(p_qty,1),1);
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
    -- норма времени по операции (глобальная или тенантная)
    select coalesce(max(n.unit_min),0) into nmin from public.app_ref_op_norms n
      where lower(n.operation) = lower(st.e->>'op') and (n.tenant_id is null or n.tenant_id = ten);
    insert into public.app_route_steps (route_id, seq, operation_id, setup_min, unit_min, qty, plan_min, note)
    values (newid, s, oid, 0, coalesce(nmin,0), qty, round(coalesce(nmin,0) * qty, 1),
            nullif(concat_ws(' · ',
              nullif('Обор.: ' || coalesce(st.e->>'equip',''),'Обор.: '),
              nullif('Припуск: ' || coalesce(st.e->>'allow',''),'Припуск: '),
              nullif('IT: ' || coalesce(st.e->>'acc',''),'IT: '),
              nullif('Ra: ' || coalesce(st.e->>'rough',''),'Ra: ')), ''));
  end loop;
  return query select true, 'Маршрут создан (' || s || ' операций)', newid, num;
end $$;

-- ---------- preview v2: с нормой ----------
drop function if exists public.app_tech_wizard_preview(uuid,text);
create or replace function public.app_tech_wizard_preview(p_token uuid, p_code text)
returns table (seq integer, operation text, equipment text, note text, unit_min numeric)
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
             nullif('Ra ' || coalesce(t.e->>'rough',''), 'Ra ')), ''),
           coalesce((select max(n.unit_min) from public.app_ref_op_norms n
                      where lower(n.operation) = lower(t.e->>'op') and (n.tenant_id is null or n.tenant_id = ten)), 0)
      from public.app_ref_tech_routes r,
           jsonb_array_elements(coalesce(r.steps, '[]'::jsonb)) with ordinality as t(e, ord)
     where r.code = p_code and (r.tenant_id is null or r.tenant_id = ten or adm)
     order by t.ord;
end $$;

-- ---------- run v3: передаёт партию в маршрут ----------
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

  select r.ok, r.message, r.id, r.number into rokm, rmsg, rid, rnum
    from public.app_route_from_typical(p_token, p_code, ttl, greatest(coalesce(p_qty,1),1)) r;
  if not coalesce(rokm,false) or rid is null then
    return query select false, coalesce(rmsg,'Типовой маршрут не найден'),null::uuid,null::text,0,null::text,null::text,0::numeric; return;
  end if;
  update public.app_routes set qty = greatest(coalesce(p_qty,1),1),
         note = nullif('Материал: ' || coalesce(p_material,''), 'Материал: ')
   where id = rid;

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
              round(coalesce((select max(n.unit_min) from public.app_ref_op_norms n where lower(n.operation)=lower(trim(p_operation)) and (n.tenant_id is null or n.tenant_id=ten)),0) * greatest(coalesce(p_qty,1),1), 1),
              'Добавлено мастером');
    end if;
  end if;

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
             || ' | норма: ' || round(coalesce(pmin,0),1) || ' мин' || chr(10) || coalesce(content, '');
    select d.number into dnum from public.app_doc_create(p_token, 'techcard', 'Техкарта: ' || ttl, null, null, null, content) d;
  end if;

  return query select true,
    'Создано: маршрут ' || rnum || coalesce(' · наряд ' || nnum, '') || coalesce(' · документ ' || dnum, '')
      || ' · норма ' || round(coalesce(pmin,0),1) || ' мин',
    rid, rnum, scnt, nnum, dnum, pmin;
end $$;

grant execute on function public.app_route_from_typical(uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_tech_wizard_preview(uuid,text) to anon, authenticated;
grant execute on function public.app_tech_wizard_run(uuid,text,text,text,numeric,date,boolean,boolean,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Нормы времени операций и авто-расчёт в маршрутах',
   'Справочник «Нормы времени» (app_ref_op_norms) задаёт типовую норму (мин/шт) по операции. При создании маршрута из типового (app_route_from_typical) шаги получают unit_min из справочника, а plan_min = норма × партия; наряд получает plan_hours = норма/60. Предпросмотр мастера показывает норму по каждой операции. Редактирование — «Справочники → Техданные → Нормы времени» (кнопка «＋ Норма времени», RPC app_op_norm_save).',
   'нормы времени операции авто-расчёт маршрут plan_min app_ref_op_norms app_route_from_typical')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
