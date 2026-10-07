-- ============================================================
-- 3DMP Service · 0153_analytics_l4.sql  (W8 — Аналитика L4)
-- Конструктор отчётов (сохранённые определения) + прогнозы спроса/сроков/рисков.
-- Идемпотентно. Зависит от 0001..0152.
-- ============================================================

-- ---------- Сохранённые определения отчётов ----------
create table if not exists public.app_report_defs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  dataset       text not null,                       -- orders|naryads|tenders|materials|passports|invoices|economics|qc|routes
  columns       jsonb not null default '[]'::jsonb,  -- массив ключей выбранных колонок
  filters       jsonb not null default '{}'::jsonb,  -- {status, q, date_from, date_to}
  group_by      text,                                -- ключ колонки для группировки (необязательно)
  agg           text not null default 'count',       -- count|sum|avg
  chart         text not null default 'table',       -- table|bar|line
  shared        boolean not null default false,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_report_defs_tenant_idx on public.app_report_defs (tenant_id, created_at desc);
alter table public.app_report_defs enable row level security;

-- ---------- RPC: определения отчётов ----------
create or replace function public.app_report_defs_list(p_token uuid)
returns table (id uuid, name text, dataset text, columns jsonb, filters jsonb, group_by text,
               agg text, chart text, shared boolean, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.name, d.dataset, d.columns, d.filters, d.group_by, d.agg, d.chart, d.shared, d.created_login, d.created_at
      from public.app_report_defs d
     where adm or d.tenant_id = ten
     order by d.created_at desc;
end $$;

create or replace function public.app_report_def_get(p_token uuid, p_id uuid)
returns table (id uuid, name text, dataset text, columns jsonb, filters jsonb, group_by text,
               agg text, chart text, shared boolean, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.name, d.dataset, d.columns, d.filters, d.group_by, d.agg, d.chart, d.shared, d.created_login, d.created_at
      from public.app_report_defs d
     where d.id = p_id and (adm or d.tenant_id = ten);
end $$;

create or replace function public.app_report_def_save(
  p_token uuid, p_id uuid, p_name text, p_dataset text, p_columns jsonb, p_filters jsonb,
  p_group_by text, p_agg text, p_chart text, p_shared boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname
    from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название отчёта', null::uuid; return; end if;
  if coalesce(trim(p_dataset),'') not in ('orders','naryads','tenders','materials','passports','invoices','economics','qc','routes') then
    return query select false,'Неизвестный набор данных', null::uuid; return;
  end if;
  if coalesce(trim(p_agg),'') not in ('count','sum','avg') then
    return query select false,'Недопустимая агрегация', null::uuid; return;
  end if;
  if coalesce(trim(p_chart),'') not in ('table','bar','line') then
    return query select false,'Недопустимый тип графика', null::uuid; return;
  end if;

  if p_id is null then
    insert into public.app_report_defs (tenant_id, name, dataset, columns, filters, group_by, agg, chart, shared, created_by, created_login)
    values (ten, left(trim(p_name),120), p_dataset, coalesce(p_columns,'[]'::jsonb), coalesce(p_filters,'{}'::jsonb),
            nullif(trim(coalesce(p_group_by,'')),''), coalesce(nullif(trim(p_agg),''),'count'), coalesce(nullif(trim(p_chart),''),'table'),
            coalesce(p_shared,false),
            (select s.uid from public.app_session_user(p_token) s), uname)
    returning app_report_defs.id into newid;
    return query select true,'Отчёт сохранён', newid;
  else
    update public.app_report_defs d
       set name = left(trim(p_name),120), dataset = p_dataset, columns = coalesce(p_columns, d.columns),
           filters = coalesce(p_filters, d.filters), group_by = nullif(trim(coalesce(p_group_by,'')),''),
           agg = coalesce(nullif(trim(p_agg),''),'count'), chart = coalesce(nullif(trim(p_chart),''),'table'),
           shared = coalesce(p_shared, d.shared), updated_at = now()
     where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Отчёт не найден', null::uuid; return; end if;
    return query select true,'Отчёт обновлён', newid;
  end if;
end $$;

create or replace function public.app_report_def_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_report_defs d
   where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Отчёт не найден'; return; end if;
  return query select true,'Отчёт удалён';
end $$;

-- ---------- RPC: прогноз спроса (заявки + выручка по месяцам) ----------
create or replace function public.app_forecast_demand(p_token uuid, p_months integer default 6)
returns table (month date, orders bigint, revenue numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; n integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  n := greatest(least(coalesce(p_months,6), 24), 1);
  return query
    select g.m::date,
      (select count(*) from public.app_orders o
        where (adm or o.tenant_id = ten) and date_trunc('month', o.created_at) = g.m),
      (select coalesce(sum(i.amount),0) from public.app_invoices i
        where (adm or i.tenant_id = ten) and i.status <> 'cancelled'
          and date_trunc('month', coalesce(i.created_at, now())) = g.m)
    from generate_series(date_trunc('month', current_date) - ((n-1) || ' month')::interval,
                         date_trunc('month', current_date), '1 month') as g(m)
    order by g.m;
end $$;

-- ---------- RPC: риски по срокам заявок ----------
create or replace function public.app_forecast_risks(p_token uuid, p_limit integer default 50)
returns table (number text, title text, customer text, due_date date, days_left integer,
               amount numeric, status text, priority text, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select o.number, o.title, o.customer, o.due_date,
           (o.due_date - current_date)::int,
           o.amount, o.status, o.priority,
           case when o.due_date < current_date then 'просрочен'
                when o.due_date <= current_date + 3 then 'риск'
                else 'норма' end
      from public.app_orders o
     where (adm or o.tenant_id = ten)
       and o.due_date is not null
       and o.status not in ('done','cancelled')
     order by o.due_date
     limit greatest(coalesce(p_limit,50),1);
end $$;

-- ---------- Демо: сохранённые отчёты ----------
insert into public.app_report_defs (tenant_id, name, dataset, columns, filters, group_by, agg, chart, shared, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.dataset, v.columns::jsonb, v.filters::jsonb, v.group_by, v.agg, v.chart, true, 'owner'
from (values
  ('Просроченные заявки', 'orders', '["number","title","customer","status","priority"]', '{"status":"in_progress"}', null, 'count', 'table'),
  ('Наряды по центрам', 'naryads', '["wc_name","title","status"]', '{}', 'wc_name', 'count', 'bar')
) as v(name, dataset, columns, filters, group_by, agg, chart)
where not exists (select 1 from public.app_report_defs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name = v.name);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Аналитика','Аналитика L4: конструктор отчётов и прогнозы',
   'Аналитика L4: конструктор отчётов — сохраняемые определения (app_report_defs: набор данных, колонки, фильтры, группировка, агрегация count/sum/avg, тип графика) с запуском и выгрузкой PDF/CSV через export.js; прогноз спроса (app_forecast_demand: заявки и выручка по месяцам + линейная проекция на графике); риски по срокам (app_forecast_risks: просрочен/риск/норма по заявкам); предиктив ТОиР (app_mnt_runtime_status: наработка/остаток до ТО). Модули «Отчёты и экспорт» и «Прогноз загрузки».',
   'аналитика конструктор отчётов app_report_defs прогноз спрос риски предиктив ТОиР L4')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Аналитика L4: конструктор отчётов и прогнозы'
);

-- ---------- Права ----------
grant execute on function public.app_report_defs_list(uuid) to anon, authenticated;
grant execute on function public.app_report_def_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_report_def_save(uuid,uuid,text,text,jsonb,jsonb,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_report_def_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_forecast_demand(uuid,integer) to anon, authenticated;
grant execute on function public.app_forecast_risks(uuid,integer) to anon, authenticated;
