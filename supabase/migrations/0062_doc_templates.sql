-- ============================================================
-- 3DMP Service · 0062_doc_templates.sql  (v40 — ЭПИК E: шаблоны документов, B33)
-- Шаблоны документов (КП/договор/акт/техкарта) с подстановкой по заявке.
-- База знаний. Зависит от 0001..0061.
-- ============================================================

create table if not exists public.app_doc_templates (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  doc_type   text not null default 'kp',  -- kp|contract|act|techcard|other
  name       text not null,
  body       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_doc_templates_idx on public.app_doc_templates (tenant_id, doc_type);
alter table public.app_doc_templates enable row level security;

-- ---------- Шаблоны ----------
create or replace function public.app_doc_templates_list(p_token uuid, p_doc_type text default null, p_q text default null)
returns table (id uuid, doc_type text, name text, body text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.doc_type, t.name, t.body, t.active
    from public.app_doc_templates t
    where (t.tenant_id is null or t.tenant_id = ten or urole='admin')
      and (p_doc_type is null or p_doc_type='' or t.doc_type = p_doc_type)
      and (qq='' or lower(t.name) like '%'||qq||'%')
    order by t.doc_type, t.name;
end $$;

create or replace function public.app_doc_template_save(p_token uuid, p_id uuid, p_doc_type text, p_name text, p_body text, p_active boolean)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; tid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите название шаблона'; return; end if;
  if p_id is null then
    insert into public.app_doc_templates (tenant_id, doc_type, name, body, active)
    values (ten, coalesce(nullif(trim(p_doc_type),''),'kp'), trim(p_name), p_body, coalesce(p_active,true))
    returning id into tid;
  else
    update public.app_doc_templates set doc_type=coalesce(nullif(trim(p_doc_type),''),doc_type), name=trim(p_name), body=p_body, active=coalesce(p_active,active)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into tid;
  end if;
  return query select tid, 'Шаблон сохранён';
end $$;

-- ---------- Создать документ из шаблона ----------
create or replace function public.app_doc_from_template(p_token uuid, p_template_id uuid, p_order_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; t record; o record; prefix text; dnum text; did uuid; body text; cust text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_doc_templates where id = p_template_id and (tenant_id is null or tenant_id = ten or urole='admin');
  if t.id is null then raise exception 'Шаблон не найден'; end if;
  if p_order_id is not null then
    select o0.*, c.name as cname into o from public.app_orders o0 left join public.app_customers c on c.id = o0.customer_id where o0.id = p_order_id;
    cust := coalesce(o.cname, o.customer, '');
  end if;
  prefix := case t.doc_type when 'kp' then 'KP' when 'contract' then 'DOG' when 'techcard' then 'TC' when 'act' then 'ACT' else 'DOC' end;
  dnum := prefix || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  body := coalesce(t.body,'');
  body := replace(body, '{customer}', coalesce(cust,''));
  body := replace(body, '{order}', coalesce(o.number,''));
  body := replace(body, '{title}', coalesce(o.title,''));
  body := replace(body, '{amount}', coalesce(o.amount::text,''));
  body := replace(body, '{date}', to_char(current_date,'DD.MM.YYYY'));
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, customer_id, amount, status, content, created_by, created_login)
  values (ten, t.doc_type, dnum, t.name, p_order_id, o.customer_id, o.amount, 'draft', body, 
          (select uid from public.app_session_user(p_token)), ulogin)
  returning id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, t.name, body, ulogin);
  return query select did, dnum, 'Документ создан из шаблона';
end $$;

grant execute on function public.app_doc_templates_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_template_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_doc_from_template(uuid,uuid,uuid) to anon, authenticated;

-- ---------- Демо-шаблоны (тенант A) ----------
insert into public.app_doc_templates (tenant_id, doc_type, name, body)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.t, v.n, v.b
from (values
  ('kp','Коммерческое предложение','Коммерческое предложение № {order} от {date}.
Заказчик: {customer}.
Предмет: {title}.
Стоимость: {amount} ₽. Срок действия — 30 дней.'),
  ('contract','Договор','Договор № {order} от {date}.
Стороны: Исполнитель и {customer}.
Предмет: {title}. Сумма: {amount} ₽.'),
  ('act','Акт выполненных работ','Акт № {order} от {date}.
Заказчик: {customer}. Работы: {title}. Сумма: {amount} ₽. Претензий нет.')
) as v(t, n, b)
where not exists (select 1 from public.app_doc_templates where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Шаблоны','Как использовать шаблоны документов?',
   'В модуле «Шаблоны документов» задаются КП/договор/акт/техкарта с подстановками: {customer}, {order}, {title}, {amount}, {date}. Кнопкой «Создать документ из шаблона» выбирается заявка — документ создаётся в «Документах» с подставленными данными и версией.',
   'шаблоны документы КП договор акт подстановка заявка печать')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как использовать шаблоны документов?');
