-- ============================================================
-- 3DMP Service · 0093_usage_counters.sql  (v71 — Пункт 3: P1 счётчики использования)
-- Счётчики использования по организации (метрика → значение) для тарифов/аналитики.
-- Зависит от 0001..0092.
-- ============================================================

create table if not exists public.app_usage_counters (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  metric     text not null,
  value      numeric not null default 0,
  updated_at timestamptz not null default now()
);
create unique index if not exists app_usage_counters_uq on public.app_usage_counters (tenant_id, metric);
create index if not exists app_usage_counters_idx on public.app_usage_counters (tenant_id);
alter table public.app_usage_counters enable row level security;

create or replace function public.app_counter_bump(p_token uuid, p_metric text, p_delta numeric default 1)
returns table (metric text, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; m text; v numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'platform', 'edit');
  ten := public.app_my_tenant(p_token);
  m := lower(trim(coalesce(p_metric,'')));
  if m = '' then raise exception 'Укажите метрику'; return; end if;
  insert into public.app_usage_counters (tenant_id, metric, value)
  values (ten, m, coalesce(p_delta,1))
  on conflict (tenant_id, metric)
  do update set value = public.app_usage_counters.value + coalesce(p_delta,1), updated_at = now()
  returning public.app_usage_counters.metric, public.app_usage_counters.value into metric, value;
  return next;
end $$;

create or replace function public.app_counters_list(p_token uuid)
returns table (metric text, value numeric, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.metric, c.value, c.updated_at
    from public.app_usage_counters c
    where (urole='admin' or c.tenant_id=ten) order by c.metric;
end $$;

create or replace function public.app_counters_kpi(p_token uuid)
returns table (metrics bigint, total numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(value),0) from public.app_usage_counters where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_counter_bump(uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_counters_list(uuid) to anon, authenticated;
grant execute on function public.app_counters_kpi(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Счётчики использования (P1)',
   'Модуль «Счётчики использования»: учёт метрик (заявки, наряды, созданные документы, файлы, вход пользователей и др.) по организации — для тарифов P1 Cloud и аналитики. Инкремент: app_counter_bump(metric, delta); просмотр: app_counters_list.',
   'счётчики использование метрики тарифы аналитика P1')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Счётчики использования (P1)');
