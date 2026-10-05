-- ============================================================
-- 3DMP Service · 0030_docs_ref.sql  (v13.0 — переработка «Документы»)
-- КП/договор/техкарта/акт: CRM-заказчик, срок действия, исполнитель, подписание.
-- Номера по типу: KP-/DOG-/TC-/ACT-. Связь с заявкой. Версии. База знаний.
-- Изоляция по tenant. Зависит от 0001..0029.
-- ============================================================

alter table public.app_documents add column if not exists customer_id uuid references public.app_customers (id) on delete set null;
alter table public.app_documents add column if not exists valid_until date;
alter table public.app_documents add column if not exists assignee    text;
alter table public.app_documents add column if not exists signed_at   timestamptz;
create index if not exists app_documents_customer_idx on public.app_documents (customer_id);

-- ---------- Список ----------
drop function if exists public.app_doc_list(uuid,text);
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, customer_id uuid, customer_name text,
               amount numeric, status text, version integer, order_id uuid, order_number text,
               valid_until date, assignee text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.doc_type, d.number, d.title, d.counterparty, d.customer_id, c.name,
           d.amount, d.status, d.version, d.order_id, o.number, d.valid_until, d.assignee, d.updated_at
    from public.app_documents d
    left join public.app_orders o on o.id = d.order_id
    left join public.app_customers c on c.id = d.customer_id
    where (urole='admin' or d.tenant_id = ten) and (p_type is null or p_type = '' or d.doc_type = p_type)
    order by d.updated_at desc;
end $$;

-- ---------- Один документ ----------
drop function if exists public.app_doc_get(uuid,uuid);
create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, order_number text,
               counterparty text, customer_id uuid, customer_name text, amount numeric, status text, version integer,
               valid_until date, assignee text, signed_at timestamptz, content text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.order_id, o.number, d.counterparty,
    d.customer_id, c.name, d.amount, d.status, d.version, d.valid_until, d.assignee, d.signed_at, d.content,
    d.created_login, d.created_at, d.updated_at
    from public.app_documents d
    left join public.app_orders o on o.id = d.order_id
    left join public.app_customers c on c.id = d.customer_id
    where d.id = p_id and (urole='admin' or d.tenant_id = ten);
end $$;

-- ---------- Создание (номер по типу) ----------
drop function if exists public.app_doc_create(uuid,text,text,uuid,text,numeric,text);
create or replace function public.app_doc_create(p_token uuid, p_doc_type text, p_title text, p_order_id uuid,
  p_counterparty text, p_amount numeric, p_content text,
  p_customer_id uuid default null, p_valid_until date default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; ten uuid; did uuid; dnum text; prefix text; dtype text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название документа'; end if;
  dtype := coalesce(nullif(trim(p_doc_type),''),'kp');
  prefix := case dtype when 'kp' then 'KP' when 'contract' then 'DOG' when 'techcard' then 'TC' when 'act' then 'ACT' else 'DOC' end;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, customer_id, amount,
                                    valid_until, assignee, content, created_by, created_login)
  values (ten, dtype, dnum, trim(p_title), p_order_id, coalesce(cname, nullif(trim(p_counterparty),'')),
          p_customer_id, p_amount, p_valid_until, nullif(trim(p_assignee),''), p_content, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, trim(p_title), p_content, ulogin);
  return query select did, dnum;
end $$;

-- ---------- Обновление (новая версия) ----------
drop function if exists public.app_doc_update(uuid,uuid,text,text,numeric,text);
create or replace function public.app_doc_update(p_token uuid, p_id uuid, p_title text, p_counterparty text, p_amount numeric, p_content text,
  p_customer_id uuid default null, p_valid_until date default null, p_assignee text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; urole text; ten uuid; v integer; cname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.version into v from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if v is null then return query select false,'Документ не найден'; return; end if;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  v := v + 1;
  update public.app_documents set title = coalesce(nullif(trim(p_title),''), title),
    counterparty = coalesce(cname, nullif(trim(p_counterparty),''), counterparty),
    customer_id = coalesce(p_customer_id, customer_id),
    amount = coalesce(p_amount, amount), valid_until = coalesce(p_valid_until, valid_until),
    assignee = coalesce(nullif(trim(p_assignee),''), assignee),
    content = coalesce(p_content, content), version = v, updated_at = now()
   where id = p_id;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (p_id, v, coalesce(nullif(trim(p_title),''),'—'), p_content, ulogin);
  return query select true,'Сохранено (версия ' || v || ')';
end $$;

-- ---------- Статус (с подписанием и уведомлением) ----------
create or replace function public.app_doc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ulogin text; ten uuid; dnum text; dtype text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.number, d.doc_type into dnum, dtype from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if dnum is null then return query select false,'Документ не найден'; return; end if;
  update public.app_documents set status = p_status,
    signed_at = case when p_status = 'active' and dtype = 'contract' and signed_at is null then now() else signed_at end,
    updated_at = now()
   where id = p_id;
  if p_status = 'active' then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director'], 'Документ ' || dnum || ' в работе', 'Подготовил: ' || coalesce(ulogin,''), 'apps/docs/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_doc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_doc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_create(uuid,text,text,uuid,text,numeric,text,uuid,date,text) to anon, authenticated;
grant execute on function public.app_doc_update(uuid,uuid,text,text,numeric,text,uuid,date,text) to anon, authenticated;
grant execute on function public.app_doc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо: КП по первой заявке тенанта A ----------
do $$
declare ten uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
        oid uuid; ocust uuid; dnum text; did uuid;
begin
  select o.id, o.customer_id into oid, ocust from public.app_orders o where o.tenant_id = ten order by o.created_at limit 1;
  if oid is null then return; end if;
  if exists (select 1 from public.app_documents where tenant_id = ten and order_id = oid) then return; end if;
  dnum := 'KP-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, valid_until, status, content, created_login)
  values (ten, 'kp', dnum, 'Коммерческое предложение', oid, ocust, 39167.09, current_date + 30, 'draft',
          'Предложение по заявке. Срок действия — 30 дней.', 'owner')
  returning id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, 'Коммерческое предложение', 'Предложение по заявке.', 'owner');
end $$;

-- ---------- База знаний: документы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Документы','Какие документы и как нумеруются?',
   'Типы: КП (коммерческое предложение) → номер KP-NNNNN; договор → DOG-NNNNN; техкарта → TC-NNNNN; акт → ACT-NNNNN. У каждого документа есть версии (v1, v2…): каждая правка создаёт новую версию, историю видно в карточке.',
   'документ КП договор техкарта акт номер версии'),
  ('Документы','Как документы связаны с заявкой и заказчиком?',
   'Документ создаётся с указанием заявки (заказ) и заказчика из CRM. В карточке заявки виден блок «Документы», в карточке документа — номер заявки. Связка: заявка → КП → договор → акт; далее счёт (Финансы) и наряд (Производство).',
   'документ заявка заказчик CRM связь КП договор акт'),
  ('Документы','Срок действия КП и подписание договора',
   'У КП указывается срок действия (valid_until) — до какой даты предложение актуально. У договора при переводе в статус «В работе» фиксируется дата подписания (signed_at) и уходит уведомление. Статусы: черновик → в работе → архив.',
   'КП срок действия договор подписание статус')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Документы');
