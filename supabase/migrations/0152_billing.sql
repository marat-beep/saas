-- ============================================================
-- 3DMP Service · 0152_billing.sql  (W7 — Биллинг/подписки и SLA платформы)
-- Тарифы с лимитами, подписки организаций, счета платформы, статус-борд доступности.
-- Идемпотентно. Зависит от 0001..0151.
-- ============================================================

-- ---------- Тарифы: лимиты (квоты) и период ----------
alter table public.app_plans add column if not exists limits jsonb not null default '{}'::jsonb;
alter table public.app_plans add column if not exists period text not null default 'month';
alter table public.app_plans add column if not exists description text;

update public.app_plans set
  limits = '{"users":5,"orders":200,"naryads":100,"documents":100,"files":100,"storage_mb":200,"suppliers":20,"service":50}'::jsonb,
  period = 'month',
  description = 'Для небольшой мастерской: базовые модули продаж и учёта.'
 where code = 'start';

update public.app_plans set
  limits = '{"users":25,"orders":1000,"naryads":1000,"documents":1000,"files":1000,"storage_mb":2000,"suppliers":200,"service":500}'::jsonb,
  period = 'month',
  description = 'Для среднего завода: производство, склад, качество, экономика.'
 where code = 'business';

update public.app_plans set
  limits = '{}'::jsonb,
  period = 'month',
  description = 'Для крупного предприятия: без ограничений по модулям.'
 where code = 'corp';

-- ---------- Подписки организаций ----------
create table if not exists public.app_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants (id) on delete cascade,
  plan_code    text not null references public.app_plans (code),
  status       text not null default 'active',   -- trial|active|past_due|suspended|cancelled
  seats        integer,
  amount       numeric not null default 0,
  period_start date not null default current_date,
  period_end   date not null default (current_date + interval '1 month'),
  auto_renew   boolean not null default true,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists app_subscriptions_tenant_uq on public.app_subscriptions (tenant_id);
create index if not exists app_subscriptions_status_idx on public.app_subscriptions (status);
alter table public.app_subscriptions enable row level security;

-- ---------- Счета платформы (биллинг организаций) ----------
create sequence if not exists public.app_platform_invoice_seq;
create table if not exists public.app_platform_invoices (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id) on delete set null,
  number       text unique,
  plan_code    text,
  period_start date,
  period_end   date,
  amount       numeric not null default 0,
  status       text not null default 'draft',    -- draft|issued|paid|overdue|cancelled
  issued_at    timestamptz,
  due_at       date,
  paid_at      timestamptz,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_platform_invoices_tenant_idx on public.app_platform_invoices (tenant_id, status);
create index if not exists app_platform_invoices_status_idx on public.app_platform_invoices (status, due_at);
alter table public.app_platform_invoices enable row level security;

-- ---------- Проверки доступности (SLA платформы) ----------
create table if not exists public.app_health_checks (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null,           -- db|tables|functions|realtime|integration|billing|backup
  name       text not null,
  status     text not null default 'ok',  -- ok|warn|fail
  detail     text,
  latency_ms integer,
  checked_at timestamptz not null default now()
);
create index if not exists app_health_checks_time_idx on public.app_health_checks (checked_at desc);
create index if not exists app_health_checks_kind_idx on public.app_health_checks (kind, checked_at desc);
alter table public.app_health_checks enable row level security;

-- ---------- Квоты: использовано/лимит по метрике ----------
create or replace function public.app_quota_used(p_tenant uuid, p_metric text)
returns numeric language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare m text; v numeric;
begin
  m := lower(trim(coalesce(p_metric,'')));
  if m = 'users'      then select count(*) into v from public.app_users where tenant_id = p_tenant;
  elsif m = 'orders'  then select count(*) into v from public.app_orders where tenant_id = p_tenant;
  elsif m = 'naryads' then select count(*) into v from public.app_naryads where tenant_id = p_tenant;
  elsif m = 'documents' then select count(*) into v from public.app_documents where tenant_id = p_tenant;
  elsif m = 'files'   then select count(*) into v from public.app_attachments where tenant_id = p_tenant;
  elsif m = 'storage_mb' then select coalesce(sum(coalesce(size,0)),0)/1048576.0 into v from public.app_attachments where tenant_id = p_tenant;
  elsif m = 'suppliers' then select count(*) into v from public.app_suppliers where tenant_id = p_tenant;
  elsif m = 'service' then select count(*) into v from public.app_service_requests where tenant_id = p_tenant;
  else select coalesce(value,0) into v from public.app_usage_counters where tenant_id = p_tenant and metric = m limit 1;
  end if;
  return coalesce(v,0);
end $$;

create or replace function public.app_quota_limit(p_tenant uuid, p_metric text)
returns numeric language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare lm jsonb; q numeric;
begin
  select coalesce(p.limits,'{}'::jsonb) into lm
    from public.tenants t left join public.app_plans p on p.code = t.plan
   where t.id = p_tenant;
  if lm is null then return null; end if;
  q := nullif(lm ->> lower(trim(coalesce(p_metric,''))), '')::numeric;
  return q;
end $$;

-- Публичная проверка квоты (для модулей и UI). quota = null → без ограничения.
create or replace function public.app_quota_check(p_token uuid, p_metric text)
returns table (ok boolean, used numeric, quota numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; u numeric; q numeric; m text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  m := lower(trim(coalesce(p_metric,'')));
  if m = '' then return query select false, 0::numeric, null::numeric, 'Укажите метрику'; return; end if;
  u := public.app_quota_used(ten, m);
  q := public.app_quota_limit(ten, m);
  if q is null then
    return query select true, u, null::numeric, 'Без ограничений';
  elsif u >= q then
    return query select false, u, q, 'Достигнут лимит тарифа по метрике «' || m || '» (' || q::int || ')';
  else
    return query select true, u, q, 'В пределах лимита (' || u::int || '/' || q::int || ')';
  end if;
end $$;

-- ---------- Контроль квоты заявок (пример применения лимитов) ----------
create or replace function public.app_orders_quota_trg()
returns trigger language plpgsql security definer set search_path = public
as $$
declare q numeric; u numeric;
begin
  if new.tenant_id is null then return new; end if;
  if not exists (select 1 from public.app_subscriptions s
                  where s.tenant_id = new.tenant_id and s.status in ('active','trial','past_due')) then
    return new;
  end if;
  q := public.app_quota_limit(new.tenant_id, 'orders');
  if q is not null then
    u := public.app_quota_used(new.tenant_id, 'orders');
    if u >= q then
      raise exception 'Достигнут лимит тарифа по заявкам: % (использовано %)', q::int, u::int;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists app_orders_quota on public.app_orders;
create trigger app_orders_quota before insert on public.app_orders
  for each row execute function public.app_orders_quota_trg();

-- ---------- RPC: тарифы ----------
create or replace function public.app_billing_plans(p_token uuid)
returns table (code text, name text, price numeric, period text, max_users integer,
               limits jsonb, features jsonb, description text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select p.code, p.name, p.price, p.period, p.max_users, p.limits, p.features, p.description
    from public.app_plans p order by p.sort;
end $$;

-- ---------- RPC: подписка организации ----------
create or replace function public.app_subscription_get(p_token uuid, p_tenant uuid default null)
returns table (tenant_id uuid, tenant_name text, plan_code text, plan_name text, plan_price numeric,
               price_period text, status text, seats integer, amount numeric,
               period_start date, period_end date, auto_renew boolean, note text, days_left integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := coalesce(case when adm then p_tenant else null end, public.app_my_tenant(p_token));
  if ten is null then return; end if;
  return query
    select s.tenant_id, t.name, s.plan_code, p.name, p.price, p.period, s.status, s.seats, s.amount,
           s.period_start, s.period_end, s.auto_renew, s.note,
           (s.period_end - current_date)::int
      from public.app_subscriptions s
      join public.tenants t on t.id = s.tenant_id
      left join public.app_plans p on p.code = s.plan_code
     where s.tenant_id = ten;
end $$;

create or replace function public.app_subscription_save(
  p_token uuid, p_tenant uuid, p_plan text, p_status text, p_seats integer, p_amount numeric,
  p_period_start date, p_period_end date, p_auto_renew boolean, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; pcode text; amt numeric; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := coalesce(case when adm then p_tenant else null end, public.app_my_tenant(p_token));
  if ten is null then return query select false,'Организация не определена'; return; end if;
  if not adm and not public.app_is_owner(p_token) then return query select false,'Недостаточно прав'; return; end if;

  pcode := nullif(trim(coalesce(p_plan,'')), '');
  if pcode is null then
    select plan into pcode from public.tenants where id = ten;
  end if;
  if pcode is null or not exists (select 1 from public.app_plans where code = pcode) then
    return query select false,'Тариф не найден'; return;
  end if;
  st := lower(trim(coalesce(nullif(p_status,''), 'active')));
  if st not in ('trial','active','past_due','suspended','cancelled') then
    return query select false,'Недопустимый статус подписки'; return;
  end if;
  select price into amt from public.app_plans where code = pcode;

  insert into public.app_subscriptions (tenant_id, plan_code, status, seats, amount, period_start, period_end, auto_renew, note, updated_at)
  values (ten, pcode, st, p_seats, coalesce(p_amount, amt, 0),
          coalesce(p_period_start, current_date), coalesce(p_period_end, current_date + interval '1 month'),
          coalesce(p_auto_renew, true), nullif(trim(coalesce(p_note,'')),''), now())
  on conflict (tenant_id) do update set
    plan_code = excluded.plan_code,
    status = excluded.status,
    seats = coalesce(excluded.seats, public.app_subscriptions.seats),
    amount = excluded.amount,
    period_start = excluded.period_start,
    period_end = excluded.period_end,
    auto_renew = excluded.auto_renew,
    note = excluded.note,
    updated_at = now();

  update public.tenants set plan = pcode where id = ten;
  return query select true,'Подписка сохранена';
end $$;

create or replace function public.app_subscriptions_list(p_token uuid)
returns table (tenant_id uuid, tenant_name text, plan_code text, plan_name text, plan_price numeric,
               status text, seats integer, amount numeric, period_start date, period_end date,
               auto_renew boolean, users_used numeric, users_limit numeric, mrr numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  return query
    select t.id, t.name, coalesce(s.plan_code, t.plan), p.name, p.price,
           coalesce(s.status, 'active'), s.seats, coalesce(s.amount, p.price, 0),
           s.period_start, s.period_end, coalesce(s.auto_renew, true),
           (select count(*) from public.app_users u where u.tenant_id = t.id)::numeric,
           nullif(p.limits->>'users','')::numeric,
           (case when coalesce(s.status,'active') in ('active','trial','past_due') then coalesce(s.amount, p.price, 0) else 0 end)
      from public.tenants t
      left join public.app_subscriptions s on s.tenant_id = t.id
      left join public.app_plans p on p.code = coalesce(s.plan_code, t.plan)
     where adm or t.id = public.app_my_tenant(p_token)
     order by t.name;
end $$;

-- ---------- RPC: использование и квоты ----------
create or replace function public.app_billing_usage(p_token uuid)
returns table (metric text, label text, used numeric, quota numeric, unit text, pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; lm jsonb;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  select coalesce(p.limits,'{}'::jsonb) into lm
    from public.tenants t left join public.app_plans p on p.code = t.plan where t.id = ten;
  lm := coalesce(lm, '{}'::jsonb);

  return query
  select x.metric, x.label, public.app_quota_used(ten, x.metric), x.quota, x.unit,
         case when x.quota is null or x.quota = 0 then null
              else round(public.app_quota_used(ten, x.metric) / x.quota * 100, 1) end
  from (
    select 'users'::text as metric, 'Пользователи'::text as label, nullif(lm->>'users','')::numeric as quota, 'чел.'::text as unit
    union all select 'orders', 'Заявки', nullif(lm->>'orders','')::numeric, 'шт.'
    union all select 'naryads', 'Наряды', nullif(lm->>'naryads','')::numeric, 'шт.'
    union all select 'documents', 'Документы', nullif(lm->>'documents','')::numeric, 'шт.'
    union all select 'files', 'Файлы', nullif(lm->>'files','')::numeric, 'шт.'
    union all select 'storage_mb', 'Объём файлов', nullif(lm->>'storage_mb','')::numeric, 'МБ'
    union all select 'suppliers', 'Поставщики', nullif(lm->>'suppliers','')::numeric, 'шт.'
    union all select 'service', 'Сервисные заявки', nullif(lm->>'service','')::numeric, 'шт.'
  ) x;
end $$;

-- ---------- RPC: счета платформы ----------
create or replace function public.app_platform_invoice_list(p_token uuid, p_status text default null)
returns table (id uuid, number text, tenant_name text, plan_code text, period_start date, period_end date,
               amount numeric, status text, issued_at timestamptz, due_at date, paid_at timestamptz,
               note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')), '');
  return query
    select i.id, i.number, t.name, i.plan_code, i.period_start, i.period_end, i.amount, i.status,
           i.issued_at, i.due_at, i.paid_at, i.note, i.created_at
      from public.app_platform_invoices i
      left join public.tenants t on t.id = i.tenant_id
     where (adm or i.tenant_id = ten)
       and (st is null or i.status = st)
     order by i.created_at desc;
end $$;

create or replace function public.app_platform_invoice_save(
  p_token uuid, p_id uuid, p_tenant uuid, p_plan text, p_period_start date, p_period_end date,
  p_amount numeric, p_due_at date, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare newid uuid; num text;
begin
  if not public.app_is_platform_admin(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if p_tenant is null then return query select false,'Выберите организацию', null::uuid; return; end if;

  if p_id is null then
    num := 'PLT-' || to_char(now(),'YYYY') || '-' || lpad(nextval('public.app_platform_invoice_seq')::text, 5, '0');
    insert into public.app_platform_invoices (tenant_id, number, plan_code, period_start, period_end, amount, status, due_at, note)
    values (p_tenant, num, nullif(trim(coalesce(p_plan,'')),''), p_period_start, p_period_end,
            coalesce(p_amount,0), 'draft', p_due_at, nullif(trim(coalesce(p_note,'')),''))
    returning app_platform_invoices.id into newid;
    return query select true, 'Счёт создан: ' || num, newid;
  else
    update public.app_platform_invoices
       set tenant_id = p_tenant,
           plan_code = nullif(trim(coalesce(p_plan,'')),''),
           period_start = p_period_start,
           period_end = p_period_end,
           amount = coalesce(p_amount, amount),
           due_at = p_due_at,
           note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_id
     returning app_platform_invoices.id into newid;
    if newid is null then return query select false,'Счёт не найден', null::uuid; return; end if;
    return query select true, 'Счёт сохранён', newid;
  end if;
end $$;

create or replace function public.app_platform_invoice_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare st text; n integer;
begin
  if not public.app_is_platform_admin(p_token) then return query select false,'Доступ запрещён'; return; end if;
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('draft','issued','paid','overdue','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_platform_invoices
     set status = st,
         issued_at = case when st = 'issued' and issued_at is null then now() else issued_at end,
         paid_at = case when st = 'paid' then coalesce(paid_at, now()) else paid_at end
   where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Счёт не найден'; return; end if;
  return query select true,'Статус счёта: ' || st;
end $$;

create or replace function public.app_billing_generate_invoices(p_token uuid, p_period_start date, p_period_end date)
returns table (created integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare d1 date; d2 date; rec record; num text; cnt integer := 0;
begin
  if not public.app_is_platform_admin(p_token) then return query select 0,'Доступ разрешён только администратору платформы'; return; end if;
  d1 := coalesce(p_period_start, date_trunc('month', current_date)::date);
  d2 := coalesce(p_period_end, (date_trunc('month', current_date) + interval '1 month - 1 day')::date);
  for rec in
    select s.tenant_id, s.plan_code, s.amount, p.price
      from public.app_subscriptions s
      left join public.app_plans p on p.code = s.plan_code
     where s.status in ('active','trial','past_due','suspended')
  loop
    if not exists (select 1 from public.app_platform_invoices i
                    where i.tenant_id = rec.tenant_id and i.period_start = d1) then
      num := 'PLT-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.app_platform_invoice_seq')::text, 5, '0');
      insert into public.app_platform_invoices (tenant_id, number, plan_code, period_start, period_end, amount, status, due_at)
      values (rec.tenant_id, num, rec.plan_code, d1, d2, coalesce(rec.amount, rec.price, 0), 'issued', d2 + 10);
      cnt := cnt + 1;
    end if;
  end loop;
  return query select cnt, 'Сформировано счетов: ' || cnt;
end $$;

-- ---------- RPC: KPI биллинга ----------
create or replace function public.app_billing_kpi(p_token uuid)
returns table (tenants bigint, active_subs bigint, mrr numeric, overdue_amount numeric,
               overdue_count bigint, issued_amount numeric, paid_amount numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select
      (select count(*) from public.tenants t where adm or t.id = ten),
      (select count(*) from public.app_subscriptions s where (adm or s.tenant_id = ten) and s.status in ('active','trial')),
      (select coalesce(sum(s.amount),0) from public.app_subscriptions s where (adm or s.tenant_id = ten) and s.status in ('active','trial','past_due')),
      (select coalesce(sum(i.amount),0) from public.app_platform_invoices i where (adm or i.tenant_id = ten) and i.status = 'overdue'),
      (select count(*) from public.app_platform_invoices i where (adm or i.tenant_id = ten) and i.status = 'overdue'),
      (select coalesce(sum(i.amount),0) from public.app_platform_invoices i where (adm or i.tenant_id = ten) and i.status = 'issued'),
      (select coalesce(sum(i.amount),0) from public.app_platform_invoices i where (adm or i.tenant_id = ten) and i.status = 'paid');
end $$;

-- ---------- RPC: доступность (SLA платформы) ----------
create or replace function public.app_health_scan(p_token uuid)
returns table (kind text, name text, status text, detail text, latency_ms integer, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare t0 timestamptz; lat integer; cnt integer; pend integer; over_c integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;

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

  return query select h.kind, h.name, h.status, h.detail, h.latency_ms, h.checked_at
    from public.app_health_checks h order by h.checked_at desc, h.kind limit 60;
end $$;

create or replace function public.app_health_list(p_token uuid, p_limit integer default 30)
returns table (kind text, name text, status text, detail text, latency_ms integer, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select h.kind, h.name, h.status, h.detail, h.latency_ms, h.checked_at
    from public.app_health_checks h order by h.checked_at desc, h.id limit greatest(coalesce(p_limit,30),1);
end $$;

create or replace function public.app_health_board(p_token uuid)
returns table (kind text, name text, status text, detail text, latency_ms integer, checked_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select distinct on (h.kind) h.kind, h.name, h.status, h.detail, h.latency_ms, h.checked_at
      from public.app_health_checks h
     order by h.kind, h.checked_at desc;
end $$;

-- ---------- Демо: подписки и счета ----------
insert into public.app_subscriptions (tenant_id, plan_code, status, seats, amount, period_start, period_end, auto_renew, note)
values ('aaaaaaaa-0000-0000-0000-000000000001','business','active',25,19900, date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, true,'Демо-подписка')
on conflict (tenant_id) do nothing;

insert into public.app_subscriptions (tenant_id, plan_code, status, seats, amount, period_start, period_end, auto_renew, note)
values ('bbbbbbbb-0000-0000-0000-000000000002','business','active',10,19900, date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, true,'Демо-подписка')
on conflict (tenant_id) do nothing;

insert into public.app_platform_invoices (tenant_id, number, plan_code, period_start, period_end, amount, status, issued_at, due_at, paid_at, note)
select 'aaaaaaaa-0000-0000-0000-000000000001','PLT-2026-00001','business',
       (date_trunc('month', current_date) - interval '1 month')::date,
       (date_trunc('month', current_date) - interval '1 day')::date,
       19900,'paid', (date_trunc('month', current_date) - interval '1 month')::timestamptz,
       (date_trunc('month', current_date) + interval '9 day')::date,
       (date_trunc('month', current_date) - interval '20 day')::timestamptz, 'Демо: прошлый период'
where not exists (select 1 from public.app_platform_invoices where number = 'PLT-2026-00001');

insert into public.app_platform_invoices (tenant_id, number, plan_code, period_start, period_end, amount, status, issued_at, due_at, note)
select 'bbbbbbbb-0000-0000-0000-000000000002','PLT-2026-00002','business',
       date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date,
       19900,'issued', now(), (date_trunc('month', current_date) + interval '1 month + 9 day')::date, 'Демо: текущий период'
where not exists (select 1 from public.app_platform_invoices where number = 'PLT-2026-00002');

select setval('public.app_platform_invoice_seq',
  greatest(coalesce((select max(split_part(number,'-',3)::int) from public.app_platform_invoices where number like 'PLT-%'), 0), 2), true);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Биллинг и подписки: тарифы, квоты, счета, доступность',
   'Модуль «Биллинг и подписки»: тарифы (app_plans) с лимитами (limits jsonb) и периодом; подписки организаций (app_subscriptions: статус trial/active/past_due/suspended/cancelled, места, сумма, период, автопродление); использование и квоты по модулям (app_billing_usage, app_quota_check); счета платформы (app_platform_invoices, номера PLT-ГГГГ-NNNNN; создание/статусы/авто-формирование app_billing_generate_invoices); статус-борд доступности (app_health_checks, app_health_scan/board: БД, таблицы, функции, Realtime, интеграции, просрочка). Роли: администратор платформы — все организации; владелец — своя. Связи: Организации (SaaS), Админ-панель клиента, Счётчики использования, Финансы, Интеграции.',
   'биллинг подписки тариф квоты лимиты счета платформы доступность SLA health')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Биллинг и подписки: тарифы, квоты, счета, доступность'
);

-- ---------- Права на выполнение ----------
grant execute on function public.app_quota_check(uuid,text) to anon, authenticated;
grant execute on function public.app_billing_plans(uuid) to anon, authenticated;
grant execute on function public.app_subscription_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_subscription_save(uuid,uuid,text,text,integer,numeric,date,date,boolean,text) to anon, authenticated;
grant execute on function public.app_subscriptions_list(uuid) to anon, authenticated;
grant execute on function public.app_billing_usage(uuid) to anon, authenticated;
grant execute on function public.app_platform_invoice_list(uuid,text) to anon, authenticated;
grant execute on function public.app_platform_invoice_save(uuid,uuid,uuid,text,date,date,numeric,date,text) to anon, authenticated;
grant execute on function public.app_platform_invoice_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_billing_generate_invoices(uuid,date,date) to anon, authenticated;
grant execute on function public.app_billing_kpi(uuid) to anon, authenticated;
grant execute on function public.app_health_scan(uuid) to anon, authenticated;
grant execute on function public.app_health_list(uuid,integer) to anon, authenticated;
grant execute on function public.app_health_board(uuid) to anon, authenticated;
