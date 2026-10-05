-- ============================================================
-- 3DMP Service · 0018_api.sql  (v3.0 — Public API и вебхуки)
-- API-ключи организации и публичное чтение данных по ключу; вебхуки (регистрация).
-- Зависит от 0001..0017.
-- ============================================================

create table if not exists public.app_api_keys (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  name         text not null,
  api_key      uuid unique not null default gen_random_uuid(),
  active       boolean not null default true,
  created_by   uuid references public.app_users (id) on delete set null,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);
alter table public.app_api_keys enable row level security;

create table if not exists public.app_webhooks (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  url        text not null,
  event      text not null default '*',   -- order.created | bid.created | * …
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.app_webhooks enable row level security;

-- ---------- Ключи ----------
create or replace function public.app_api_key_list(p_token uuid)
returns table (id uuid, name text, api_key uuid, active boolean, created_at timestamptz, last_used_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  select u.tenant_id, s.urole into ten, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if urole not in ('owner','manager','admin') then raise exception 'Доступ запрещён'; end if;
  return query select k.id, k.name, k.api_key, k.active, k.created_at, k.last_used_at
    from public.app_api_keys k where k.tenant_id = ten order by k.created_at desc;
end $$;

create or replace function public.app_api_key_create(p_token uuid, p_name text)
returns table (id uuid, api_key uuid)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; kid uuid; kkey uuid; uid uuid;
begin
  if not public.app_is_owner(p_token) then raise exception 'Только владелец может создавать ключи'; end if;
  select u.tenant_id, s.uid into ten, uid from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  insert into public.app_api_keys (tenant_id, name, created_by) values (ten, coalesce(nullif(trim(p_name),''),'API-ключ'), uid)
  returning app_api_keys.id, app_api_keys.api_key into kid, kkey;
  return query select kid, kkey;
end $$;

create or replace function public.app_api_key_revoke(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.app_api_keys set active = false where id = p_id and tenant_id = ten;
  return query select true,'Ключ отозван';
end $$;

-- ---------- Вебхуки ----------
create or replace function public.app_webhook_list(p_token uuid)
returns table (id uuid, url text, event text, active boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  select u.tenant_id, s.urole into ten, urole from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if urole not in ('owner','manager','admin') then raise exception 'Доступ запрещён'; end if;
  return query select w.id, w.url, w.event, w.active, w.created_at from public.app_webhooks w where w.tenant_id = ten order by w.created_at desc;
end $$;

create or replace function public.app_webhook_add(p_token uuid, p_url text, p_event text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_url),'') = '' then return query select false,'Укажите URL'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  insert into public.app_webhooks (tenant_id, url, event) values (ten, trim(p_url), coalesce(nullif(trim(p_event),''),'*'));
  return query select true,'Вебхук добавлен';
end $$;

create or replace function public.app_webhook_toggle(p_token uuid, p_id uuid, p_active boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  update public.app_webhooks set active = p_active where id = p_id and tenant_id = ten;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_webhook_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  if not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  delete from public.app_webhooks where id = p_id and tenant_id = ten;
  return query select true,'Вебхук удалён';
end $$;

-- ============================================================
--  Публичное чтение по API-ключу (внешние интеграции)
-- ============================================================
create or replace function public.api_tenant_of(p_key uuid)
returns uuid language sql security definer set search_path = public
as $$
  select k.tenant_id from public.app_api_keys k where k.api_key = p_key and k.active;
$$;

create or replace function public.api_touch(p_key uuid)
returns void language sql security definer set search_path = public
as $$ update public.app_api_keys set last_used_at = now() where api_key = p_key and active; $$;

create or replace function public.api_orders(p_key uuid)
returns table (number text, title text, customer text, status text, priority text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select o.number, o.title, o.customer, o.status, o.priority, o.created_at
    from public.app_orders o where o.tenant_id = ten order by o.created_at desc;
end $$;

create or replace function public.api_tenders(p_key uuid)
returns table (title text, category text, customer text, status text, bids_count bigint)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select t.title, t.category, t.customer, t.status,
    (select count(*) from public.bids b where b.tender_id = t.id)
    from public.tenders t where t.tenant_id = ten order by t.created_at desc;
end $$;

create or replace function public.api_stock(p_key uuid)
returns table (name text, unit text, qty numeric, min_qty numeric)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  ten := public.api_tenant_of(p_key);
  if ten is null then raise exception 'Недействительный API-ключ'; end if;
  perform public.api_touch(p_key);
  return query select m.name, m.unit, m.qty, m.min_qty from public.app_materials m where m.tenant_id = ten order by m.name;
end $$;

grant execute on function public.app_api_key_list(uuid) to anon, authenticated;
grant execute on function public.app_api_key_create(uuid,text) to anon, authenticated;
grant execute on function public.app_api_key_revoke(uuid,uuid) to anon, authenticated;
grant execute on function public.app_webhook_list(uuid) to anon, authenticated;
grant execute on function public.app_webhook_add(uuid,text,text) to anon, authenticated;
grant execute on function public.app_webhook_toggle(uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.app_webhook_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.api_orders(uuid) to anon, authenticated;
grant execute on function public.api_tenders(uuid) to anon, authenticated;
grant execute on function public.api_stock(uuid) to anon, authenticated;
