-- ============================================================
-- 3DMP Service · 0006_orders.sql  (v1.2 — единый приём заявок + уведомления)
-- ВАЖНО: public.orders НЕ трогаем (проект «гравировка»). Наши таблицы — app_*.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.  Зависит от 0001..0005.
-- ============================================================

-- ---------- Заявки/заказы (из любых модулей и сервисов) ----------
create sequence if not exists public.app_order_seq;

create table if not exists public.app_orders (
  id           uuid primary key default gen_random_uuid(),
  number       text unique not null,
  title        text not null,
  description  text,
  source       text,                    -- модуль/сервис-источник (eco:A1, supplier, manual …)
  customer     text,
  contact      text,
  status       text not null default 'new',   -- new | in_progress | done | cancelled
  priority     text not null default 'normal',-- low | normal | high
  created_by   uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_orders_created_idx on public.app_orders (created_at desc);

create table if not exists public.app_order_items (
  id       uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.app_orders (id) on delete cascade,
  name     text not null,
  qty      numeric default 1,
  unit     text,
  price    numeric
);
create index if not exists app_order_items_order_idx on public.app_order_items (order_id);

create table if not exists public.app_order_history (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.app_orders (id) on delete cascade,
  status     text not null,
  comment    text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_order_history_order_idx on public.app_order_history (order_id);

-- ---------- Уведомления (адресные) ----------
create table if not exists public.app_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users (id) on delete cascade,
  title      text not null,
  body       text,
  link       text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists app_notifications_user_idx on public.app_notifications (user_id, created_at desc);

alter table public.app_orders        enable row level security;
alter table public.app_order_items   enable row level security;
alter table public.app_order_history enable row level security;
alter table public.app_notifications enable row level security;

-- ---------- Внутренние помощники ----------
create or replace function public.app_session_user(p_token uuid)
returns table (uid uuid, ulogin text, urole text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.role
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

create or replace function public.app_notif_send(p_user uuid, p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  values (p_user, left(p_title, 200), left(coalesce(p_body, ''), 500), p_link);
$$;

create or replace function public.app_notif_roles(p_roles text[], p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  select u.id, left(p_title, 200), left(coalesce(p_body, ''), 500), p_link
  from public.app_users u
  where u.active and u.role = any(p_roles);
$$;

-- ---------- Создать заявку ----------
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; oid uuid; onum text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, contact, priority, status, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          nullif(trim(p_customer), ''), nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles(array['admin', 'manager', 'owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');

  return query select oid, onum;
end $$;

-- ---------- Список заявок ----------
drop function if exists public.app_order_list(uuid);
create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole in ('admin', 'manager', 'owner') then
    return query select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
      from public.app_orders o order by o.created_at desc;
  else
    return query select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
      from public.app_orders o where o.created_by = uid order by o.created_at desc;
  end if;
end $$;

-- ---------- Одна заявка + позиции + история ----------
drop function if exists public.app_order_get(uuid, uuid);
create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; owner uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  select o.created_by into owner from public.app_orders o where o.id = p_id;
  if owner is null then return; end if;
  if not (urole in ('admin','manager','owner') or owner = uid) then raise exception 'Доступ запрещён'; end if;
  return query select o.id, o.number, o.title, o.description, o.source, o.customer, o.contact,
    o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o where o.id = p_id;
end $$;

create or replace function public.app_order_history_list(p_token uuid, p_id uuid)
returns table (status text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  return query select h.status, h.comment, h.by_login, h.created_at
    from public.app_order_history h where h.order_id = p_id order by h.created_at;
end $$;

-- ---------- Сменить статус ----------
create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; owner uuid; onum text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  select o.created_by, o.number into owner, onum from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole in ('admin','manager','owner') or owner = uid) then return query select false, 'Доступ запрещён'; return; end if;

  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment), ''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment, ''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- Уведомления: список/счётчик/прочитано ----------
create or replace function public.app_notif_list(p_token uuid, p_limit integer default 20)
returns table (id uuid, title text, body text, link text, read_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  return query select n.id, n.title, n.body, n.link, n.read_at, n.created_at
    from public.app_notifications n where n.user_id = uid
    order by n.created_at desc limit greatest(1, least(coalesce(p_limit,20),100));
end $$;

create or replace function public.app_notif_unread(p_token uuid)
returns integer language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; c integer;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return 0; end if;
  select count(*) into c from public.app_notifications n where n.user_id = uid and n.read_at is null;
  return c;
end $$;

create or replace function public.app_notif_mark_read(p_token uuid, p_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  update public.app_notifications set read_at = now() where id = p_id and user_id = uid;
end $$;

create or replace function public.app_notif_mark_all(p_token uuid)
returns void language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return; end if;
  update public.app_notifications set read_at = now() where user_id = uid and read_at is null;
end $$;

-- ---------- Уведомление о новом КП (переписываем supplier_submit_bid) ----------
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin uuid; uname text; ttitle text;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  select t.title into ttitle from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/supplier/index.html');

  return query select true, 'Предложение сохранено';
end $$;

grant execute on function public.app_order_create(uuid,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_order_list(uuid)                              to anon, authenticated;
grant execute on function public.app_order_get(uuid,uuid)                          to anon, authenticated;
grant execute on function public.app_order_history_list(uuid,uuid)                 to anon, authenticated;
grant execute on function public.app_order_set_status(uuid,uuid,text,text)         to anon, authenticated;
grant execute on function public.app_notif_list(uuid,integer)                      to anon, authenticated;
grant execute on function public.app_notif_unread(uuid)                            to anon, authenticated;
grant execute on function public.app_notif_mark_read(uuid,uuid)                    to anon, authenticated;
grant execute on function public.app_notif_mark_all(uuid)                         to anon, authenticated;
