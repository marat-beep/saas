-- ============================================================
-- 3DMP Service · 0254_client2.sql
-- X15 (остаток) · Кабинет заказчика: чат клиент ↔ менеджер.
-- Идемпотентно. Зависит от 0001..0253.
-- ============================================================

create table if not exists public.app_client_messages (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  customer_id uuid references public.app_customers (id) on delete cascade,
  order_id    uuid references public.app_orders (id) on delete set null,
  direction   text not null default 'client',   -- client|manager
  body        text not null,
  by_login    text,
  at          timestamptz not null default now(),
  read_at     timestamptz
);
create index if not exists app_client_messages_idx on public.app_client_messages (customer_id, at desc);
alter table public.app_client_messages enable row level security;

create or replace function public.app_client_chat_post(p_token uuid, p_customer_id uuid, p_order_id uuid, p_body text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ulogin text; ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.urole, s.ulogin into uid, urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_body),'') = '' then return query select false,'Пустое сообщение'; return; end if;
  if urole = 'client' then
    select l.customer_id into cid from public.app_client_links l where l.app_user_id = uid limit 1;
    if cid is null then return query select false,'Клиент не привязан'; return; end if;
  else
    cid := p_customer_id;
    if cid is null then return query select false,'Выберите заказчика'; return; end if;
  end if;
  insert into public.app_client_messages (tenant_id, customer_id, order_id, direction, body, by_login)
  values (ten, cid, p_order_id, case when urole='client' then 'client' else 'manager' end, left(trim(p_body),2000), ulogin);
  return query select true, 'Отправлено';
end $$;

create or replace function public.app_client_chat_list(p_token uuid, p_customer_id uuid default null, p_order_id uuid default null)
returns table (id uuid, direction text, body text, by_login text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole = 'client' then
    select l.customer_id into cid from public.app_client_links l where l.app_user_id = uid limit 1;
  else
    cid := p_customer_id;
  end if;
  if cid is null then return; end if;
  return query select m.id, m.direction, m.body, m.by_login, m.at
    from public.app_client_messages m
   where m.customer_id = cid and (p_order_id is null or m.order_id = p_order_id or m.order_id is null)
   order by m.at;
end $$;

grant execute on function public.app_client_chat_post(uuid,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_client_chat_list(uuid,uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Кабинет заказчика','Чат клиент ↔ менеджер',
   'Чат в кабинете заказчика: клиент пишет сообщения (app_client_chat_post — привязка заказчика из app_client_links), менеджер отвечает (та же функция, указывая заказчика). История — app_client_chat_list (по заказчику/заявке). Уведомления о новых сообщениях — через app_notif_* при необходимости.',
   'кабинет заказчика чат клиент менеджер app_client_messages app_client_chat_post')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
