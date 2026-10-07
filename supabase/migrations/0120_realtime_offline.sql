-- ============================================================
-- 3DMP Service · 0120_realtime_offline.sql  (W5 — Realtime и PWA-офлайн)
-- Realtime-публикация уведомлений (best-effort) + журнал синхронизации
-- офлайн-очереди (IndexedDB → RPC). Идемпотентно. Зависит от 0001..0119.
-- ============================================================

-- Realtime: добавить app_notifications в публикацию supabase_realtime (если есть).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.app_notifications;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

create table if not exists public.app_offline_sync (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  user_id    uuid references public.app_users (id) on delete set null,
  login      text,
  client_id  text,
  ops_count  integer not null default 0,
  failed     integer not null default 0,
  detail     text,
  device     text,
  created_at timestamptz not null default now()
);
create index if not exists app_offline_sync_idx on public.app_offline_sync (tenant_id, created_at desc);
alter table public.app_offline_sync enable row level security;

-- Зафиксировать синхронизацию офлайн-очереди (вызывается клиентом при восстановлении связи).
drop function if exists public.app_offline_log(uuid,text,integer,integer,text,text);
create or replace function public.app_offline_log(
  p_token uuid, p_client_id text, p_ops_count integer, p_failed integer default 0, p_detail text default null, p_device text default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_offline_sync (tenant_id, user_id, login, client_id, ops_count, failed, detail, device)
  values (ten, uid, ulogin, nullif(trim(p_client_id),''), coalesce(p_ops_count,0), coalesce(p_failed,0),
          left(coalesce(p_detail,''), 500), left(coalesce(p_device,''), 200));
  return query select true, 'Синхронизация зафиксирована';
end $$;

-- Журнал синхронизаций (для admin/owner).
drop function if exists public.app_offline_list(uuid,integer);
create or replace function public.app_offline_list(p_token uuid, p_limit integer default 50)
returns table (id uuid, login text, client_id text, ops_count integer, failed integer, detail text, device text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  if urole not in ('admin','owner') then raise exception 'Нет прав'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.login, o.client_id, o.ops_count, o.failed, o.detail, o.device, o.created_at
      from public.app_offline_sync o
     where (urole = 'admin' or o.tenant_id = ten)
     order by o.created_at desc
     limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

grant execute on function public.app_offline_log(uuid,text,integer,integer,text,text) to anon, authenticated;
grant execute on function public.app_offline_list(uuid,integer) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Realtime и офлайн-очередь (PWA)',
   'Уведомления мгновенно приходят через Supabase Realtime (подписка на app_notifications) с фолбэком на периодический опрос каждые 15 c (т.к. вход собственный, не Supabase Auth). Офлайн-очередь: клиентский модуль assets/js/offline-queue.js (IndexedDB) копит действия терминала/ОТК при отсутствии сети и повторяет их (flush) при восстановлении; факт синхронизации пишется в app_offline_sync (app_offline_log), журнал — app_offline_list. Service worker (sw.js v2) кэширует оболочку для офлайн-режима.',
   'realtime уведомления офлайн IndexedDB PWA service worker синхронизация терминал ОТК')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Realtime и офлайн-очередь (PWA)'
);
