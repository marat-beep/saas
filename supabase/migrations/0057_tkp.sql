-- ============================================================
-- 3DMP Service · 0057_tkp.sql  (v36.1 — ЭПИК A: реестр ТКП)
-- Технико-коммерческие предложения: номер, контрагент, срок, цена, статусы.
-- Связь с заявкой/документом. База знаний. Зависит от 0001..0056.
-- ============================================================

create sequence if not exists public.app_tkp_seq;

create table if not exists public.app_tkp_registry (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text,
  tkp_date     date not null default current_date,
  counterparty text,
  customer_id  uuid references public.app_customers (id) on delete set null,
  subject      text not null,
  valid_until  date,
  price        numeric,
  status       text not null default 'actual',  -- actual|expired|contracted|closed
  order_id     uuid references public.app_orders (id) on delete set null,
  document_id  uuid references public.app_documents (id) on delete set null,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_tkp_idx on public.app_tkp_registry (tenant_id, status);
alter table public.app_tkp_registry enable row level security;

create or replace function public.app_tkp_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, tkp_date date, counterparty text, customer text, subject text, valid_until date,
               price numeric, status text, order_id uuid, order_number text, document_number text, note text, expired boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select t.id, t.number, t.tkp_date, t.counterparty, c.name, t.subject, t.valid_until, t.price, t.status, t.order_id, o.number, d.number, t.note,
      (t.valid_until is not null and t.valid_until < current_date and t.status = 'actual')
    from public.app_tkp_registry t
    left join public.app_customers c on c.id = t.customer_id
    left join public.app_orders o on o.id = t.order_id
    left join public.app_documents d on d.id = t.document_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(coalesce(t.number,'')) like '%'||qq||'%' or lower(t.subject) like '%'||qq||'%' or lower(coalesce(t.counterparty,'')) like '%'||qq||'%' or lower(coalesce(c.name,'')) like '%'||qq||'%')
    order by t.tkp_date desc, t.created_at desc;
end $$;

create or replace function public.app_tkp_save(p_token uuid, p_id uuid, p_customer_id uuid, p_counterparty text, p_subject text,
  p_valid_until date, p_price numeric, p_order_id uuid, p_document_id uuid, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_subject),'') = '' then raise exception 'Укажите предмет ТКП'; return; end if;
  if p_id is null then
    tnum := 'TKP-' || lpad(nextval('public.app_tkp_seq')::text, 5, '0');
    insert into public.app_tkp_registry (tenant_id, number, counterparty, customer_id, subject, valid_until, price, order_id, document_id, note, created_login)
    values (ten, tnum, nullif(trim(p_counterparty),''), p_customer_id, trim(p_subject), p_valid_until, p_price, p_order_id, p_document_id, nullif(trim(p_note),''), ulogin)
    returning id into tid;
    return query select tid, tnum, 'ТКП добавлено';
  else
    update public.app_tkp_registry set counterparty=nullif(trim(p_counterparty),''), customer_id=p_customer_id, subject=trim(p_subject),
      valid_until=p_valid_until, price=p_price, order_id=p_order_id, document_id=p_document_id, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into tid, tnum;
    return query select tid, tnum, 'ТКП обновлено';
  end if;
end $$;

create or replace function public.app_tkp_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('actual','expired','contracted','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_tkp_registry set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус ТКП обновлён';
end $$;

grant execute on function public.app_tkp_list(uuid,text) to anon, authenticated;
grant execute on function public.app_tkp_save(uuid,uuid,uuid,text,text,date,numeric,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_tkp_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_tkp_registry (tenant_id, number, counterparty, customer_id, subject, valid_until, price, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'TKP-' || lpad(nextval('public.app_tkp_seq')::text, 5, '0'),
       c.name, c.id, v.subject, current_date + v.days, v.price, v.status, 'manager'
from public.app_customers c
join (values ('Изготовление штампа Ш-001', 30, 1000000, 'actual'), ('Оснастка, комплект', -5, 250000, 'expired')) as v(subject, days, price, status)
  on c.name = (select name from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1)
where not exists (select 1 from public.app_tkp_registry where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('ТКП','Что такое реестр ТКП?',
   'Реестр технико-коммерческих предложений: номер (TKP-NNNNN), дата, контрагент/заказчик, предмет, срок действия, цена и статус (Актуальное/Истёк срок/Заключён договор/Закрыто). Просроченные по сроку (но ещё «Актуальные») выделяются. ТКП связывается с заявкой и КП.',
   'ТКП реестр предложение срок цена статус контрагент')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что такое реестр ТКП?');
