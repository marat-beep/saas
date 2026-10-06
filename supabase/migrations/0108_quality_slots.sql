-- ============================================================
-- 3DMP Service · 0108_quality_slots.sql  (v93 — PLAN_MODERNIZATION, Партия E)
-- Производство/Качество:
--   * протокол ОТК → документ (схема protocol) из app_qc_checks;
--   * паспорт → документ (схема passport) из app_passports;
--   * слоты ↔ прогноз: сводка день/план/мощность/свободно/загрузка/совет.
-- Идемпотентно. Зависит от 0001..0107.
-- ============================================================

-- ---------- Типы документов: добавить «protocol» ----------
create or replace function public.app_doc_type_schemas(p_token uuid)
returns table (schema_id uuid, code text, name text, icon text, fields bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select sc.id, sc.code, sc.name, sc.icon,
           (select count(*) from public.app_schema_fields f where f.schema_id = sc.id)
    from public.app_schemas sc
    where (urole='admin' or sc.tenant_id = ten)
      and sc.active
      and sc.code in ('kp','contract','act','techcard','invoice','waybill','tz','passport','protocol')
    order by array_position(array['kp','contract','act','techcard','invoice','waybill','tz','passport','protocol'], sc.code);
end $$;
grant execute on function public.app_doc_type_schemas(uuid) to anon, authenticated;

-- ---------- Протокол ОТК → документ ----------
create or replace function public.app_doc_from_qc(p_token uuid, p_qc_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; q record; sid uuid; did uuid; dnum text; body text; ln record; cnt int := 0; res text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select q0.* into q from public.app_qc_checks q0 where q0.id = p_qc_id and (urole='admin' or q0.tenant_id=ten);
  if q.id is null then raise exception 'Проверка ОТК не найдена'; return; end if;
  select sc.id into sid from public.app_schemas sc where sc.code='protocol' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'PRT-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  res := case when coalesce(q.qty_total,0)>0 and coalesce(q.qty_good,0) >= coalesce(q.qty_total,0) then 'годен'
              when coalesce(q.qty_good,0) > 0 then 'условно' else 'брак' end;
  body := 'Протокол контроля ' || coalesce(q.number,'') || ' от ' || to_char(current_date,'DD.MM.YYYY') || E'\n' ||
          'Изделие: ' || coalesce(q.product,'') || E'\n' ||
          'Контролёр: ' || coalesce(q.inspector,'—') || E'\n' ||
          'Всего: ' || coalesce(q.qty_total,0)::text || ' · годных: ' || coalesce(q.qty_good,0)::text || E'\n' ||
          'Результат: ' || res || E'\n\nПозиции контроля:' || E'\n';
  for ln in select l.name, l.norm, l.value, l.result from public.app_qc_lines_list(p_token, p_qc_id) l loop
    cnt := cnt + 1;
    body := body || '  ' || cnt::text || '. ' || coalesce(ln.name,'') ||
            (case when coalesce(ln.norm,'')<>'' then ' (норма: '||ln.norm||')' else '' end) ||
            '  →  ' || coalesce(nullif(ln.value,''),'—') || '  [' || coalesce(ln.result,'—') || ']' || E'\n';
  end loop;
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'protocol', dnum, 'Протокол контроля: ' || coalesce(q.product,''), q.order_id, 'draft', body,
          jsonb_build_object('product', coalesce(q.product,''), 'qc_number', coalesce(q.number,''), 'inspector', coalesce(q.inspector,''),
                             'qty_total', coalesce(q.qty_total,0), 'qty_good', coalesce(q.qty_good,0), 'result', res),
          sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Протокол контроля: ' || coalesce(q.product,''), body, ulogin);
  return query select did, dnum, 'Протокол ОТК создан';
end $$;

-- ---------- Паспорт → документ ----------
create or replace function public.app_doc_from_passport(p_token uuid, p_passport_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; pp record; sid uuid; did uuid; dnum text; body text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select p0.* into pp from public.app_passports p0 where p0.id = p_passport_id and (urole='admin' or p0.tenant_id=ten);
  if pp.id is null then raise exception 'Паспорт не найден'; return; end if;
  select sc.id into sid from public.app_schemas sc where sc.code='passport' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'PSP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  body := 'Паспорт изделия ' || coalesce(pp.number,'') || ' от ' || to_char(current_date,'DD.MM.YYYY') || E'\n' ||
          'Изделие: ' || coalesce(pp.product,'') || E'\n' ||
          'Серийный №: ' || coalesce(pp.serial,'—') || E'\n' ||
          'Количество: ' || coalesce(pp.qty,1)::text || E'\n' ||
          'Статус: ' || coalesce(pp.status,'') || E'\n';
  if pp.data is not null then body := body || E'\nДанные: ' || pp.data::text || E'\n'; end if;
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'passport', dnum, 'Паспорт: ' || coalesce(pp.product,''), pp.order_id, 'draft', body,
          jsonb_build_object('product', coalesce(pp.product,''), 'serial', coalesce(pp.serial,''), 'qty', coalesce(pp.qty,1),
                             'note', coalesce(pp.status,'')),
          sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Паспорт: ' || coalesce(pp.product,''), body, ulogin);
  return query select did, dnum, 'Документ-паспорт создан';
end $$;

-- ---------- Слоты ↔ прогноз ----------
create or replace function public.app_forecast_slots(p_token uuid, p_days integer default 14)
returns table (day date, planned numeric, capacity numeric, free numeric, load_pct numeric, advice text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with days as (
      select generate_series(current_date, current_date + greatest(coalesce(p_days,14),1) - 1, interval '1 day')::date as d
    )
    select d.d,
           p.plan, c.cap, greatest(c.cap - p.plan, 0),
           case when c.cap > 0 then round(p.plan / c.cap * 100, 1) else null end,
           case when c.cap = 0 and p.plan > 0 then 'Нет слотов — создайте'
                when c.cap > 0 and p.plan > c.cap then 'Перегрузка — добавьте смену/слот'
                when c.cap > 0 and p.plan >= c.cap * 0.9 then 'Близко к пределу'
                else 'В норме' end
    from days d
    cross join lateral (
      select coalesce(sum(n.plan_hours),0) as plan from public.app_naryads n
       where (urole='admin' or n.tenant_id=ten) and n.status not in ('closed','cancelled') and n.due_date = d.d
    ) p
    cross join lateral (
      select coalesce(sum(w.capacity_hours),0) as cap from public.app_work_slots w
       where (urole='admin' or w.tenant_id=ten) and w.slot_date = d.d
    ) c
    order by d.d;
end $$;

grant execute on function public.app_doc_from_qc(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_from_passport(uuid,uuid) to anon, authenticated;
grant execute on function public.app_forecast_slots(uuid,integer) to anon, authenticated;

-- ---------- Демо: схема «Протокол контроля» (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='protocol') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'protocol','Протокол контроля','🔬','Протокол ОТК') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, required, sort) values
      (sid,'product','Изделие','text',true,10),
      (sid,'qc_number','№ проверки','text',false,20),
      (sid,'inspector','Контролёр','text',false,30),
      (sid,'qty_total','Всего','number',false,40),
      (sid,'qty_good','Годных','number',false,50),
      (sid,'result','Результат','select',false,60),
      (sid,'note','Примечание','textarea',false,70);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Качество','Протоколы ОТК и паспорта (Партия E)',
   'Протокол ОТК: app_doc_from_qc формирует документ-протокол (PRT-) из проверки ОТК и её позиций (норма/факт/результат), результат годен/условно/брак. Паспорт: app_doc_from_passport формирует документ-паспорт (PSP-) из паспорта изделия. Слоты↔прогноз: app_forecast_slots — сводка по дням (план-часы открытых нарядов, мощность слотов, свободно, загрузка %, совет по перегрузке).',
   'ОТК протокол паспорт документ слоты прогноз загрузка партия E app_doc_from_qc app_doc_from_passport app_forecast_slots')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Протоколы ОТК и паспорта (Партия E)');
