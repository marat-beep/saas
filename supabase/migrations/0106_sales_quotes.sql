-- ============================================================
-- 3DMP Service · 0106_sales_quotes.sql  (v90 — PLAN_MODERNIZATION, Партия C)
-- Продажи/КП: КП из спецификации (BOM: материалы+работы+накладные, наценка)
-- и прайс/КП из каталога оборудования. Печать — через app_doc_render_text (0105).
-- Идемпотентно. Зависит от 0001..0105.
-- ============================================================

-- ---------- Опции каталога оборудования (для прайса) ----------
create or replace function public.app_equipment_price_options(p_token uuid)
returns table (id uuid, name text, brand text, price numeric, currency text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, coalesce(e.brand || ' ', '') || e.name, e.brand, e.price, e.currency
    from public.app_equipment_catalog e
    where (urole='admin' or e.tenant_id=ten) and coalesce(e.active,true)
    order by e.name;
end $$;

-- ---------- КП из спецификации ----------
create or replace function public.app_quote_from_bom(p_token uuid, p_bom_id uuid, p_margin_pct numeric default 0, p_valid_days integer default 30)
returns table (id uuid, number text, amount numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; b record; mc numeric; wc numeric; tot numeric; margin numeric; amt numeric;
        sid uuid; did uuid; dnum text; vd date; body text := ''; ln record; cust text; cust_id uuid; ord_num text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select b0.* into b from public.app_bom b0 where b0.id = p_bom_id and (urole='admin' or b0.tenant_id=ten);
  if b.id is null then raise exception 'Спецификация не найдена'; return; end if;

  select c.materials_cost, c.work_cost, c.total into mc, wc, tot from public.app_bom_cost(p_token, p_bom_id, coalesce(b.qty,1)) c;
  margin := greatest(coalesce(p_margin_pct,0),0);
  amt := round(coalesce(tot,0) * (1 + margin/100.0), 2);
  vd := current_date + greatest(coalesce(p_valid_days,30),1);

  body := 'Коммерческое предложение по спецификации «' || coalesce(b.product,'') || '»' || E'\n' ||
          'Количество: ' || coalesce(b.qty,1)::text || E'\n\nПозиции:' || E'\n';
  for ln in select * from public.app_bom_lines_list(p_token, p_bom_id) l order by l.seq loop
    body := body || '  ' || coalesce(ln.name,'') || '  —  ' || coalesce(ln.qty,0)::text || ' ' || coalesce(ln.unit,'') ||
            '  ·  ' || round(coalesce(ln.cost,0),2)::text || ' ₽' || E'\n';
  end loop;
  body := body || E'\n' || 'Материалы: ' || round(coalesce(mc,0),2)::text || ' ₽' || E'\n' ||
          'Работы: ' || round(coalesce(wc,0),2)::text || ' ₽' || E'\n' ||
          'Наценка: ' || margin::text || ' %' || E'\n' ||
          'ИТОГО: ' || amt::text || ' ₽';

  if b.order_id is not null then
    select o0.customer_id, o0.number into cust_id, ord_num from public.app_orders o0 where o0.id = b.order_id;
    if cust_id is not null then select c2.name into cust from public.app_customers c2 where c2.id = cust_id; end if;
    body := 'Заявка: ' || coalesce(ord_num,'') || E'\n' || body;
  end if;

  select sc.id into sid from public.app_schemas sc where sc.code='kp' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'kp', dnum, 'КП: ' || coalesce(b.product,'спецификация'), b.order_id, cust_id, amt, vd, 'draft', body,
          jsonb_build_object('customer', coalesce(cust,''), 'valid_until', to_char(vd,'DD.MM.YYYY'), 'discount', margin, 'items', 'из спецификации'),
          sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'КП: ' || coalesce(b.product,'спецификация'), body, ulogin);
  return query select did, dnum, amt, 'КП из спецификации создано';
end $$;

-- ---------- Прайс/КП из каталога оборудования ----------
create or replace function public.app_quote_from_equipment(p_token uuid, p_ids uuid[], p_margin_pct numeric default 0)
returns table (id uuid, number text, amount numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; margin numeric; amt numeric := 0; sid uuid; did uuid; dnum text;
        body text := ''; cnt int := 0; e record; line_sum numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_ids is null or array_length(p_ids,1) is null then raise exception 'Выберите позиции'; return; end if;
  margin := greatest(coalesce(p_margin_pct,0),0);
  body := 'Прайс-лист оборудования' || E'\n\n';
  for e in select ec.id, ec.name, ec.brand, ec.price, ec.currency from public.app_equipment_catalog ec
             where ec.id = any(p_ids) and (urole='admin' or ec.tenant_id=ten) order by ec.name loop
    cnt := cnt + 1;
    line_sum := round(coalesce(e.price,0) * (1 + margin/100.0), 2);
    amt := amt + line_sum;
    body := body || cnt::text || '. ' || coalesce(e.brand || ' ','') || coalesce(e.name,'') || '  —  ' || line_sum::text || ' ' || coalesce(e.currency,'RUB') || E'\n';
  end loop;
  if cnt = 0 then raise exception 'Позиции не найдены'; return; end if;
  body := body || E'\n' || 'Позиций: ' || cnt::text || ' · наценка ' || margin::text || ' %' || E'\n' || 'ИТОГО: ' || round(amt,2)::text || ' ₽';

  select sc.id into sid from public.app_schemas sc where sc.code='kp' and (urole='admin' or sc.tenant_id=ten) order by (sc.tenant_id=ten) desc limit 1;
  dnum := 'PRC-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, amount, status, content, fields, schema_id, created_by, created_login)
  values (ten, 'kp', dnum, 'Прайс оборудования (' || cnt::text || ')', round(amt,2), 'draft', body,
          jsonb_build_object('discount', margin, 'items', 'прайс оборудования'), sid, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Прайс оборудования', body, ulogin);
  return query select did, dnum, round(amt,2), 'Прайс создан';
end $$;

grant execute on function public.app_equipment_price_options(uuid) to anon, authenticated;
grant execute on function public.app_quote_from_bom(uuid,uuid,numeric,integer) to anon, authenticated;
grant execute on function public.app_quote_from_equipment(uuid,uuid[],numeric) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','КП из спецификации и прайс оборудования (Партия C)',
   'КП из спецификации: в «Конструкторе документов» выберите спецификацию (BOM) и наценку — создаётся КП с позициями (материалы+работы+накладные из app_bom_cost) и итогом; заказчик подставляется из заявки. Прайс: выберите позиции каталога оборудования и наценку — создаётся КП-прайс с ценами. Печать — через предпросмотр (app_doc_render_text).',
   'КП спецификация BOM прайс оборудование наценка продажи партия C app_quote_from_bom app_quote_from_equipment')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='КП из спецификации и прайс оборудования (Партия C)');


-- ---------- Согласование рендера (v90): состав КП/прайса важнее полей ----------
-- Схемные документы (docbuilder) не хранят готовый текст — рендер строит его из полей
-- с раскрытием ссылок. Документы с готовым составом (КП из спецификации/прайс) возвращают content.
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
  values (ten, sc.code, dnum, coalesce(nullif(trim(p_title),''), sc.name), p_order_id, p_customer_id, p_amount, 'draft', null,
          coalesce(p_fields,'{}'::jsonb), p_schema_id, (select uid from public.app_session_user(p_token)), ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, coalesce(nullif(trim(p_title),''), sc.name), body, ulogin);
  return query select did, dnum, 'Документ создан';
end $$;

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
  body := coalesce(d.content, '');
  if trim(body) <> '' then
    if position('Документ №' in body) = 0 then
      body := 'Документ № ' || coalesce(d.number,'') || ' от ' || to_char(d.created_at,'DD.MM.YYYY') || E'\n' || body;
    end if;
  else
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
  end if;
  return query select d.id, d.number, d.doc_type, d.title, d.fields, body;
end $$;