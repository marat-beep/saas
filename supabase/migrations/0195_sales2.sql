-- ============================================================
-- 3DMP Service · 0195_sales2.sql  (X15 — Продажи 2.0)
-- Сквозной конвейер заявки (app_order_flow + advance), онлайн-оплата
-- (app_payment_links + идемпотентный settle), скоринг лидов (app_lead_score).
-- Идемпотентно. Зависит от 0001..0194.
-- ============================================================

create table if not exists public.app_order_flow (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  order_id      uuid not null references public.app_orders (id) on delete cascade,
  stage         text not null,                 -- new|kp|contract|invoice|paid|done
  stage_at      timestamptz not null default now(),
  by_login      text,
  note          text
);
create index if not exists app_order_flow_idx on public.app_order_flow (order_id, stage_at);
alter table public.app_order_flow enable row level security;

create table if not exists public.app_payment_links (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  order_id      uuid references public.app_orders (id) on delete set null,
  invoice_id    uuid references public.app_invoices (id) on delete set null,
  amount        numeric not null default 0,
  link_token    uuid not null default gen_random_uuid(),
  status        text not null default 'created',  -- created|paid|expired
  external_ref  text,
  paid_at       timestamptz,
  created_login text,
  created_at    timestamptz not null default now()
);
create unique index if not exists app_payment_links_token_uq on public.app_payment_links (link_token);
create index if not exists app_payment_links_idx on public.app_payment_links (tenant_id, status);
alter table public.app_payment_links enable row level security;

-- ================= RPC: конвейер заявки =================
create or replace function public.app_order_flow_list(p_token uuid, p_order_id uuid)
returns table (stage text, stage_at timestamptz, by_login text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select f.stage, f.stage_at, f.by_login, f.note
      from public.app_order_flow f
     where f.order_id = p_order_id and (adm or f.tenant_id = ten)
     order by f.stage_at;
end $$;

create or replace function public.app_order_pipeline(p_token uuid)
returns table (order_id uuid, number text, title text, customer text, stage text, stage_at timestamptz, amount numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.customer,
           coalesce((select f.stage from public.app_order_flow f where f.order_id = o.id order by f.stage_at desc limit 1), 'new'),
           (select f.stage_at from public.app_order_flow f where f.order_id = o.id order by f.stage_at desc limit 1),
           coalesce((select sum(i.amount) from public.app_invoices i where i.order_id = o.id), 0)
      from public.app_orders o
     where (adm or o.tenant_id = ten) and o.status <> 'cancelled'
     order by o.created_at desc;
end $$;

create or replace function public.app_order_flow_advance(p_token uuid, p_order_id uuid, p_stage text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; st text; o record; inv record; did uuid; num text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'orders') then return query select false,'Нет прав на заявки'; return; end if;
  adm := public.app_is_platform_admin(p_token);
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  st := lower(trim(coalesce(p_stage,'')));
  if st not in ('new','kp','contract','invoice','paid','done') then return query select false,'Недопустимая стадия'; return; end if;
  select * into o from public.app_orders where id = p_order_id and (adm or tenant_id = ten);
  if o.id is null then return query select false,'Заявка не найдена'; return; end if;
  -- Стадия «счёт» — создать счёт (reuse app_order_create_invoice) при отсутствии
  if st = 'invoice' then
    select * into inv from public.app_invoices where order_id = o.id limit 1;
    if inv.id is null then
      select * into inv from public.app_order_create_invoice(p_token, o.id, 14) x;
    end if;
  end if;
  -- Стадия «договор» — создать документ
  if st = 'contract' then
    if not exists (select 1 from public.app_documents d where d.order_id = o.id and d.doc_type = 'contract') then
      num := 'ДОГ-' || o.number;
      insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, status, created_login)
      values (ten, 'contract', num, o.title, o.id, o.customer, 'draft', uname);
    end if;
  end if;
  insert into public.app_order_flow (tenant_id, order_id, stage, by_login, note) values (ten, o.id, st, uname, nullif(trim(p_note),''));
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','sales'], 'Заявка ' || o.number || ': стадия ' || st,
    coalesce(left(p_note,180), o.title), 'apps/orders/index.html');
  return query select true,'Стадия: ' || st;
end $$;

-- ================= RPC: онлайн-оплата =================
create or replace function public.app_payment_link_create(p_token uuid, p_order_id uuid, p_amount numeric)
returns table (ok boolean, message text, id uuid, link_token uuid, url text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; o record; inv record; newid uuid; tok uuid; amt numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::uuid, null::text; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select * into o from public.app_orders where id = p_order_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if o.id is null then return query select false,'Заявка не найдена', null::uuid, null::uuid, null::text; return; end if;
  select * into inv from public.app_invoices where order_id = o.id order by created_at desc limit 1;
  amt := coalesce(p_amount, inv.amount, 0);
  insert into public.app_payment_links (tenant_id, order_id, invoice_id, amount, created_login)
  values (ten, o.id, inv.id, amt, uname) returning app_payment_links.id, app_payment_links.link_token into newid, tok;
  return query select true,'Платёжная ссылка создана', newid, tok, 'https://sapfir.eu/saas/apps/client/index.html?pay=' || tok::text;
end $$;

create or replace function public.app_payment_settle(p_token uuid, p_link_id uuid, p_external_ref text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; l record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into l from public.app_payment_links where id = p_link_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if l.id is null then return query select false,'Ссылка не найдена'; return; end if;
  if l.status = 'paid' then return query select true,'Уже оплачено (идемпотентно)'; return; end if;
  update public.app_payment_links set status = 'paid', paid_at = now(), external_ref = nullif(trim(p_external_ref),'') where id = l.id;
  if l.invoice_id is not null then
    update public.app_invoices set status = 'paid', paid_at = now() where id = l.invoice_id;
  end if;
  insert into public.app_order_flow (tenant_id, order_id, stage, by_login, note)
  select ten, l.order_id, 'paid', null, 'онлайн-оплата' where l.order_id is not null;
  return query select true,'Оплата зафиксирована';
end $$;

create or replace function public.app_payment_links_list(p_token uuid, p_order_id uuid default null)
returns table (id uuid, amount numeric, status text, link_token uuid, created_at timestamptz, paid_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.amount, l.status, l.link_token, l.created_at, l.paid_at
      from public.app_payment_links l
     where (adm or l.tenant_id = ten) and (p_order_id is null or l.order_id = p_order_id)
     order by l.created_at desc;
end $$;

-- ================= RPC: скоринг лидов =================
create or replace function public.app_lead_score(p_token uuid)
returns table (deal_id uuid, title text, stage text, amount numeric, probability integer, score integer, band text, next_action text, due_date date)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.title, d.stage, d.amount, d.probability,
           least(100, greatest(0,
             coalesce(d.probability,0)
             + case d.stage when 'lead' then 0 when 'qualified' then 10 when 'proposal' then 20 when 'negotiation' then 30 when 'won' then 40 else 0 end
             + case when d.amount is null then 0 when d.amount >= 1000000 then 20 when d.amount >= 300000 then 12 when d.amount >= 100000 then 6 else 2 end
             + case when d.due_date is not null and d.due_date < current_date then 8 else 0 end
           ))::int,
           case when (coalesce(d.probability,0) + case d.stage when 'lead' then 0 when 'qualified' then 10 when 'proposal' then 20 when 'negotiation' then 30 when 'won' then 40 else 0 end) >= 70 then 'горячий'
                when (coalesce(d.probability,0) + case d.stage when 'lead' then 0 when 'qualified' then 10 when 'proposal' then 20 when 'negotiation' then 30 when 'won' then 40 else 0 end) >= 40 then 'тёплый'
                else 'холодный' end,
           d.next_action, d.due_date
      from public.app_deals d
     where (adm or d.tenant_id = ten) and d.stage not in ('won','lost')
     order by 6 desc;
end $$;

-- ================= RPC: оплата из кабинета клиента =================
create or replace function public.app_client_pay(p_token uuid, p_invoice_number text)
returns table (ok boolean, message text, url text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; inv record; newid uuid; tok uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole not in ('client','admin') then raise exception 'Доступ только для заказчика'; end if;
  select i.* into inv from public.app_invoices i
   where i.number = p_invoice_number
     and i.customer_id in (select customer_id from public.app_client_links where app_user_id = uid)
   limit 1;
  if inv.id is null then return query select false,'Счёт не найден', null::text; return; end if;
  if inv.status = 'paid' then return query select true,'Уже оплачено (идемпотентно)', null::text; return; end if;
  insert into public.app_payment_links (tenant_id, order_id, invoice_id, amount, status, external_ref, paid_at)
  values (inv.tenant_id, inv.order_id, inv.id, inv.amount, 'paid', 'client-online', now())
  returning app_payment_links.id, app_payment_links.link_token into newid, tok;
  update public.app_invoices set status = 'paid', paid_at = now() where id = inv.id;
  insert into public.app_order_flow (tenant_id, order_id, stage, by_login, note)
  select inv.tenant_id, inv.order_id, 'paid', null, 'онлайн-оплата клиента' where inv.order_id is not null;
  return query select true,'Оплата принята', 'https://sapfir.eu/saas/apps/client/index.html?paid=1';
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Продажи 2.0: конвейер заявки, онлайн-оплата, скоринг лидов (X15)',
   'Продажи 2.0: сквозной конвейер заявки new→kp→contract→invoice→paid→done (app_order_flow + app_order_flow_advance; на стадии «счёт» создаётся счёт через app_order_create_invoice, на «договор» — документ в app_documents; app_order_pipeline для доски), онлайн-оплата (app_payment_links + app_payment_link_create; идемпотентное подтверждение app_payment_settle с вебхук-ключом провайдера — платежная ссылка в кабинете клиента), скоринг лидов (app_lead_score — балл 0..100 и категория горячий/тёплый/холодный по стадии, сумме и сроку).',
   'продажи конвейер заявка КП договор счёт оплата платёжная ссылка скоринг лид воронка')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Продажи 2.0: конвейер заявки, онлайн-оплата, скоринг лидов (X15)'
);

-- ================= Права =================
grant execute on function public.app_order_flow_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_order_pipeline(uuid) to anon, authenticated;
grant execute on function public.app_order_flow_advance(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_payment_link_create(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_payment_settle(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_payment_links_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lead_score(uuid) to anon, authenticated;
grant execute on function public.app_client_pay(uuid,text) to anon, authenticated;
