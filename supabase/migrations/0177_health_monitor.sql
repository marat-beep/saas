-- ============================================================
-- 3DMP Service · 0177_health_monitor.sql  (план v3, W33 «Эксплуатация»)
-- Мониторинг доступности: внешний пинг по API-ключу, алерты с дедупом,
-- «свежесть данных» и тренд доступности. Идемпотентно. Зависит от 0001..0176.
-- ============================================================

-- ---------- Алерты доступности (дедуп по kind:name) ----------
create table if not exists public.app_health_alerts (
  id          uuid primary key default gen_random_uuid(),
  dedup_key   text not null unique,
  kind        text not null,
  name        text not null,
  severity    text not null default 'warn',   -- warn|fail
  status      text not null default 'open',   -- open|resolved
  detail      text,
  occurrences integer not null default 1,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists app_health_alerts_status_idx on public.app_health_alerts (status, last_seen desc);
create index if not exists app_health_alerts_kind_idx on public.app_health_alerts (kind, last_seen desc);
alter table public.app_health_alerts enable row level security;

-- ---------- Внешние пинги (uptime-мониторинг по API-ключу) ----------
create table if not exists public.app_health_pings (
  id         uuid primary key default gen_random_uuid(),
  api_key    uuid,
  tenant_id  uuid,
  status     text not null default 'ok',
  latency_ms integer,
  source     text,
  detail     text,
  created_at timestamptz not null default now()
);
create index if not exists app_health_pings_time_idx on public.app_health_pings (created_at desc);
alter table public.app_health_pings enable row level security;

-- ---------- Пинг по API-ключу (для внешних мониторов/uptime) ----------
create or replace function public.app_health_ping(p_key uuid)
returns table (status text, server_time timestamptz, latency_ms integer, detail text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare t0 timestamptz; lat integer; ten uuid;
begin
  select k.tenant_id into ten from public.app_api_keys k where k.api_key = p_key and k.active;
  if ten is null then
    insert into public.app_health_pings (api_key, status, source, detail)
    values (p_key, 'fail', 'ping', 'Недействительный или отозванный ключ');
    return query select 'fail'::text, clock_timestamp(), 0, 'Недействительный или отозванный ключ'::text;
    return;
  end if;
  t0 := clock_timestamp();
  perform 1;
  lat := round(extract(epoch from clock_timestamp() - t0) * 1000)::int;
  update public.app_api_keys set last_used_at = now() where api_key = p_key and active;
  insert into public.app_health_pings (api_key, tenant_id, status, latency_ms, source, detail)
  values (p_key, ten, 'ok', lat, 'ping', 'Пинг принят');
  return query select 'ok'::text, clock_timestamp(), lat, 'Пинг принят'::text;
end $$;

-- ---------- RPC: скан доступности (с алертами и «свежестью») ----------
create or replace function public.app_health_scan(p_token uuid)
returns table (kind text, name text, status text, detail text, latency_ms integer, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare
  t0 timestamptz; run_ts timestamptz; lat integer; cnt integer; pend integer; over_c integer;
  last_run timestamptz; last_ping timestamptz; has_key integer; r record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;

  run_ts := now();          -- метка текущего прогона (совпадает с checked_at по умолчанию)
  t0 := clock_timestamp();
  perform 1;
  lat := round(extract(epoch from clock_timestamp() - t0) * 1000)::int;
  insert into public.app_health_checks (kind, name, status, detail, latency_ms)
  values ('db','База данных','ok','Соединение установлено', lat);

  select count(*) into cnt from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname='public' and c.relname in ('app_orders','app_users','app_plans','app_subscriptions');
  insert into public.app_health_checks (kind, name, status, detail)
  values ('tables','Ключевые таблицы', case when cnt = 4 then 'ok' else 'fail' end, 'Найдено ' || cnt || ' из 4');

  select count(*) into cnt from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname='public';
  insert into public.app_health_checks (kind, name, status, detail)
  values ('functions','Функции RPC', case when cnt > 300 then 'ok' else 'warn' end, 'Всего функций: ' || cnt);

  select count(*) into cnt from pg_catalog.pg_publication_tables
   where pubname='supabase_realtime' and schemaname='public' and tablename='app_notifications';
  insert into public.app_health_checks (kind, name, status, detail)
  values ('realtime','Realtime-канал', case when cnt > 0 then 'ok' else 'warn' end,
          case when cnt > 0 then 'Публикация app_notifications активна' else 'Публикация не найдена' end);

  select count(*) into pend from public.app_integration_log where status in ('pending','error','failed');
  insert into public.app_health_checks (kind, name, status, detail)
  values ('integration','Очередь интеграций', case when pend = 0 then 'ok' when pend < 10 then 'warn' else 'fail' end,
          'Проблемных записей: ' || pend);

  select count(*) into over_c from public.app_platform_invoices where status = 'overdue';
  insert into public.app_health_checks (kind, name, status, detail)
  values ('billing','Просроченные счета', case when over_c = 0 then 'ok' else 'warn' end,
          'Просрочено счетов: ' || over_c);

  -- «Свежесть данных»: плановые проверки должны идти регулярно
  select max(h.checked_at) into last_run from public.app_health_checks h where h.kind = 'tables' and h.checked_at < run_ts;
  insert into public.app_health_checks (kind, name, status, detail)
  values ('freshness','Свежесть проверок',
          case when last_run is null then 'ok' when last_run < clock_timestamp() - interval '26 hours' then 'warn' else 'ok' end,
          case when last_run is null then 'Первый запуск' else 'Предыдущая проверка: ' || to_char(last_run,'DD.MM HH24:MI') end);

  -- Внешний мониторинг: пинги по API-ключу
  select max(p.created_at) into last_ping from public.app_health_pings p;
  select count(*) into has_key from public.app_api_keys where active;
  insert into public.app_health_checks (kind, name, status, detail)
  values ('ping','Внешний мониторинг',
          case when last_ping is null then (case when has_key > 0 then 'warn' else 'ok' end)
               when last_ping < clock_timestamp() - interval '24 hours' then 'warn' else 'ok' end,
          case when last_ping is null then (case when has_key > 0 then 'Пингов нет (настроен API-ключ)' else 'Внешний мониторинг не настроен' end)
               else 'Последний пинг: ' || to_char(last_ping,'DD.MM HH24:MI') end);

  -- ---------- Алерты: открыть/обновить (дедуп по kind:name) ----------
  insert into public.app_health_alerts (dedup_key, kind, name, severity, status, detail, occurrences, first_seen, last_seen)
  select h.kind || ':' || h.name, h.kind, h.name, h.status, 'open', h.detail, 1, clock_timestamp(), clock_timestamp()
    from (
      select distinct on (kind) kind, name, status, detail
        from public.app_health_checks
       where checked_at >= run_ts
       order by kind, checked_at desc
    ) h
   where h.status in ('warn','fail')
  on conflict (dedup_key) do update
     set first_seen  = case when public.app_health_alerts.status = 'resolved' then clock_timestamp() else public.app_health_alerts.first_seen end,
         last_seen   = clock_timestamp(),
         occurrences = case when public.app_health_alerts.status = 'resolved' then 1 else public.app_health_alerts.occurrences + 1 end,
         severity    = excluded.severity,
         detail      = excluded.detail,
         status      = 'open',
         resolved_at = null;

  -- ---------- Алерты: закрыть те, что снова в норме ----------
  update public.app_health_alerts a
     set status = 'resolved', resolved_at = clock_timestamp()
   where a.status = 'open'
     and exists (select 1 from public.app_health_checks h
                  where h.checked_at >= run_ts and h.kind = a.kind and h.name = a.name and h.status = 'ok');

  -- ---------- Уведомления по новым/переоткрытым алертам ----------
  for r in select a.name, a.severity, a.detail from public.app_health_alerts a
            where a.status = 'open' and a.first_seen >= run_ts and a.occurrences = 1
  loop
    perform public.app_notif_roles_t(null, array['admin'],
      (case when r.severity = 'fail' then '⚠️ Сбой доступности: ' else '⚠ Отклонение: ' end) || r.name,
      coalesce(r.detail, ''), 'apps/billing/index.html');
  end loop;

  return query select h.kind, h.name, h.status, h.detail, h.latency_ms, h.checked_at
    from public.app_health_checks h order by h.checked_at desc, h.kind limit 60;
end $$;

-- ---------- RPC: список алертов ----------
create or replace function public.app_health_alerts_list(p_token uuid, p_status text default 'open')
returns table (id uuid, kind text, name text, severity text, status text, detail text, occurrences integer,
               first_seen timestamptz, last_seen timestamptz, resolved_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  st := lower(trim(coalesce(p_status,'open')));
  return query
    select a.id, a.kind, a.name, a.severity, a.status, a.detail, a.occurrences, a.first_seen, a.last_seen, a.resolved_at
      from public.app_health_alerts a
     where (st = 'all' or a.status = st)
     order by (a.status = 'open') desc, a.last_seen desc
     limit 200;
end $$;

-- ---------- RPC: закрыть алерт вручную ----------
create or replace function public.app_health_alert_resolve(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  update public.app_health_alerts set status = 'resolved', resolved_at = clock_timestamp()
   where id = p_id and status = 'open';
  if not found then return query select false, 'Алерт не найден или уже закрыт'::text; return; end if;
  return query select true, 'Алерт закрыт'::text;
end $$;

-- ---------- RPC: тренд доступности ----------
create or replace function public.app_health_trend(p_token uuid, p_days integer default 14)
returns table (day date, total integer, ok integer, warn integer, fail integer, uptime_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare days integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  days := greatest(coalesce(p_days,14),1);
  return query
    select g.d::date,
           count(h.id)::int,
           count(*) filter (where h.status = 'ok')::int,
           count(*) filter (where h.status = 'warn')::int,
           count(*) filter (where h.status = 'fail')::int,
           round(100.0 * count(*) filter (where h.status = 'ok') / greatest(count(h.id), 1), 2)
      from generate_series(current_date - (days - 1), current_date, interval '1 day') g(d)
      left join public.app_health_checks h on h.checked_at::date = g.d::date
     group by g.d
     order by g.d;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','Мониторинг доступности: пинг, алерты, тренд, расписание',
 'Эксплуатация и мониторинг (W33): плановые проверки — tools/run-checks.ps1 (audit + db-smoke, лог в dist/checks, код возврата) по расписанию (Task Scheduler/CI). Внешний uptime-мониторинг — app_health_ping(p_key) по API-ключу организации (пишет app_health_pings, обновляет last_used_at). app_health_scan дополнительно проверяет «свежесть данных» и наличие пингов, открывает алерты (app_health_alerts, дедуп по kind:name) и уведомляет администраторов платформы при сбое; закрытие автоматическое, когда показатель снова в норме (или вручную app_health_alert_resolve). Тренд доступности — app_health_trend(days) (доля ok по дням). Дашборд — в модуле «Диагностика».',
 'мониторинг доступность uptime health алерты тренд расписание run-checks пинг SLA'
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Мониторинг доступности: пинг, алерты, тренд, расписание'
);

-- ---------- Права на выполнение ----------
grant execute on function public.app_health_ping(uuid) to anon, authenticated;
grant execute on function public.app_health_scan(uuid) to anon, authenticated;
grant execute on function public.app_health_alerts_list(uuid,text) to anon, authenticated;
grant execute on function public.app_health_alert_resolve(uuid,uuid) to anon, authenticated;
grant execute on function public.app_health_trend(uuid,integer) to anon, authenticated;
