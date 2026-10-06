-- ============================================================
-- 3DMP Service · 0105_docs_l3.sql  (v89 — PLAN_MODERNIZATION, Партия B «Документы L3»)
-- Документы, управляемые схемой: типы (Договор/Техкарта/КП/Акт/Счёт/Накладная/ТЗ/Паспорт)
-- → поля (app_schemas/app_schema_fields) → значения в app_documents.fields jsonb;
-- генерация текста (рендер) и печать; связи с заявкой/заказчиком.
-- Идемпотентно. Зависит от 0001..0104.
-- ============================================================

alter table public.app_documents
  add column if not exists fields      jsonb not null default '{}'::jsonb,
  add column if not exists schema_id   uuid references public.app_schemas (id) on delete set null,
  add column if not exists template_id uuid references public.app_doc_templates (id) on delete set null;
create index if not exists app_documents_type_idx on public.app_documents (tenant_id, doc_type, created_at desc);

-- ---------- Типы документов (схемы) ----------
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
      and sc.code in ('kp','contract','act','techcard','invoice','waybill','tz','passport')
    order by array_position(array['kp','contract','act','techcard','invoice','waybill','tz','passport'], sc.code);
end $$;

-- ---------- Создание документа по типу (со значениями полей) ----------
create or replace function public.app_doc_create_typed(p_token uuid, p_schema_id uuid, p_title text,
  p_fields jsonb, p_order_id uuid, p_customer_id uuid, p_amount numeric)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sc record; prefix text; dnum text; did uuid; body text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; return; end if;
  select sc0.id, sc0.code, sc0.name into sc from public.app_schemas sc0
    where sc0.id = p_schema_id and (urole='admin' or sc0.tenant_id = ten);
  if sc.id is null then raise exception 'Тип документа не найден'; return; end if;
  prefix := case sc.code when 'kp' then 'KP' when 'contract' then 'DOG' when 'act' then 'ACT' when 'techcard' then 'TC'
                         when 'invoice' then 'SCH' when 'waybill' then 'NAK' when 'tz' then 'TZ' when 'passport' then 'PSP'
                         else 'DOC' end;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  select coalesce(string_agg(f.label || ': ' || case when coalesce(p_fields->>f.code,'')='' then '—' else (p_fields->>f.code) end, E'\n' order by f.sort), '')
    into body from public.app_schema_fields f where f.schema_id = p_schema_id;
  body := 'Документ № ' || dnum || ' от ' || to_char(current_date,'DD.MM.YYYY') || E'\n' || coalesce(nullif(trim(p_title),''), sc.name) || E'\n\n' || body;
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, status, content, fields, schema_id, created_by, created_login)
  values (ten, sc.code, dnum, coalesce(nullif(trim(p_title),''), sc.name), p_order_id, p_customer_id, p_amount, 'draft', body,
          coalesce(p_fields,'{}'::jsonb), p_schema_id, (select uid from public.app_session_user(p_token)), ulogin)
  returning id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, coalesce(nullif(trim(p_title),''), sc.name), body, ulogin);
  return query select did, dnum, 'Документ создан';
end $$;

-- ---------- Сохранение значений полей ----------
create or replace function public.app_doc_fields_save(p_token uuid, p_id uuid, p_fields jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then return query select false,'Недостаточно прав'; return; end if;
  update public.app_documents set fields=coalesce(p_fields,'{}'::jsonb), updated_at=now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  if not found then return query select false,'Документ не найден'; return; end if;
  return query select true,'Поля сохранены';
end $$;

-- ---------- Рендер текста (для предпросмотра/печати) ----------
create or replace function public.app_doc_render_text(p_token uuid, p_id uuid)
returns table (id uuid, number text, doc_type text, title text, fields jsonb, content text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; d record; f record; val text; rlabel text; body text; k text; c text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d0.id, d0.number, d0.doc_type, d0.title, d0.fields, d0.schema_id, d0.created_at, d0.content
    into d from public.app_documents d0 where d0.id=p_id and (urole='admin' or d0.tenant_id=ten);
  if d.id is null then raise exception 'Документ не найден'; return; end if;
  body := 'Документ № ' || coalesce(d.number,'') || ' от ' || to_char(d.created_at,'DD.MM.YYYY') || E'\n' || coalesce(d.title,'') || E'\n\n';
  for f in select * from public.app_schema_fields sf where sf.schema_id = d.schema_id order by sf.sort loop
    val := coalesce(d.fields->>f.code, '');
    if f.field_type = 'ref' and f.ref_source is not null and val <> '' then
      k := split_part(f.ref_source, ':', 1); c := nullif(split_part(f.ref_source, ':', 2), '');
      begin
        select o.label into rlabel from public.app_ref_options(p_token, k, c) o where o.value = val;
      exception when others then rlabel := null; end;
      if rlabel is not null then val := rlabel; end if;
    end if;
    body := body || f.label || ': ' || case when val = '' then '—' else val end || E'\n';
  end loop;
  return query select d.id, d.number, d.doc_type, d.title, d.fields, body;
end $$;

-- ---------- Список документов по типу ----------
create or replace function public.app_doc_typed_list(p_token uuid, p_doc_type text default null, p_q text default null)
returns table (id uuid, number text, doc_type text, title text, status text, amount numeric, schema_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.number, d.doc_type, d.title, d.status, d.amount, d.schema_id, d.created_at
    from public.app_documents d
    where (urole='admin' or d.tenant_id=ten)
      and (coalesce(p_doc_type,'')='' or d.doc_type=p_doc_type)
      and (qq='' or lower(coalesce(d.number,'')) like '%'||qq||'%' or lower(coalesce(d.title,'')) like '%'||qq||'%')
    order by d.created_at desc;
end $$;

grant execute on function public.app_doc_type_schemas(uuid) to anon, authenticated;
grant execute on function public.app_doc_create_typed(uuid,uuid,text,jsonb,uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_doc_fields_save(uuid,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_doc_render_text(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_typed_list(uuid,text,text) to anon, authenticated;

-- ---------- Демо: недостающие типы документов (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='act') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'act','Акт','✅','Акт выполненных работ') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'customer','Заказчик','ref','clients',true,10),
      (sid,'works','Работы','textarea',null,true,20),
      (sid,'amount','Сумма','number',null,false,30),
      (sid,'act_date','Дата акта','date',null,false,40),
      (sid,'basis','Основание','text',null,false,50);
  end if;
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='invoice') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'invoice','Счёт','💳','Счёт на оплату') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'customer','Заказчик','ref','clients',true,10),
      (sid,'amount','Сумма','number',null,true,20),
      (sid,'vat','НДС, %','number',null,false,30),
      (sid,'due_date','Оплатить до','date',null,false,40),
      (sid,'purpose','Назначение','text',null,false,50);
  end if;
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='waybill') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'waybill','Накладная','🚚','Товарная накладная') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'customer','Получатель','ref','clients',true,10),
      (sid,'cargo','Груз','text',null,true,20),
      (sid,'weight','Вес, кг','number',null,false,30),
      (sid,'places','Мест','number',null,false,40),
      (sid,'waybill_date','Дата','date',null,false,50);
  end if;
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='tz') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'tz','ТЗ','📋','Техническое задание') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'title','Тема','text',null,true,10),
      (sid,'requirements','Требования','textarea',null,true,20),
      (sid,'material','Материал','ref','dict:material_kind',false,30),
      (sid,'deadline','Срок','date',null,false,40);
  end if;
  if not exists (select 1 from public.app_schemas where tenant_id=A and code='passport') then
    insert into public.app_schemas (tenant_id, code, name, icon, description) values (A,'passport','Паспорт','📘','Паспорт изделия') returning id into sid;
    insert into public.app_schema_fields (schema_id, code, label, field_type, ref_source, required, sort) values
      (sid,'product','Изделие','text',null,true,10),
      (sid,'serial','Серийный №','text',null,false,20),
      (sid,'qty','Количество','number',null,false,30),
      (sid,'qc_result','Результат контроля','select','годен,брак,условно',false,40),
      (sid,'issue_date','Дата выдачи','date',null,false,50),
      (sid,'note','Примечание','textarea',null,false,60);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Документы','Конструктор документов (Документы L3)',
   'Партия B: типы документов (КП, Договор, Акт, Техкарта, Счёт, Накладная, ТЗ, Паспорт) описаны схемами (app_schemas/app_schema_fields), значения хранятся в app_documents.fields (jsonb). Модуль «Конструктор документов» строит форму по полям типа, создаёт документ (app_doc_create_typed), сохраняет значения (app_doc_fields_save) и формирует текст для печати (app_doc_render_text, с раскрытием ссылок на заказчика/оборудование и т.п.). Номер присваивается по префиксу типа (KP/DOG/ACT/TC/SCH/NAK/TZ/PSP).',
   'документы конструктор схемы поля jsonb печать КП договор акт счёт накладная ТЗ паспорт L3 партия B')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Конструктор документов (Документы L3)');
